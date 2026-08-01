#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUNNER="$REPO_ROOT/tools/run-behavioral-evals.py"
  PROVIDER="$REPO_ROOT/evals/providers/fake-provider.py"
  LIVE_PROVIDER="$REPO_ROOT/evals/providers/claude-cli-provider.py"
  TMP_ROOT="$(mktemp -d)"
  FIXTURE="$TMP_ROOT/repo"
  mkdir -p "$FIXTURE/skills/demo/evals"
  printf '%s\n' '# Demo skill' 'Always be explicit.' >"$FIXTURE/skills/demo/SKILL.md"
  printf '%s\n' '{"schema_version":1,"skill_name":"demo","cases":[{"id":"one","type":"behavioral","prompt":"Do the work","expect":["states intent","verifies result"]}]}' \
    >"$FIXTURE/skills/demo/evals/evals.json"
  SCENARIO="$TMP_ROOT/scenario.json"
  ARTIFACTS="$TMP_ROOT/artifacts"
  export FAKE_EVAL_SCENARIO="$SCENARIO"
}

teardown() {
  rm -rf "$TMP_ROOT"
}

run_eval() {
  run python3 "$RUNNER" \
    --repo-root "$FIXTURE" \
    --provider-command "python3 $PROVIDER" \
    --artifacts-dir "$ARTIFACTS" \
    --run-id test-run \
    "$@"
}

@test "repository behavioral corpus validates" {
  run python3 "$RUNNER" --repo-root "$REPO_ROOT" --validate-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"behavioral corpus: OK"* ]]
}

@test "repository behavioral corpus executes with free fake provider" {
  printf '%s\n' '{"default":{"candidate":true,"baseline":false}}' >"$SCENARIO"
  run python3 "$RUNNER" \
    --repo-root "$REPO_ROOT" \
    --provider-command "python3 $PROVIDER" \
    --artifacts-dir "$ARTIFACTS/full-corpus" \
    --run-id full-corpus
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); assert s["ok"] is True and s["total_cases"] >= 50 and s["harness_errors"] == 0' \
    "$ARTIFACTS/full-corpus/summary.json"
}

@test "invalid corpus contract fails before provider execution" {
  printf '%s\n' '{"schema_version":0,"skill_name":"demo","cases":[]}' \
    >"$FIXTURE/skills/demo/evals/evals.json"
  run python3 "$RUNNER" --repo-root "$FIXTURE" --validate-only
  [ "$status" -eq 2 ]
  [[ "$output" == *"schema_version must be 1"* ]]
  [[ "$output" == *"cases must be a non-empty array"* ]]
}

@test "candidate and no-skill baseline run in isolated sandboxes with artifacts" {
  printf '%s\n' '{"default":{"candidate":[true,true],"baseline":[false,false]}}' >"$SCENARIO"
  run_eval
  [ "$status" -eq 0 ]
  [ -f "$ARTIFACTS/manifest.json" ]
  [ -f "$ARTIFACTS/cases/demo/one/candidate/invoke.json" ]
  [ -f "$ARTIFACTS/cases/demo/one/baseline/assert.json" ]
  [ -f "$ARTIFACTS/summary.json" ]
  python3 - "$ARTIFACTS" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
candidate = json.loads((root / "cases/demo/one/candidate/invoke.json").read_text())
baseline = json.loads((root / "cases/demo/one/baseline/invoke.json").read_text())
assert candidate["request"]["skill_text"] == "# Demo skill\nAlways be explicit.\n"
assert baseline["request"]["skill_text"] is None
assert candidate["response"]["metadata"]["cwd"] != baseline["response"]["metadata"]["cwd"]
summary = json.loads((root / "summary.json").read_text())
assert summary["ok"] is True
assert summary["results"][0]["comparison_delta"] == 1.0
PY
}

@test "unmet candidate expectations return status 1" {
  printf '%s\n' '{"default":{"candidate":[true,false],"baseline":[false,false]}}' >"$SCENARIO"
  run_eval
  [ "$status" -eq 1 ]
  python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); assert s["quality_failures"] == 1 and s["harness_errors"] == 0' "$ARTIFACTS/summary.json"
}

