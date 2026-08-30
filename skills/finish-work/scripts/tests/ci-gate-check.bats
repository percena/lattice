#!/usr/bin/env bats
# Tests for skills/finish-work/scripts/ci-gate-check.sh (spc-186 A6/A8, ADR-007 §5a).
# Exercises the CI merge gate: checks rollup fetch, failure classification
# (infra-class vs real), compiled waiver stamp + trace, HARD block on real.

setup() {
  SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  GATE_SCRIPT="$SCRIPT_DIR/ci-gate-check.sh"
  TEST_DIR="${BATS_TEST_TMPDIR:-$(mktemp -d "${TMPDIR:-/tmp}/ci-gate.XXXXXX")}"
  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"
  export LATTICE_HOME="$TEST_DIR/.lattice"
  mkdir -p "$LATTICE_HOME"
  # minimal config.yaml so the config parser has a file to read (uses defaults)
  printf 'profile: strict\n' >"$LATTICE_HOME/config.yaml"
}

setup_gh_stub() {
  local checks_json="$1"
  local log_excerpt="${2:-}"
  cat >"$STUB_BIN/gh" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "pr" && "\$2" == "checks" ]]; then
  printf '%s' '$checks_json'
  exit 0
fi
if [[ "\$1" == "run" && "\$2" == "view" ]]; then
  printf '%s' "$log_excerpt"
  exit 0
fi
exit 1
EOF
  chmod +x "$STUB_BIN/gh"
  export PATH="$STUB_BIN:$PATH"
}

teardown() {
  cd /
  if [[ -n "${TEST_DIR:-}" ]]; then rm -rf "$TEST_DIR"; fi
}

# --- usage / arg validation ---

@test "ci-gate-check requires --pr" {
  run bash "$GATE_SCRIPT"
  [ "$status" -eq 2 ]
}

@test "ci-gate-check --help shows usage" {
  run bash "$GATE_SCRIPT" --help
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "Usage"
}

@test "ci-gate-check rejects non-numeric --pr" {
  run bash "$GATE_SCRIPT" --pr abc
  [ "$status" -eq 2 ]
}

# --- all green ---

@test "all-green checks pass (exit 0)" {
  setup_gh_stub '[{"name":"lint","state":"SUCCESS","conclusion":"SUCCESS","link":"https://github.com/o/r/runs/1"}]'
  run bash "$GATE_SCRIPT" --pr 1
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "PASS"
  printf '%s\n' "$output" | grep -qF "all green"
}

@test "all-green checks --json" {
  setup_gh_stub '[{"name":"lint","state":"SUCCESS","conclusion":"SUCCESS","link":""}]'
  run bash "$GATE_SCRIPT" --pr 1 --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == true'
  echo "$output" | jq -e '.decision == "PASS — all green"'
}

# --- real failures block HARD ---

@test "real failure blocks (exit 1)" {
  setup_gh_stub \
    '[{"name":"tests","state":"FAILURE","conclusion":"FAILURE","link":"https://github.com/o/r/runs/1"}]' \
    'AssertionError: expected 5 got 3'
  run bash "$GATE_SCRIPT" --pr 1 --evidence "local tests green"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "REAL failures"
  printf '%s\n' "$output" | grep -qF "HARD BLOCK"
}

@test "real failure --json reports block_reason" {
  setup_gh_stub \
    '[{"name":"tests","state":"FAILURE","conclusion":"FAILURE","link":"https://github.com/o/r/runs/2"}]' \
    'compile error: undefined symbol'
  run bash "$GATE_SCRIPT" --pr 1 --evidence "ok" --json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.ok == false'
  echo "$output" | jq -e '.block_reason == "real_or_unknown_failures"'
}

# --- infra-only red + evidence = compiled waiver ---

@test "infra-only billing failure + evidence = waiver pass (exit 0)" {
  setup_gh_stub \
    '[{"name":"lint-heavy","state":"FAILURE","conclusion":"FAILURE","link":"https://github.com/o/r/runs/3"}]' \
    'Error: billing quota exceeded — action required: update billing'
  run bash "$GATE_SCRIPT" --pr 1 --evidence "local bats + ci-local all-green"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "compiled waiver"
  printf '%s\n' "$output" | grep -qF "rule_id=ci-gate"
  printf '%s\n' "$output" | grep -qF "authorizer=human-at-merge-time"
  printf '%s\n' "$output" | grep -qF "billing"
}

@test "infra-only rate-limit failure + evidence = waiver pass" {
  setup_gh_stub \
    '[{"name":"lint","state":"FAILURE","conclusion":"FAILURE","link":"https://github.com/o/r/runs/4"}]' \
    'Error: API rate limit exceeded — too many requests'
  run bash "$GATE_SCRIPT" --pr 1 --evidence "ci-local green"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "rate_limit"
}

