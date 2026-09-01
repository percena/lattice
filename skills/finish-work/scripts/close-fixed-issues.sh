#!/usr/bin/env bash
# close-fixed-issues.sh — After a PR merges (especially to a non-default base),
# close OPEN delivery issues listed as Fixes/Closes/Resolves on the PR body.
#
# GitHub only auto-closes those keywords when the PR merges into the repository
# default branch. Lattice delivery can land on a non-default base, so
# finish-work closes explicitly after proving the PR is merged.
#
# Usage:
#   close-fixed-issues.sh --pr <N> --expected-closing-ids <csv> [--dry-run] [--json]
#   close-fixed-issues.sh --body-file <path> [--dry-run] [--json]   # parse only; no gh
#   close-fixed-issues.sh --body-stdin [--dry-run] [--json]
#
# Exit:
#   0  all actionable closing-keyword issues are CLOSED, excluded, or dry-run only
#   1  PR is not proven merged, or one or more issue operations failed
#   2  usage / cannot load PR
#
set -euo pipefail

# Fail fast with a friendly install hint if python3 is absent (spc-212 A2/D3).
bash "$(dirname "${BASH_SOURCE[0]}")/../../_lattice-lib/scripts/ensure-python3.sh" || exit 1

PR=""
BODY_FILE=""
BODY_STDIN=false
DRY_RUN=false
AS_JSON=false
EXPECTED_CLOSING_IDS_RAW=""
EXPECTED_CLOSING_IDS_PROVIDED=false
GH_BIN="${GH_BIN:-gh}"

usage() {
  cat <<'EOF' >&2
Usage:
  close-fixed-issues.sh --pr <N> --expected-closing-ids <csv> [--dry-run] [--json]
  close-fixed-issues.sh --body-file <path> [--dry-run] [--json]
  close-fixed-issues.sh --body-stdin [--dry-run] [--json]
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR="${2:-}"; shift 2 ;;
    --body-file) BODY_FILE="${2:-}"; shift 2 ;;
    --body-stdin) BODY_STDIN=true; shift ;;
    --expected-closing-ids) EXPECTED_CLOSING_IDS_RAW="${2-}"; EXPECTED_CLOSING_IDS_PROVIDED=true; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --json) AS_JSON=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

# Parse executable closing directives from prose outside fenced Markdown.
# Bare #N is the supported local-repository form. Repository-qualified forms
# are reported as unsupported rather than silently coerced to local ids.
# Shared implementation: scripts/lib/closing_directives.py.
SCRIPT_DIR_CF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOSING_DIRECTIVES_PY="${SCRIPT_DIR_CF}/lib/closing_directives.py"

extract_directives() {
  local body="$1"
  if [[ ! -f "$CLOSING_DIRECTIVES_PY" ]]; then
    echo "Error: missing closing directive extractor: $CLOSING_DIRECTIVES_PY" >&2
    exit 2
  fi
  printf '%s' "$body" | python3 "$CLOSING_DIRECTIVES_PY"
}

metadata_failure() {
  local reason="$1"
  local message="$2"
  if [[ "$AS_JSON" == true ]]; then
    export CF_META_REASON="$reason"
    export CF_META_MESSAGE="$message"
    export CF_META_PR="$PR"
    export CF_META_DRY="$DRY_RUN"
    python3 - <<'PY'
import json, os
payload = {
    "ok": False,
    "status": "fail",
    "closing_ids": [],
    "closed": [],
    "already_closed": [],
    "skipped_epic": [],
    "failed": [],
    "unsupported_references": [],
    "dry_run": os.environ.get("CF_META_DRY") == "true",
    "reason": os.environ.get("CF_META_REASON") or "pr_metadata_unavailable",
    "note": os.environ.get("CF_META_MESSAGE") or None,
}
pr = os.environ.get("CF_META_PR") or ""
if pr:
    payload["pr"] = int(pr) if pr.isdigit() else pr
print(json.dumps(payload, separators=(",", ":")))
PY
  else
    echo "Error: $message" >&2
  fi
  exit 2
}

BODY=""
PR_URL=""
BASE_REF=""
DEFAULT_REF=""
PR_STATE=""
MERGED_AT=""
REASON=""

