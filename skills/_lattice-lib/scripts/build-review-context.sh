#!/usr/bin/env bash
# Build the artifact-only context manifest for a review-delivery chain review.
#
# Canonical home: skills/_lattice-lib/scripts/.
# The chain reviewer (review-delivery) consumes durable artifacts ONLY — never
# implementer transcripts. This script enumerates those artifacts so the
# reviewer reads from a manifest instead of ad-hoc discovery. (ADR-004 §4)
#
# Usage:
#   build-review-context.sh (--spec N | --ids N1,N2,... | --batch-report PATH)
#                           [--home <lattice-home>] [--from-heads] [--help]
#
# Inputs (exactly one required):
#   --spec N            resolve tickets from spc-N front matter `tickets:` list
#   --ids N1,N2,...     explicit ticket numbers (bare N or tkt-N, comma/space)
#   --batch-report PATH batch-work report file; ticket set = tkt-N ids found in it
#
# Options:
#   --from-heads        pre-merge mode: for each ticket with an OPEN PR (number
#                       from the binder prs row, else the gh search fallback),
#                       `git fetch origin <headRef>` and read the binder from
#                       `FETCH_HEAD:<binder path>` — stamped state (pr-open,
#                       journals) lives on unmerged PR heads. Falls back to the
#                       local file when the head is unavailable; each ticket's
#                       manifest entry marks its source (`local` vs `head:pr-N`).
#
# Output (stdout): a Markdown manifest — chosen over JSON because the consumer
# is an LLM reviewer and the format stays grep-able/diff-able like every other
# Lattice artifact. Shape:
#   header field table (generated/input/home/spec/batch report)
#   ## ADRs cited        — ADR-NNN refs found in Spec + binders → docs/adr path + exists?
#   ## Tickets           — per ticket: binder path, status, covers, prs row,
#                          gh PR fallback, evidence presence flags
#   ## Gaps              — empty/missing evidence sections (artifact-insufficiency
#                          candidates; feed review-delivery findings)
#
# Contract:
#   - READ-ONLY: never writes or mutates repo files. (`--from-heads` runs
#     `git fetch origin <ref>`, which only refreshes FETCH_HEAD — no worktree,
#     branch, or artifact is touched.)
#   - Fail loud (exit 1) on: missing spec file, spec with no tickets, missing
#     binder for any requested ticket, missing batch report.
#   - gh PR lookup is best-effort fallback ONLY when the binder `prs` row is
#     empty/(none); gh absent or failing degrades to a note, never an error.
#
# Exit: 0 on success; 1 on usage/missing-artifact failure. Logs → stderr.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lattice-home.sh
source "$SCRIPT_DIR/_lattice-home.sh"

log() { printf 'build-review-context: %s\n' "$*" >&2; }

usage() {
  sed -n '2,44p' "$0" | sed 's/^# \{0,1\}//'
}

SPEC_N=""
IDS_RAW=""
BATCH_REPORT=""
HOME_DIR=""
FROM_HEADS=false

require_value() {
  local flag="$1" val="${2-}"
  if [[ $# -lt 2 || -z "$val" || "$val" == -* ]]; then
    log "$flag requires a value"
    usage >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --spec)
      require_value "$1" "${2-}"
      SPEC_N="$2"
      shift 2
      ;;
    --spec=*)
      SPEC_N="${1#--spec=}"
      shift
      ;;
    --ids)
      require_value "$1" "${2-}"
      IDS_RAW="$2"
      shift 2
      ;;
    --ids=*)
      IDS_RAW="${1#--ids=}"
      shift
      ;;
    --batch-report)
      require_value "$1" "${2-}"
      BATCH_REPORT="$2"
      shift 2
      ;;
    --batch-report=*)
      BATCH_REPORT="${1#--batch-report=}"
      shift
      ;;
    --home)
      require_value "$1" "${2-}"
      HOME_DIR="$2"
      shift 2
      ;;
    --home=*)
      HOME_DIR="${1#--home=}"
      shift
      ;;
    --from-heads)
      FROM_HEADS=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      log "unknown argument: $1"
      usage >&2
      exit 1
      ;;
  esac
done

MODE_COUNT=0
[[ -n "$SPEC_N" ]] && MODE_COUNT=$((MODE_COUNT + 1))
[[ -n "$IDS_RAW" ]] && MODE_COUNT=$((MODE_COUNT + 1))
[[ -n "$BATCH_REPORT" ]] && MODE_COUNT=$((MODE_COUNT + 1))
if [[ "$MODE_COUNT" -ne 1 ]]; then
  log "exactly one of --spec | --ids | --batch-report is required"
  usage >&2
  exit 1
fi