@test "TIMED_OUT with timeout-pattern log is infra (waiver)" {
  setup_gh_stub \
    '[{"name":"slow-tests","state":"FAILURE","conclusion":"TIMED_OUT","link":"https://github.com/o/r/runs/5"}]' \
    'Error: the operation was canceled due to timeout'
  run bash "$GATE_SCRIPT" --pr 1 --evidence "ci-local green"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "timeout"
  printf '%s\n' "$output" | grep -qF "compiled waiver"
}

@test "TIMED_OUT with hanging-test log blocks (fail-closed, not waived)" {
  setup_gh_stub \
    '[{"name":"slow-tests","state":"FAILURE","conclusion":"TIMED_OUT","link":"https://github.com/o/r/runs/5b"}]' \
    'test deadlock: infinite loop detected in suite'
  run bash "$GATE_SCRIPT" --pr 1 --evidence "ci-local green"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "UNCLASSIFIED"
}

@test "empty-step flake (FAILURE + no log) is infra" {
  setup_gh_stub \
    '[{"name":"ci","state":"FAILURE","conclusion":"FAILURE","link":"https://github.com/o/r/runs/6"}]' \
    ''
  run bash "$GATE_SCRIPT" --pr 1 --evidence "local bats green"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "empty_step"
}

@test "CANCELLED with empty log blocks (fail-closed, not empty_step infra)" {
  setup_gh_stub \
    '[{"name":"ci","state":"FAILURE","conclusion":"CANCELLED","link":"https://github.com/o/r/runs/19"}]' \
    ''
  run bash "$GATE_SCRIPT" --pr 1 --evidence "local bats green"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "UNCLASSIFIED"
}

@test "STARTUP_FAILURE conclusion is infra (runner)" {
  setup_gh_stub \
    '[{"name":"ci","state":"FAILURE","conclusion":"STARTUP_FAILURE","link":"https://github.com/o/r/runs/7"}]' \
    'runner offline'
  run bash "$GATE_SCRIPT" --pr 1 --evidence "ok"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "runner_infra"
}

# --- infra-only WITHOUT evidence = HARD block (fail-closed) ---

@test "infra-only red WITHOUT evidence blocks (fail-closed)" {
  setup_gh_stub \
    '[{"name":"lint","state":"FAILURE","conclusion":"FAILURE","link":"https://github.com/o/r/runs/8"}]' \
    'billing quota exceeded'
  run bash "$GATE_SCRIPT" --pr 1
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "fail-closed"
}

@test "infra-only without evidence --json reports block_reason" {
  setup_gh_stub \
    '[{"name":"lint","state":"FAILURE","conclusion":"FAILURE","link":"https://github.com/o/r/runs/9"}]' \
    'rate limit exceeded'
  run bash "$GATE_SCRIPT" --pr 1 --json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.ok == false'
  echo "$output" | jq -e '.block_reason == "infra_without_evidence"'
}

# --- pending blocks ---

@test "pending checks block (exit 1)" {
  setup_gh_stub \
    '[{"name":"lint","state":"PENDING","conclusion":"","link":"https://github.com/o/r/runs/10"}]'
  run bash "$GATE_SCRIPT" --pr 1 --evidence "ok"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "PENDING"
  printf '%s\n' "$output" | grep -qF "BLOCKED"
}

@test "infra failure + evidence + pending blocks (not waived — MH1)" {
  setup_gh_stub \
    '[{"name":"lint-heavy","state":"FAILURE","conclusion":"FAILURE","link":"https://github.com/o/r/runs/20"},{"name":"tests","state":"PENDING","conclusion":"","link":"https://github.com/o/r/runs/21"}]' \
    'billing quota exceeded'
  run bash "$GATE_SCRIPT" --pr 1 --evidence "ci-local all-green"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "PENDING"
  printf '%s\n' "$output" | grep -qF "BLOCKED"
}

# --- mixed infra + real = HARD block (real dominates) ---

@test "mixed infra + real failures block (real dominates)" {
  setup_gh_stub \
    '[{"name":"lint","state":"FAILURE","conclusion":"FAILURE","link":"https://github.com/o/r/runs/11"},{"name":"tests","state":"FAILURE","conclusion":"FAILURE","link":"https://github.com/o/r/runs/12"}]' \
    'test assertion failed'
  run bash "$GATE_SCRIPT" --pr 1 --evidence "ok"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "REAL failures"
}

# --- waiver trace stamps binder journal ---

