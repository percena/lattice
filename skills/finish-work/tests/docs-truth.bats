#!/usr/bin/env bats
# Docs-truth tests for skills/finish-work prose (tkt-341, spc-337 A5).
#
# Guards the four finish-work prose repairs from rev-20260902-015425Z F4 so the
# SKILL/flow text cannot drift back away from its scripts:
#   (a) flow.md §7 LAYER LOOP proves each multi-PR merge with
#       `verify-main-chain.sh --stage merge`, never `verify-mutation.sh --pr`
#       (whose default rejects MERGED — rev-20260831 F4).
#   (b) the batch-work marker lives at the out-of-repo state home
#       (`lattice-state-home.sh`, ADR-011 / spc-282 A1), not "MAIN clone `.lattice/`".
#   (c) SKILL.md names `ci-gate-check.sh` (spc-186 A6 hard rule).
#   (d) SKILL.md carries the explicit pre-merge base-tip capture
#       (`git ls-remote origin refs/heads/<base>`).
#
# Pure grep over checked-in prose; no temp dirs, no network, no gh.

setup_file() {
  SKILL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export SKILL_MD="$SKILL_DIR/SKILL.md"
  export FLOW_MD="$SKILL_DIR/references/flow.md"
  [ -f "$SKILL_MD" ] || { echo "missing $SKILL_MD" >&2; return 1; }
  [ -f "$FLOW_MD" ] || { echo "missing $FLOW_MD" >&2; return 1; }
}

# Print flow.md §7 only: from the "## 7." heading up to (not including) the
# next level-2 heading.
flow_section_7() {
  awk '/^## 7\. /{on=1; print; next} on && /^## /{exit} on{print}' "$FLOW_MD"
}

@test "flow.md has a §7 multi-PR section with a LAYER LOOP (precondition)" {
  run flow_section_7
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  grep -q '^### LAYER LOOP' <<<"$output"
}

@test "(a) flow.md §7 does not verify a merge with verify-mutation.sh --pr" {
  run flow_section_7
  [ "$status" -eq 0 ]
  ! grep -qF 'verify-mutation.sh --pr' <<<"$output"
}

@test "(a) flow.md §7 proves each merge with verify-main-chain.sh --stage merge + captured base tip" {
  run flow_section_7
  [ "$status" -eq 0 ]
  grep -qF 'verify-main-chain.sh" --stage merge' <<<"$output"
  grep -qF -- '--expected-oid "$BASE_TIP"' <<<"$output"
  grep -qE 'BASE_TIP=\$\(git ls-remote origin "?refs/heads/' <<<"$output"
}

@test "(b) SKILL.md no longer places the batch marker at MAIN clone .lattice/" {
  ! grep -qF 'MAIN clone `.lattice/`' "$SKILL_MD"
}

@test "(b) flow.md no longer places the batch marker at MAIN clone .lattice/" {
  ! grep -qF 'MAIN clone `.lattice/`' "$FLOW_MD"
}

@test "(b) SKILL.md names the out-of-repo state home for the batch marker (ADR-011)" {
  grep -qF 'lattice-state-home.sh' "$SKILL_MD"
  grep -qF 'ADR-011' "$SKILL_MD"
  grep -qF '/.batch-work-active' "$SKILL_MD"
}

@test "(c) SKILL.md names ci-gate-check.sh in the Finish-cycle checklist and the short path" {
  grep -qF 'ci-gate-check.sh' "$SKILL_MD"
  # checklist row (a `- [ ]` line) and a numbered short-path step both carry it
  grep -qE '^- \[ \] .*ci-gate-check\.sh' "$SKILL_MD"
  grep -qE '^[0-9]+\. .*ci-gate-check\.sh' "$SKILL_MD"
}

@test "(d) SKILL.md short path captures the pre-merge base tip explicitly" {
  grep -qF 'ls-remote' "$SKILL_MD"
  grep -qF 'refs/heads' "$SKILL_MD"
  grep -qE '^[0-9]+\. .*BASE_TIP=\$\(git ls-remote origin "?refs/heads/' "$SKILL_MD"
  grep -qF -- '--stage merge --pr N --expected-oid "$BASE_TIP"' "$SKILL_MD"
}
