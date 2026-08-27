#!/usr/bin/env bash
# ci-local: run locally, in one command, every check CI runs — so a green run
# here predicts a green run on GitHub. Mirrors:
# - lint.yml            shellcheck (same file set/flags), broken-symlink check
# - lint-heavy.yml      validate-skills, validate-plugin-versions (with CI's
#                       path-filter skip), routing evals, behavioral corpus
#                       validate + fake-provider smoke, claude plugin validate
# - lattice-scripts.yml every discovered bats suite under skills/ and tools/
# - plugin-hooks.yml    bats from plugins/lattice (its working-directory)
# Plus tools/validate-lattice-artifacts.py (L0 contract check; CI parity via
# .github/workflows/artifacts.yml on pull_request + push to main/dev — tkt-92).
#
# Usage: bash tools/ci-local.sh [--base-ref REF] [--release-check] [--fast]
#   --base-ref REF  base for validate-plugin-versions and its path-filter skip
#                   (default: fork point `git merge-base origin/dev HEAD`)
#   --release-check  simulate the dev→main release boundary: base-ref becomes
#                   origin/main and the validator enforces the version-increment
#                   invariant (bundled change without bump = error). Default is
#                   dev-mode (lenient: only non-decrease enforced). [ADR-005]
#   --fast          skip the bats suites (the slow step); default runs full
#
# Steps never abort the run: each records pass/FAIL/skip, a summary table
# prints at the end, and the exit code is nonzero if any step failed.
set -u -o pipefail # deliberately no -e: per-step failure capture

# This file lives at monorepo tools/ci-local.sh.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

usage() {
  sed -n 's/^# \{0,1\}//p' "$0" | sed -n '1,18p'
}

BASE_REF=""
RELEASE_CHECK=0
FAST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base-ref)
      BASE_REF="${2:?--base-ref requires a value}"
      shift 2
      ;;
    --base-ref=*)
      BASE_REF="${1#*=}"
      shift
      ;;
    --release-check)
      RELEASE_CHECK=1
      shift
      ;;
    --fast)
      FAST=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "ci-local: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

LOG_DIR="$(mktemp -d)"
trap 'rm -rf "$LOG_DIR"' EXIT

STEP_NAMES=()
STEP_RESULTS=() # pass | FAIL | skip
STEP_NOTES=()

record() {
  STEP_NAMES+=("$1")
  STEP_RESULTS+=("$2")
  STEP_NOTES+=("${3:-}")
}

# run_step <name> <command...> — capture output; on failure replay its tail.
run_step() {
  local name="$1"
  shift
  local log="$LOG_DIR/step-${#STEP_NAMES[@]}.log"
  printf '==> %s\n' "$name"
  if "$@" > "$log" 2>&1; then
    record "$name" pass ""
  else
    local rc=$?
    record "$name" FAIL "exit $rc"
    printf '    FAIL (exit %s); last output lines:\n' "$rc"
    tail -n 60 "$log" | sed 's/^/    | /'
  fi
}

skip_step() {
  printf '==> %s\n    skip: %s\n' "$1" "$2"
  record "$1" skip "$2"
}

have() { command -v "$1" > /dev/null 2>&1; }

# --- step bodies -------------------------------------------------------------

# lint.yml shellcheck job: same file set and severity as CI.
step_shellcheck() {
  find skills plugins tools -name '*.sh' -print0 | xargs -0 shellcheck -S warning
}

# lint.yml symlink-integrity job.
step_symlinks() {
  local broken
  broken="$(find . -type l ! -exec test -e {} \; -print)"
  if [ -n "$broken" ]; then
    echo "Broken symlinks found:"
    echo "$broken"
    return 1
  fi
}

# lint-heavy.yml behavioral smoke: protocol only, fake provider (not model quality).
step_behavioral_smoke() {
  local dir rc
  dir="$(mktemp -d)"
  printf '%s\n' '{"default":{"candidate":true,"baseline":false}}' > "$dir/scenario.json"
  FAKE_EVAL_SCENARIO="$dir/scenario.json" python3 tools/run-behavioral-evals.py \
    --provider-command "python3 evals/providers/fake-provider.py" \
    --artifacts-dir "$dir/behavioral-evals"
  rc=$?
  rm -rf "$dir"
  return "$rc"
}

# lint-heavy.yml plugin-validate job (CI pins @anthropic-ai/claude-code@2.1.216).
step_plugin_validate() {
  claude plugin validate . && claude plugin validate plugins/lattice
}

# Run one bats suite with the BATS_TEST_TMPDIR shim: local bats 1.2.x predates
# BATS_TEST_TMPDIR (CI's bats provides it), so inject a throwaway dir per suite.
bats_shimmed() {
  local suite="$1" workdir="$2" tmp rc
  tmp="$(mktemp -d)"
  (cd "$workdir" && BATS_TEST_TMPDIR="$tmp" bats "$suite")
  rc=$?
  rm -rf "$tmp"
  return "$rc"
}