@test "baseline regression is a separate comparison failure" {
  printf '%s\n' '{"default":{"candidate":[true,false],"baseline":[true,true]}}' >"$SCENARIO"
  run_eval --min-candidate-pass-rate 0.5
  [ "$status" -eq 1 ]
  python3 -c 'import json,sys; r=json.load(open(sys.argv[1]))["results"][0]; assert r["threshold_ok"] is True and r["comparison_ok"] is False' "$ARTIFACTS/summary.json"
}

@test "allow-regression keeps an explicit exploratory escape" {
  printf '%s\n' '{"default":{"candidate":[true,false],"baseline":[true,true]}}' >"$SCENARIO"
  run_eval --min-candidate-pass-rate 0.5 --allow-regression
  [ "$status" -eq 0 ]
}

@test "json mode emits one machine-parseable document on stdout" {
  printf '%s\n' '{"default":{"candidate":[true,true],"baseline":[false,false]}}' >"$SCENARIO"
  run bash -c 'python3 "$1" --repo-root "$2" --provider-command "python3 $3" --artifacts-dir "$4" --run-id test-run --json 2>"$5" | python3 -c '\''import json,sys; s=json.load(sys.stdin); assert s["ok"] is True and s["total_cases"] == 1'\''' _ "$RUNNER" "$FIXTURE" "$PROVIDER" "$ARTIFACTS" "$TMP_ROOT/progress.log"
  [ "$status" -eq 0 ]
  grep -q 'behavioral corpus: OK' "$TMP_ROOT/progress.log"
  grep -q 'PASS demo/one' "$TMP_ROOT/progress.log"
}

@test "nonpositive timeout fails as a harness configuration error" {
  printf '%s\n' '{"default":{"candidate":[true,true],"baseline":[false,false]}}' >"$SCENARIO"
  run_eval --timeout 0
  [ "$status" -eq 2 ]
  [[ "$output" == *"--timeout must be a finite number greater than 0"* ]]
}

@test "artifacts path must be a directory" {
  printf '%s\n' '{"default":{"candidate":[true,true],"baseline":[false,false]}}' >"$SCENARIO"
  printf '%s\n' 'occupied' >"$ARTIFACTS"
  run_eval
  [ "$status" -eq 2 ]
  [[ "$output" == *"artifacts path is not a directory"* ]]
}

@test "provider protocol failures return status 2 and preserve raw artifacts" {
  printf '%s\n' '{"default":{"candidate":[true,true],"baseline":[false,false]}}' >"$SCENARIO"
  export FAKE_EVAL_MODE=malformed-assert
  run_eval
  [ "$status" -eq 2 ]
  [ -f "$ARTIFACTS/cases/demo/one/candidate/assert.json" ]
  grep -q 'not-json' "$ARTIFACTS/cases/demo/one/candidate/assert.json"
}

@test "provider timeout with partial output is a harness error with artifact" {
  SLOW="$TMP_ROOT/slow-provider.py"
  printf '%s\n' \
    'import sys, time' \
    'sys.stdout.write("partial output before hanging")' \
    'sys.stdout.flush()' \
    'time.sleep(30)' >"$SLOW"
  run python3 "$RUNNER" \
    --repo-root "$FIXTURE" \
    --provider-command "python3 $SLOW" \
    --artifacts-dir "$ARTIFACTS" \
    --run-id test-run \
    --timeout 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"timed out after"* ]]
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert "timed out" in d["error"] and "partial output" in d["stdout"]' \
    "$ARTIFACTS/cases/demo/one/candidate/invoke.json"
}

