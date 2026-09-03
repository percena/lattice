#!/usr/bin/env bash
# Ensure a feature branch and optionally an isolated git worktree.
#
# Policy default: skills should call --mode worktree for any
# shippable work so the main checkout stays on base for orchestration / parallel
# slots. --mode branch remains supported as an explicit escape hatch (and tests).
#
# Usage:
#   ensure-workspace.sh --mode branch|worktree --branch <name> [options]
#   ensure-workspace.sh --mode branch|worktree --bind tkt|spc|spec --id <id> --slug <slug> [options]
#
# Bind form builds Percena names:
#   tkt  → branch/path tkt-<id>-<slug>     (id = GitHub issue number)
#   spc  → branch/path spc-<id>-<slug>     (id = primary GitHub issue # / Spec n, bare decimal)
#   spec → alias of spc (accepts N or legacy YYYY-MM-DD for migration)
# Optional --type feat|fix|chore|… → feat/tkt-N-slug (default is id-first, no prefix)
#
# Options:
#   --base <ref>           base branch/ref (default: config, GitHub, origin/HEAD, common refs)
#   --path <worktree-path> override worktree path
#   --type <kind>          optional type prefix (feat, fix, chore, docs, …)
#   --no-stamp             skip the queued → in-progress binder stamp (see below)
# Bind is the default for every shippable mode (worktree and branch):
#   use --bind tkt|spc|spec --id <id> --slug <slug>
#   or --branch that already matches tkt-<id>-* / spc-<n>-* (optional <type>/ prefix)
# Capability-first escape: --allow-unbound --reason <why/equivalent evidence>
# with an explicit semantic --branch. The JSON output records the escape.
#
# Env:
#   LATTICE_HOME   committed L0 root (default: <show-toplevel>/.lattice)
#   WORKTREE_ROOT  physical worktrees (default: <parent>/<repo-name>.worktrees — SIBLING of main checkout)
#
# Why sibling (not <repo>/.worktrees): avoids nested worktrees, double-indexing of the
# monorepo, and "recursive directory" pain when creating trees from an existing worktree.
# Override with WORKTREE_ROOT if you prefer in-repo .worktrees (gitignored).
#
# Path-point stamp (spc-337 A3 / ADR-012 §1): a successful `--bind tkt --id N`
# is the step every ticket passes through on its way to work, so it is the
# writer of the `queued → in-progress` edge. When exactly one
# <lattice_home>/tickets/tkt-N-*/README.md exists and its `| status |` is
# `queued`, the bind commits the edge through transition-api.py (owner
# `system`, reason `spawn`; ledger lands in the binder's own home). Any other
# status (in-progress on a re-bind, pr-open, rework, parked, stuck, deferred,
# closed) is left untouched; no binder → no-op; `--no-stamp` opts out; a stamp
# failure warns on stderr and the bind still exits 0. The JSON reports
# `stamped_in_progress`.
#
# stdout: single JSON object on success
set -euo pipefail

