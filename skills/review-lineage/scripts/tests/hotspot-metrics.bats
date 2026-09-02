#!/usr/bin/env bats
# hotspot-metrics.bats — tests for the L4 synthesis sensor (spc-387 A4).
#
# Tests:
# 1. The Python lib imports and produces all 5 metric sections.
# 2. The bash wrapper runs and produces Markdown output.
# 3. The bash wrapper --json produces valid JSON.
# 4. Fix-class classification: 'flip' subject → status-flip.
# 5. File attribution: skills/finish-work/ → finish-work skill.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export HM="$REPO_ROOT/skills/review-lineage/scripts/hotspot-metrics.sh"
  export HM_LIB="$REPO_ROOT/skills/review-lineage/scripts/lib"
  export QH_LIB="$REPO_ROOT/skills/_lattice-lib/scripts/lib"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hm.XXXXXX")"
  export HM_TEST_REPO="$REPO_ROOT"
  export HM_TEST_HOME="$REPO_ROOT/.lattice"
}

teardown() {
  [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

@test "hotspot_metrics.py imports and produces all 5 metric sections" {
  python3 - <<PY
import sys, os, json
sys.path.insert(0, os.environ["QH_LIB"])
sys.path.insert(0, os.environ["HM_LIB"])
import hotspot_metrics as hm

repo_root = os.environ["HM_TEST_REPO"]
home = os.path.join(repo_root, ".lattice")
if not os.path.isdir(home):
    home = repo_root

result = hm.collect(home, repo_root=repo_root, since="30d")
assert "hotspot_clusters" in result, "missing hotspot_clusters"
assert "fix_class_histogram" in result, "missing fix_class_histogram"
assert "ticket_genealogy" in result, "missing ticket_genealogy"
assert "cross_audit_recurrence" in result, "missing cross_audit_recurrence"
assert "noticed_feedback" in result, "missing noticed_feedback"
assert result["schema"] == 1, "schema != 1"
print("OK: all 5 metric sections present, schema=1")
PY
}

@test "hotspot-metrics.sh runs and produces Markdown" {
  [[ -x "$HM" ]] || skip "script not executable"
  run bash "$HM" --no-snapshot --md 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hotspot metrics"* || "$output" == *"Total fix()"* ]]
}

@test "hotspot-metrics.sh --json produces valid JSON" {
  [[ -x "$HM" ]] || skip "script not executable"
  run bash "$HM" --no-snapshot --json 2>&1
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)"
}

@test "fix-class classification: 'flip' subject → status-flip" {
  python3 - <<PY
import sys, os
sys.path.insert(0, os.environ["QH_LIB"])
sys.path.insert(0, os.environ["HM_LIB"])
import hotspot_metrics as hm

assert hm._classify_fix("fix(tkt-127): flip binder status pr-open -> closed") == "status-flip"
assert hm._classify_fix("fix(tkt-360): finish-ledger fail-closed when ledger not staged") == "hardening"
assert hm._classify_fix("fix(tkt-367): finish-commit.sh bash-3.2 unbound-variable on empty array") == "bash-guard"
print("OK: fix-class classification correct")
PY
}

@test "file attribution: skills/finish-work/ → finish-work skill" {
  python3 - <<PY
import sys, os
sys.path.insert(0, os.environ["QH_LIB"])
sys.path.insert(0, os.environ["HM_LIB"])
import hotspot_metrics as hm

skill, stage, ckey = hm._attrib_file("skills/finish-work/scripts/ci-gate-check.sh")
assert skill == "finish-work", "expected finish-work, got %s" % skill
assert stage == "delivery", "expected delivery, got %s" % stage

skill, stage, ckey = hm._attrib_file("skills/_lattice-lib/scripts/finish-ledger.sh")
assert skill == "shared", "expected shared, got %s" % skill

skill, stage, ckey = hm._attrib_file("tools/validate-lattice-artifacts.py")
assert skill == "cross-cutting", "expected cross-cutting, got %s" % skill

print("OK: file attribution correct")
PY
}

# --- Extended fix-class taxonomy (tkt-392) ---

@test "fix-class: hardening (fail-closed/loud/open, guard, enforce)" {
  python3 - <<PY
import sys, os
sys.path.insert(0, os.environ["QH_LIB"])
sys.path.insert(0, os.environ["HM_LIB"])
import hotspot_metrics as hm
assert hm._classify_fix("fix(tkt-360): finish-ledger fail-closed when ledger not staged") == "hardening"
assert hm._classify_fix("fix(tkt-326): make jq failures non-fatal (fail-open)") == "hardening"
assert hm._classify_fix("fix: hard-enforce skill pipeline — strict hooks default") == "hardening"
print("OK: hardening classification correct")
PY
}

@test "fix-class: binder-format (binder format drift, prs-row, binder_rows)" {
  python3 - <<PY
import sys, os
sys.path.insert(0, os.environ["QH_LIB"])
sys.path.insert(0, os.environ["HM_LIB"])
import hotspot_metrics as hm
assert hm._classify_fix("fix(tkt-260): binder format drift caught by warning ratchet") == "binder-format"
assert hm._classify_fix("fix(#91): prs-row grammar single-source — binder_rows lib") == "binder-format"
print("OK: binder-format classification correct")
PY
}

@test "fix-class: ci-infra (ci-gate, routing-eval, bats pin)" {
  python3 - <<PY
import sys, os
sys.path.insert(0, os.environ["QH_LIB"])
sys.path.insert(0, os.environ["HM_LIB"])
import hotspot_metrics as hm
assert hm._classify_fix("fix(tkt-236): ci-gate pending bypass + failure-classify over-waiver") == "ci-infra"
assert hm._classify_fix("fix(tkt-246): pin CI bats to bats-core v1.13.0") == "ci-infra"
print("OK: ci-infra classification correct")
PY
}

@test "fix-class: docs-sync (stale ref, rename, TL;DR)" {
  python3 - <<PY
import sys, os
sys.path.insert(0, os.environ["QH_LIB"])
sys.path.insert(0, os.environ["HM_LIB"])
import hotspot_metrics as hm
assert hm._classify_fix("fix(spc-186): clean stale spc-187 ref in workflow-fsm.md") == "docs-sync"
assert hm._classify_fix("fix(spc-220): align TL;DR header status to done") == "docs-sync"
print("OK: docs-sync classification correct")
PY
}

@test "fix-class: feature-bug (hostname, git branch, terminal cancel)" {
  python3 - <<PY
import sys, os
sys.path.insert(0, os.environ["QH_LIB"])
sys.path.insert(0, os.environ["HM_LIB"])
import hotspot_metrics as hm
assert hm._classify_fix("fix(tkt-325): add --hostname to gh api base-sha fetch") == "feature-bug"
assert hm._classify_fix("fix(tkt-150): finish-ledger terminal cancel + full working-state vocabulary") == "feature-bug"
print("OK: feature-bug classification correct")
PY
}

@test "fix-class: portability (python 3.x, CJK, BSD)" {
  python3 - <<PY
import sys, os
sys.path.insert(0, os.environ["QH_LIB"])
sys.path.insert(0, os.environ["HM_LIB"])
import hotspot_metrics as hm
assert hm._classify_fix("fix(#143): binder_rows.py Python 3.9 compat") == "portability"
assert hm._classify_fix("fix(#22): check-duplicate-work.sh CJK matching — LC_ALL=C for BSD grep") == "portability"
print("OK: portability classification correct")
PY
}

@test "fix-class: residue-cleanup (residue, leftover)" {
  python3 - <<PY
import sys, os
sys.path.insert(0, os.environ["QH_LIB"])
sys.path.insert(0, os.environ["HM_LIB"])
import hotspot_metrics as hm
assert hm._classify_fix("fix(tkt-299): remove committed tkt-7.jsonl residue") == "residue-cleanup"
assert hm._classify_fix("fix(#133): finish-work train-retirement residue cleanup") == "residue-cleanup"
print("OK: residue-cleanup classification correct")
PY
}

@test "fix-class: review-followup (post-review, post-merge review)" {
  python3 - <<PY
import sys, os
sys.path.insert(0, os.environ["QH_LIB"])
sys.path.insert(0, os.environ["HM_LIB"])
import hotspot_metrics as hm
assert hm._classify_fix("fix(tkt-216): post-review batch — 4 HIGH + 2 MEDIUM bugs") == "review-followup"
assert hm._classify_fix("fix(tkt-179): 9 MEDIUM post-merge review fixes across ratify") == "review-followup"
print("OK: review-followup classification correct")
PY
}