if [[ -n "$PR" ]]; then
  if ! command -v "$GH_BIN" >/dev/null 2>&1 && [[ "$GH_BIN" == "gh" ]]; then
    metadata_failure "gh_unavailable" "gh not found"
  fi
  if ! meta=$("$GH_BIN" pr view "$PR" --json body,url,baseRefName,state,mergedAt 2>/dev/null); then
    metadata_failure "pr_metadata_unavailable" "cannot load PR #$PR"
  fi
  if ! parsed_meta=$(printf '%s' "$meta" | python3 -c '
import json,sys,shlex
d=json.load(sys.stdin)
def q(s): return shlex.quote(s if s is not None else "")
print("BODY="+q(d.get("body") or ""))
print("PR_URL="+q(d.get("url") or ""))
print("BASE_REF="+q(d.get("baseRefName") or ""))
print("PR_STATE="+q(d.get("state") or ""))
print("MERGED_AT="+q(d.get("mergedAt") or ""))
' 2>/dev/null); then
    metadata_failure "pr_metadata_invalid" "invalid metadata for PR #$PR"
  fi
  eval "$parsed_meta"
  DEFAULT_REF=$("$GH_BIN" repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo "")
elif [[ -n "$BODY_FILE" ]]; then
  BODY=$(cat "$BODY_FILE")
elif [[ "$BODY_STDIN" == true ]]; then
  BODY=$(cat)
else
  usage
fi

IDS=()
EXPECTED_IDS=()
UNSUPPORTED_REFS=()
# Capture explicitly: with `< <(extract_directives …)` an extractor failure
# (missing lib, broken python3) dies in the subshell and the script would
# report ok:true with zero ids — issues silently stay open.
if ! DIRECTIVES=$(extract_directives "$BODY"); then
  metadata_failure "closing_extractor_failed" \
    "closing directive extractor failed (python3 or lib unavailable); refusing to report zero closing ids"
fi
while IFS=$'\t' read -r kind value; do
  case "$kind" in
    id) [[ -n "$value" ]] && IDS+=("$value") ;;
    unsupported) [[ -n "$value" ]] && UNSUPPORTED_REFS+=("$value") ;;
  esac
done <<< "$DIRECTIVES"

if [[ "$EXPECTED_CLOSING_IDS_PROVIDED" == true ]]; then
  if ! EXPECTED_NORMALIZED=$(python3 - "$EXPECTED_CLOSING_IDS_RAW" <<'PY'
import re
import sys

raw = sys.argv[1].strip()
if not raw:
    print("")
    raise SystemExit(0)
parts = [part for part in re.split(r"[\s,]+", raw) if part]
if any(not part.isdigit() or int(part) < 1 for part in parts):
    print("Error: --expected-closing-ids accepts positive issue numbers separated by commas or spaces", file=sys.stderr)
    raise SystemExit(1)
print(" ".join(str(value) for value in sorted({int(part) for part in parts})))
PY
  ); then
    exit 2
  fi
  read -r -a EXPECTED_IDS <<<"$EXPECTED_NORMALIZED"
fi

CLOSED=()
ALREADY=()
ALREADY_REASONS=()
SKIPPED_EPIC=()
FAILED=()

NOTE="explicit close for Fixes/Closes/Resolves delivery issues"
if [[ -n "$BASE_REF" && -n "$DEFAULT_REF" && "$BASE_REF" != "$DEFAULT_REF" ]]; then
  NOTE="merged to non-default base '$BASE_REF' (default is '$DEFAULT_REF'); GitHub does not auto-close"
elif [[ -n "$BASE_REF" ]]; then
  NOTE="explicit close after land on base '$BASE_REF'"
fi