@test "waiver trace stamps binder ## Decision journal" {
  setup_gh_stub \
    '[{"name":"lint","state":"FAILURE","conclusion":"FAILURE","link":"https://github.com/o/r/runs/13"}]' \
    'billing quota exceeded'
  BINDER="$TEST_DIR/binder.md"
  printf '# tkt-1\n\n## Acceptance\n\n- [ ] A1\n\n## Decision journal\n\n- existing entry\n\n## Notes\n\nfoo\n' >"$BINDER"
  run bash "$GATE_SCRIPT" --pr 1 --evidence "ci-local green" --binder "$BINDER"
  [ "$status" -eq 0 ]
  grep -qF "rule_id=ci-gate" "$BINDER"
  grep -qF "authorizer=human-at-merge-time" "$BINDER"
  grep -qF "existing entry" "$BINDER"
}

@test "waiver trace creates ## Decision journal when absent" {
  setup_gh_stub \
    '[{"name":"lint","state":"FAILURE","conclusion":"FAILURE","link":"https://github.com/o/r/runs/14"}]' \
    'rate limit exceeded'
  BINDER="$TEST_DIR/binder2.md"
  printf '# tkt-1\n\n## Acceptance\n\n- [ ] A1\n\n## Notes\n\nfoo\n' >"$BINDER"
  run bash "$GATE_SCRIPT" --pr 1 --evidence "ok" --binder "$BINDER"
  [ "$status" -eq 0 ]
  grep -qF "## Decision journal" "$BINDER"
  grep -qF "rule_id=ci-gate" "$BINDER"
}

@test "dry-run does not stamp binder" {
  setup_gh_stub \
    '[{"name":"lint","state":"FAILURE","conclusion":"FAILURE","link":"https://github.com/o/r/runs/15"}]' \
    'billing quota exceeded'
  BINDER="$TEST_DIR/binder3.md"
  printf '# tkt-1\n\n## Notes\n\nfoo\n' >"$BINDER"
  run bash "$GATE_SCRIPT" --pr 1 --evidence "ok" --binder "$BINDER" --dry-run
  [ "$status" -eq 0 ]
  # binder NOT stamped (dry-run)
  run grep -qF "rule_id=ci-gate" "$BINDER"
  [ "$status" -ne 0 ]
}

# --- PR comment body is emitted ---

@test "PR comment body emitted on waiver" {
  setup_gh_stub \
    '[{"name":"lint","state":"FAILURE","conclusion":"FAILURE","link":"https://github.com/o/r/runs/16"}]' \
    'billing quota exceeded'
  run bash "$GATE_SCRIPT" --pr 1 --evidence "ci-local green"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "PR comment body"
  printf '%s\n' "$output" | grep -qF "ci-gate-waiver"
}

# --- config-tunable patterns ---

@test "config-tunable patterns from .lattice/config.yaml" {
  printf 'profile: strict\nci_gate:\n  infra_patterns:\n    custom_infra:\n      - "special_error_code_XYZ999"\n' >"$LATTICE_HOME/config.yaml"
  setup_gh_stub \
    '[{"name":"lint","state":"FAILURE","conclusion":"FAILURE","link":"https://github.com/o/r/runs/17"}]' \
    'special_error_code_XYZ999 detected'
  run bash "$GATE_SCRIPT" --pr 1 --evidence "ok"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "custom_infra"
  printf '%s\n' "$output" | grep -qF "special_error_code_XYZ999"
}

@test "default patterns apply when config absent" {
  rm -f "$LATTICE_HOME/config.yaml"
  setup_gh_stub \
    '[{"name":"lint","state":"FAILURE","conclusion":"FAILURE","link":"https://github.com/o/r/runs/18"}]' \
    'spending limit reached'
  run bash "$GATE_SCRIPT" --pr 1 --evidence "ok"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "billing"
}

# --- gh failure (cannot load checks) ---

@test "gh cannot load checks exits 2" {
  cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$STUB_BIN/gh"
  export PATH="$STUB_BIN:$PATH"
  run bash "$GATE_SCRIPT" --pr 1 --evidence "ok"
  [ "$status" -eq 2 ]
}

@test "empty gh pr checks output (no-CI repo) is green (exit 0)" {
  setup_gh_stub '' ''
  run bash "$GATE_SCRIPT" --pr 1
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "PASS"
  printf '%s\n' "$output" | grep -qF "all green"
}

@test "valid empty-array gh pr checks (no checks) is green" {
  setup_gh_stub '[]' ''
  run bash "$GATE_SCRIPT" --pr 1
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "PASS"
  printf '%s\n' "$output" | grep -qF "all green"
}

@test "malformed gh pr checks JSON exits 2" {
  cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "pr" && "$2" == "checks" ]]; then
  printf '%s' 'not-valid-json{'
  exit 0
fi
exit 1
EOF
  chmod +x "$STUB_BIN/gh"
  export PATH="$STUB_BIN:$PATH"
  run bash "$GATE_SCRIPT" --pr 1
  [ "$status" -eq 2 ]
}

# --- classifier unit tests (direct Python) ---

