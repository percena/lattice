#!/usr/bin/env bats
# Docs-truth tests for skills/batch-work prose (tkt-350, ADR-012 §1).
#
# Guards the spawn-brief status-stamping repair: since tkt-339 the
# `ensure-workspace --bind tkt` bind stamps `queued → in-progress` at spawn
# (a second `commit … in-progress` is refused — no `in-progress → in-progress`
# edge) and the L3 status-row hook (tkt-340) rejects a hand edit, so the
# spawn-brief must NOT instruct an agent to stamp `in-progress` by prose.
# `pr-open` is stamped by `after-pr-open.sh` / the PostToolUse hook, not by
# agent hand. A regression that re-introduces a "stamp in-progress" imperative
# to agents sends spawned agents into a dead end on their first step.
#
# Pure grep over checked-in prose; no temp dirs, no network, no gh.

setup_file() {
  SKILL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export SKILL_MD="$SKILL_DIR/SKILL.md"
  export FLOW_MD="$SKILL_DIR/references/flow.md"
  [ -f "$SKILL_MD" ] || { echo "missing $SKILL_MD" >&2; return 1; }
  [ -f "$FLOW_MD" ] || { echo "missing $FLOW_MD" >&2; return 1; }
}

# Print the flow.md spawn-brief BINDER STATUS block (the indented heredoc lines
# that carry the agent-facing status instruction), bounded by the surrounding
# VERIFY-AFTER-MUTATE and DECISION PROTOCOL markers.
binder_status_block() {
  awk '/BINDER STATUS:/{on=1; print; next} on && /^[^ ]/{exit} on{print}' "$FLOW_MD"
}

@test "(a) flow.md BINDER STATUS block tells agents NOT to hand-stamp in-progress" {
  run binder_status_block
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  # The bind stamps in-progress at spawn; the block must say so and forbid a
  # hand stamp.
  grep -qi 'ensure-workspace' <<<"$output"
  grep -qi 'do NOT hand-stamp' <<<"$output"
}

@test "(b) flow.md BINDER STATUS block has no imperative 'stamp in-progress when you start'" {
  run binder_status_block
  [ "$status" -eq 0 ]
  # The pre-fix imperative "stamp the binder field-table status: in-progress
  # when you start" must not return.
  if grep -qiE 'stamp.*in-progress.*when you start' <<<"$output"; then
    echo "regression: agent instructed to stamp in-progress by prose" >&2
    false
  fi
}

@test "(c) SKILL.md does not frame in-progress stamping as an agent 'instruction'" {
  # The spawn-brief contract description must not call status stamping an
  # "instruction" the agent executes for in-progress (the pre-fix wording was
  # "the binder `status` stamping instruction (`in-progress` on start, …)").
  if grep -qiE 'stamping instruction.*in-progress' "$SKILL_MD"; then
    echo "regression: SKILL.md frames in-progress stamping as an agent instruction" >&2
    false
  fi
}

@test "(d) SKILL.md stamps row names the path points, not agents" {
  # The "Binder `status` is stamped" row must name ensure-workspace /
  # after-pr-open.sh as the stampers, not "agents stamp it per their brief".
  row=$(grep -n 'Binder `status` is stamped' "$SKILL_MD" | head -1)
  [ -n "$row" ]
  # Extract the full table row (single line) and assert it names the bind.
  line=$(awk '/^\| Binder `status` is stamped/{print; exit}' "$SKILL_MD")
  grep -qi 'ensure-workspace' <<<"$line"
  grep -qi 'after-pr-open' <<<"$line"
  # The old "agents stamp it per their brief" phrasing must be gone.
  if grep -qF 'agents stamp it per their brief' <<<"$line"; then
    echo "regression: row still says agents stamp status per their brief" >&2
    false
  fi
}
