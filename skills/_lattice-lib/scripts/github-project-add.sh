#!/usr/bin/env bash
# Best-effort: add a GitHub issue or PR URL to an optional org/user Project.
#
# Canonical home: skills/_lattice-lib/scripts/. Callers:
#   create-tickets / start-work / create-spec (issues), create-pr (new PRs)
#
# Usage:
#   bash github-project-add.sh <issue-or-pr-url>
#   bash github-project-add.sh --url <url>
#
# Exit: always 0 (soft-fail). Missing config → silent no-op.
# Logs go to stderr only.
#
# Enable when BOTH owner and number are set (env wins over file for each key):
#   LATTICE_GITHUB_PROJECT_OWNER
#   LATTICE_GITHUB_PROJECT_NUMBER
# Optional:
#   LATTICE_GITHUB_PROJECT_ADD_ISSUES  (default true)
#   LATTICE_GITHUB_PROJECT_ADD_PRS     (default true)
#   LATTICE_GITHUB_PROJECT_ALLOW_DOTENV (default false) — explicit opt-in to
#       trust a repo .env that targets an org/other-owner board. A .env whose
#       OWNER equals the authenticated `gh` user (your OWN board) is auto-
#       trusted and needs no opt-in.
#
# File load: MAIN_ROOT/.env then MAIN_ROOT/.env.local (local overrides file).
# Process env wins when the variable is set. MAIN_ROOT = primary checkout.
#
# Requires `gh` with `project` scope when enabled:
#   gh auth refresh -s project

set -uo pipefail

log() { printf 'github-project-add: %s\n' "$*" >&2; }