@test "classifier: billing pattern matches" {
  CLASSIFY_LIB="$SCRIPT_DIR/lib"
  result=$(CI_GATE_LIB="$CLASSIFY_LIB" python3 -c '
import os, sys, json
sys.path.insert(0, os.environ["CI_GATE_LIB"])
import ci_failure_classify as clf
r = clf.classify_failure("lint", "FAILURE", "Error: billing quota exceeded", None)
print(json.dumps(r))
')
  echo "$result" | jq -e '.class == "infra"'
  echo "$result" | jq -e '.category == "billing"'
}

@test "classifier: real failure (no pattern match)" {
  CLASSIFY_LIB="$SCRIPT_DIR/lib"
  result=$(CI_GATE_LIB="$CLASSIFY_LIB" python3 -c '
import os, sys, json
sys.path.insert(0, os.environ["CI_GATE_LIB"])
import ci_failure_classify as clf
r = clf.classify_failure("tests", "FAILURE", "AssertionError: expected 5 got 3", None)
print(json.dumps(r))
')
  echo "$result" | jq -e '.class == "real"'
}

@test "classifier: empty-step flake (empty log + FAILURE)" {
  CLASSIFY_LIB="$SCRIPT_DIR/lib"
  result=$(CI_GATE_LIB="$CLASSIFY_LIB" python3 -c '
import os, sys, json
sys.path.insert(0, os.environ["CI_GATE_LIB"])
import ci_failure_classify as clf
r = clf.classify_failure("ci", "FAILURE", "", None)
print(json.dumps(r))
')
  echo "$result" | jq -e '.class == "infra"'
  echo "$result" | jq -e '.category == "empty_step"'
}

@test "classifier: TIMED_OUT with timeout-pattern log is infra" {
  CLASSIFY_LIB="$SCRIPT_DIR/lib"
  result=$(CI_GATE_LIB="$CLASSIFY_LIB" python3 -c '
import os, sys, json
sys.path.insert(0, os.environ["CI_GATE_LIB"])
import ci_failure_classify as clf
r = clf.classify_failure("slow", "TIMED_OUT", "the operation was canceled", None)
print(json.dumps(r))
')
  echo "$result" | jq -e '.class == "infra"'
  echo "$result" | jq -e '.category == "timeout"'
}

@test "classifier: TIMED_OUT with non-infra log is unknown (fail-closed)" {
  CLASSIFY_LIB="$SCRIPT_DIR/lib"
  result=$(CI_GATE_LIB="$CLASSIFY_LIB" python3 -c '
import os, sys, json
sys.path.insert(0, os.environ["CI_GATE_LIB"])
import ci_failure_classify as clf
r = clf.classify_failure("slow", "TIMED_OUT", "test deadlock detected", None)
print(json.dumps(r))
')
  echo "$result" | jq -e '.class == "unknown"'
  echo "$result" | jq -e '.category == "timeout"'
}

@test "classifier: CANCELLED without infra pattern is unknown" {
  CLASSIFY_LIB="$SCRIPT_DIR/lib"
  result=$(CI_GATE_LIB="$CLASSIFY_LIB" python3 -c '
import os, sys, json
sys.path.insert(0, os.environ["CI_GATE_LIB"])
import ci_failure_classify as clf
r = clf.classify_failure("ci", "CANCELLED", "no relevant text", None)
print(json.dumps(r))
')
  echo "$result" | jq -e '.class == "unknown"'
}

@test "classifier: CANCELLED with empty log is unknown (not empty_step infra)" {
  CLASSIFY_LIB="$SCRIPT_DIR/lib"
  result=$(CI_GATE_LIB="$CLASSIFY_LIB" python3 -c '
import os, sys, json
sys.path.insert(0, os.environ["CI_GATE_LIB"])
import ci_failure_classify as clf
r = clf.classify_failure("ci", "CANCELLED", "", None)
print(json.dumps(r))
')
  echo "$result" | jq -e '.class == "unknown"'
}

@test "classifier: waiver_trace contains required fields" {
  CLASSIFY_LIB="$SCRIPT_DIR/lib"
  result=$(CI_GATE_LIB="$CLASSIFY_LIB" python3 -c '
import os, sys, json
sys.path.insert(0, os.environ["CI_GATE_LIB"])
import ci_failure_classify as clf
infra = [{"name":"lint","category":"billing","pattern":"billing"}]
t = clf.waiver_trace("1", infra, "ci-local green", "2026-01-01T00:00:00Z")
print(json.dumps({"trace": t}))
')
  echo "$result" | jq -r '.trace' | grep -qF "rule_id=ci-gate"
  echo "$result" | jq -r '.trace' | grep -qF "authorizer=human-at-merge-time"
  echo "$result" | jq -r '.trace' | grep -qF "ADR-007 §5a"
}
