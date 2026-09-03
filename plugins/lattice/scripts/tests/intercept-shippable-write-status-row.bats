#!/usr/bin/env bats
# L3-status-row guard tests for intercept-shippable-write.sh (spc-337 A4 /
# ADR-012 §2, tkt-340): an Edit/Write on `.lattice/tickets/<dir>/README.md`
# that would CHANGE the `| status |` row value is denied (exit 2) with the
# transition command named; other rows, binder creation, unchanged-status
# Write and malformed input pass (exit 0).
#
# All writes run from a linked worktree so the existing location gate ALLOWS
# and only the status-row rule decides. The last test checks ordering: on the
# main clone the location gate still denies first.

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK_SCRIPT="$SCRIPT_DIR/hooks/intercept-shippable-write.sh"

  TDIR="$(mktemp -d)"
  MAIN_ROOT="$TDIR/main"
  git init -q "$MAIN_ROOT"
  git -C "$MAIN_ROOT" symbolic-ref HEAD refs/heads/main
  git -C "$MAIN_ROOT" config user.email t@t.test
  git -C "$MAIN_ROOT" config user.name t
  git -C "$MAIN_ROOT" commit -q --allow-empty -m init
  mkdir -p "$MAIN_ROOT/.lattice"
  printf 'profile: strict\n' >"$MAIN_ROOT/.lattice/config.yaml"
  git -C "$MAIN_ROOT" add -A
  git -C "$MAIN_ROOT" commit -q -m files
  git -C "$MAIN_ROOT" worktree add -q "$MAIN_ROOT.wt" -b feat-wt

  WT="$MAIN_ROOT.wt"
  BINDER_DIR="$WT/.lattice/tickets/tkt-7-demo"
  BINDER="$BINDER_DIR/README.md"
  mkdir -p "$BINDER_DIR"
  write_binder "$BINDER" queued
}

teardown() {
  git -C "$MAIN_ROOT" worktree remove --force "$MAIN_ROOT.wt" 2>/dev/null || true
  rm -rf "$TDIR" "$MAIN_ROOT.wt" 2>/dev/null || true
}

# A minimal binder with the field table the real template emits.
write_binder() {  # <path> <status>
  cat >"$1" <<EOF
# tkt-7-demo

> note: queued for wave W1

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| status | $2 |
| fix_cycles | 0 |
| prs | (none) |

## Decision journal

- 2026-09-02 seed
EOF
}

run_edit() {  # <cwd> <file_path> <old_string> <new_string>
  jq -cn --arg w "$1" --arg f "$2" --arg o "$3" --arg n "$4" \
    '{tool_name:"Edit",tool_input:{file_path:$f,old_string:$o,new_string:$n},cwd:$w}' \
    | bash "$HOOK_SCRIPT" 2>&1
}

run_write() {  # <cwd> <file_path> <content>
  jq -cn --arg w "$1" --arg f "$2" --arg c "$3" \
    '{tool_name:"Write",tool_input:{file_path:$f,content:$c},cwd:$w}' \
    | bash "$HOOK_SCRIPT" 2>&1
}

assert_status_row_denied() {  # <status> <output>
  [ "$1" -eq 2 ]
  printf '%s\n' "$2" | grep -qF "L3-status-row"
  printf '%s\n' "$2" | grep -qF "ADR-012"
  printf '%s\n' "$2" | grep -qE 'transition-api\.py commit tkt-7 <to> <owner> <reason> --binder '
}

# ===================== DENY: status value changes =====================

@test "edit: denies status change (old_string vs new_string differ on the row)" {
  run run_edit "$WT" "$BINDER" "| status | queued |" "| status | closed |"
  assert_status_row_denied "$status" "$output"
  printf '%s\n' "$output" | grep -qF "'queued' (old_string) -> 'closed'"
}

@test "edit: denies status change inside a larger block edit" {
  run run_edit "$WT" "$BINDER" \
    $'| priority | P2 |\n| status | queued |' \
    $'| priority | P1 |\n| status | in-progress |'
  assert_status_row_denied "$status" "$output"
}

@test "edit: denies when only new_string carries a status row that differs from disk" {
  run run_edit "$WT" "$BINDER" "| fix_cycles | 0 |" $'| fix_cycles | 0 |\n| status | closed |'
  assert_status_row_denied "$status" "$output"
  printf '%s\n' "$output" | grep -qF "(on disk, simulated edit)"
}