report() {
  local ok_flag="$1"
  export CF_OK="$ok_flag"
  export CF_IDS="${IDS[*]:-}"
  export CF_EXPECTED_IDS="${EXPECTED_IDS[*]:-}"
  export CF_CLOSED="${CLOSED[*]:-}"
  export CF_ALREADY="${ALREADY[*]:-}"
  export CF_ALREADY_REASONS="${ALREADY_REASONS[*]:-}"
  export CF_SKIPPED_EPIC="${SKIPPED_EPIC[*]:-}"
  export CF_FAILED="${FAILED[*]:-}"
  export CF_UNSUPPORTED="${UNSUPPORTED_REFS[*]:-}"
  export CF_NOTE="$NOTE"
  export CF_REASON="$REASON"
  export CF_PR="${PR:-}"
  export CF_PR_STATE="$PR_STATE"
  export CF_MERGED_AT="$MERGED_AT"
  export CF_BASE="$BASE_REF"
  export CF_DEFAULT="$DEFAULT_REF"
  export CF_DRY="$DRY_RUN"
  export CF_JSON="$AS_JSON"
  python3 - <<'PY'
import json, os

def nums(value):
    return [int(item) for item in (value or "").split() if item.strip().isdigit()]

def words(value):
    return [item for item in (value or "").split() if item]

def reason_map(value):
    result = {}
    for item in (value or "").split():
        if "=" in item:
            k, v = item.split("=", 1)
            if k.strip().isdigit():
                result[int(k)] = v
    return result

ok = os.environ.get("CF_OK") == "true"
already_reasons = reason_map(os.environ.get("CF_ALREADY_REASONS"))
payload = {
    "ok": ok,
    "status": "ok" if ok else "fail",
    "closing_ids": nums(os.environ.get("CF_IDS")),
    "expected_closing_ids": nums(os.environ.get("CF_EXPECTED_IDS")),
    "closed": nums(os.environ.get("CF_CLOSED")),
    "already_closed": nums(os.environ.get("CF_ALREADY")),
    "already_closed_reasons": already_reasons,
    "skipped_epic": nums(os.environ.get("CF_SKIPPED_EPIC")),
    "failed": nums(os.environ.get("CF_FAILED")),
    "unsupported_references": words(os.environ.get("CF_UNSUPPORTED")),
    "dry_run": os.environ.get("CF_DRY") == "true",
    "note": os.environ.get("CF_NOTE") or None,
}
if os.environ.get("CF_REASON"):
    payload["reason"] = os.environ["CF_REASON"]
if os.environ.get("CF_PR"):
    payload["pr"] = int(os.environ["CF_PR"]) if os.environ["CF_PR"].isdigit() else os.environ["CF_PR"]
if os.environ.get("CF_PR_STATE"):
    payload["pr_state"] = os.environ["CF_PR_STATE"]
if os.environ.get("CF_MERGED_AT"):
    payload["merged_at"] = os.environ["CF_MERGED_AT"]
if os.environ.get("CF_BASE"):
    payload["base"] = os.environ["CF_BASE"]
if os.environ.get("CF_DEFAULT"):
    payload["default_branch"] = os.environ["CF_DEFAULT"]

if os.environ.get("CF_JSON") == "true":
    print(json.dumps(payload, separators=(",", ":")))
else:
    print("close-fixed-issues" + (f" PR #{payload.get('pr')}" if payload.get("pr") else ""))
    print(f"  candidates: {' '.join(map(str, payload['closing_ids'])) or '(none)'}")
    if payload["unsupported_references"]:
        print(f"  unsupported_references: {' '.join(payload['unsupported_references'])}")
    if payload["dry_run"]:
        print("  dry_run: true")
    else:
        closed_items = payload['closed']
        print(f"  closed: {' '.join(map(str, closed_items)) or '(none)'}")
        already_items = payload['already_closed']
        if already_items and already_reasons:
            items_str = ' '.join(f"{n} ({already_reasons.get(n, 'unknown')})" for n in already_items)
        else:
            items_str = ' '.join(map(str, already_items))
        print(f"  already_closed: {items_str or '(none)'}")
        print(f"  skipped_epic: {' '.join(map(str, payload['skipped_epic'])) or '(none)'}")
        print(f"  failed: {' '.join(map(str, payload['failed'])) or '(none)'}")
    if payload.get("reason"):
        print(f"  reason: {payload['reason']}")
    if payload.get("note"):
        print(f"  note: {payload['note']}")
    print(f"  status: {payload['status']}")
PY
}

