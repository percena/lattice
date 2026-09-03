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
  cat <<'EOF'
ci-local: run locally, in one command, every check CI runs — so a green run
here predicts a green run on GitHub. Mirrors lint.yml, lint-heavy.yml,
lattice-scripts.yml, plugin-hooks.yml, plus validate-lattice-artifacts.py.

Usage: bash tools/ci-local.sh [--base-ref REF] [--release-check] [--fast]
  --base-ref REF   base for validate-plugin-versions and its path-filter skip
                   (default: fork point `git merge-base origin/dev HEAD`).
                   Must resolve to a commit — an unresolvable ref FAILs the
                   plugin-versions step; it never silently skips the gate.
  --release-check  simulate the dev→main release boundary: base-ref becomes
                   origin/main and the validator enforces the version-increment
                   invariant (bundled change without bump = error). Default is
                   dev-mode (lenient: only non-decrease enforced). [ADR-005]
  --fast           skip the bats suites (the slow step); default runs full

Note (tkt-239): changed_paths counts UNTRACKED files (git ls-files --others)
  in addition to the committed diff. CI's clean checkout only sees the
  committed set, so locally ci-local is a conservative superset of CI —
  scratch/untracked files under plugins/ skills/ can report bundle_changed
  (and under --release-check demand a bump) where CI would not. This fails
  closed locally (safe direction); commit or clean untracked files to match CI.

Bats version parity (spc-254 A9): the bats suites run with whatever bats is
  on PATH, but ci-local first checks it against BATS_PIN (the single version
  both CIs pin). A mismatch is reported DEGRADED (non-fatal): suites still run,
  but a local green may not predict GitHub CI. It is never silent. The
  installed-skill drift check runs only in dev mode (default), not under
  --release-check, and never overwrites the installed tree.

Steps never abort the run: each records pass/FAIL/skip/degraded, a summary
table prints at the end, and the exit code is nonzero if any step failed.
EOF
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
STEP_RESULTS=() # pass | FAIL | skip | degraded
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

# degrade_step <name> <note> — non-fatal advisory (does not fail the run).
# Used for environment-parity warnings (bats version mismatch, installed-skill
# drift) that do not by themselves predict a CI failure. spc-254 A9.
degrade_step() {
  printf '==> %s\n    DEGRADED: %s\n' "$1" "$2"
  record "$1" degraded "$2"
}

have() { command -v "$1" > /dev/null 2>&1; }

# --- bats version parity (spc-254 A9 / F7) -----------------------------------
# Single source of truth for the Bats version both CIs pin. ci-local refuses
# to silently use any PATH bats: it checks `bats --version` against this pin
# and reports DEGRADED on mismatch (suites still run, but local results may
# not predict GitHub CI). Both .github/workflows/lattice-scripts.yml and
# plugin-hooks.yml pin v1.13.0 — keep this in sync with them.
BATS_PIN="1.13.0"

# Echo the installed bats version string (e.g. "Bats 1.13.0") or empty.
bats_installed_version() {
  bats --version 2>/dev/null || true
}

# 0 if the installed bats matches the CI pin, 1 otherwise (or bats absent).
bats_version_matches_pin() {
  bats_installed_version | grep -qF "$BATS_PIN"
}

# --- step bodies -------------------------------------------------------------

# lint.yml shellcheck job: same file set and severity as CI.
step_shellcheck() {
  find skills plugins tools -name '*.sh' -print0 | xargs -0 shellcheck -S warning
}