if [[ -z "$HOME_DIR" ]]; then
  HOME_DIR="$(lattice_default_home || echo "${LATTICE_HOME:-.lattice}")"
fi
HOME_DIR="$(cd "$HOME_DIR" 2>/dev/null && pwd)" || {
  log "lattice home not found: pass --home or run inside a repo with .lattice/"
  exit 1
}
REPO_ROOT="$(dirname "$HOME_DIR")"

SPEC_PATH=""
INPUT_DESC=""
TICKET_IDS=()

# --- frontmatter helper (same discipline as tools/validate-skills.sh) ---
frontmatter() {
  awk 'NR==1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
       /^---[[:space:]]*$/ { exit }
       { print }' "$1"
}

normalize_id() {
  local raw="$1"
  raw="${raw#tkt-}"
  raw="${raw//[[:space:]]/}"
  if ! [[ "$raw" =~ ^[1-9][0-9]*$ ]]; then
    log "invalid ticket id: '$1' (want N or tkt-N, N ≥ 1)"
    exit 1
  fi
  printf '%s' "$raw"
}

if [[ -n "$SPEC_N" ]]; then
  SPEC_N="${SPEC_N#spc-}"
  if ! [[ "$SPEC_N" =~ ^[1-9][0-9]*$ ]]; then
    log "--spec wants N or spc-N (got '$SPEC_N')"
    exit 1
  fi
  INPUT_DESC="spec spc-$SPEC_N"
  shopt -s nullglob
  spec_candidates=("$HOME_DIR/specs/spc-$SPEC_N-"*.md "$HOME_DIR/specs/spc-$SPEC_N.md")
  shopt -u nullglob
  SPEC_PATH=""
  for c in "${spec_candidates[@]}"; do
    if [[ -f "$c" ]]; then
      SPEC_PATH="$c"
      break
    fi
  done
  if [[ -z "$SPEC_PATH" ]]; then
    log "spec spc-$SPEC_N not found under $HOME_DIR/specs/"
    exit 1
  fi
  # tickets from front matter `tickets: [tkt-43, tkt-44]` (flow list)
  tickets_line="$(frontmatter "$SPEC_PATH" | grep -E '^tickets:' | head -1 || true)"
  mapfile -t raw_ids < <(printf '%s\n' "$tickets_line" | grep -oE 'tkt-[1-9][0-9]*' || true)
  if [[ "${#raw_ids[@]}" -eq 0 ]]; then
    log "spec $SPEC_PATH front matter lists no tickets — nothing to review"
    exit 1
  fi
  for t in "${raw_ids[@]}"; do
    TICKET_IDS+=("$(normalize_id "$t")")
  done
elif [[ -n "$IDS_RAW" ]]; then
  INPUT_DESC="ids $IDS_RAW"
  IFS=', ' read -r -a raw_ids <<<"$IDS_RAW"
  for t in "${raw_ids[@]}"; do
    [[ -z "$t" ]] && continue
    TICKET_IDS+=("$(normalize_id "$t")")
  done
  if [[ "${#TICKET_IDS[@]}" -eq 0 ]]; then
    log "--ids resolved to an empty ticket set"
    exit 1
  fi
else
  INPUT_DESC="batch-report $BATCH_REPORT"
  if [[ ! -f "$BATCH_REPORT" ]]; then
    log "batch report not found: $BATCH_REPORT"
    exit 1
  fi
  mapfile -t raw_ids < <(grep -oE 'tkt-[1-9][0-9]*' "$BATCH_REPORT" | sort -u -t- -k2,2n || true)
  if [[ "${#raw_ids[@]}" -eq 0 ]]; then
    log "batch report $BATCH_REPORT contains no tkt-N ids"
    exit 1
  fi
  for t in "${raw_ids[@]}"; do
    TICKET_IDS+=("$(normalize_id "$t")")
  done
fi

# --- binder helpers ---

binder_path_for() {
  # stdout: binder README path, or empty when missing
  local id="$1"
  shopt -s nullglob
  local candidates=("$HOME_DIR/tickets/tkt-$id-"*/README.md)
  shopt -u nullglob
  if [[ "${#candidates[@]}" -gt 0 ]]; then
    printf '%s' "${candidates[0]}"
  fi
}

field_row() {
  # $1 file, $2 field name → third cell of the first `| field | value |` row
  local file="$1" field="$2"
  grep -m1 -E "^\|[[:space:]]*${field}[[:space:]]*\|" "$file" 2>/dev/null \
    | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3}' || true
}

section_body() {
  # $1 file, $2 heading text → section body with HTML comments stripped
  local file="$1" heading="$2"
  awk -v h="## ${heading}" '
    index($0, h) == 1 { on = 1; next }
    on && /^## / { exit }
    on { print }
  ' "$file" \
    | awk '
      { gsub(/<!--([^-]|-[^-]|--+[^->])*--+>/, "") }
      /<!--/ { inc = 1 }
      inc { if (/-->/) inc = 0; next }
      { print }
    '
}