@test "edit: denies removing the status row (old has it, new does not)" {
  run run_edit "$WT" "$BINDER" "| status | queued |" "| state | queued |"
  assert_status_row_denied "$status" "$output"
  printf '%s\n' "$output" | grep -qF "<row removed>"
}

@test "write: denies rewriting an existing binder with a different status" {
  local content
  content=$(printf '| Field | Value |\n| --- | --- |\n| kind | feat |\n| status | closed |\n')
  run run_write "$WT" "$BINDER" "$content"
  assert_status_row_denied "$status" "$output"
  printf '%s\n' "$output" | grep -qF "'queued' (on disk) -> 'closed'"
}

@test "deny message derives <tkt> from the binder dir and tolerates loose cell spacing" {
  local d="$WT/.lattice/tickets/tkt-12-some-long-slug"
  mkdir -p "$d"
  printf '| Field | Value |\n| --- | --- |\n|  status  |   queued   |\n' >"$d/README.md"
  run run_edit "$WT" "$d/README.md" "|  status  |   queued   |" "| status | pr-open |"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qE 'transition-api\.py commit tkt-12 <to>'
  printf '%s\n' "$output" | grep -qF "'queued' (old_string) -> 'pr-open'"
}

# ---- partial-line Edits (review cycle 1): the guard simulates the edit on disk ----

@test "edit: denies partial-line status change (old_string lacks the leading pipe)" {
  run run_edit "$WT" "$BINDER" "status | queued" "status | closed"
  assert_status_row_denied "$status" "$output"
  printf '%s\n' "$output" | grep -qF "'queued' (on disk, simulated edit) -> 'closed'"
}

@test "edit: denies partial-line status change spanning into the next row" {
  run run_edit "$WT" "$BINDER" $'queued |\n| fix_cycles' $'closed |\n| fix_cycles'
  assert_status_row_denied "$status" "$output"
  printf '%s\n' "$output" | grep -qF "finding: status changed"
}

@test "edit: denies bare-word status change with replace_all (row is a later occurrence)" {
  run bash -c "jq -cn --arg w '$WT' --arg f '$BINDER' \
    '{tool_name:\"Edit\",tool_input:{file_path:\$f,old_string:\"queued\",new_string:\"closed\",replace_all:true},cwd:\$w}' \
    | '$HOOK_SCRIPT' 2>&1"
  assert_status_row_denied "$status" "$output"
}

