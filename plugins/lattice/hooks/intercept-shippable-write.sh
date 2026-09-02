#!/usr/bin/env bash
# PreToolUse (Write/Edit): block shippable writes when the cwd is not a
# shippable workspace. Runs assert-shippable-cwd.sh before writes to the core
# L0 delivery artifacts (.lattice/specs|tickets|lineage) and tracked product
# code, denying on fail. This is the L3 asset-protection backstop: even if an
# agent evades L1 (git-branch hook) onto a pre-existing non-base branch in the
# main clone, the WRITE is blocked at the moment it touches a shippable asset.
#
# Scope (kept narrow to avoid false positives and preserve documented exemptions):
#   gated  — .lattice/specs/**, .lattice/tickets/**, .lattice/lineage/**,
#            and files tracked by git (existing product code)
#   exempt — .lattice/reviews/** (create-review may write on team base),
#            docs/adr/** (ADR-only durable doc; ADR skill allows base write),
#            new untracked files outside the gated L0 dirs (scratch),
#            anything outside the repo working tree
#
# L3 does NOT trust the L1 sentinel — it calls assert directly, so it is the
# spoof-resistant backstop.
#
# Second rule, L3-status-row (spc-337 A4 / ADR-012 §2): once the location gate
# allows, an Edit/Write on `.lattice/tickets/<dir>/README.md` that would CHANGE
# the binder's `| status |` row value is denied and the transition command
# (`transition-api.py commit …`) is named. Other rows/sections, new-binder
# creation, and unchanged-status writes pass.
#
# Delivery contract: block -> exit 2 + stderr advice; allow -> exit 0.
# Fail OPEN on ambiguity (missing jq/git, non-Write/Edit tool, parse failure).
set -euo pipefail

hook_data=$(cat)

# tkt-239: a missing required dependency makes this gate silently inert. Keep
# fail-open (don't break missing-dep envs) but emit a once-per-session stderr
# advisory so the gap is visible rather than silent. Sentinel is keyed by
# session_id (extracted without jq, since jq may be the missing dep).
_lattice_dep_advisory() {
  local missing="$1" sid sentinel
  sid=$(printf '%s' "$hook_data" 2>/dev/null \
    | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null \
    | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null \
    || true)
  sentinel="${TMPDIR:-/tmp}/lattice-hook-dep-missing-${sid:-default}"
  if [[ -e "$sentinel" ]]; then return 0; fi
  { : > "$sentinel"; } 2>/dev/null || true
  cat >&2 <<EOF
lattice: enforcement hook inert — required dependency (${missing}) not found on PATH.
  The strict-profile L3 shippable-write gate cannot enforce; writes to
  .lattice/specs|tickets|lineage and tracked product code will be ALLOWED.
  Install the missing dependency to restore protection.
  (advisory only, not a block; printed once per session)
EOF
}

if ! command -v jq >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  _missing=""
  command -v jq >/dev/null 2>&1 || _missing="jq"
  command -v git >/dev/null 2>&1 || _missing="${_missing:+$_missing }git"
  _lattice_dep_advisory "$_missing"
  exit 0
fi

# Unparseable hook input (truncated/invalid JSON) -> fail OPEN with a one-line
# advisory instead of aborting under `set -e` with jq's exit code (tkt-340).
if ! tool_name=$(printf '%s' "$hook_data" | jq -r '.tool_name // empty' 2>/dev/null); then
  echo "lattice: L3 shippable-write hook could not parse its input JSON — allowing (fail-open, advisory)." >&2
  exit 0
fi
case "$tool_name" in
  Write|Edit|NotebookEdit) ;;
  *) exit 0 ;;
esac