# lint.yml symlink-integrity job.
step_symlinks() {
  local broken rc
  # tkt-239: capture find's exit status explicitly. With set -u -o pipefail
  # (no -e) an empty-stdout find failure (perm/cycle error on a subdir) would
  # leave broken="" and the [ -n "$broken" ] gate report PASS while find
  # actually failed — a false green. A non-zero find rc now surfaces as FAIL.
  broken="$(find . -type l ! -exec test -e {} \; -print 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "find exited non-zero (rc=$rc) during broken-symlink scan — cannot verify integrity"
    return 1
  fi
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
  local installed expected="2.1.216"
  installed=$(claude --version 2>/dev/null || true)
  if [ -z "$installed" ]; then
    echo "note: could not determine installed claude version (CI pins @${expected}); running validate with whatever is on PATH"
  elif printf '%s' "$installed" | grep -qF "$expected"; then
    echo "claude CLI: $installed (matches CI pin @${expected})"
  else
    echo "note: installed claude ($installed) differs from CI pin @${expected} — version drift is advisory; validate results may diverge from CI"
  fi
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

# A bogus ref must fail the gate, never let it vanish into a clean skip
# (git diff in plugin_version_paths_changed would yield nothing → "no bundled
# paths changed" → green run while CI fails hard on the same ref).
BASE_REF_OK=1
if [ -n "$BASE_REF" ] && ! git rev-parse --verify --quiet "$BASE_REF^{commit}" > /dev/null; then
  BASE_REF_OK=0
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

if [ "$BASE_REF_OK" -eq 0 ]; then
  record "plugin-versions" FAIL "unresolvable --base-ref: $BASE_REF"
  echo "==> plugin-versions"
  echo "    FAIL: --base-ref '$BASE_REF' does not resolve to a commit (refusing to skip the gate silently)"
elif [ -n "$BASE_REF" ]; then
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

if ! have bats; then
  record "bats-version-parity" FAIL "bats not installed"
  echo "==> bats-version-parity"
  echo "    FAIL: bats not installed (CI pins v$BATS_PIN; apt-get install bats)"
  record "bats (all suites)" FAIL "bats not installed"
  echo "==> bats"
  echo "    FAIL: bats not installed (CI installs it; apt-get install bats)"
else
  # spc-254 A9: refuse to silently use any PATH bats. Check the installed
  # version against BATS_PIN (what both CIs pin) before running suites.
  installed_bats_ver="$(bats_installed_version)"
  if bats_version_matches_pin; then
    record "bats-version-parity" pass "bats $installed_bats_ver == CI pin v$BATS_PIN"
    echo "==> bats-version-parity"
    echo "    pass: $installed_bats_ver matches CI pin v$BATS_PIN"
  else
    degrade_step "bats-version-parity" \
      "local bats (${installed_bats_ver:-unknown}) != CI pin v$BATS_PIN — suites still run, but local results may not predict GitHub CI"
  fi
  if [ "$FAST" -eq 1 ]; then
    # tkt-401: --fast still runs the quick assertion guard (<1s on 75 files)
    # to catch banned [[ ]] forms that would fail CI test 910. The full bats
    # suites are skipped (slow), but the guard is always run.
    if [ -f "$ROOT/tools/check-bats-assertions.py" ]; then
      run_step "bats-assertion-guard (--fast)" python3 "$ROOT/tools/check-bats-assertions.py"
    fi
    skip_step "bats (all suites)" "--fast (assertion guard ran above)"
  else
    # lattice-scripts.yml discovery, verbatim. Portable read (no mapfile, which
    # is bash 4+ — macOS default /bin/bash is 3.2 and lacks it).
    suites=(); while IFS= read -r _s; do suites+=("$_s"); done < <(find skills tools -type d \( -path '*/scripts/tests' -o -path 'tools/tests' \) | sort)
    for suite in "${suites[@]}"; do
      run_step "bats $suite" bats_shimmed "$suite" .
    done
    # plugin-hooks.yml runs from plugins/lattice as its working-directory.
    run_step "bats plugins/lattice/scripts/tests" bats_shimmed "scripts/tests/" "plugins/lattice"
  fi
fi

# --- installed-skill drift check (spc-254 A9 / F7) ---------------------------
# Runs only in Lattice dev mode (default, non-release). Advisory — not a CI
# check, so drift is DEGRADED (non-fatal) but surfaced. The underlying script
# NEVER writes to the installed tree (it is check-only by design), satisfying
# the "does not overwrite the installed tree" invariant.
DRIFT_CHECK="$ROOT/skills/_lattice-lib/scripts/check-installed-skill-drift.sh"
if [ "$RELEASE_CHECK" -eq 1 ]; then
  skip_step "installed-skill-drift" "release-check mode (dev-mode only; spc-254 A9)"
elif [ ! -d "$HOME/.claude/skills" ]; then
  skip_step "installed-skill-drift" "no installed skill home ($HOME/.claude/skills)"
else
  drift_log="$LOG_DIR/drift.log"
  if bash "$DRIFT_CHECK" --check-only > "$drift_log" 2>&1; then
    record "installed-skill-drift" pass "in sync"
    echo "==> installed-skill-drift"
    echo "    pass: installed skills in sync with repo"
  else
    drift_rc=$?
    if [ "$drift_rc" -eq 2 ]; then
      # exit 2 = misuse (bad args / missing dirs) — a real failure, not drift.
      record "installed-skill-drift" FAIL "misuse (exit $drift_rc)"
      echo "==> installed-skill-drift"
      echo "    FAIL: drift check exited $drift_rc (misuse); last output:"
      tail -n 60 "$drift_log" | sed 's/^/    | /'
    else
      degrade_step "installed-skill-drift" \
        "drift detected (exit $drift_rc) — refresh install; see docs/getting-started § Refresh install"
      tail -n 60 "$drift_log" | sed 's/^/    | /'
    fi
  fi
fi

# --- summary -----------------------------------------------------------------

failures=0
degraded=0
printf '\n%-42s %-9s %s\n' "step" "result" "note"
printf '%-42s %-9s %s\n' "----" "---------" "----"
for i in "${!STEP_NAMES[@]}"; do
  printf '%-42s %-9s %s\n' "${STEP_NAMES[$i]}" "${STEP_RESULTS[$i]}" "${STEP_NOTES[$i]}"
  case "${STEP_RESULTS[$i]}" in
    FAIL) failures=$((failures + 1)) ;;
    degraded) degraded=$((degraded + 1)) ;;
  esac
done

echo
if [ "$failures" -gt 0 ]; then
  echo "ci-local: $failures step(s) FAILED${degraded:+, $degraded degraded}"
  exit 1
fi
if [ "$degraded" -gt 0 ]; then
  echo "ci-local: all steps green, but $degraded degraded (parity warnings above — local may not predict CI)"
else
  echo "ci-local: all steps green (skips noted above)"
fi
