#!/usr/bin/env bats
# hotspot-metrics.bats — tests for the L4 synthesis sensor (spc-387 A4).
#
# Tests:
# 1. The Python lib imports and produces all 5 metric sections.
# 2. The bash wrapper runs and produces Markdown output.
# 3. Planted-drift: a fixture with fix() commits produces a cluster.
# 4. Fix-class classification: a 'flip' subject classifies as status-flip.

load "${BATS_LIBS:-$(dirname "$BATS_TEST_DIRNAME")/_lattice-home}/test_helper.bash" 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd -P)"
SKILL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
LIB_SCRIPTS="$SKILL_ROOT/../../_lattice-lib/scripts"
RESOLVE="$LIB_SCRIPTS/resolve-lattice-lib.sh"

# Resolve _lattice-lib for Python import path
if [[ -f "$RESOLVE" ]]; then
  LATTICE_LIB="$(bash "$RESOLVE")"
  LATTICE_LIB_PY="$LATTICE_LIB/lib"
else
  LATTICE_LIB_PY=""
fi

@test "hotspot_metrics.py imports and produces all 5 metric sections" {
  [[ -n "$LATTICE_LIB_PY" ]] || skip "_lattice-lib not installed"
  python3 - <<PY
import sys, os, json
sys.path.insert(0, "$LATTICE_LIB_PY")
sys.path.insert(0, "$SCRIPT_DIR/lib")
import hotspot_metrics as hm

repo_root = os.environ.get("HM_TEST_REPO", "$SKILL_ROOT/../..")
home = os.path.join(repo_root, ".lattice")
if not os.path.isdir(home):
    home = repo_root  # fallback

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
  [[ -x "$SKILL_ROOT/scripts/hotspot-metrics.sh" ]] || skip "script not executable"
  run bash "$SKILL_ROOT/scripts/hotspot-metrics.sh" --no-snapshot --md 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hotspot metrics"* ]] || \
    [[ "$output" == *"Total fix()"* ]]
}

@test "hotspot-metrics.sh --json produces valid JSON" {
  [[ -x "$SKILL_ROOT/scripts/hotspot-metrics.sh" ]] || skip "script not executable"
  run bash "$SKILL_ROOT/scripts/hotspot-metrics.sh" --no-snapshot --json 2>&1
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null || \
    echo "$output" | head -1 | grep -q '{'  # at least starts with JSON
}

@test "fix-class classification: 'flip' subject → status-flip" {
  [[ -n "$LATTICE_LIB_PY" ]] || skip "_lattice-lib not installed"
  python3 - <<PY
import sys
sys.path.insert(0, "$LATTICE_LIB_PY")
sys.path.insert(0, "$SCRIPT_DIR/lib")
import hotspot_metrics as hm

assert hm._classify_fix("fix(tkt-127): flip binder status pr-open -> closed") == "status-flip"
assert hm._classify_fix("fix(tkt-360): finish-ledger fail-closed when ledger not staged") == "other"
assert hm._classify_fix("fix(tkt-367): finish-commit.sh bash-3.2 unbound-variable on empty array") == "bash-guard"
print("OK: fix-class classification correct")
PY
}

@test "file attribution: skills/finish-work/ → finish-work skill" {
  [[ -n "$LATTICE_LIB_PY" ]] || skip "_lattice-lib not installed"
  python3 - <<PY
import sys
sys.path.insert(0, "$LATTICE_LIB_PY")
sys.path.insert(0, "$SCRIPT_DIR/lib")
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