# True when the change vs BASE_REF touches lint-heavy.yml's `on.paths` filter —
# the same gate CI uses to decide whether validate-plugin-versions runs.
# Untracked files count: they will be part of the diff CI sees once committed.
plugin_version_paths_changed() {
  local path
  while IFS= read -r path; do
    case "$path" in
      skills/* | tools/* | evals/* | plugins/* | .claude-plugin/* | .github/workflows/lint-heavy.yml)
        return 0
        ;;
    esac
  done < <(
    git diff --name-only "$BASE_REF" --
    git ls-files --others --exclude-standard
  )
  return 1
}

# --- base ref ----------------------------------------------------------------

# --- base ref + validator command --------------------------------------------

# --release-check changes both the base-ref default (origin/main instead of
# dev fork point) and the enforcement mode (strict version-increment invariant
# at the release boundary per ADR-005). Default is dev-mode (lenient:
# non-decrease only).
if [ -z "$BASE_REF" ] && [ "$RELEASE_CHECK" -eq 1 ]; then
  BASE_REF="origin/main"
fi

if [ -z "$BASE_REF" ]; then
  BASE_REF="$(git merge-base origin/dev HEAD 2> /dev/null || true)"
  if [ -n "$BASE_REF" ]; then
    echo "base ref: fork point of origin/dev ($(git rev-parse --short "$BASE_REF")) [dev mode: lenient]"
  else
    echo "base ref: origin/dev unavailable; validate-plugin-versions will use its own default [dev mode: lenient]"
  fi
else
  echo "base ref: $BASE_REF $([ "$RELEASE_CHECK" -eq 1 ] && echo '[release-check: strict]' || echo '[dev mode: lenient]')"
fi

PV_CMD=(python3 tools/validate-plugin-versions.py)
if [ -n "$BASE_REF" ]; then
  PV_CMD+=(--base-ref "$BASE_REF")
fi
if [ "$RELEASE_CHECK" -eq 1 ]; then
  PV_CMD+=(--release-check)
fi

# --- steps -------------------------------------------------------------------

run_step "validate-skills" bash tools/validate-skills.sh
run_step "lattice-artifacts" python3 tools/validate-lattice-artifacts.py

if [ -n "$BASE_REF" ]; then
  if plugin_version_paths_changed; then
    run_step "plugin-versions" "${PV_CMD[@]}"
  else
    skip_step "plugin-versions" "no bundled paths changed vs $BASE_REF (mirrors lint-heavy path filter)"
  fi
else
  run_step "plugin-versions" "${PV_CMD[@]}"
fi

run_step "routing-evals" python3 tools/run-routing-evals.py --min-rank1 80
run_step "behavioral-validate" python3 tools/run-behavioral-evals.py --validate-only
run_step "behavioral-smoke" step_behavioral_smoke

if have claude; then
  run_step "plugin-validate" step_plugin_validate
else
  skip_step "plugin-validate" "claude CLI not installed (CI pins @2.1.216)"
fi

if have shellcheck; then
  run_step "shellcheck" step_shellcheck
else
  record "shellcheck" FAIL "shellcheck not installed"
  echo "==> shellcheck"
  echo "    FAIL: shellcheck not installed (CI installs it; apt-get install shellcheck)"
fi

run_step "symlink-integrity" step_symlinks

if [ "$FAST" -eq 1 ]; then
  skip_step "bats (all suites)" "--fast"
elif ! have bats; then
  record "bats (all suites)" FAIL "bats not installed"
  echo "==> bats"
  echo "    FAIL: bats not installed (CI installs it; apt-get install bats)"
else
  # lattice-scripts.yml discovery, verbatim.
  mapfile -t suites < <(find skills tools -type d \( -path '*/scripts/tests' -o -path 'tools/tests' \) | sort)
  for suite in "${suites[@]}"; do
    run_step "bats $suite" bats_shimmed "$suite" .
  done
  # plugin-hooks.yml runs from plugins/lattice as its working-directory.
  run_step "bats plugins/lattice/scripts/tests" bats_shimmed "scripts/tests/" "plugins/lattice"
fi

# --- summary -----------------------------------------------------------------

failures=0
printf '\n%-42s %-6s %s\n' "step" "result" "note"
printf '%-42s %-6s %s\n' "----" "------" "----"
for i in "${!STEP_NAMES[@]}"; do
  printf '%-42s %-6s %s\n' "${STEP_NAMES[$i]}" "${STEP_RESULTS[$i]}" "${STEP_NOTES[$i]}"
  if [ "${STEP_RESULTS[$i]}" = FAIL ]; then
    failures=$((failures + 1))
  fi
done

echo
if [ "$failures" -gt 0 ]; then
  echo "ci-local: $failures step(s) FAILED"
  exit 1
fi
echo "ci-local: all steps green (skips noted above)"
