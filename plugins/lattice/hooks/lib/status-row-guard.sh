#!/usr/bin/env bash
# shellcheck disable=SC2154
# ^ sourced library: abs_path / tool_name / hook_data / file_path are set by the
#   caller (intercept-shippable-write.sh) before the guard function runs (tkt-459
#   NOTICED-drain: lint.yml shellcheck -S warning went red on dev at #456).
# L3-status-row guard (spc-337 A4 / ADR-012 §2)
#
# Sourced by intercept-shippable-write.sh after the L1 location gate allows.
# Expects the following variables from the caller's scope:
#   abs_path, toplevel, tool_name, hook_data, file_path, HOOK_DIR
#
# tkt-356: _status_cell, _status_row_count, and the partial-line edit simulation
# use Python instead of sed/grep/bash-substitution.  Bash 3.2 (macOS) treats `|`
# as extglob alternation in ${var/"$old"/"$new"} even when quoted, corrupting
# the simulated result; BSD sed/grep -E also differ from GNU in edge cases.
# Python is portable, already a hook dependency (jq + python3).  The -c code uses
# single-quote delimiters so the double-quoted regex strings are safe from shell
# expansion; stdin is the text, argv carries substitution arguments.

_status_cell() {  # <text> -> first status cell value on stdout ("" when none)
  local v
  v=$(printf '%s' "$1" | python3 -c '
import sys, re
STATUS_CELL_RE = re.compile(r"^\| *status *\| *([^|]*[^| ]) *\|.*$")
for line in sys.stdin.read().split("\n"):
    m = STATUS_CELL_RE.match(line)
    if m:
        print(m.group(1).strip())
        break
' 2>/dev/null) || v=""
  printf '%s' "${v%%$'\n'*}"
}

_status_row_count() {  # <text> -> number of status rows on stdout
  local n
  n=$(printf '%s' "$1" | python3 -c '
import sys, re
STATUS_ROW_RE = re.compile(r"^\| *status *\| *[^|]*[^| ] *\|")
print(sum(1 for line in sys.stdin.read().split("\n") if STATUS_ROW_RE.match(line)))
' 2>/dev/null) || n="0"
  printf '%s' "${n:-0}"
}

# Simulate a bash string substitution (first-occurrence or replace_all) without
# bash 3.2 glob-alternation corruption on `|`.  <disk> <old> <new> <replace_all>.
_simulate_substitution() {
  printf '%s' "$1" | python3 -c '
import sys
disk = sys.stdin.read()
old, new, replace_all = sys.argv[1], sys.argv[2], sys.argv[3]
count = -1 if replace_all == "true" else 1
sys.stdout.write(disk.replace(old, new, count) if old else disk)
' "$2" "$3" "${4:-false}" 2>/dev/null
}

_status_row_guard() {
  local rel dir tkt old new content new_status ref_status src lib_dir replace_all
  rel=${abs_path#"$toplevel/"}
  [[ "$rel" =~ ^\.lattice/tickets/([^/]+)/README\.md$ ]] || return 0
  dir="${BASH_REMATCH[1]}"
  tkt=$(printf '%s' "$dir" | sed -E 's/^(tkt-[0-9]+).*$/\1/' 2>/dev/null || true)
  tkt="${tkt:-$dir}"

  # `disk` is the current file text; `result` is what the file would hold
  # after the tool ran. The guard compares first status cells, and also
  # refuses a result carrying MORE status rows than the file has (a
  # duplicate-row insert would otherwise shadow the real row).
  local disk="" result="" disk_status="" result_status="" old_n new_n why=""
  case "$tool_name" in
    Edit)
      old=$(printf '%s' "$hook_data" | jq -r '.tool_input.old_string // empty' 2>/dev/null) || old=""
      new=$(printf '%s' "$hook_data" | jq -r '.tool_input.new_string // empty' 2>/dev/null) || new=""
      new_status=$(_status_cell "$new")
      ref_status=$(_status_cell "$old")
      if [[ -n "$ref_status" && -n "$new_status" ]]; then
        # Fast path: both sides carry a complete row -> compare directly
        # (no disk read needed; also covers a file that is not readable).
        src="old_string"
        if [[ "$new_status" != "$ref_status" ]]; then
          why="status changed"
        fi
      fi
      if [[ -z "$why" ]]; then
        # Partial-line edit (review cycle 1): Claude Code's Edit routinely
        # uses a minimal old_string such as `status | queued` or
        # `queued |\n| prs`, neither of which is a complete row. Simulate the
        # edit on the on-disk text — first occurrence, or every occurrence
        # when replace_all is set — and judge the RESULT. Fail open when the
        # file is unreadable, old_string is empty, or old_string does not
        # occur on disk (the Edit tool itself would then fail).
        [[ -n "$old" && -f "$abs_path" ]] || return 0
        disk=$(cat "$abs_path" 2>/dev/null) || return 0
        [[ "$disk" == *"$old"* ]] || return 0
        replace_all=$(printf '%s' "$hook_data" | jq -r '.tool_input.replace_all // false' 2>/dev/null) || replace_all=false
        result=$(_simulate_substitution "$disk" "$old" "$new" "$replace_all")
        disk_status=$(_status_cell "$disk")
        [[ -n "$disk_status" ]] || return 0   # legacy binder without the row
        result_status=$(_status_cell "$result")
        old_n=$(_status_row_count "$disk"); new_n=$(_status_row_count "$result")
        ref_status="$disk_status"; new_status="$result_status"; src="on disk, simulated edit"
        if [[ "$result_status" != "$disk_status" ]]; then
          why="status changed"
        elif [[ "$new_n" -gt "$old_n" ]]; then
          why="duplicate status row inserted ($old_n -> $new_n rows)"
        fi
      fi
      ;;
    Write)
      # File absent -> binder creation, allowed with any status.
      [[ -f "$abs_path" ]] || return 0
      content=$(printf '%s' "$hook_data" | jq -r '.tool_input.content // empty' 2>/dev/null) || content=""
      disk=$(cat "$abs_path" 2>/dev/null) || return 0
      disk_status=$(_status_cell "$disk")
      [[ -n "$disk_status" ]] || return 0   # legacy binder without the row
      new_status=$(_status_cell "$content")
      old_n=$(_status_row_count "$disk"); new_n=$(_status_row_count "$content")
      ref_status="$disk_status"; src="on disk"
      if [[ "$new_status" != "$disk_status" ]]; then
        why="status changed"
      elif [[ "$new_n" -gt "$old_n" ]]; then
        why="duplicate status row inserted ($old_n -> $new_n rows)"
      fi
      ;;
    *) return 0 ;;   # NotebookEdit etc.: no binder row semantics
  esac

  # No finding -> allow (row untouched, same value, nothing to compare).
  [[ -n "$why" ]] || return 0

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
  finding: $why

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