if [[ ${#UNSUPPORTED_REFS[@]} -gt 0 ]]; then
  for reference in "${UNSUPPORTED_REFS[@]}"; do
    echo "close-fixed-issues: unsupported repository-qualified reference skipped: $reference" >&2
  done
fi

# Parsing-only dry runs are intentionally offline. Any live mutation requires
# both the terminal MERGED state and a concrete mergedAt timestamp.
if [[ -n "$PR" && "$DRY_RUN" != true ]]; then
  if [[ "$PR_STATE" != "MERGED" || -z "$MERGED_AT" ]]; then
    REASON="pr_not_merged"
    merge_evidence="absent"
    [[ -n "$MERGED_AT" ]] && merge_evidence="present"
    NOTE="refusing issue mutation: PR state is '${PR_STATE:-unknown}' and mergedAt is $merge_evidence"
    report false
    exit 1
  fi
  if [[ "$EXPECTED_CLOSING_IDS_PROVIDED" != true ]]; then
    REASON="expected_closing_ids_required"
    NOTE="refusing issue mutation without the pre-merge approved closing-id set"
    report false
    exit 1
  fi

  ACTUAL_NORMALIZED="${IDS[*]:-}"
  EXPECTED_NORMALIZED="${EXPECTED_IDS[*]:-}"
  if [[ "$ACTUAL_NORMALIZED" != "$EXPECTED_NORMALIZED" ]]; then
    REASON="closing_set_changed"
    NOTE="refusing issue mutation: current PR closing ids differ from the pre-merge approved set"
    report false
    exit 1
  fi
fi

if [[ ${#IDS[@]} -eq 0 ]]; then
  report true
  exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
  report true
  exit 0
fi

if [[ -z "$PR" ]]; then
  echo "Error: --body-file/--body-stdin only support --dry-run (no live close without --pr)" >&2
  exit 2
fi

COMMENT="Landed in ${PR_URL:-PR #$PR}."
COMMENT+=" $NOTE."
COMMENT+=" Closed explicitly by finish-work (close-fixed-issues.sh)."

for id in "${IDS[@]}"; do
  issue_meta=$("$GH_BIN" issue view "$id" --json state,labels 2>/dev/null) || {
    FAILED+=("$id")
    echo "close-fixed-issues: cannot load issue #$id" >&2
    continue
  }
  ISSUE_STATE=""
  ISSUE_EPIC=false
  eval "$(printf '%s' "$issue_meta" | python3 -c '
import json,sys,shlex
d=json.load(sys.stdin)
labels=d.get("labels") or []
names={str(item.get("name") or "").lower() for item in labels if isinstance(item,dict)}
print("ISSUE_STATE="+shlex.quote(d.get("state") or ""))
print("ISSUE_EPIC="+("true" if "epic" in names else "false"))
')"

  if [[ "$ISSUE_EPIC" == true ]]; then
    SKIPPED_EPIC+=("$id")
    echo "close-fixed-issues: skipping Spec primary / epic issue #$id" >&2
    continue
  fi
  if [[ "$ISSUE_STATE" == "CLOSED" ]]; then
    ALREADY+=("$id")
    # Fetch close reason for awareness (tkt-294). state_reason is not a
    # gh issue view --json field on all gh versions; use REST.
    close_reason=""
    if [[ -n "$PR_URL" ]]; then
      repo_base=$(printf '%s' "$PR_URL" | sed -E 's#https?://[^/]+/([^/]+/[^/]+)/pull/.*#\1#')
      if [[ -n "$repo_base" ]]; then
        if ! close_reason=$("$GH_BIN" api "repos/${repo_base}/issues/${id}" --jq '.state_reason' 2>/dev/null); then
          echo "close-fixed-issues: WARNING — cannot fetch state_reason for issue #$id (REST API failed)" >&2
        fi
      fi
    fi
    if [[ -n "$close_reason" ]]; then
      echo "close-fixed-issues: issue #$id already CLOSED (reason: $close_reason)" >&2
    else
      echo "close-fixed-issues: issue #$id already CLOSED" >&2
    fi
    ALREADY_REASONS+=("${id}=${close_reason:-unknown}")
    continue
  fi
  if [[ "$ISSUE_STATE" != "OPEN" ]]; then
    FAILED+=("$id")
    echo "close-fixed-issues: cannot determine state for #$id ($ISSUE_STATE)" >&2
    continue
  fi
  if "$GH_BIN" issue close "$id" --comment "$COMMENT" >/dev/null 2>&1; then
    CLOSED+=("$id")
  else
    FAILED+=("$id")
    echo "close-fixed-issues: failed to close #$id" >&2
  fi
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
  REASON="issue_operation_failed"
  report false
  exit 1
fi
report true
exit 0
