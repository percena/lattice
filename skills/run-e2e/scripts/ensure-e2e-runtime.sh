#!/usr/bin/env sh
# ensure-e2e-runtime.sh — platform-aware e2e runtime preflight for run-e2e.
#
# Implements ADR-009: macOS uses ego-lite (ego-browser CLI); Linux uses
# camoufox-js driven via Playwright, surfaced through playwright-cli.
#
# This script DETECTS. It never auto-installs. On a missing runtime it prints
# install guidance to stderr and exits non-zero so the calling agent surfaces
# it to the user and WAITS for explicit confirmation before installing.
# After install, the presence check is re-run on every invocation; passing it
# is the gate, so subsequent runs proceed directly without re-prompting.
# No sentinel file is needed.
#
# Usage:
#   bash skills/run-e2e/scripts/ensure-e2e-runtime.sh
#   E2E_BACKEND=$(bash skills/run-e2e/scripts/ensure-e2e-runtime.sh)   # exits 0 on ready
#
# Output on success (stdout): "E2E_BACKEND=<ego|camoufox>"
# Output on failure (stderr): install guidance; exit status 1.
set -eu

platform=$(uname -s)

print_macos_guidance() {
  cat >&2 <<'EOF'
[ensure-e2e-runtime] macOS backend (ego-lite) is not installed.

ego-lite is macOS-only. Install it from the ego-lite macOS DMG flow:
  1. Download the DMG for your arch:
     - Apple Silicon: https://cdn.ego.app/setup/macos/arm64/egolite.dmg
     - Intel:          https://cdn.ego.app/setup/macos/x64/egolite.dmg
  2. Open the DMG and drag "ego lite" to /Applications.
  3. Launch "ego lite" once to complete onboarding (registers the `ego-browser`
     command on PATH, normally under $HOME/.local/bin).
  4. If `command -v ego-browser` still fails, ensure PATH includes:
       export PATH="$HOME/.local/bin:$PATH"

Full install reference: the ego-browser skill's references/install.md.

Confirm with the user before running any install step.
EOF
}

print_linux_guidance() {
  missing="$1"
  cat >&2 <<EOF
[ensure-e2e-runtime] Linux backend (camoufox-js via Playwright) is not ready.

Missing: ${missing}

Install steps (confirm with the user before running):
  npm install -g camoufox-js          # Node port of the camoufox anti-detect browser
  npx camoufox-js fetch               # download the patched Firefox binary (~hundreds of MB)
  npm install -g @playwright/cli@latest   # playwright-cli surface

Set CAMOUFOX_INSTALL_DIR if you need the browser binary in a non-default location
(e.g. on a headless VPS with an ephemeral home):
  CAMOUFOX_INSTALL_DIR=/opt/camoufox npx camoufox-js fetch

Fallback (NOT primary): the camoufox Python remote-server
(`python -m camoufox server` -> firefox.connect(ws://...)) is experimental with
non-rotating fingerprints — only use it for pool/fingerprint-rotation at scale.
EOF
}

have_ego_browser() {
  command -v ego-browser >/dev/null 2>&1
}

have_camoufox_js() {
  if command -v camoufox-js >/dev/null 2>&1; then
    return 0
  fi
  if command -v npx >/dev/null 2>&1; then
    npx --no-install camoufox-js --version >/dev/null 2>&1 && return 0
  fi
  return 1
}

have_camoufox_browser() {
  # The patched Firefox binary fetched by `npx camoufox-js fetch`.
  dir="${CAMOUFOX_INSTALL_DIR:-$HOME/.cache/camoufox}"
  [ -d "$dir" ] || return 1
  # Heuristic: the fetch step populates the dir with the camoufox binary tree.
  [ -n "$(ls -A "$dir" 2>/dev/null)" ] || return 1
  return 0
}

have_playwright_cli() {
  if command -v playwright-cli >/dev/null 2>&1; then
    return 0
  fi
  if command -v npx >/dev/null 2>&1; then
    npx --no-install playwright-cli --version >/dev/null 2>&1 && return 0
  fi
  return 1
}

case "$platform" in
  Darwin)
    if have_ego_browser; then
      echo "E2E_BACKEND=ego"
      exit 0
    fi
    print_macos_guidance
    exit 1
    ;;
  Linux)
    missing=""
    have_camoufox_js       || missing="camoufox-js (npm package)"
    have_camoufox_browser  || missing="${missing:+$missing, }camoufox browser (run: npx camoufox-js fetch)"
    have_playwright_cli    || missing="${missing:+$missing, }playwright-cli (npm i -g @playwright/cli)"
    if [ -z "$missing" ]; then
      echo "E2E_BACKEND=camoufox"
      exit 0
    fi
    print_linux_guidance "$missing"
    exit 1
    ;;
  *)
    cat >&2 <<EOF
[ensure-e2e-runtime] Unsupported platform: ${platform}
run-e2e supports macOS (ego-lite) and Linux (camoufox-js via playwright-cli) only.
EOF
    exit 1
    ;;
esac