@test "harness timeout kills the provider's whole process group" {
  SLOW="$TMP_ROOT/spawning-provider.py"
  PID_FILE="$TMP_ROOT/grandchild.pid"
  printf '%s\n' \
    'import os, subprocess, sys, time' \
    'child = subprocess.Popen(["sleep", "300"])' \
    'with open(os.environ["GRANDCHILD_PID_FILE"], "w") as fh:' \
    '    fh.write(str(child.pid))' \
    'sys.stdout.write("spawned grandchild")' \
    'sys.stdout.flush()' \
    'time.sleep(300)' >"$SLOW"
  export GRANDCHILD_PID_FILE="$PID_FILE"
  run python3 "$RUNNER" \
    --repo-root "$FIXTURE" \
    --provider-command "python3 $SLOW" \
    --artifacts-dir "$ARTIFACTS" \
    --run-id test-run \
    --timeout 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"timed out after"* ]]
  [ -f "$PID_FILE" ]
  grandchild="$(cat "$PID_FILE")"
  # Allow a beat for SIGKILL delivery and init reaping the orphan.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$grandchild" 2>/dev/null || break
    sleep 0.2
  done
  ! kill -0 "$grandchild" 2>/dev/null
}

@test "shlex-quoted provider path containing spaces works end-to-end" {
  SPACED_DIR="$TMP_ROOT/pro vider"
  mkdir -p "$SPACED_DIR"
  cp "$PROVIDER" "$SPACED_DIR/fake provider.py"
  printf '%s\n' '{"default":{"candidate":[true,true],"baseline":[false,false]}}' >"$SCENARIO"
  run python3 "$RUNNER" \
    --repo-root "$FIXTURE" \
    --provider-command "python3 '$SPACED_DIR/fake provider.py'" \
    --artifacts-dir "$ARTIFACTS" \
    --run-id test-run
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); assert s["ok"] is True and s["harness_errors"] == 0' \
    "$ARTIFACTS/summary.json"
}

@test "missing provider binary is a harness error, not a quality failure" {
  run python3 "$RUNNER" \
    --repo-root "$FIXTURE" \
    --provider-command "no-such-provider-xyz-tkt272" \
    --artifacts-dir "$ARTIFACTS" \
    --run-id test-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"provider command failed to start"* ]]
  python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); assert s["harness_errors"] >= 1 and s["ok"] is False' \
    "$ARTIFACTS/summary.json"
}

@test "previous-skill baseline content is loaded explicitly" {
  mkdir -p "$TMP_ROOT/previous/skills/demo"
  printf '%s\n' '# Old demo' >"$TMP_ROOT/previous/skills/demo/SKILL.md"
  printf '%s\n' '{"default":{"candidate":[true,true],"baseline":[false,false]}}' >"$SCENARIO"
  run_eval --baseline-skill-root "$TMP_ROOT/previous"
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["request"]["skill_text"] == "# Old demo\n"' "$ARTIFACTS/cases/demo/one/baseline/invoke.json"
}

@test "Claude CLI adapter parses invoke and structured judge envelopes" {
  STUB="$TMP_ROOT/claude-stub"
  ARGS_LOG="$TMP_ROOT/claude-args"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >>"$CLAUDE_ARGS_LOG"' \
    'input=$(cat)' \
    'if [[ " $* " == *" --json-schema "* ]]; then' \
    '  printf '\''%s\n'\'' '\''{"structured_output":{"assertions":[{"index":0,"passed":true,"evidence":"stub evidence"}]},"model":"stub"}'\''' \
    'else' \
    '  printf '\''%s\n'\'' '\''{"result":"stub response","model":"stub"}'\''' \
    'fi' >"$STUB"
  chmod +x "$STUB"
  export CLAUDE_ARGS_LOG="$ARGS_LOG"

  run bash -c 'printf '\''%s\n'\'' '\''{"phase":"invoke","prompt":"hello","skill_text":"rules","protocol_version":1}'\'' | python3 "$1" --claude-command "$2"' _ "$LIVE_PROVIDER" "$STUB"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"text": "stub response"'* ]]

  run bash -c 'printf '\''%s\n'\'' '\''{"phase":"assert","prompt":"hello","response_text":"answer","expectations":["does it"],"protocol_version":1}'\'' | python3 "$1" --claude-command "$2"' _ "$LIVE_PROVIDER" "$STUB"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"evidence": "stub evidence"'* ]]
  grep -q -- '--safe-mode' "$ARGS_LOG"
  grep -q -- '--no-session-persistence' "$ARGS_LOG"
  grep -q -- '--json-schema' "$ARGS_LOG"
}