# Resolve the physical installed script directory, including when the
# entrypoint itself was reached through a symlink (tkt-239 — same pattern as
# ensure-lattice.sh / lattice-init.sh resolve_script_dir). The lexical
# BASH_SOURCE directory would let a consumer checkout place a fake
# resolve-integration-branch.sh / _lattice-home.sh beside a symlink to this
# trusted script and source it in-process (RCE). Both _RIB and SCRIPT_DIR_ENSURE
# below route through this resolver.
resolve_script_dir() {
  local source="$1"
  local dir target
  while [[ -L "$source" ]]; do
    dir="$(cd -P "$(dirname "$source")" && pwd)"
    target="$(readlink "$source")"
    if [[ "$target" == /* ]]; then
      source="$target"
    else
      source="$dir/$target"
    fi
  done
  cd -P "$(dirname "$source")" && pwd
}

MODE=""
BRANCH=""
BASE=""
WT_PATH=""
BIND=""
BIND_ID=""
SLUG=""
ALLOW_UNBOUND=false
ESCAPE_REASON=""
NO_STAMP=false

usage() {
  cat >&2 <<'EOF'
Usage:
  ensure-workspace.sh --mode branch|worktree --branch <name> [options]
  ensure-workspace.sh --mode branch|worktree --bind tkt|spc|spec --id <id> --slug <slug> [options]

Options: --base <ref>  --path <worktree-path>  --type <kind>
         --allow-unbound --reason <why/equivalent evidence>
         --no-stamp  (skip the queued → in-progress binder stamp on tkt bind)

Bind (default): --bind tkt|spc|spec --id <id> --slug <slug>
  or --branch matching tkt-<id>-* / spc-<n>-* (optional <type>/ prefix).
  Unbound names require explicit --allow-unbound plus a non-empty --reason.
EOF
  exit 2
}

TYPE_PREFIX=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --base) BASE="${2:-}"; shift 2 ;;
    --path) WT_PATH="${2:-}"; shift 2 ;;
    --bind) BIND="${2:-}"; shift 2 ;;
    --id) BIND_ID="${2:-}"; shift 2 ;;
    --slug) SLUG="${2:-}"; shift 2 ;;
    --type) TYPE_PREFIX="${2:-}"; shift 2 ;;
    --allow-unbound) ALLOW_UNBOUND=true; shift ;;
    --reason) ESCAPE_REASON="${2:-}"; shift 2 ;;
    --no-stamp) NO_STAMP=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

if [[ -n "$TYPE_PREFIX" ]]; then
  TYPE_PREFIX=$(printf '%s' "$TYPE_PREFIX" | tr '[:upper:]' '[:lower:]' | sed 's#/*$##')
  case "$TYPE_PREFIX" in
    feature) TYPE_PREFIX=feat ;;
    bugfix) TYPE_PREFIX=fix ;;
  esac
  case "$TYPE_PREFIX" in
    feat|fix|chore|docs|refactor|perf|test|spike|hotfix) ;;
    *)
      echo "Error: unsupported --type '$TYPE_PREFIX' (feat|fix|chore|docs|refactor|perf|test|spike|hotfix)" >&2
      exit 1
      ;;
  esac
fi

if [[ -z "$MODE" ]]; then
  usage
fi
if [[ "$MODE" != "branch" && "$MODE" != "worktree" ]]; then
  echo "Error: --mode must be branch or worktree" >&2
  exit 1
fi

if [[ -n "$BIND" ]]; then
  if [[ "$BIND" != "tkt" && "$BIND" != "spc" && "$BIND" != "spec" ]]; then
    echo "Error: --bind must be tkt, spc, or spec" >&2
    exit 1
  fi
  if [[ -z "$BIND_ID" || -z "$SLUG" ]]; then
    echo "Error: --bind requires --id and --slug" >&2
    exit 1
  fi
  # normalize slug: lowercase-ish, spaces to -, strip bad chars
  SLUG=$(printf '%s' "$SLUG" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')
  if [[ -z "$SLUG" ]]; then
    echo "Error: empty slug after normalize" >&2
    exit 1
  fi
  if [[ "$BIND" == "tkt" ]]; then
    if [[ ! "$BIND_ID" =~ ^[0-9]+$ ]]; then
      echo "Error: tkt --id must be numeric GitHub issue number, got: $BIND_ID" >&2
      exit 1
    fi
    if [[ "$BIND_ID" =~ ^0+$ ]]; then
      echo "Error: tkt --id must be a real GitHub issue (≥1); got: $BIND_ID. Docs-only still needs a real issue or Spec bind (spc-…); never tkt-0 / unbound names." >&2
      exit 1
    fi
    BRANCH="tkt-${BIND_ID}-${SLUG}"
  else
    # spc | spec — monotonic bare decimal; allow legacy YYYY-MM-DD
    if [[ "$BIND_ID" =~ ^[0-9]+$ ]]; then
      if [[ "$BIND_ID" =~ ^0+$ ]]; then
        echo "Error: spc --id must be a real Spec primary issue (≥1); got: $BIND_ID" >&2
        exit 1
      fi
      N=$((10#$BIND_ID))
      BRANCH="spc-${N}-${SLUG}"
    elif [[ "$BIND_ID" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
      # New date-shaped Spec binds fail closed (legacy paths may
      # still match BOUND_RE for already-existing branches, but --bind refuses).
      echo "Error: date-shaped spc id is no longer accepted for new binds ($BIND_ID); use monotonic spc-N (GitHub Spec primary issue number)" >&2
      exit 1
    else
      echo "Error: spc --id must be numeric N (≥1), got: $BIND_ID" >&2
      exit 1
    fi
  fi
  if [[ -n "$TYPE_PREFIX" ]]; then
    BRANCH="${TYPE_PREFIX}/${BRANCH}"
  fi
fi

if [[ -z "$BRANCH" ]]; then
  usage
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: not inside a git work tree" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required by ensure-workspace.sh" >&2
  exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
GIT_COMMON=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
if [[ -z "$GIT_COMMON" ]]; then
  # git < 2.31 fallback: relative rev-parse output is relative to CWD
  # (from a subdir it prints e.g. ../.git), so normalize against $PWD.
  # Keep in sync with cleanup-workspace.sh.
  GIT_COMMON=$(git rev-parse --git-common-dir)
  [[ "$GIT_COMMON" != /* ]] && GIT_COMMON="$PWD/$GIT_COMMON"
fi
if [[ "$GIT_COMMON" == */.git/modules/* ]]; then
  # Submodule checkouts nest their git dir under the superproject's
  # .git/modules/; mapping MAIN_ROOT there would place this submodule's
  # worktree beside the SUPERPROJECT (<super>.worktrees/…). Refuse instead of
  # guessing. Keep in sync with cleanup-workspace.sh.
  echo "Error: this checkout is a git submodule (git-common-dir: $GIT_COMMON)" >&2
  echo "  run ensure-workspace from the superproject or the submodule's own repository, not the embedded checkout" >&2
  exit 1
elif [[ "$GIT_COMMON" == */.git ]]; then
  MAIN_ROOT="${GIT_COMMON%/.git}"
elif [[ "$GIT_COMMON" == */.git/* ]]; then
  MAIN_ROOT="${GIT_COMMON%%/.git/*}"
else
  MAIN_ROOT="$REPO_ROOT"
fi
# Committed L0 default is current checkout top. For --mode worktree the
# shippable tree is PATH_OUT — retarget lattice_home after the worktree path is
# known (below) unless the caller already set LATTICE_HOME. Pool still MAIN_ROOT.
LATTICE_HOME_FROM_ENV=false
if [[ -n "${LATTICE_HOME:-}" ]]; then
  LATTICE_HOME_FROM_ENV=true
else
  LATTICE_HOME="$REPO_ROOT/.lattice"
fi

# Base resolution: optional config pin → gh default → origin/HEAD → fallbacks.
# Track source for agent observability (base_source in JSON).
BASE_SOURCE=""
if [[ -n "$BASE" ]]; then
  BASE_SOURCE="explicit"
fi

# config.yaml base_branch: (optional pin)
if [[ -z "$BASE" ]]; then
  CFG_HOME=""
  if [[ -n "${LATTICE_HOME:-}" && -f "${LATTICE_HOME}/config.yaml" ]]; then
    CFG_HOME="$LATTICE_HOME"
  elif [[ -f "$REPO_ROOT/.lattice/config.yaml" ]]; then
    CFG_HOME="$REPO_ROOT/.lattice"
  fi
  if [[ -n "$CFG_HOME" && -f "$CFG_HOME/config.yaml" ]]; then
    cfg_line=$(grep -E '^[[:space:]]*base_branch:[[:space:]]*' "$CFG_HOME/config.yaml" 2>/dev/null | head -1 || true)
    if [[ -n "$cfg_line" ]]; then
      BASE=$(printf '%s' "$cfg_line" | sed -E 's/^[[:space:]]*base_branch:[[:space:]]*//; s/[[:space:]]*[#].*$//; s/[\"'\'']//g' | tr -d '[:space:]')
      [[ -n "$BASE" ]] && BASE_SOURCE="config"
    fi
  fi
fi

# Integration-branch resolution: base on the user's long-lived branch
# when on one, or fork-point infer when on a temp branch — BEFORE the blind
# gh-default fallback. Fixes the dev-vs-main merge-target bug.
if [[ -z "$BASE" ]]; then
  _RIB="$(resolve_script_dir "${BASH_SOURCE[0]}")/resolve-integration-branch.sh"
  if [[ -f "$_RIB" ]]; then
    _UB=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)
    _RIB_JSON=$(bash "$_RIB" --repo-root "$REPO_ROOT" --user-branch "${_UB:-}" --head "${_UB:-}" --json 2>/dev/null || true)
    if [[ -n "$_RIB_JSON" ]]; then
      _REC=$(printf '%s' "$_RIB_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("recommended_base") or "")' 2>/dev/null || true)
      _SRC=$(printf '%s' "$_RIB_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("base_source") or "")' 2>/dev/null || true)
      if [[ -n "$_REC" && "$_SRC" != "ask" && "$_SRC" != "default" ]]; then
        BASE="$_REC"
        BASE_SOURCE="integration-branch:$_SRC"
      fi
    fi
  fi
fi

if [[ -z "$BASE" ]]; then
  # Prefer GitHub default branch (may differ from a stale origin/HEAD).
  if command -v gh >/dev/null 2>&1; then
    BASE=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || true)
    [[ -n "$BASE" ]] && BASE_SOURCE="gh-default"
  fi
  if [[ -z "$BASE" ]]; then
    BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@' || true)
    [[ -n "$BASE" ]] && BASE_SOURCE="origin-HEAD"
  fi
  if [[ -z "$BASE" ]]; then
    for cand in main master; do
      if git show-ref --verify --quiet "refs/remotes/origin/$cand" 2>/dev/null \
        || git show-ref --verify --quiet "refs/heads/$cand" 2>/dev/null; then
        BASE="$cand"
        BASE_SOURCE="fallback"
        break
      fi
    done
  fi
  if [[ -z "$BASE" ]]; then
    BASE=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    BASE_SOURCE="fallback"
  fi
fi
[[ -z "$BASE_SOURCE" ]] && BASE_SOURCE="unknown"

# The resolved base reaches `git fetch`, and `git fetch` keeps parsing options
# AFTER the positional <repository>, so a base beginning with '-' would be read
# as a flag (e.g. --upload-pack=./x runs a local program). BASE is not always
# operator-typed: it can come from a checked-out .lattice/config.yaml
# (base_branch:) or from remote branch names. Refuse anything that is not a
# well-formed ref before it is used anywhere.
assert_ref_shaped() {
  local ref="$1" what="$2"
  if [[ "$ref" == -* ]]; then
    echo "Error: $what must not start with '-' (option injection): $ref" >&2
    echo "  base_source: $BASE_SOURCE" >&2
    exit 1
  fi
  if ! git check-ref-format --allow-onelevel "$ref" >/dev/null 2>&1; then
    echo "Error: $what is not a valid git ref name: $ref" >&2
    echo "  base_source: $BASE_SOURCE" >&2
    exit 1
  fi
}
assert_ref_shaped "$BASE" "resolved base"

BASE_BRANCH_NAME="$BASE"
BASE_BRANCH_NAME="${BASE_BRANCH_NAME#refs/remotes/origin/}"
BASE_BRANCH_NAME="${BASE_BRANCH_NAME#refs/heads/}"
BASE_BRANCH_NAME="${BASE_BRANCH_NAME#origin/}"
# Stripping a prefix can expose a leading '-' that was legal mid-ref
# (origin/-x → -x); the short name is what gets fetched.
assert_ref_shaped "$BASE_BRANCH_NAME" "resolved base branch name"

# Freshness: fetch base before creating branch/worktree.
# Opt out: LATTICE_SKIP_FETCH=1 or ENSURE_SKIP_FETCH=1 (offline). Truthiness,
# not set-ness: only 1/true/yes/on (case-insensitive) skip; 0/false/no/off/empty fetch.
FETCHED=false
SKIP_FETCH=false
case "$(printf '%s' "${LATTICE_SKIP_FETCH:-${ENSURE_SKIP_FETCH:-}}" | tr '[:upper:]' '[:lower:]')" in
  1|true|yes|on) SKIP_FETCH=true ;;
esac
if ! $SKIP_FETCH; then
  if git remote get-url origin >/dev/null 2>&1; then
    # Fetch the SHORT name: `git fetch origin origin/main` asks the remote for a
    # ref literally named "origin/main", which always fails and forces the
    # whole-remote fallback below. `--` stops option parsing (see
    # assert_ref_shaped above for why that matters).
    if git fetch origin --quiet -- "$BASE_BRANCH_NAME" 2>/dev/null || git fetch origin --quiet 2>/dev/null; then
      FETCHED=true
    else
      echo "ensure-workspace: WARNING — git fetch origin failed; using local refs for base='$BASE' (stale risk)" >&2
    fi
  fi
else
  echo "ensure-workspace: skip fetch (LATTICE_SKIP_FETCH/ENSURE_SKIP_FETCH set)" >&2
fi

# Resolve the selected base to a real commit once. A successful fetch must affect
# actual workspace ancestry: unqualified names prefer the fresh origin-tracking
# ref. Qualified refs retain their exact requested meaning. Never silently fall
# back to current HEAD when the declared base cannot be found.
BASE_START=""
BASE_CANDIDATES=()
case "$BASE" in
  refs/*|origin/*)
    BASE_CANDIDATES=("$BASE")
    ;;
  *)
    if $FETCHED && git show-ref --verify --quiet "refs/remotes/origin/$BASE_BRANCH_NAME" 2>/dev/null; then
      BASE_CANDIDATES=("refs/remotes/origin/$BASE_BRANCH_NAME" "$BASE" "refs/heads/$BASE_BRANCH_NAME")
    else
      # Preserve offline/failed-fetch behavior: prefer the caller's local short
      # name before any possibly stale remote-tracking ref.
      BASE_CANDIDATES=("$BASE" "refs/heads/$BASE_BRANCH_NAME" "refs/remotes/origin/$BASE_BRANCH_NAME")
    fi
    ;;
esac
for base_candidate in "${BASE_CANDIDATES[@]}"; do
  if git rev-parse --verify --quiet "${base_candidate}^{commit}" >/dev/null 2>&1; then
    BASE_START="$base_candidate"
    break
  fi
done
if [[ -z "$BASE_START" ]]; then
  echo "Error: resolved base is not available as a commit: $BASE" >&2
  exit 1
fi
BASE_START_OID=$(git rev-parse "${BASE_START}^{commit}")

DIRTY=false
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  DIRTY=true
fi

# Soft warn when the *caller* tree is dirty (common: pre-worktree L0 on base).
# Worktree mode still proceeds so rescue is possible, but agents must NOT keep
# writing on the dirty base — shippable work continues only under PATH_OUT.
if $DIRTY; then
  cat >&2 <<'EOF'
ensure-workspace: WARNING — caller working tree is dirty (was_dirty=true).
  If you already wrote binders/Specs/lineage on the team base, STOP writing there.
  After this command, cd to the worktree path and continue only in that tree.
  Prefer: open WORKSPACE *before* any shippable L0 write (assert-shippable-cwd.sh).
  Finish path: check-base-residue.sh on MAIN after merge if pull is blocked.
EOF
fi

# Default shippable identity binds tkt- or spc-. Capability-first callers may
# choose a semantic unbound branch when they record a reason/equivalent proof.
BOUND_RE='^([a-z]+/)?(tkt-[1-9][0-9]*-|spc-[1-9][0-9]*-|spc-[0-9]{4}-[0-9]{2}-[0-9]{2}-)'
IS_BOUND=true
if [[ ! "$BRANCH" =~ $BOUND_RE ]]; then
  IS_BOUND=false
  if $ALLOW_UNBOUND; then
    if [[ -n "$BIND" ]]; then
      echo "Error: --allow-unbound cannot be combined with --bind" >&2
      exit 1
    fi
    if [[ -z "$ESCAPE_REASON" ]]; then
      echo "Error: --allow-unbound requires --reason describing ownership, scope, or equivalent delivery evidence" >&2
      exit 1
    fi
    if ! git check-ref-format --branch "$BRANCH" >/dev/null 2>&1; then
      echo "Error: invalid unbound branch name: $BRANCH" >&2
      exit 1
    fi
    case "$BRANCH" in
      main|master|dev|develop|trunk|production|prod|"$BASE_BRANCH_NAME")
        echo "Error: --allow-unbound cannot target a protected/team-base branch: $BRANCH" >&2
        exit 1
        ;;
    esac
    echo "ensure-workspace: capability escape — unbound workspace accepted with explicit reason" >&2
    echo "  branch: $BRANCH" >&2
    echo "  reason: $ESCAPE_REASON" >&2
  else
  cat >&2 <<EOF
Error: workspace branch should bind a ticket or Spec (tkt-<issue≥1>-* or spc-<n≥1>-*; optional <type>/ prefix).
  got: $BRANCH
  mode: $MODE

Required:
  --bind tkt --id <GitHub-issue-number≥1> --slug <slug>
  --bind spc --id <monotonic-n> --slug <slug>
  (or --branch that already matches the pattern above)

Default:
  use a bound name for durable recovery and lineage.

Capability-first escape:
  --branch <semantic-name> --allow-unbound --reason <ownership/scope/evidence>

Always invalid:
  tkt-0 / spc-0 / fake ids

If you do not have an issue or Spec yet, stop and create one (start-work /
create-tickets / create-spec) before calling ensure-workspace again.
EOF
  exit 1
  fi
fi

REUSED_EXISTING_BRANCH=false
create_branch_from_base() {
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    REUSED_EXISTING_BRANCH=true
    return 0
  fi
  # Freeze the resolved commit so a concurrent ref update cannot make the
  # created branch disagree with base_start_oid telemetry on *new* branches.
  # Existing branches keep their tip; workspace_head_oid reports the truth.
  local create_err
  if ! create_err=$(git branch "$BRANCH" "$BASE_START_OID" 2>&1 >/dev/null); then
    # TOCTOU: a concurrent same-bind call can create the branch between the
    # show-ref probe above and this create. If the ref exists now, adopt it
    # as a reuse; any other failure is real.
    if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
      REUSED_EXISTING_BRANCH=true
      return 0
    fi
    printf '%s\n' "$create_err" >&2
    echo "Error: could not create branch '$BRANCH' from $BASE_START_OID" >&2
    return 1
  fi
}

if [[ "$MODE" == "branch" ]]; then
  if $DIRTY; then
    echo "Error: working tree is dirty; use --mode worktree or clean/stash first." >&2
    exit 1
  fi
  # Under strict profile, a --mode branch lives on the main clone as a non-base
  # branch. L2 (assert-shippable-cwd) now fails that, and L3 (Write hook) blocks
  # shippable writes on it (spc-145/ADR-006). Warn loudly so the escape is not
  # mistaken for a usable workspace; prefer --mode worktree. Resolve profile
  # inline (lattice_profile is sourced later).
  _BRANCH_PROFILE="${LATTICE_PROFILE:-}"
  if [[ -z "$_BRANCH_PROFILE" ]]; then
    for _cfg in "$REPO_ROOT/.lattice/config.yaml" "$LATTICE_HOME/config.yaml"; do
      [[ -f "$_cfg" ]] || continue
      _line=$(grep -E '^[[:space:]]*profile:[[:space:]]*' "$_cfg" 2>/dev/null | head -1 || true)
      if [[ -n "$_line" ]]; then
        _BRANCH_PROFILE=$(printf '%s' "$_line" | sed -E 's/^[[:space:]]*profile:[[:space:]]*//; s/[[:space:]]*[#].*$//; s/["'"'"']//g' | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
        break
      fi
    done
  fi
  case "$_BRANCH_PROFILE" in light|strict) ;; *) _BRANCH_PROFILE="strict" ;; esac
  if [[ "$_BRANCH_PROFILE" == "strict" ]]; then
    echo "ensure-workspace: profile=strict — WARNING: --mode branch sits on the main clone; L2/L3 write-block shippable writes on it." >&2
    echo "  Each shippable write needs assert-shippable-cwd --allow-base-write --reason \"user-authorized: <why>\". Prefer --mode worktree." >&2
  fi
  CURRENT=$(git branch --show-current 2>/dev/null || true)
  # Quiet on success, but keep stderr so a failed checkout says why.
  if [[ "$CURRENT" == "$BRANCH" ]]; then
    REUSED_EXISTING_BRANCH=true
  elif git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    REUSED_EXISTING_BRANCH=true
    git checkout --quiet "$BRANCH"
  else
    git checkout --quiet -b "$BRANCH" "$BASE_START_OID"
  fi
  PATH_OUT="$REPO_ROOT"
else
  # Physical worktrees: sibling of main checkout by default (never under .claude/)
  #   e.g. /src/myrepo.worktrees/tkt-N-foo   alongside /src/myrepo
  if [[ -n "${WORKTREE_ROOT:-}" ]]; then
    WT_ROOT="$WORKTREE_ROOT"
  else
    REPO_BASENAME=$(basename "$MAIN_ROOT")
    WT_ROOT="$(dirname "$MAIN_ROOT")/${REPO_BASENAME}.worktrees"
  fi
  mkdir -p "$WT_ROOT"
  if [[ -z "$WT_PATH" ]]; then
    SAFE_BRANCH=${BRANCH//\//-}
    WT_PATH="$WT_ROOT/$SAFE_BRANCH"
  fi
  create_branch_from_base
  if [[ -d "$WT_PATH" ]]; then
    # Being inside *some* work tree is not enough: a plain subdirectory of the
    # main checkout, or a stale worktree on another branch, would silently
    # route shippable writes to the wrong branch. Require the path to be the
    # worktree root AND have the target branch checked out.
    WT_TOP=$(git -C "$WT_PATH" rev-parse --show-toplevel 2>/dev/null || true)
    WT_BR=$(git -C "$WT_PATH" branch --show-current 2>/dev/null || true)
    WT_COMMON=$(git -C "$WT_PATH" rev-parse --path-format=absolute --git-common-dir 2>/dev/null \
      || git -C "$WT_PATH" rev-parse --git-common-dir 2>/dev/null || true)
    [[ -n "$WT_COMMON" && "$WT_COMMON" != /* ]] && WT_COMMON="$WT_PATH/$WT_COMMON"
    if [[ -z "$WT_TOP" ]]; then
      echo "Error: path exists and is not a git worktree: $WT_PATH" >&2
      exit 1
    elif [[ "$(cd "$WT_TOP" && pwd -P)" != "$(cd "$WT_PATH" && pwd -P)" ]]; then
      echo "Error: path exists but is not a worktree root (toplevel: $WT_TOP): $WT_PATH" >&2
      exit 1
    elif [[ -z "$WT_COMMON" || "$(cd "$WT_COMMON" 2>/dev/null && pwd -P)" != "$(cd "$GIT_COMMON" 2>/dev/null && pwd -P)" ]]; then
      # Same branch name + toplevel is not enough: with a shared WORKTREE_ROOT
      # another repository's worktree can sit at this exact path, and adopting
      # it would silently route commits into the wrong repository.
      echo "Error: path exists but belongs to another repository (git-common-dir: ${WT_COMMON:-unknown}, expected: $GIT_COMMON): $WT_PATH" >&2
      echo "Hint: set WORKTREE_ROOT per repository or pass --path" >&2
      exit 1
    elif [[ "$WT_BR" != "$BRANCH" ]]; then
      echo "Error: path exists but has '${WT_BR:-detached}' checked out, expected '$BRANCH': $WT_PATH" >&2
      echo "Hint: remove the stale worktree (cleanup-workspace.sh) or pass --path" >&2
      exit 1
    fi
    PATH_OUT="$WT_PATH"
  else
    if ! git worktree add --quiet "$WT_PATH" "$BRANCH" >/dev/null; then
      # No residue: when create_branch_from_base created the branch in THIS
      # run, delete it again so a failed add leaves nothing unexplained.
      # Reused pre-existing branches are never touched.
      if [[ "$REUSED_EXISTING_BRANCH" == false ]]; then
        git branch -D "$BRANCH" >/dev/null 2>&1 || true
        echo "Error: git worktree add failed for $WT_PATH — removed just-created branch '$BRANCH' (no residue left)" >&2
      else
        echo "Error: git worktree add failed for $WT_PATH — existing branch '$BRANCH' left untouched" >&2
      fi
      echo "Hint: check the git error above (path collision? permissions?), then re-run ensure-workspace" >&2
      exit 1
    fi
    PATH_OUT="$WT_PATH"
  fi
fi

# Worktree EXECUTE: committed L0 belongs on the worktree tip, not the caller
# checkout (usually team base). Honour explicit LATTICE_HOME from the environment.
if [[ "$MODE" == "worktree" && "$LATTICE_HOME_FROM_ENV" == false && "$PATH_OUT" != "$REPO_ROOT" ]]; then
  LATTICE_HOME="$PATH_OUT/.lattice"
fi
export LATTICE_HOME

# Actual workspace tip after create/reuse. Distinct from base_start_oid, which is
# the resolved *requested* base used only when creating a new branch.
WORKSPACE_HEAD_OID=$(git -C "$PATH_OUT" rev-parse HEAD)

export ENSURE_MODE="$MODE"
export ENSURE_BRANCH="$BRANCH"
export ENSURE_BASE="$BASE"
export ENSURE_BASE_SOURCE="${BASE_SOURCE:-unknown}"
export ENSURE_BASE_START="$BASE_START"
export ENSURE_BASE_START_OID="$BASE_START_OID"
export ENSURE_WORKSPACE_HEAD_OID="$WORKSPACE_HEAD_OID"
export ENSURE_REUSED_EXISTING_BRANCH="$REUSED_EXISTING_BRANCH"
export ENSURE_FETCHED="$FETCHED"
export ENSURE_PATH="$PATH_OUT"
export ENSURE_DIRTY="$DIRTY"
export ENSURE_REPO="$REPO_ROOT"
export ENSURE_BIND="${BIND:-}"
export ENSURE_BIND_ID="${BIND_ID:-}"
export ENSURE_SLUG="${SLUG:-}"
export ENSURE_BOUND="$IS_BOUND"
export ENSURE_ESCAPE_REASON="$ESCAPE_REASON"

# Profile — informational; worktree remains the default.
SCRIPT_DIR_ENSURE="$(resolve_script_dir "${BASH_SOURCE[0]}")"
ENSURE_PROFILE="strict"
if [[ -f "$SCRIPT_DIR_ENSURE/_lattice-home.sh" ]]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR_ENSURE/_lattice-home.sh"
  ENSURE_PROFILE=$(lattice_profile 2>/dev/null || echo "strict")
elif [[ -n "${LATTICE_PROFILE:-}" ]]; then
  ENSURE_PROFILE=$(printf '%s' "$LATTICE_PROFILE" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
fi
case "$ENSURE_PROFILE" in light|strict) ;; *) ENSURE_PROFILE="strict" ;; esac
export ENSURE_PROFILE
if [[ "$ENSURE_PROFILE" == "light" && "$MODE" == "branch" ]]; then
  echo "ensure-workspace: profile=light — shippable --mode branch allowed" >&2
elif [[ "$ENSURE_PROFILE" == "strict" && "$MODE" == "branch" ]]; then
  echo "ensure-workspace: profile=strict — --mode branch is user escape hatch; default remains worktree" >&2
fi

# --- Path-point stamp: queued → in-progress (spc-337 A3 / ADR-012 §1) ---------
# The bind is the writer of this edge. Runs AFTER the workspace exists and
# BEFORE the JSON is emitted so the result is reportable. Never changes the
# exit code: a stamp failure is a stderr warning, the bind already succeeded.
STAMPED_IN_PROGRESS=false
stamp_in_progress() {
  local id="$1" home="$2"
  local api="$SCRIPT_DIR_ENSURE/transition-api.py"
  local binder="" d n=0 status
  [[ -d "$home/tickets" ]] || return 0
  # tkt-<id>-* matches the id segment exactly (the trailing dash stops
  # tkt-3- from matching tkt-33-…). Exactly one directory, else no-op.
  for d in "$home/tickets/tkt-${id}-"*/; do
    [[ -d "$d" ]] || continue
    n=$((n + 1))
    binder="${d%/}/README.md"
  done
  if [[ "$n" -ne 1 || ! -f "$binder" ]]; then
    return 0
  fi
  status=$(grep -m1 -E '^\| *status *\|' "$binder" 2>/dev/null \
    | awk -F'|' '{ v=$3; gsub(/^[ \t]+|[ \t]+$/, "", v); print v }' || true)
  # Only the queued → in-progress edge belongs to the bind. A re-bind sees
  # in-progress (no-op, idempotent); pr-open / rework / parked / stuck /
  # deferred / closed hold state other path points own — untouched.
  [[ "$status" == "queued" ]] || return 0
  if [[ ! -f "$api" ]]; then
    echo "ensure-workspace: WARNING — transition-api.py missing beside this script; queued → in-progress not stamped for tkt-$id" >&2
    return 0
  fi
  # stdout is reserved for the JSON contract: route the API's "committed:"
  # line to stderr.
  if python3 "$api" commit "tkt-$id" in-progress system spawn --binder "$binder" >&2; then
    STAMPED_IN_PROGRESS=true
  else
    echo "ensure-workspace: WARNING — queued → in-progress stamp FAILED for tkt-$id (bind succeeded; binder: $binder)." >&2
    echo "  Re-run the transition: python3 $(printf '%q' "$api") commit tkt-$id in-progress system spawn --binder $(printf '%q' "$binder")" >&2
  fi
}
if [[ "$BIND" == "tkt" && "$NO_STAMP" == false ]]; then
  stamp_in_progress "$BIND_ID" "$LATTICE_HOME"
elif [[ "$BIND" == "tkt" ]]; then
  echo "ensure-workspace: --no-stamp — queued → in-progress stamp skipped for tkt-$BIND_ID" >&2
fi
export ENSURE_STAMPED_IN_PROGRESS="$STAMPED_IN_PROGRESS"

# Agent-facing hint: shippable writes must use this path (cwd / -C / working_directory).
if [[ "$MODE" == "worktree" ]]; then
  echo "ensure-workspace: use worktree path for all shippable Write/Edit/git/gh:" >&2
  echo "  cd $(printf '%q' "$PATH_OUT")" >&2
  echo "  lattice_home=$(printf '%q' "$LATTICE_HOME")" >&2
fi

python3 - <<'PY'
import json, os
path = os.environ["ENSURE_PATH"]
mode = os.environ["ENSURE_MODE"]
print(json.dumps({
  "ok": True,
  "mode": mode,
  "branch": os.environ["ENSURE_BRANCH"],
  "base": os.environ["ENSURE_BASE"],
  "base_source": os.environ.get("ENSURE_BASE_SOURCE") or "unknown",
  "base_start": os.environ["ENSURE_BASE_START"],
  "base_start_oid": os.environ["ENSURE_BASE_START_OID"],
  "workspace_head_oid": os.environ.get("ENSURE_WORKSPACE_HEAD_OID") or None,
  "reused_existing_branch": os.environ.get("ENSURE_REUSED_EXISTING_BRANCH") == "true",
  "fetched": os.environ.get("ENSURE_FETCHED") == "true",
  "path": path,
  "was_dirty": os.environ["ENSURE_DIRTY"] == "true",
  "repo_root": os.environ["ENSURE_REPO"],
  "bind": os.environ.get("ENSURE_BIND") or None,
  "bind_id": os.environ.get("ENSURE_BIND_ID") or None,
  "slug": os.environ.get("ENSURE_SLUG") or None,
  "cd_hint": f"cd {path}" if mode == "worktree" else None,
  "lattice_home": os.environ.get("LATTICE_HOME") or None,
  "profile": os.environ.get("ENSURE_PROFILE") or "strict",
  "bound": os.environ.get("ENSURE_BOUND") == "true",
  "escape_reason": os.environ.get("ENSURE_ESCAPE_REASON") or None,
  "stamped_in_progress": os.environ.get("ENSURE_STAMPED_IN_PROGRESS") == "true",
}))
PY
