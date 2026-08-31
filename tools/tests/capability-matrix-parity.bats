#!/usr/bin/env bats
# Capability matrix docs parity (spc-254 A6 / D1, rev-20260830-141357Z F5): the
# README and docs/workflow-fsm.md must state guarantee strength PER call path
# (scripted = hard gate; strict Claude hook = defense-in-depth;
# advisory/uninstalled = detection only) and must NOT claim an unconditional
# global invariant. Reverting the qualified wording to the old overclaim fails
# this suite.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export README="$REPO_ROOT/README.md"
  export FSM_DOC="$REPO_ROOT/docs/workflow-fsm.md"
}

@test "README states the tiered capability matrix (hard gate / defense-in-depth / detection only)" {
  grep -q "fail-closed hard gate" "$README"
  grep -q "defense-in-depth" "$README"
  grep -q "detection only" "$README"
}

@test "README cites ADR-007 §5b and rev-20260830-141357Z F5 for the matrix" {
  grep -q "ADR-007 §5b" "$README"
  grep -q "rev-20260830-141357Z" "$README"
  grep -q "F5" "$README"
}

@test "README no longer claims the unconditional 'chain never skips a step' invariant" {
  # The old overclaim read: "so the chain never skips a step and never loses
  # its lineage" — an unconditional connector. The qualified text may quote
  # the phrase to scope it ("...is true only on the scripted path"), which is
  # acceptable. What must be gone is the unconditional construction.
  run grep -c "so the chain never skips a step" "$README"
  [ "$status" -ne 0 ] || [ "$output" -eq 0 ]
  # And if the phrase survives, it must be immediately qualified.
  if grep -q "chain never skips a step" "$README"; then
    grep -q "chain never skips a step.*only on the scripted path" "$README"
  fi
}

@test "workflow-fsm.md states guarantee strength per call path" {
  grep -q "Hard gate (fail-closed)" "$FSM_DOC"
  grep -q "Defense-in-depth" "$FSM_DOC"
  grep -q "Detection only" "$FSM_DOC"
  grep -q "Strict fail-opens" "$FSM_DOC"
}

@test "workflow-fsm.md qualifies the 'night states never reach merged' invariant (not unconditional)" {
  grep -q "Night states never reach merged on the scripted path" "$FSM_DOC"
  grep -q "unconditional global invariant" "$FSM_DOC"
}

@test "workflow-fsm.md cites ADR-007 §5b and rev-20260830-141357Z F5 for the matrix" {
  grep -q "ADR-007 §5b" "$FSM_DOC"
  grep -q "rev-20260830-141357Z" "$FSM_DOC"
  grep -q "F5" "$FSM_DOC"
}

@test "workflow-fsm.md notes a portable wrapper/CLI would be needed for global enforcement" {
  grep -q "portable wrapper/CLI" "$FSM_DOC"
}