# --- MAIN_ROOT (inline; keep aligned with _lattice-home.sh / ensure-workspace) ---
main_root() {
  local repo_root git_common root
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 1
  fi
  repo_root=$(git rev-parse --show-toplevel)
  git_common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  if [[ -z "$git_common" ]]; then
    git_common=$(git rev-parse --git-common-dir)
    [[ "$git_common" != /* ]] && git_common="$PWD/$git_common"
  fi
  if [[ "$git_common" == */.git ]]; then
    root="${git_common%/.git}"
  elif [[ "$git_common" == */.git/* ]]; then
    root="${git_common%%/.git/*}"
  else
    root="$repo_root"
  fi
  printf '%s' "$root"
}

# Parse allowlisted KEY=value from a dotenv file into FILE_* vars (never source).
# Later files overwrite earlier file values. Process env is applied after files.
load_dotenv_file_into() {
  local file="$1"
  [[ -f "$file" && -r "$file" ]] || return 0
  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == export\ * ]] && line="${line#export }"
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    val="${line#*=}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    case "$key" in
      LATTICE_GITHUB_PROJECT_OWNER | LATTICE_GITHUB_PROJECT_NUMBER | \
      LATTICE_GITHUB_PROJECT_ADD_ISSUES | LATTICE_GITHUB_PROJECT_ADD_PRS) ;;
      *) continue ;;
    esac
    # Quoted value: the quoted span IS the value — a ` # ` inside quotes is
    # data, anything after the closing quote (e.g. a comment) is dropped.
    # Unquoted: strip from the first ` #` (space-hash); `value#fragment`
    # without the space keeps the hash (documented dotenv behavior).
    if [[ "$val" == \"* ]]; then
      val="${val#\"}"
      val="${val%%\"*}"
    elif [[ "$val" == \'* ]]; then
      val="${val#\'}"
      val="${val%%\'*}"
    else
      if [[ "$val" == *" #"* ]]; then
        val="${val%% #*}"
      fi
      val="${val%"${val##*[![:space:]]}"}"
    fi
    case "$key" in
      LATTICE_GITHUB_PROJECT_OWNER) FILE_OWNER="$val" ;;
      LATTICE_GITHUB_PROJECT_NUMBER) FILE_NUMBER="$val" ;;
      LATTICE_GITHUB_PROJECT_ADD_ISSUES) FILE_ADD_ISSUES="$val" ;;
      LATTICE_GITHUB_PROJECT_ADD_PRS) FILE_ADD_PRS="$val" ;;
    esac
  done <"$file"
}

falsy() {
  case "${1:-}" in
    0 | false | FALSE | False | no | NO | No | off | OFF) return 0 ;;
    *) return 1 ;;
  esac
}

# Default true when unset/empty; false only when explicitly falsy.
flag_enabled() {
  local v="${1:-}"
  if [[ -z "$v" ]]; then
    return 0
  fi
  if falsy "$v"; then
    return 1
  fi
  return 0
}

url_kind() {
  # prints: issue | pr | unknown
  local u="$1"
  if [[ "$u" == */pull/* || "$u" == */pulls/* ]]; then
    printf 'pr'
  elif [[ "$u" == */issues/* ]]; then
    printf 'issue'
  else
    printf 'unknown'
  fi
}

URL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      # Missing value must not hang: `shift 2 || true` leaves $1 forever.
      if [[ $# -lt 2 || -z "${2-}" || "${2-}" == -* ]]; then
        log "--url requires a value — skip"
        exit 0
      fi
      URL="$2"
      shift 2
      ;;
    --url=*)
      URL="${1#--url=}"
      if [[ -z "$URL" ]]; then
        log "--url requires a value — skip"
        exit 0
      fi
      shift
      ;;
    -h | --help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      log "unknown flag: $1 (ignored)"
      shift
      ;;
    *)
      if [[ -z "$URL" ]]; then
        URL="$1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$URL" ]]; then
  log "no URL — skip"
  exit 0
fi

# Normalize accidental whitespace
URL="${URL//[$'\t\r\n ']/}"

if [[ "$URL" != https://github.com/* && "$URL" != http://github.com/* ]]; then
  log "not a github.com URL — skip ($URL)"
  exit 0
fi

FILE_OWNER=""
FILE_NUMBER=""
FILE_ADD_ISSUES=""
FILE_ADD_PRS=""
ROOT=""
if ROOT=$(main_root 2>/dev/null); then
  # .env then .env.local (local overrides file); process env still wins below
  load_dotenv_file_into "$ROOT/.env"
  load_dotenv_file_into "$ROOT/.env.local"
fi

# Process environment wins when the variable is set (including empty).
if [[ -n "${LATTICE_GITHUB_PROJECT_OWNER+x}" ]]; then
  OWNER="$LATTICE_GITHUB_PROJECT_OWNER"
else
  OWNER="$FILE_OWNER"
fi
if [[ -n "${LATTICE_GITHUB_PROJECT_NUMBER+x}" ]]; then
  NUMBER="$LATTICE_GITHUB_PROJECT_NUMBER"
else
  NUMBER="$FILE_NUMBER"
fi
if [[ -n "${LATTICE_GITHUB_PROJECT_ADD_ISSUES+x}" ]]; then
  ADD_ISSUES="$LATTICE_GITHUB_PROJECT_ADD_ISSUES"
else
  ADD_ISSUES="$FILE_ADD_ISSUES"
fi
if [[ -n "${LATTICE_GITHUB_PROJECT_ADD_PRS+x}" ]]; then
  ADD_PRS="$LATTICE_GITHUB_PROJECT_ADD_PRS"
else
  ADD_PRS="$FILE_ADD_PRS"
fi

# trim
OWNER="${OWNER#"${OWNER%%[![:space:]]*}"}"
OWNER="${OWNER%"${OWNER##*[![:space:]]}"}"
NUMBER="${NUMBER#"${NUMBER%%[![:space:]]*}"}"
NUMBER="${NUMBER%"${NUMBER##*[![:space:]]}"}"

if [[ -z "$OWNER" || -z "$NUMBER" ]]; then
  # Quiet no-op when not configured (public default).
  exit 0
fi

if ! [[ "$NUMBER" =~ ^[0-9]+$ ]]; then
  log "LATTICE_GITHUB_PROJECT_NUMBER must be digits (got '$NUMBER') — skip"
  exit 0
fi
# This helper MUTATES an external surface (gh project item-add) with the user's
# token. A `.env` is a file in the checked-out repository, so a cloned or
# untrusted repo could otherwise redirect every item this workflow creates onto
# a third-party board simply by committing one. A repository file may therefore
# SUGGEST a target but never authorize the write on its own: the operator must
# confirm it through the process environment (which only they control) or opt in
# explicitly. Reads are advisory and stay softer — see list-board-items.sh.
DOTENV_CHOSE_TARGET=false
[[ -z "${LATTICE_GITHUB_PROJECT_OWNER+x}" && -n "$FILE_OWNER" && "$OWNER" == "$FILE_OWNER" ]] && DOTENV_CHOSE_TARGET=true
[[ -z "${LATTICE_GITHUB_PROJECT_NUMBER+x}" && -n "$FILE_NUMBER" && "$NUMBER" == "$FILE_NUMBER" ]] && DOTENV_CHOSE_TARGET=true
if $DOTENV_CHOSE_TARGET; then
  # Auto-trust: if the .env-selected board owner == the authenticated `gh` user,
  # the write targets the operator's OWN board — inherently non-abusable (a
  # third party cannot be the redirect target unless the owner IS the user), so
  # no explicit LATTICE_GITHUB_PROJECT_ALLOW_DOTENV is required. This removes the
  # common silent-no-op friction for single-user/self boards. Soft-fail: if
  # `gh api user` cannot resolve (no auth / no network), do NOT auto-trust —
  # fall through to the explicit opt-in below (fail closed when self-ownership
  # is unprovable). GitHub logins are case-insensitive.
  AUTH_USER="$(gh api user --jq .login 2>/dev/null || true)"
  OWNER_LOWER="$(printf '%s' "$OWNER" | tr '[:upper:]' '[:lower:]')"
  AUTH_USER_LOWER="$(printf '%s' "$AUTH_USER" | tr '[:upper:]' '[:lower:]')"
  if [[ -n "$AUTH_USER_LOWER" && "$OWNER_LOWER" == "$AUTH_USER_LOWER" ]]; then
    log "board target $OWNER/$NUMBER owned by authenticated user ($AUTH_USER) — auto-trusted, no LATTICE_GITHUB_PROJECT_ALLOW_DOTENV needed"
  else
    ALLOW_DOTENV=false
    case "$(printf '%s' "${LATTICE_GITHUB_PROJECT_ALLOW_DOTENV:-}" | tr '[:upper:]' '[:lower:]')" in
      1|true|yes|on) ALLOW_DOTENV=true ;;
    esac
    if ! $ALLOW_DOTENV; then
      log "skip: repository .env selects Project $OWNER/$NUMBER, but a repo file cannot authorize writing to an external board"
      log "  export LATTICE_GITHUB_PROJECT_OWNER/_NUMBER in your environment, set LATTICE_GITHUB_PROJECT_ALLOW_DOTENV=1, or ensure OWNER ($OWNER) is your own gh login"
      exit 0
    fi
    log "board target from repository .env, allowed by LATTICE_GITHUB_PROJECT_ALLOW_DOTENV: owner=$OWNER project=$NUMBER"
  fi
fi

kind=$(url_kind "$URL")
case "$kind" in
  issue)
    if ! flag_enabled "$ADD_ISSUES"; then
      log "ADD_ISSUES disabled — skip"
      exit 0
    fi
    ;;
  pr)
    if ! flag_enabled "$ADD_PRS"; then
      log "ADD_PRS disabled — skip"
      exit 0
    fi
    ;;
  unknown)
    if ! flag_enabled "$ADD_ISSUES" && ! flag_enabled "$ADD_PRS"; then
      log "both ADD_ISSUES and ADD_PRS disabled — skip"
      exit 0
    fi
    ;;
esac

if ! command -v gh >/dev/null 2>&1; then
  log "gh not on PATH — skip"
  exit 0
fi

out=""
status=0
out=$(gh project item-add "$NUMBER" --owner "$OWNER" --url "$URL" 2>&1) || status=$?

if [[ $status -eq 0 ]]; then
  log "added to $OWNER/projects/$NUMBER — $URL"
  exit 0
fi

# Treat already-present as success
if printf '%s' "$out" | grep -qiE 'already|duplicate|exists'; then
  log "already on $OWNER/projects/$NUMBER — $URL"
  exit 0
fi

if printf '%s' "$out" | grep -qiE 'INSUFFICIENT_SCOPES|required scopes|read:project|project.*scope'; then
  log "gh missing project scope — run: gh auth refresh -s project"
  log "detail: $out"
  exit 0
fi

log "item-add failed (non-fatal) for $URL"
log "detail: $out"
exit 0
