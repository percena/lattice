#!/usr/bin/env bats
# tkt-160: Python 3.8 floor guard for tools/ + shipped scripts, and the
# routing-evals per-skill zero-positives guard.
#
# Assertion ergonomics (#167): only errexit-effective forms ([ ], grep -q)
# are used; no mid-body [[ ]] / ! cmd assertions.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export REPO_ROOT
}

@test "python floor: no 3.9+-only runtime APIs in tools/ or shipped skill/plugin scripts" {
  # Denylist of APIs that crash on the documented 3.8 floor (README
  # Requirements: python3 >= 3.8). `str.removeprefix/removesuffix` (3.9),
  # `tomllib` (3.11), `zoneinfo` (3.9). Annotations are excluded by the
  # `from __future__ import annotations` contract (tkt-143).
  run bash -c '
    cd "$1" || exit 2
    grep -rnE "\.removeprefix\(|\.removesuffix\(|import tomllib|import zoneinfo" \
      tools/*.py skills/*/scripts plugins/lattice/scripts \
      --include="*.py" 2>/dev/null
  ' _ "$REPO_ROOT"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "routing evals fail loudly when a skill case file has zero positives" {
  run python3 - "$REPO_ROOT" <<'PY'
import importlib.util
import json
import shutil
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("rre", root / "tools/run-routing-evals.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

tmp = Path(tempfile.mkdtemp())
try:
    cases = tmp / "routing"
    shutil.copytree(root / "evals/routing", cases)
    victim = cases / "start-work.json"
    data = json.loads(victim.read_text(encoding="utf-8"))
    data["trigger"]["positive"] = []
    victim.write_text(json.dumps(data), encoding="utf-8")

    m.CASES_DIR = cases
    sys.argv = ["run-routing-evals.py"]
    rc = m.main()
finally:
    shutil.rmtree(tmp)

assert rc == 1, f"expected exit 1 on zero-positive case file, got {rc}"
print("guard ok")
PY
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "guard ok"
}

@test "routing evals print per-skill positive/rank1 stats for every catalog skill" {
  run python3 "$REPO_ROOT/tools/run-routing-evals.py"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "routing: start-work: positives="
  printf '%s\n' "$output" | grep -qF "routing: review-delivery: positives="
  [ "$(printf '%s\n' "$output" | grep -c '^routing: .*: positives=')" -eq 14 ]
}