section_state() {
  # "present" when the section has non-comment, non-blank content
  local body
  body="$(section_body "$1" "$2" | tr -d '[:space:]')"
  if [[ -n "$body" ]]; then
    printf 'present'
  else
    printf 'empty'
  fi
}

# --- resolve binders (fail loud on any missing one) ---

BINDERS=()
for id in "${TICKET_IDS[@]}"; do
  b="$(binder_path_for "$id")"
  if [[ -z "$b" ]]; then
    log "missing binder for tkt-$id under $HOME_DIR/tickets/ — refuse partial manifest"
    exit 1
  fi
  BINDERS+=("$b")
done

GH_AVAILABLE=false
command -v gh >/dev/null 2>&1 && GH_AVAILABLE=true

# --- --from-heads: read binder state from open PR heads -----------------------
# Stamped state (pr-open, journals) lives on unmerged PR branches; pre-merge,
# the local binder under-reports evidence. `git fetch origin <headRef>` only
# refreshes FETCH_HEAD (read-only for worktree + artifacts); the binder content
# is read with `git show`, never a checkout.
HEADS_TMP=""
if $FROM_HEADS; then
  HEADS_TMP="$(mktemp -d "${TMPDIR:-/tmp}/brc-heads.XXXXXX")"
  trap 'rm -rf "$HEADS_TMP"' EXIT
fi

head_binder_for() {
  # $1 ticket id, $2 local binder path
  # stdout: "<file to read>\t<source label>" — label is head:pr-N (+ref) when
  # the open PR head was fetched and carries the binder, else local (+reason).
  local id="$1" b="$2"
  local prn state headref relpath snap pr_json
  prn="$(field_row "$b" "prs" | grep -oE 'pr-[1-9][0-9]*' | head -1 | cut -d- -f2)" || true
  if [[ -z "$prn" && "$GH_AVAILABLE" == true ]]; then
    prn="$(gh pr list --state open --limit 10 --search "#$id" \
      --json number --template '{{range .}}{{.number}}{{"\n"}}{{end}}' 2>/dev/null \
      | head -1)" || true
  fi
  if [[ -z "$prn" ]]; then
    printf '%s\tlocal (no PR known for tkt-%s)\n' "$b" "$id"
    return 0
  fi
  if ! $GH_AVAILABLE; then
    printf '%s\tlocal (gh unavailable — cannot resolve pr-%s head)\n' "$b" "$prn"
    return 0
  fi
  pr_json="$(gh pr view "$prn" --json state,headRefName 2>/dev/null)" || true
  state="" headref=""
  if [[ -n "${pr_json:-}" ]]; then
    read -r state headref < <(printf '%s' "$pr_json" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print(d.get("state") or "-", d.get("headRefName") or "-")
' 2>/dev/null) || true
  fi
  if [[ "${state:-}" != "OPEN" || -z "${headref:-}" || "$headref" == "-" ]]; then
    printf '%s\tlocal (pr-%s is %s — not an open head)\n' "$b" "$prn" "${state:-unknown}"
    return 0
  fi
  # headRefName feeds a git command line — refuse option-shaped/odd refs.
  if [[ ! "$headref" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]]; then
    printf '%s\tlocal (pr-%s head ref refused: %s)\n' "$b" "$prn" "$headref"
    return 0
  fi
  relpath="${b#"$REPO_ROOT"/}"
  snap="$HEADS_TMP/tkt-$id-head.md"
  if git -C "$REPO_ROOT" fetch --quiet origin "$headref" 2>/dev/null \
    && git -C "$REPO_ROOT" show "FETCH_HEAD:$relpath" >"$snap" 2>/dev/null; then
    printf '%s\thead:pr-%s (%s)\n' "$snap" "$prn" "$headref"
  else
    printf '%s\tlocal (fetch/show failed for pr-%s head %s)\n' "$b" "$prn" "$headref"
  fi
}

# --- emit manifest ---

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '# Review context manifest\n\n'
printf '| Field | Value |\n| --- | --- |\n'
printf '| generated | %s |\n' "$NOW"
printf '| input | %s |\n' "$INPUT_DESC"
printf '| lattice home | %s |\n' "$HOME_DIR"
printf '| spec | %s |\n' "${SPEC_PATH:-(none — ticket-id input)}"
printf '| batch report | %s |\n' "${BATCH_REPORT:-(none)}"
printf '| tickets | %s |\n' "$(printf 'tkt-%s ' "${TICKET_IDS[@]}" | sed 's/ $//')"

