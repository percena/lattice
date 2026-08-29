#!/usr/bin/env bash
# ensure-python3.sh — fail-fast with a friendly, platform-specific install
# hint when python3 is absent (or is the macOS Command Line Tools stub).
#
# Standalone-callable (Decision D4, spc-212): no single sourced common library
# reaches every python3 call site, so scripts call this as a subprocess:
#
#     bash "$ENSURE_PY" || exit 1
#
# Exit codes:
#   0  — python3 is present and usable (real interpreter, not the macOS stub)
#   1  — python3 is absent or is the macOS stub without CLT; install hint on stderr
#
# Why a filesystem check on macOS (not python3 -c): /usr/bin/python3 is a stub
# that triggers a GUI install dialog when invoked. Running it to "test" would
# hang non-interactive/SSH/Claude-Code-Bash contexts. We detect the stub without
# ever invoking it.
set -euo pipefail

# Is python3 present AND a real interpreter (not the macOS CLT stub)?
python3_is_real() {
  command -v python3 >/dev/null 2>&1 || return 1
  if [[ "$(uname -s)" == "Darwin" ]]; then
    local p
    p=$(command -v python3 2>/dev/null || true)
    # The stub lives at /usr/bin/python3; the real CLT interpreter lives under
    # /Library/Developer/CommandLineTools. If CLT is absent, the stub cannot run
    # code — treat as missing.
    if [[ "$p" == "/usr/bin/python3" ]] && [[ ! -x /Library/Developer/CommandLineTools/usr/bin/python3 ]]; then
      return 1
    fi
  fi
  return 0
}

emit_hint() {
  local cmd=""
  case "$(uname -s)" in
    Darwin)
      cmd="xcode-select --install    (or: brew install python)"
      ;;
    Linux)
      if [[ -r /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release 2>/dev/null || true
        case "${ID:-}" in
          arch|endeavouros|manjaro|garuda) cmd="sudo pacman -S python" ;;
          alpine)                          cmd="sudo apk add python3" ;;
          debian|ubuntu|linuxmint|pop|elementary) cmd="sudo apt-get install -y python3" ;;
          fedora|rhel|centos|rocky|almalinux|opensuse-leap|opensuse-tumbleweed) cmd="sudo dnf install -y python3" ;;
          *) cmd="install python3 via your package manager" ;;
        esac
      else
        cmd="install python3 via your package manager"
      fi
      ;;
    *) cmd="install python3 — https://www.python.org/downloads/" ;;
  esac
  echo "Error: python3 is required by Lattice but was not found (or is the macOS stub)." >&2
  echo "  Install:  $cmd" >&2
  echo "  Lattice uses python3 (stdlib only, no pip needed)." >&2
}

if python3_is_real; then
  exit 0
fi

emit_hint >&2
exit 1