file_path=$(printf '%s' "$hook_data" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' 2>/dev/null)
[[ -n "$file_path" ]] || exit 0

hook_cwd=$(printf '%s' "$hook_data" | jq -r '.cwd // empty' 2>/dev/null)
[[ -n "$hook_cwd" ]] || hook_cwd="$PWD"

# Resolve repo root / toplevel for the cwd.
if ! toplevel=$(git -C "$hook_cwd" rev-parse --show-toplevel 2>/dev/null); then
  exit 0  # not in a git work tree -> allow
fi

# Make the target path absolute (relative paths resolve against cwd) before
# canonicalization.
abs_path="$file_path"
[[ "$abs_path" = /* ]] || abs_path="$hook_cwd/$abs_path"

# Resolve symlinks so the path matches git's physical toplevel (macOS /tmp ->
# /private/tmp, etc.). Write may target a not-yet-created file, so resolve the
# longest existing ancestor and append the non-existent tail.
canonicalize() {
  local p="$1" parent base
  if [[ -e "$p" ]]; then
    if command -v realpath >/dev/null 2>&1; then realpath "$p" 2>/dev/null || printf '%s' "$p"
    else printf '%s' "$p"; fi
    return
  fi
  parent=$(dirname "$p"); base=$(basename "$p")
  local depth=0
  while [[ ! -d "$parent" && $depth -lt 64 ]]; do
    base=$(basename "$parent")/$base
    parent=$(dirname "$parent")
    depth=$((depth+1))
  done
  local resolved
  if command -v realpath >/dev/null 2>&1 && [[ -d "$parent" ]]; then
    resolved=$(realpath "$parent" 2>/dev/null || printf '%s' "$parent")
  else
    resolved="$parent"
  fi
  printf '%s/%s' "$resolved" "$base"
}
abs_path=$(canonicalize "$abs_path")
# Canonicalize the toplevel the same way so both share a physical form.
toplevel=$(canonicalize "$toplevel")

shippable=false
case "$abs_path" in
  "$toplevel/.lattice/specs/"*|"$toplevel/.lattice/tickets/"*|"$toplevel/.lattice/lineage/"*)
    shippable=true ;;
  "$toplevel/.lattice/reviews/"*|"$toplevel/docs/adr/"*)
    shippable=false ;;   # documented base-write exemption
  "$toplevel/"*)
    # Inside the repo but not a gated L0 dir: gate only if git tracks it
    # (modifying existing product code). New untracked files are allowed.
    rel=${abs_path#"$toplevel/"}
    if git -C "$toplevel" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
      shippable=true
    fi
    ;;
  *) shippable=false ;;  # outside the repo (scratch)
esac

if [[ "$shippable" != "true" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# L3-status-row (spc-337 A4 / ADR-012 §2): the `| status |` row of a ticket
# binder is written only by the path-point scripts through the transition API
# (ensure-workspace --bind, stamp-pr-open, finish-ledger, batch barrier,
# morning-triage `transition-api.py commit`). Scripts run via Bash and never
# pass through this Write/Edit hook, so an Edit/Write that would CHANGE the
# status value is refused here and the legal command is named.
#
# Runs only after the location gate above has decided to ALLOW (so the
# existing gate behaviour for every other path is unchanged). Fail OPEN on
# anything unparseable: no status row in the new text -> nothing to compare.
#
# Same row grammar as transition-api.py `_FIELD_RE_TMPL` / binder_rows.py:
# first `| status | <value> |` cell, cell value trimmed; an empty cell counts
# as "no status row".
# ---------------------------------------------------------------------------
_status_cell() {  # <text> -> first status cell value on stdout ("" when none)
  local v
  v=$(printf '%s\n' "$1" \
      | sed -n -E 's/^\| *status *\| *([^|]*[^| ]) *\|.*$/\1/p' 2>/dev/null) || v=""
  printf '%s' "${v%%$'\n'*}"
}

_status_row_guard() {
  local rel dir tkt old new content new_status ref_status src lib_dir
  rel=${abs_path#"$toplevel/"}
  [[ "$rel" =~ ^\.lattice/tickets/([^/]+)/README\.md$ ]] || return 0
  dir="${BASH_REMATCH[1]}"
  tkt=$(printf '%s' "$dir" | sed -E 's/^(tkt-[0-9]+).*$/\1/' 2>/dev/null || true)
  tkt="${tkt:-$dir}"

  case "$tool_name" in
    Edit)
      old=$(printf '%s' "$hook_data" | jq -r '.tool_input.old_string // empty' 2>/dev/null) || old=""
      new=$(printf '%s' "$hook_data" | jq -r '.tool_input.new_string // empty' 2>/dev/null) || new=""
      new_status=$(_status_cell "$new")
      ref_status=$(_status_cell "$old")
      if [[ -n "$ref_status" ]]; then
        src="old_string"
      else
        # Only new_string carries a status row: compare against the on-disk
        # value (an Edit cannot create the file, so absent-on-disk -> allow).
        [[ -n "$new_status" && -f "$abs_path" ]] || return 0
        ref_status=$(_status_cell "$(cat "$abs_path" 2>/dev/null || true)")
        src="on disk"
      fi
      ;;
    Write)
      # File absent -> binder creation, allowed with any status.
      [[ -f "$abs_path" ]] || return 0
      content=$(printf '%s' "$hook_data" | jq -r '.tool_input.content // empty' 2>/dev/null) || content=""
      new_status=$(_status_cell "$content")
      ref_status=$(_status_cell "$(cat "$abs_path" 2>/dev/null || true)")
      src="on disk"
      ;;
    *) return 0 ;;   # NotebookEdit etc.: no binder row semantics
  esac

  # Nothing to compare against -> allow (legacy binder without the row, or
  # the edit does not touch the row at all).
  [[ -n "$ref_status" ]] || return 0
  # Same value (or the row is untouched) -> allow. A removed row (new text
  # has no status cell while the reference had one) counts as a change.
  [[ "$new_status" != "$ref_status" ]] || return 0

  lib_dir="…/skills/_lattice-lib/scripts"
  for cand in \
    "${CLAUDE_PLUGIN_ROOT:-$HOOK_DIR}/../../skills/_lattice-lib/scripts" \
    "$toplevel/skills/_lattice-lib/scripts" \
    "$HOOK_DIR/../../../skills/_lattice-lib/scripts"
  do
    if [[ -f "$cand/transition-api.py" ]]; then
      lib_dir=$(cd "$cand" 2>/dev/null && pwd) || lib_dir="$cand"
      break
    fi
  done

  cat >&2 <<EOF
lattice: ticket-binder status-row edit blocked (rule L3-status-row).

  target:  $file_path
  status:  '${ref_status}' ($src) -> '${new_status:-<row removed>}'

ADR-012 §2: the binder \`| status |\` row is written only by the path-point
scripts through the transition API — never by a direct Edit/Write. Edits to
every other row/section, and creation of a new binder, are allowed. To move
this ticket's state, run the transition command instead:

  python3 $lib_dir/transition-api.py commit $tkt <to> <owner> <reason> --binder $file_path

  e.g. python3 $lib_dir/transition-api.py commit $tkt ${new_status:-<to>} agent block --binder $file_path

Side states (stuck/deferred) take --wait-reason <unblock|decision|deps|review>.
EOF
  exit 2
}

# Locate assert-shippable-cwd.sh: prefer the co-installed skills tree beside
# the plugin, fall back to the git toplevel's skills/ dir, else fail open.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSERT=""
for cand in \
  "${CLAUDE_PLUGIN_ROOT:-$HOOK_DIR}/../../skills/_lattice-lib/scripts/assert-shippable-cwd.sh" \
  "$toplevel/skills/_lattice-lib/scripts/assert-shippable-cwd.sh" \
  "$HOOK_DIR/../../../skills/_lattice-lib/scripts/assert-shippable-cwd.sh"
do
  if [[ -n "$cand" && -f "$cand" ]]; then ASSERT="$cand"; break; fi
done
if [[ -z "$ASSERT" ]]; then _status_row_guard; exit 0; fi

# Run the gate from the agent's cwd. Gate on the exit code (robust against
# jq's `//` treating boolean false as empty): 0 = ok (allow); 1 = fail (block);
# 2 = usage/parse error (fail OPEN — not a policy denial). Parse reason only
# for the denial message. The `if` form suspends `set -e` so a failed assert
# (rc 1) is handled instead of aborting the script.
if assert_out=$(cd "$hook_cwd" 2>/dev/null && bash "$ASSERT" --json 2>/dev/null); then
  _status_row_guard   # location allowed -> L3-status-row check (exit 2 on change)
  exit 0
else
  assert_rc=$?
  [[ "$assert_rc" -eq 1 ]] || { _status_row_guard; exit 0; }   # usage/other -> fail open
fi

# jq failures are non-fatal: empty assert output (e.g. cwd worktree removed
# mid-session) or partial JSON must not abort before the remediation block
# prints. Default reason to "unknown" when jq produces no usable value (tkt-326).
reason=$(printf '%s' "$assert_out" | jq -r '.reason // "unknown"' 2>/dev/null || true)
reason="${reason:-unknown}"
branch=$(printf '%s' "$assert_out" | jq -r '.branch // ""' 2>/dev/null || true)
cat >&2 <<EOF
lattice: shippable write blocked — cwd is not a shippable workspace.

  target:  $file_path
  cwd:     $hook_cwd (${branch:-detached})
  reason:  $reason

Under strict profile, Specs / ticket binders / lineage / tracked product code
must be written inside a bound worktree, not on the main clone. Use:

  /start-work                                          (ticket + worktree)
  bash …/ensure-workspace.sh --mode worktree --bind tkt --id <N> --slug <slug>

For a non-standard flow (authorized direct write on the main clone), ASK THE
USER first, then the skill routes through the audited escape:

  assert-shippable-cwd.sh --allow-base-write --reason "user-authorized: <why>"

Reviews (.lattice/reviews/) and ADRs (docs/adr/) are exempt and may be written
on the team base.
EOF
exit 2