printf '\n## ADRs cited\n\n'
scan_files=("${BINDERS[@]}")
[[ -n "$SPEC_PATH" ]] && scan_files+=("$SPEC_PATH")
mapfile -t adr_refs < <(grep -ohE 'ADR-[0-9]{1,3}' "${scan_files[@]}" 2>/dev/null | sort -u || true)
if [[ "${#adr_refs[@]}" -eq 0 ]]; then
  printf -- '- (none cited)\n'
else
  for ref in "${adr_refs[@]}"; do
    num="${ref#ADR-}"
    padded="$(printf '%03d' "$((10#$num))")"
    shopt -s nullglob
    adr_files=("$REPO_ROOT/docs/adr/$padded-"*.md)
    shopt -u nullglob
    if [[ "${#adr_files[@]}" -gt 0 ]]; then
      printf -- '- %s → %s (exists)\n' "$ref" "${adr_files[0]}"
    else
      printf -- '- %s → MISSING under %s/docs/adr/ (artifact-insufficiency candidate)\n' "$ref" "$REPO_ROOT"
    fi
  done
fi

printf '\n## Tickets\n'
GAPS=()
for i in "${!TICKET_IDS[@]}"; do
  id="${TICKET_IDS[$i]}"
  b="${BINDERS[$i]}"
  src_file="$b"
  src_label=""
  if $FROM_HEADS; then
    IFS=$'\t' read -r src_file src_label <<<"$(head_binder_for "$id" "$b")"
  fi
  status_val="$(field_row "$src_file" "status")"
  covers_val="$(field_row "$src_file" "covers")"
  prs_val="$(field_row "$src_file" "prs")"
  blocked_val="$(field_row "$src_file" "blocked_by")"

  printf '\n### tkt-%s\n\n' "$id"
  printf -- '- binder: %s\n' "$b"
  if $FROM_HEADS; then
    printf -- '- binder source: %s\n' "$src_label"
  fi
  printf -- '- status: %s\n' "${status_val:-(no status row)}"
  printf -- '- covers: %s\n' "${covers_val:-(none)}"
  printf -- '- blocked_by: %s\n' "${blocked_val:-(none)}"
  printf -- '- prs (binder row): %s\n' "${prs_val:-(no prs row)}"

  if [[ -z "$prs_val" || "$prs_val" == "(none)" || "$prs_val" == "(none yet)" ]]; then
    if $GH_AVAILABLE; then
      gh_status=0
      gh_out="$(gh pr list --state all --limit 10 --search "#$id" \
        --json number,url,title --template '{{range .}}pr-{{.number}} {{.url}} · {{.title}}{{"\n"}}{{end}}' 2>/dev/null)" || gh_status=$?
      if [[ "$gh_status" -ne 0 ]]; then
        printf -- '- prs (gh fallback): (gh query failed — binder row is the only source)\n'
      elif [[ -n "$gh_out" ]]; then
        printf -- '- prs (gh fallback, verify linkage): %s\n' "$(printf '%s' "$gh_out" | paste -sd'; ' -)"
      else
        printf -- '- prs (gh fallback): (no PR found for #%s)\n' "$id"
      fi
    else
      printf -- '- prs (gh fallback): (gh unavailable — binder row is the only source)\n'
    fi
  fi

  journal_state="$(section_state "$src_file" "Decision journal")"
  pending_state="$(section_state "$src_file" "Pending decisions")"
  attempts_state="$(section_state "$src_file" "Attempts")"
  approach_state="$(section_state "$src_file" "Approach")"
  printf -- '- evidence: approach=%s · decision-journal=%s · pending-decisions=%s · attempts=%s\n' \
    "$approach_state" "$journal_state" "$pending_state" "$attempts_state"

  empties=()
  [[ "$approach_state" == "empty" ]] && empties+=("approach")
  [[ "$journal_state" == "empty" ]] && empties+=("decision-journal")
  [[ "$attempts_state" == "empty" ]] && empties+=("attempts")
  if [[ "${#empties[@]}" -gt 0 ]]; then
    GAPS+=("tkt-$id: $(printf '%s, ' "${empties[@]}" | sed 's/, $//') empty")
  fi
done

printf '\n## Gaps (artifact-insufficiency candidates)\n\n'
if [[ "${#GAPS[@]}" -eq 0 ]]; then
  printf -- '- (none — every binder carries approach + journal + attempts content)\n'
else
  for g in "${GAPS[@]}"; do
    printf -- '- %s\n' "$g"
  done
  printf '\nEmpty journal/attempts on a delivered ticket is not automatically a defect —\n'
  printf 'but the reviewer must decide whether the artifact set explains the delivery.\n'
fi

exit 0