@test "edit: allows bare-word replacement whose FIRST occurrence is not the status row" {
  # Without replace_all the Edit tool replaces only the first `queued`, which
  # is in the note line above the table; the status row is untouched.
  run run_edit "$WT" "$BINDER" "queued" "closed"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "edit: allows a partial-line edit in the status row region that leaves the value intact" {
  run run_edit "$WT" "$BINDER" $'queued |\n| fix_cycles | 0 |' $'queued |\n| fix_cycles | 1 |'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "edit: denies inserting a duplicate status row (same value, second row)" {
  run run_edit "$WT" "$BINDER" "| fix_cycles | 0 |" $'| fix_cycles | 0 |\n| status | queued |'
  assert_status_row_denied "$status" "$output"
  printf '%s\n' "$output" | grep -qF "duplicate status row inserted (1 -> 2 rows)"
}

@test "write: denies content carrying two status rows" {
  local content
  content=$(printf '| Field | Value |\n| --- | --- |\n| status | queued |\n| kind | feat |\n| status | closed |\n')
  run run_write "$WT" "$BINDER" "$content"
  assert_status_row_denied "$status" "$output"
  printf '%s\n' "$output" | grep -qF "duplicate status row inserted (1 -> 2 rows)"
}

@test "edit: fail-open when old_string does not occur on disk (the Edit tool would fail anyway)" {
  run run_edit "$WT" "$BINDER" "status | nope" "status | closed"
  [ "$status" -eq 0 ]
}

@test "edit: fail-open on a partial-line edit when the file is missing" {
  run run_edit "$WT" "$WT/.lattice/tickets/tkt-77-missing/README.md" "status | queued" "status | closed"
  [ "$status" -eq 0 ]
}

# ===================== ALLOW =====================

@test "edit: allows a change to another row (priority)" {
  run run_edit "$WT" "$BINDER" "| priority | P2 |" "| priority | P1 |"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "edit: allows a block edit that carries the status row unchanged" {
  run run_edit "$WT" "$BINDER" \
    $'| priority | P2 |\n| status | queued |\n| fix_cycles | 0 |' \
    $'| priority | P1 |\n| status | queued |\n| fix_cycles | 1 |'
  [ "$status" -eq 0 ]
}

@test "edit: allows appending to a section (no status row involved)" {
  run run_edit "$WT" "$BINDER" "- 2026-09-02 seed" $'- 2026-09-02 seed\n- 2026-09-02 chose X (chain #5)'
  [ "$status" -eq 0 ]
}

@test "write: allows creating a new binder file with any status" {
  run run_write "$WT" "$WT/.lattice/tickets/tkt-9-new/README.md" \
    "$(printf '| Field | Value |\n| --- | --- |\n| status | closed |\n')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "write: allows rewriting an existing binder when the status is unchanged" {
  local content
  content=$(printf '| Field | Value |\n| --- | --- |\n| kind | feat |\n| priority | P1 |\n| status | queued |\n')
  run run_write "$WT" "$BINDER" "$content"
  [ "$status" -eq 0 ]
}

@test "write: allows when the on-disk binder has no status row (legacy)" {
  printf '| Field | Value |\n| --- | --- |\n| kind | feat |\n' >"$BINDER"
  run run_write "$WT" "$BINDER" "$(printf '| Field | Value |\n| --- | --- |\n| status | closed |\n')"
  [ "$status" -eq 0 ]
}

@test "allows status-looking edits on non-README files under .lattice/tickets/" {
  run run_edit "$WT" "$BINDER_DIR/notes.md" "| status | queued |" "| status | closed |"
  [ "$status" -eq 0 ]
  # and on a README nested deeper than <dir>/README.md
  mkdir -p "$BINDER_DIR/sub"
  run run_edit "$WT" "$BINDER_DIR/sub/README.md" "| status | queued |" "| status | closed |"
  [ "$status" -eq 0 ]
}

@test "allows a status change on a Spec file (rule is ticket-binder only)" {
  mkdir -p "$WT/.lattice/specs"
  printf 'status: draft\n| status | draft |\n' >"$WT/.lattice/specs/spc-1.md"
  run run_edit "$WT" "$WT/.lattice/specs/spc-1.md" "| status | draft |" "| status | done |"
  [ "$status" -eq 0 ]
}

# ===================== fail-open: malformed input =====================

@test "fail-open: truncated JSON input exits 0 with an advisory" {
  run bash -c "printf '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"%s\"' '$BINDER' | '$HOOK_SCRIPT' 2>&1"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "could not parse"
}

@test "fail-open: Edit with non-string old_string/new_string exits 0" {
  run bash -c "jq -cn --arg w '$WT' --arg f '$BINDER' \
    '{tool_name:\"Edit\",tool_input:{file_path:\$f,old_string:{a:1},new_string:[1,2]},cwd:\$w}' \
    | '$HOOK_SCRIPT' 2>&1"
  [ "$status" -eq 0 ]
}

@test "fail-open: Edit payload without old_string/new_string exits 0" {
  run bash -c "jq -cn --arg w '$WT' --arg f '$BINDER' \
    '{tool_name:\"Edit\",tool_input:{file_path:\$f},cwd:\$w}' | '$HOOK_SCRIPT' 2>&1"
  [ "$status" -eq 0 ]
}

# ===================== ordering: location gate first =====================

@test "main clone: location gate denies before the status-row rule runs" {
  git -C "$MAIN_ROOT" checkout -q -b drift-branch
  mkdir -p "$MAIN_ROOT/.lattice/tickets/tkt-7-demo"
  write_binder "$MAIN_ROOT/.lattice/tickets/tkt-7-demo/README.md" queued
  run run_edit "$MAIN_ROOT" "$MAIN_ROOT/.lattice/tickets/tkt-7-demo/README.md" \
    "| status | queued |" "| status | closed |"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "shippable write blocked"
  if printf '%s\n' "$output" | grep -qF "L3-status-row"; then false; fi
}
