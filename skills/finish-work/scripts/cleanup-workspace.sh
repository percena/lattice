#!/usr/bin/env bash
# Remove a Percena feature branch and its git worktree after merge/close.
#
# Usage:
#   cleanup-workspace.sh --branch <name> [options]
#
# Options:
#   --worktree-path <path>  explicit worktree path
#   --pr <number>            verify merged PR/head identity before squash cleanup
#   --delete-remote         legacy no-op (remote delete is the default)
#   --keep-remote           skip git push origin --delete <branch>
#   --force                 allow dirty removal + exact-OID ref deletion
#   --dry-run               print actions only
#   --keep-branch           remove worktree only; keep local branch
#   --keep-worktree         skip worktree removal; checked-out branch is preserved
#
# Env:
#   LATTICE_HOME   binders root (default: <main-repo>/.lattice)
#   WORKTREE_ROOT  physical worktrees (default: sibling <repo-name>.worktrees)
#
# Default: after local cleanup, delete the remote head when it still exists
# (repos often leave delete_branch_on_merge off; gh --delete-branch can also
# be omitted). Use --keep-remote to opt out.
#
# Order is intentional: worktree remove → local branch → remote delete.
# A local and remote branch with the same name are independent refs. Local safe
# ancestry or merged-PR proof only authorizes the exact OID it proved. Local
# fallback deletion uses compare-and-delete; remote deletion uses an OID lease.
# A ref is preserved if it diverges or changes after proof.
#
# --dry-run stays offline for remotes and must not claim deleted_local_branch /
# ok:true when the real path would preserve an unmerged tip.
#
# Protected branch names are never deleted locally or remotely by this helper.
# stdout: JSON summary (last line); exit 0 on success, 1 on preserved/residual work
set -euo pipefail

# Fail fast with a friendly install hint if python3 is absent (spc-212 A2/D3).
# Cleanup is destructive; identity verification needs python3, so refuse rather
# than blind-delete on a python3-less system.
bash "$(dirname "${BASH_SOURCE[0]}")/../../_lattice-lib/scripts/ensure-python3.sh" || exit 1

BRANCH=""
WT_PATH=""
WT_PATH_EXPLICIT=false
PR_N=""
DELETE_REMOTE=true
FORCE=false
DRY_RUN=false
KEEP_BRANCH=false
KEEP_WORKTREE=false

usage() {
  cat >&2 <<'EOF'
Usage: cleanup-workspace.sh --branch <name> [options]
  --worktree-path <path>  --pr <number>  --delete-remote  --keep-remote
  --force  --dry-run  --keep-branch  --keep-worktree
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --worktree-path) WT_PATH="${2:-}"; WT_PATH_EXPLICIT=true; shift 2 ;;
    --pr) PR_N="${2:-}"; shift 2 ;;
    --delete-remote) DELETE_REMOTE=true; shift ;;
    --keep-remote) DELETE_REMOTE=false; shift ;;
    --force) FORCE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --keep-branch) KEEP_BRANCH=true; shift ;;
    --keep-worktree) KEEP_WORKTREE=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

if [[ -z "$BRANCH" ]]; then
  usage
fi
if [[ -n "$PR_N" && ! "$PR_N" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: --pr must be a positive GitHub PR number, got: $PR_N" >&2
  exit 2
fi
# $BRANCH is interpolated into refnames, awk -v values and ls-remote patterns.
# Every current use is quoted or refs/heads/-prefixed, but validating here keeps
# that true for future edits and matches ensure-workspace.sh's check on create.
if [[ "$BRANCH" == -* ]] || ! git check-ref-format --branch "$BRANCH" >/dev/null 2>&1; then
  echo "Error: --branch is not a valid git branch name: $BRANCH" >&2
  exit 2
fi

# python3 preflight comes first: every JSON emission below needs it, so this
# is the one abort that legitimately cannot honour the JSON contract.
if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required by cleanup-workspace.sh" >&2
  exit 1
fi

# Refusals and aborts that exit before the full summary emitter still honor
# the "stdout: JSON summary (last line)" contract: ok:false + reason, fail
# closed. Defaults are safe before MAIN_ROOT/WT_PATH are derived.
JSON_EMITTED=false
emit_refusal_json() {
  CU_REASON="$1" CU_BRANCH="${BRANCH:-}" CU_WT="${WT_PATH:-}" \
    CU_MAIN="${MAIN_ROOT:-}" CU_DIRTY="${DIRTY:-false}" python3 - <<'PY'
import json, os
print(json.dumps({
    "ok": False,
    "reason": os.environ["CU_REASON"],
    "branch": os.environ["CU_BRANCH"],
    "worktree_path": os.environ["CU_WT"] or None,
    "main_root": os.environ["CU_MAIN"] or None,
    "was_dirty": os.environ.get("CU_DIRTY") == "true",
    "removed_worktree": False,
    "deleted_local_branch": False,
    "deleted_remote_branch": False,
    "unsafe_delete_blocked": True,
}))
PY
  JSON_EMITTED=true
}

# Backstop for set -e aborts (e.g. a failed run() command): the contract line
# must still be the last stdout line. exit 2 (usage) stays JSON-free.
# Also owns ACTION_LOG removal — a second `trap ... EXIT` would REPLACE this
# one and silently disable the JSON backstop for everything after it.
cleanup_exit_trap() {
  local st=$?
  if [[ $st -ne 0 && $st -ne 2 && "$JSON_EMITTED" == false ]]; then
    emit_refusal_json "internal_error"
  fi
  [[ -n "${ACTION_LOG:-}" ]] && rm -f "$ACTION_LOG"
}
trap cleanup_exit_trap EXIT

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: not inside a git work tree" >&2
  emit_refusal_json "not_inside_git_work_tree"
  exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
GIT_COMMON=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
if [[ -z "$GIT_COMMON" ]]; then
  # git < 2.31 fallback: relative rev-parse output is relative to CWD
  # (from a subdir it prints e.g. ../.git), so normalize against $PWD.
  # Keep in sync with ensure-workspace.sh.
  GIT_COMMON=$(git rev-parse --git-common-dir)
  [[ "$GIT_COMMON" != /* ]] && GIT_COMMON="$PWD/$GIT_COMMON"
fi
if [[ "$GIT_COMMON" == */.git/modules/* ]]; then
  # Submodule checkouts nest their git dir under the superproject's
  # .git/modules/; mapping MAIN_ROOT there would aim branch deletion at the
  # superproject. Refuse instead of guessing.
  echo "Error: this checkout is a git submodule (git-common-dir: $GIT_COMMON)" >&2
  echo "  run cleanup from the superproject or the submodule's own repository, not the embedded checkout" >&2
  emit_refusal_json "submodule_checkout"
  exit 1
elif [[ "$GIT_COMMON" == */.git ]]; then
  MAIN_ROOT="${GIT_COMMON%/.git}"
elif [[ "$GIT_COMMON" == */.git/* ]]; then
  MAIN_ROOT="${GIT_COMMON%%/.git/*}"
else
  MAIN_ROOT="$REPO_ROOT"
fi

# Committed L0 is per-checkout; cleanup only needs MAIN_ROOT for worktrees.
LATTICE_HOME="${LATTICE_HOME:-$REPO_ROOT/.lattice}"
if [[ -n "${WORKTREE_ROOT:-}" ]]; then
  WT_ROOT="$WORKTREE_ROOT"
else
  REPO_BASENAME=$(basename "$MAIN_ROOT")
  SIBLING="$(dirname "$MAIN_ROOT")/${REPO_BASENAME}.worktrees"
  if [[ -d "$SIBLING" ]]; then
    WT_ROOT="$SIBLING"
  elif [[ -d "$MAIN_ROOT/.worktrees" ]]; then
    WT_ROOT="$MAIN_ROOT/.worktrees"
  else
    WT_ROOT="$SIBLING"
  fi
fi

if [[ -z "$WT_PATH" ]]; then
  # Porcelain paths may contain spaces: take everything after "worktree ".
  CANDIDATE=$(git worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/$BRANCH" '
    $1=="worktree" { p=substr($0, 10) }
    $1=="branch" && $2==b { print p; exit }
  ')
  if [[ -n "$CANDIDATE" ]]; then
    WT_PATH="$CANDIDATE"
  else
    SAFE=${BRANCH//\//-}
    if [[ -d "$WT_ROOT/$SAFE" ]]; then
      WT_PATH="$WT_ROOT/$SAFE"
    elif [[ -d "$WT_ROOT/$BRANCH" ]]; then
      WT_PATH="$WT_ROOT/$BRANCH"
    fi
  fi
fi

# An explicit or discovered worktree path is only a claim
# until porcelain proves it is a registered checkout of exactly --branch.
# --force may authorize dirty/unmerged policy, never path↔branch identity.
WT_IDENTITY_REASON=""
WT_OBSERVED_REF=""
WT_IDENTITY_BLOCKED=false

normalize_path() {
  local raw="${1:-}"
  [[ -z "$raw" ]] && return 0
  if [[ -d "$raw" ]]; then
    (cd "$raw" && pwd -P)
  else
    # Non-existent paths still need a stable absolute form for porcelain compare.
    local dir base
    dir=$(dirname -- "$raw")
    base=$(basename -- "$raw")
    if [[ -d "$dir" ]]; then
      printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
    else
      printf '%s\n' "$raw"
    fi
  fi
}

if [[ -n "$WT_PATH" ]]; then
  ABS_WT_CLAIM=$(normalize_path "$WT_PATH" || true)
  export CU_WT_CLAIM="${ABS_WT_CLAIM:-$WT_PATH}"
  export CU_WT_WANT_BRANCH="$BRANCH"
  # Feed porcelain on stdin; keep the program in -c so the heredoc cannot steal it.
  # shellcheck disable=SC2016
  identity_json=$(
    git -C "$MAIN_ROOT" worktree list --porcelain 2>/dev/null | python3 -c '
import json, os, sys

want = os.environ.get("CU_WT_WANT_BRANCH") or ""
claim = os.environ.get("CU_WT_CLAIM") or ""

def norm(path):
    path = path.rstrip("/")
    try:
        return os.path.realpath(path)
    except OSError:
        return os.path.abspath(path)

claim_n = norm(claim) if claim else ""
entries = []
cur = None
for raw in sys.stdin.read().splitlines():
    if raw.startswith("worktree "):
        if cur is not None:
            entries.append(cur)
        cur = {"path": raw[len("worktree "):], "branch": None, "detached": False, "bare": False}
    elif cur is None:
        continue
    elif raw.startswith("branch "):
        cur["branch"] = raw[len("branch "):]
    elif raw == "detached":
        cur["detached"] = True
    elif raw == "bare":
        cur["bare"] = True
    elif raw == "":
        entries.append(cur)
        cur = None
if cur is not None:
    entries.append(cur)

match = None
for entry in entries:
    if norm(entry["path"]) == claim_n:
        match = entry
        break

if not claim:
    payload = {"status": "empty", "reason": "", "observed_ref": None}
elif match is None:
    payload = {
        "status": "unregistered",
        "reason": "worktree_path_unregistered",
        "observed_ref": None,
    }
elif match.get("bare"):
    payload = {
        "status": "mismatch",
        "reason": "worktree_path_bare",
        "observed_ref": "bare",
    }
elif match.get("detached") or not match.get("branch"):
    payload = {
        "status": "mismatch",
        "reason": "worktree_path_detached",
        "observed_ref": "detached",
    }
else:
    observed = match["branch"]
    expected = "refs/heads/" + want
    if observed == expected:
        payload = {
            "status": "ok",
            "reason": "",
            "observed_ref": observed,
            "path": match["path"],
        }
    else:
        payload = {
            "status": "mismatch",
            "reason": "worktree_path_branch_mismatch",
            "observed_ref": observed,
        }
print(json.dumps(payload, separators=(",", ":")))
'
  )
  WT_IDENTITY_STATUS=$(printf '%s' "$identity_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status") or "")')
  WT_IDENTITY_REASON=$(printf '%s' "$identity_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("reason") or "")')
  WT_OBSERVED_REF=$(printf '%s' "$identity_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("observed_ref") or "")')
  RESOLVED_WT=$(printf '%s' "$identity_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("path") or "")')
  if [[ -n "$RESOLVED_WT" ]]; then
    WT_PATH="$RESOLVED_WT"
  fi

  if [[ "$WT_IDENTITY_STATUS" != "ok" && "$WT_IDENTITY_STATUS" != "empty" ]]; then
    # Only block when the claim could cause removal (path exists) or was explicit.
    if $WT_PATH_EXPLICIT || [[ -d "$WT_PATH" ]]; then
      WT_IDENTITY_BLOCKED=true
      case "$WT_IDENTITY_REASON" in
        worktree_path_branch_mismatch)
          echo "Error: worktree path does not check out branch '$BRANCH' (observed: ${WT_OBSERVED_REF:-unknown}): $WT_PATH" >&2
          echo "  --force cannot bypass path↔branch identity" >&2
          ;;
        worktree_path_detached)
          echo "Error: worktree path is detached; refusing removal for branch '$BRANCH': $WT_PATH" >&2
          echo "  --force cannot bypass path↔branch identity" >&2
          ;;
        worktree_path_unregistered)
          echo "Error: worktree path is not a registered worktree of this repository: $WT_PATH" >&2
          echo "  --force cannot bypass path↔branch identity" >&2
          ;;
        *)
          echo "Error: worktree path failed identity proof for branch '$BRANCH': $WT_PATH ($WT_IDENTITY_REASON)" >&2
          ;;
      esac
    fi
  fi
fi

# ACTION_LOG removal lives in cleanup_exit_trap: re-trapping EXIT here would
# replace the JSON backstop for the whole destructive phase below.
ACTION_LOG=$(mktemp)

log_action() {
  printf '%s\n' "$1" >>"$ACTION_LOG"
}

run() {
  local desc="$*"
  if $DRY_RUN; then
    log_action "DRY: $desc"
  else
    log_action "$desc"
    "$@"
  fi
}

# emit_refusal_json is defined near the top (after the python3 preflight) so
# every abort path — including the EXIT-trap backstop — can honour the
# "stdout: JSON summary (last line)" contract.

# Protect conventional high-risk names plus every default/base name we can
# resolve locally. Use a union: stale metadata should make cleanup more
# conservative, never less.
PROTECTED_BRANCHES=(main master dev develop trunk production prod)
add_protected_branch() {
  local name="${1:-}"
  name="${name#refs/remotes/origin/}"
  name="${name#refs/heads/}"
  name="${name#origin/}"
  if [[ -n "$name" ]]; then
    PROTECTED_BRANCHES+=("$name")
  fi
}

if [[ -f "$MAIN_ROOT/.lattice/config.yaml" ]]; then
  configured_base=$(grep -E '^[[:space:]]*base_branch:[[:space:]]*' "$MAIN_ROOT/.lattice/config.yaml" 2>/dev/null | head -1 | sed -E "s/^[[:space:]]*base_branch:[[:space:]]*//; s/[[:space:]]*[#].*$//; s/[\"']//g" | tr -d '[:space:]' || true)
  add_protected_branch "$configured_base"
fi
origin_head=$(git -C "$MAIN_ROOT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
add_protected_branch "$origin_head"
if command -v gh >/dev/null 2>&1 && git -C "$MAIN_ROOT" remote get-url origin >/dev/null 2>&1; then
  github_default=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || true)
  add_protected_branch "$github_default"
fi

# Protected branches are never cleanup targets, including when the local ref is
# absent but a same-named remote ref still exists.
is_protected_branch() {
  local candidate
  for candidate in "${PROTECTED_BRANCHES[@]}"; do
    [[ "$1" == "$candidate" ]] && return 0
  done
  return 1
}

MERGED_PROOF=false
MERGED_PROOF_REASON="none"
LOCAL_PR_PROOF=false
REMOTE_PR_PROOF=false
PR_HEAD_OID=""
LOCAL_TIP_OID=""
REMOTE_TIP_OID=""
REMOTE_AFTER_OID=""
LOCAL_DELETED_OID=""
REMOTE_DELETE_EXPECTED_OID=""
REMOTE_ORIGIN_CONFIGURED=false
REMOTE_PROBED=false
REMOTE_PROBE_FAILED=false

refresh_local_tip() {
  LOCAL_TIP_OID=""
  if git -C "$MAIN_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    LOCAL_TIP_OID=$(git -C "$MAIN_ROOT" rev-parse "refs/heads/$BRANCH^{commit}")
  fi
}

# `git ls-remote --heads origin <pattern>` matches the TAIL of a refname, so the
# pattern "tkt-8-foo" also matches refs/heads/a/tkt-8-foo — and the sibling sorts
# FIRST, so `awk NR==1` would return another branch's OID. Every remote decision
# below binds a delete lease to an exact observed OID, so a wrong pick either
# refuses a correct cleanup or reports a phantom residual after a good delete.
# Query the fully-qualified refname and accept only an exact match.
ls_remote_head() {
  git -C "$MAIN_ROOT" ls-remote --heads origin "refs/heads/$BRANCH" 2>/dev/null
}
exact_remote_head_oid() {
  awk -v want="refs/heads/$BRANCH" '$2==want {print $1; exit}'
}

probe_remote_tip() {
  REMOTE_PROBED=true
  REMOTE_PROBE_FAILED=false
  REMOTE_TIP_OID=""
  local output st
  set +e
  output=$(ls_remote_head)
  st=$?
  set -e
  if [[ $st -ne 0 ]]; then
    REMOTE_PROBE_FAILED=true
    return 1
  fi
  REMOTE_TIP_OID=$(printf '%s\n' "$output" | exact_remote_head_oid)
  return 0
}

refresh_local_tip
if git -C "$MAIN_ROOT" remote get-url origin >/dev/null 2>&1; then
  REMOTE_ORIGIN_CONFIGURED=true
fi
# Real remote cleanup needs one observed OID before any local ref is removed.
# Dry-run deliberately remains offline and reports only conditional intent.
if $DELETE_REMOTE && ! $DRY_RUN && $REMOTE_ORIGIN_CONFIGURED; then
  if ! probe_remote_tip; then
    echo "Error: could not inspect remote branch origin/$BRANCH; preserving remote cleanup" >&2
    log_action "remote probe failed before cleanup: origin/$BRANCH"
  fi
fi

if [[ -n "$PR_N" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "Error: --pr verification requires gh" >&2
    emit_refusal_json "gh_required_for_pr_verification"
    exit 1
  fi
  set +e
  PR_JSON=$(gh pr view "$PR_N" --json state,headRefName,isCrossRepository,headRefOid 2>/dev/null)
  PR_ST=$?
  set -e
  if [[ $PR_ST -ne 0 || -z "$PR_JSON" ]]; then
    echo "Error: could not verify PR #$PR_N before destructive cleanup" >&2
    emit_refusal_json "pr_verification_failed"
    exit 1
  fi
  # Identity gate (fail closed): MERGED + same-repo + head name. Local and
  # remote tip gates are evaluated independently below.
  PR_IDENTITY_JSON=$(PR_JSON="$PR_JSON" BRANCH="$BRANCH" python3 - <<'PY'
import json, os, sys
branch = os.environ["BRANCH"]
try:
    data = json.loads(os.environ["PR_JSON"])
except Exception:
    raise SystemExit(1)
identity_ok = (
    data.get("state") == "MERGED"
    and data.get("headRefName") == branch
    and data.get("isCrossRepository") is not True
)
if not identity_ok:
    raise SystemExit(2)
head_oid = str(data.get("headRefOid") or "").strip()
if not head_oid:
    raise SystemExit(3)
print(head_oid)
PY
) || {
    st=$?
    if [[ $st -eq 2 ]]; then
      echo "Error: PR #$PR_N is not a merged same-repository PR for head '$BRANCH'" >&2
    elif [[ $st -eq 3 ]]; then
      echo "Error: PR #$PR_N is missing headRefOid; cannot tip-bind cleanup proof" >&2
    else
      echo "Error: could not parse PR #$PR_N verification payload" >&2
    fi
    emit_refusal_json "pr_identity_gate_failed"
    exit 1
  }
  PR_HEAD_OID="$PR_IDENTITY_JSON"

  proof_targets=0
  proof_mismatches=0
  if [[ -n "$LOCAL_TIP_OID" ]]; then
    proof_targets=$((proof_targets + 1))
    if [[ "$LOCAL_TIP_OID" == "$PR_HEAD_OID" ]]; then
      LOCAL_PR_PROOF=true
      log_action "verified local ref at merged PR #$PR_N head OID: $LOCAL_TIP_OID"
    else
      proof_mismatches=$((proof_mismatches + 1))
      echo "Warning: local branch tip does not match PR #$PR_N headRefOid" >&2
      echo "  pr headRefOid: $PR_HEAD_OID" >&2
      echo "  local tip:     $LOCAL_TIP_OID" >&2
      log_action "reject local PR proof for #$PR_N (pr=$PR_HEAD_OID local=$LOCAL_TIP_OID)"
    fi
  fi

  if $DELETE_REMOTE && ! $DRY_RUN && $REMOTE_ORIGIN_CONFIGURED && ! $REMOTE_PROBE_FAILED && [[ -n "$REMOTE_TIP_OID" ]]; then
    proof_targets=$((proof_targets + 1))
    if [[ "$REMOTE_TIP_OID" == "$PR_HEAD_OID" ]]; then
      REMOTE_PR_PROOF=true
      log_action "verified remote ref at merged PR #$PR_N head OID: $REMOTE_TIP_OID"
    else
      proof_mismatches=$((proof_mismatches + 1))
      echo "Warning: remote branch tip does not match PR #$PR_N headRefOid" >&2
      echo "  pr headRefOid: $PR_HEAD_OID" >&2
      echo "  remote tip:    $REMOTE_TIP_OID" >&2
      log_action "reject remote PR proof for #$PR_N (pr=$PR_HEAD_OID remote=$REMOTE_TIP_OID)"
    fi
  elif $DELETE_REMOTE && ! $DRY_RUN && $REMOTE_PROBE_FAILED; then
    proof_mismatches=$((proof_mismatches + 1))
  fi

  if [[ $proof_mismatches -gt 0 ]]; then
    MERGED_PROOF_REASON="pr-$PR_N-ref-mismatch"
  elif [[ $proof_targets -eq 0 ]]; then
    MERGED_PROOF=true
    MERGED_PROOF_REASON="pr-$PR_N-merged-head-match-no-observed-tip"
    log_action "verified merged PR #$PR_N identity (no targeted ref tip observed)"
  else
    MERGED_PROOF=true
    MERGED_PROOF_REASON="pr-$PR_N-all-observed-ref-oids-match"
  fi
fi

# Check one exact OID against the current MAIN HEAD. Deletion later uses the
# same OID as update-ref's expected old value, so ref changes fail atomically.
oid_fully_merged() {
  local oid="${1:-}"
  [[ -n "$oid" ]] || return 1
  local main_head
  main_head=$(git -C "$MAIN_ROOT" rev-parse HEAD 2>/dev/null) || return 1
  git -C "$MAIN_ROOT" merge-base --is-ancestor "$oid" "$main_head" 2>/dev/null
}

delete_local_ref_exact() {
  local expected_oid="$1"
  local reason="$2"
  if $DRY_RUN; then
    log_action "DRY: git -C $MAIN_ROOT update-ref -d refs/heads/$BRANCH $expected_oid ($reason)"
    DELETED_LOCAL=true
    LOCAL_DELETE_SAFE=true
    LOCAL_DELETED_OID="$expected_oid"
    return 0
  fi

  set +e
  git -C "$MAIN_ROOT" update-ref -d "refs/heads/$BRANCH" "$expected_oid"
  local st=$?
  set -e
  if [[ $st -eq 0 ]] && ! git -C "$MAIN_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    DELETED_LOCAL=true
    LOCAL_DELETE_SAFE=true
    LOCAL_DELETED_OID="$expected_oid"
    log_action "delete local ref at expected OID $expected_oid ($reason): $BRANCH"
    return 0
  fi

  echo "Error: local branch changed after proof; preserving current ref: $BRANCH" >&2
  log_action "local compare-and-delete failed (expected=$expected_oid reason=$reason): $BRANCH"
  UNSAFE_DELETE_BLOCKED=true
  return 1
}

UNSAFE_DELETE_BLOCKED=false
DRY_DIRTY_BLOCKED=false
CHECKED_OUT_REF_BLOCKED=false
DIRTY=false

if $WT_IDENTITY_BLOCKED; then
  UNSAFE_DELETE_BLOCKED=true
  log_action "preserve worktree; path identity failed ($WT_IDENTITY_REASON): $WT_PATH (observed=${WT_OBSERVED_REF:-none})"
fi

if ! $WT_IDENTITY_BLOCKED && [[ -n "$WT_PATH" && -d "$WT_PATH" ]]; then
  if git -C "$WT_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ -n "$(git -C "$WT_PATH" status --porcelain 2>/dev/null)" ]]; then
      DIRTY=true
    fi
  fi
fi

if $DIRTY && ! $FORCE && ! $DRY_RUN; then
  echo "Error: worktree is dirty: $WT_PATH (commit/stash or pass --force)" >&2
  emit_refusal_json "dirty_worktree"
  exit 1
fi
if $DIRTY && $DRY_RUN && ! $FORCE; then
  echo "Warning: worktree is dirty; dry-run predicts non-force cleanup refusal: $WT_PATH" >&2
  log_action "DRY: preserve dirty worktree (would require --force): $WT_PATH"
  UNSAFE_DELETE_BLOCKED=true
  DRY_DIRTY_BLOCKED=true
elif $DIRTY && $DRY_RUN; then
  log_action "DRY: dirty worktree removal authorized by explicit --force: $WT_PATH"
fi

if [[ -n "$WT_PATH" && -d "$WT_PATH" ]]; then
  ABS_WT=$(cd "$WT_PATH" 2>/dev/null && pwd -P || true)
  ABS_MAIN=$(cd "$MAIN_ROOT" 2>/dev/null && pwd -P || true)
  if [[ -n "$ABS_WT" && -n "$ABS_MAIN" && "$ABS_WT" == "$ABS_MAIN" ]]; then
    echo "Error: refusing to remove main repo worktree: $WT_PATH" >&2
    emit_refusal_json "main_root_worktree"
    exit 1
  fi
  # Running from inside the target worktree is the natural spot for an agent
  # that just finished work there. Removal would delete the cwd and every
  # later command that resolves relative paths would fail (the remote delete
  # then aborted with a misleading lease error) — step out first.
  if [[ -n "$ABS_WT" && "$(pwd -P)/" == "$ABS_WT"/* ]]; then
    cd "$MAIN_ROOT"
    log_action "moved cwd out of target worktree before removal: $ABS_WT"
  fi
fi

REMOVED_WT=false
if ! $KEEP_WORKTREE && ! $WT_IDENTITY_BLOCKED && [[ -n "$WT_PATH" && -d "$WT_PATH" ]]; then
  if $DRY_DIRTY_BLOCKED; then
    log_action "DRY: skip worktree removal because dirty non-force cleanup would stop"
  elif $FORCE; then
    run git -C "$MAIN_ROOT" worktree remove --force "$WT_PATH"
    REMOVED_WT=true
  else
    run git -C "$MAIN_ROOT" worktree remove "$WT_PATH"
    REMOVED_WT=true
  fi
elif $WT_IDENTITY_BLOCKED && $DRY_RUN; then
  log_action "DRY: skip worktree removal; path identity failed ($WT_IDENTITY_REASON): $WT_PATH"
fi

if ! $DRY_DIRTY_BLOCKED; then
  run git -C "$MAIN_ROOT" worktree prune
fi

# update-ref deliberately bypasses porcelain branch safety checks. Re-scan
# after the intended removal so --keep-worktree, a wrong explicit path, or an
# additional forced worktree cannot leave a retained checkout with no branch.
DRY_REMOVED_WT=""
if $DRY_RUN && ! $KEEP_WORKTREE && ! $DRY_DIRTY_BLOCKED; then
  DRY_REMOVED_WT="$WT_PATH"
fi
CHECKED_OUT_WT=$(git -C "$MAIN_ROOT" worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/$BRANCH" -v skip="$DRY_REMOVED_WT" '
  $1=="worktree" { p=substr($0, 10) }
  $1=="branch" && $2==b && p!=skip { print p; exit }
')
if ! $KEEP_BRANCH && [[ -n "$CHECKED_OUT_WT" ]]; then
  echo "Error: refusing to delete a branch that remains checked out: $CHECKED_OUT_WT" >&2
  log_action "preserve branch that remains checked out after worktree cleanup: $BRANCH ($CHECKED_OUT_WT)"
  UNSAFE_DELETE_BLOCKED=true
  CHECKED_OUT_REF_BLOCKED=true
fi

DELETED_LOCAL=false
LOCAL_DELETE_SAFE=false
if ! $KEEP_BRANCH; then
  refresh_local_tip
  if [[ -n "$LOCAL_TIP_OID" ]]; then
    if $WT_IDENTITY_BLOCKED; then
      log_action "preserve local branch because worktree path identity failed: $BRANCH"
    elif $CHECKED_OUT_REF_BLOCKED; then
      log_action "preserve local branch that remains checked out: $BRANCH"
    elif is_protected_branch "$BRANCH"; then
      echo "Error: refusing to delete protected local branch: $BRANCH" >&2
      log_action "preserve protected local branch: $BRANCH"
      UNSAFE_DELETE_BLOCKED=true
    elif $DRY_DIRTY_BLOCKED; then
      log_action "DRY: preserve local branch because dirty worktree removal would stop: $BRANCH"
    elif $FORCE; then
      delete_local_ref_exact "$LOCAL_TIP_OID" "explicit --force" || true
    elif oid_fully_merged "$LOCAL_TIP_OID"; then
      delete_local_ref_exact "$LOCAL_TIP_OID" "fully merged into MAIN HEAD" || true
    elif $LOCAL_PR_PROOF; then
      echo "Note: verified local ref at merged PR #$PR_N head; deleting squash residual: $BRANCH" >&2
      delete_local_ref_exact "$PR_HEAD_OID" "merged PR #$PR_N local headRefOid match" || true
    else
      echo "Error: local branch is not fully merged and has no exact local PR proof; preserving it: $BRANCH" >&2
      echo "  pass --pr <merged-pr> with matching local headRefOid, or --force for explicit destructive intent" >&2
      log_action "preserve local branch (unmerged; no exact local proof or --force): $BRANCH"
      UNSAFE_DELETE_BLOCKED=true
    fi
  fi
fi

# Remote deletion is independently authorized. Local safety can carry over only
# when the observed remote OID is exactly the same OID deleted safely locally.
# The push lease makes a later remote update fail closed.
DELETED_REMOTE=false
REMOTE_STILL_PRESENT=false
if $DELETE_REMOTE; then
  if $WT_IDENTITY_BLOCKED; then
    log_action "preserve remote branch because worktree path identity failed: origin/$BRANCH"
  elif $DRY_RUN; then
    # Dry runs stay offline: report the intended action without ls-remote.
    # Do not claim deleted_remote_branch — existence was never checked.
    if $DRY_DIRTY_BLOCKED; then
      log_action "DRY: preserve remote branch because dirty non-force cleanup would stop: origin/$BRANCH"
    elif is_protected_branch "$BRANCH"; then
      log_action "DRY: preserve protected remote branch origin/$BRANCH"
    else
      log_action "DRY: remote stays unprobed; delete only if its exact OID independently satisfies proof/lease"
    fi
  elif ! $REMOTE_ORIGIN_CONFIGURED; then
    log_action "origin remote absent; remote cleanup not applicable"
  elif $REMOTE_PROBE_FAILED; then
    echo "Error: remote state is unknown; preserving origin/$BRANCH" >&2
    log_action "preserve remote branch after probe failure: origin/$BRANCH"
    UNSAFE_DELETE_BLOCKED=true
  elif [[ -n "$REMOTE_TIP_OID" ]]; then
    if is_protected_branch "$BRANCH"; then
      echo "Error: refusing to delete protected remote branch: origin/$BRANCH" >&2
      log_action "preserve remote branch (protected): origin/$BRANCH"
      REMOTE_STILL_PRESENT=true
      UNSAFE_DELETE_BLOCKED=true
    else
      REMOTE_DELETE_ALLOWED=false
      REMOTE_DELETE_REASON=""
      if $FORCE; then
        REMOTE_DELETE_ALLOWED=true
        REMOTE_DELETE_EXPECTED_OID="$REMOTE_TIP_OID"
        REMOTE_DELETE_REASON="explicit --force"
      elif $REMOTE_PR_PROOF; then
        REMOTE_DELETE_ALLOWED=true
        REMOTE_DELETE_EXPECTED_OID="$PR_HEAD_OID"
        REMOTE_DELETE_REASON="merged PR #$PR_N remote headRefOid match"
      elif $LOCAL_DELETE_SAFE && [[ -n "$LOCAL_DELETED_OID" ]] && [[ "$REMOTE_TIP_OID" == "$LOCAL_DELETED_OID" ]]; then
        REMOTE_DELETE_ALLOWED=true
        REMOTE_DELETE_EXPECTED_OID="$REMOTE_TIP_OID"
        REMOTE_DELETE_REASON="same exact OID deleted safely locally"
      fi

      if ! $REMOTE_DELETE_ALLOWED; then
        echo "Error: preserving remote branch without proof for its exact OID: origin/$BRANCH" >&2
        echo "  remote tip: $REMOTE_TIP_OID" >&2
        [[ -n "$LOCAL_DELETED_OID" ]] && echo "  safely deleted local OID: $LOCAL_DELETED_OID" >&2
        [[ -n "$PR_HEAD_OID" ]] && echo "  PR headRefOid: $PR_HEAD_OID" >&2
        log_action "preserve remote ref without exact-OID proof: origin/$BRANCH ($REMOTE_TIP_OID)"
        REMOTE_STILL_PRESENT=true
        UNSAFE_DELETE_BLOCKED=true
      else
        # Do not use run(): a lease failure must still produce fail-closed JSON.
        log_action "git push --force-with-lease=refs/heads/$BRANCH:$REMOTE_DELETE_EXPECTED_OID origin --delete $BRANCH ($REMOTE_DELETE_REASON)"
        set +e
        git -C "$MAIN_ROOT" push "--force-with-lease=refs/heads/$BRANCH:$REMOTE_DELETE_EXPECTED_OID" origin --delete "$BRANCH"
        push_st=$?
        set -e

        set +e
        remote_after_output=$(ls_remote_head)
        remote_after_st=$?
        set -e
        if [[ $remote_after_st -ne 0 ]]; then
          REMOTE_PROBE_FAILED=true
          echo "Error: could not verify remote state after cleanup attempt: origin/$BRANCH" >&2
          log_action "remote re-probe failed: origin/$BRANCH"
          UNSAFE_DELETE_BLOCKED=true
        else
          REMOTE_AFTER_OID=$(printf '%s\n' "$remote_after_output" | exact_remote_head_oid)
        fi

        if [[ $push_st -eq 0 && -z "$REMOTE_AFTER_OID" ]] && ! $REMOTE_PROBE_FAILED; then
          DELETED_REMOTE=true
        elif [[ -n "$REMOTE_AFTER_OID" ]]; then
          REMOTE_STILL_PRESENT=true
          UNSAFE_DELETE_BLOCKED=true
          echo "Error: remote branch preserved or changed during cleanup: origin/$BRANCH" >&2
          echo "  expected tip: $REMOTE_DELETE_EXPECTED_OID" >&2
          echo "  current tip:  $REMOTE_AFTER_OID" >&2
          log_action "remote compare-and-delete refused/residual: origin/$BRANCH (expected=$REMOTE_DELETE_EXPECTED_OID current=$REMOTE_AFTER_OID)"
        elif [[ $push_st -ne 0 ]] && ! $REMOTE_PROBE_FAILED; then
          # Another actor may have removed the exact ref first. The desired
          # absence holds, but do not claim this process deleted it.
          log_action "remote branch absent after rejected delete attempt: origin/$BRANCH"
        fi
      fi
    fi
  else
    # Absence is also observed state. Re-probe before claiming success so a
    # same-named ref created after the first probe is preserved and reported.
    set +e
    remote_after_output=$(ls_remote_head)
    remote_after_st=$?
    set -e
    if [[ $remote_after_st -ne 0 ]]; then
      REMOTE_PROBE_FAILED=true
      UNSAFE_DELETE_BLOCKED=true
      echo "Error: could not confirm remote branch remained absent: origin/$BRANCH" >&2
      log_action "remote absent-state re-probe failed: origin/$BRANCH"
    else
      REMOTE_AFTER_OID=$(printf '%s\n' "$remote_after_output" | exact_remote_head_oid)
      if [[ -n "$REMOTE_AFTER_OID" ]]; then
        REMOTE_STILL_PRESENT=true
        UNSAFE_DELETE_BLOCKED=true
        echo "Error: remote branch appeared after initial proof; preserving it: origin/$BRANCH" >&2
        echo "  current tip: $REMOTE_AFTER_OID" >&2
        log_action "remote ref appeared after absent proof: origin/$BRANCH ($REMOTE_AFTER_OID)"
      else
        log_action "remote branch absent: $BRANCH"
      fi
    fi
  fi
fi

# Detect Lattice residue left on MAIN (pre-worktree L0 pollution). Soft by default.
BASE_RESIDUE=false
BASE_RESIDUE_COUNT=0
CHECK_BASE=""
SCRIPT_DIR_CU="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# _lattice-lib only (legacy lattice-lib dual-resolve dropped)
for cand in \
  "${LATTICE_LIB_SCRIPTS:-}/check-base-residue.sh" \
  "${SCRIPT_DIR_CU}/../../_lattice-lib/scripts/check-base-residue.sh" \
  "${SCRIPT_DIR_CU}/../../../skills/_lattice-lib/scripts/check-base-residue.sh"
do
  if [[ -n "$cand" && -f "$cand" ]]; then
    CHECK_BASE="$cand"
    break
  fi
done
if [[ -n "$CHECK_BASE" && -d "$MAIN_ROOT" ]]; then
  set +e
  RES_JSON=$(bash "$CHECK_BASE" --main-root "$MAIN_ROOT" --json 2>/dev/null)
  RES_ST=$?
  set -e
  if [[ $RES_ST -eq 0 || $RES_ST -eq 1 ]] && [[ -n "$RES_JSON" ]]; then
    if printf '%s' "$RES_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("has_residue") else 1)' 2>/dev/null; then
      BASE_RESIDUE=true
      BASE_RESIDUE_COUNT=$(printf '%s' "$RES_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("count",0))' 2>/dev/null || echo 0)
      echo "cleanup-workspace: WARNING — MAIN checkout has uncommitted .lattice residue (count=$BASE_RESIDUE_COUNT)" >&2
      echo "  main: $MAIN_ROOT" >&2
      echo "  This often means binders/lineage were written on base before the worktree." >&2
      echo "  Inspect: bash $CHECK_BASE --main-root $(printf '%q' "$MAIN_ROOT")" >&2
      echo "  Discard accidental dirt before git pull, or commit intentional finish bookkeeping." >&2
      log_action "base_residue: count=$BASE_RESIDUE_COUNT"
    fi
  fi
fi

export CU_BRANCH="$BRANCH"
export CU_WT="${WT_PATH:-}"
export CU_MAIN="$MAIN_ROOT"
export CU_DIRTY="$DIRTY"
export CU_REMOVED_WT="$REMOVED_WT"
export CU_DEL_LOCAL="$DELETED_LOCAL"
export CU_DEL_REMOTE="$DELETED_REMOTE"
export CU_REMOTE_RESIDUAL="$REMOTE_STILL_PRESENT"
export CU_UNSAFE_BLOCKED="$UNSAFE_DELETE_BLOCKED"
export CU_MERGED_PROOF="$MERGED_PROOF"
export CU_MERGED_PROOF_REASON="$MERGED_PROOF_REASON"
export CU_LOCAL_PR_PROOF="$LOCAL_PR_PROOF"
export CU_REMOTE_PR_PROOF="$REMOTE_PR_PROOF"
export CU_PR_HEAD_OID="$PR_HEAD_OID"
export CU_LOCAL_TIP_OID="$LOCAL_TIP_OID"
export CU_LOCAL_DELETED_OID="$LOCAL_DELETED_OID"
export CU_REMOTE_TIP_OID="$REMOTE_TIP_OID"
export CU_REMOTE_AFTER_OID="$REMOTE_AFTER_OID"
export CU_REMOTE_DELETE_EXPECTED_OID="$REMOTE_DELETE_EXPECTED_OID"
export CU_REMOTE_PROBED="$REMOTE_PROBED"
export CU_REMOTE_PROBE_FAILED="$REMOTE_PROBE_FAILED"
export CU_DRY="$DRY_RUN"
export CU_LOG="$ACTION_LOG"
export CU_BASE_RESIDUE="$BASE_RESIDUE"
export CU_BASE_RESIDUE_COUNT="$BASE_RESIDUE_COUNT"
export CU_WT_IDENTITY_REASON="$WT_IDENTITY_REASON"
export CU_WT_OBSERVED_REF="$WT_OBSERVED_REF"
export CU_WT_IDENTITY_BLOCKED="$WT_IDENTITY_BLOCKED"

# The full summary below IS the contract line; its nonzero exit (residual
# work) must not trigger the EXIT-trap refusal backstop on top of it.
JSON_EMITTED=true
python3 - <<'PY'
import json, os, sys
log = os.environ.get("CU_LOG", "")
actions = []
if log and os.path.isfile(log):
    with open(log, encoding="utf-8") as f:
        actions = [ln.rstrip("\n") for ln in f if ln.strip()]
remote_residual = os.environ.get("CU_REMOTE_RESIDUAL") == "true"
unsafe_blocked = os.environ.get("CU_UNSAFE_BLOCKED") == "true"
remote_probe_failed = os.environ.get("CU_REMOTE_PROBE_FAILED") == "true"
ok = not remote_residual and not unsafe_blocked and not remote_probe_failed
payload = {
  "ok": ok,
  "branch": os.environ["CU_BRANCH"],
  "worktree_path": os.environ["CU_WT"] or None,
  "main_root": os.environ["CU_MAIN"],
  "was_dirty": os.environ["CU_DIRTY"] == "true",
  "removed_worktree": os.environ["CU_REMOVED_WT"] == "true",
  "deleted_local_branch": os.environ["CU_DEL_LOCAL"] == "true",
  "deleted_remote_branch": os.environ["CU_DEL_REMOTE"] == "true",
  "remote_residual": remote_residual,
  "unsafe_delete_blocked": unsafe_blocked,
  "merged_proof": os.environ.get("CU_MERGED_PROOF") == "true",
  "merged_proof_reason": os.environ.get("CU_MERGED_PROOF_REASON") or None,
  "local_pr_proof": os.environ.get("CU_LOCAL_PR_PROOF") == "true",
  "remote_pr_proof": os.environ.get("CU_REMOTE_PR_PROOF") == "true",
  "pr_head_oid": os.environ.get("CU_PR_HEAD_OID") or None,
  "local_tip_oid": os.environ.get("CU_LOCAL_TIP_OID") or None,
  "local_deleted_oid": os.environ.get("CU_LOCAL_DELETED_OID") or None,
  "remote_tip_oid": os.environ.get("CU_REMOTE_TIP_OID") or None,
  "remote_after_oid": os.environ.get("CU_REMOTE_AFTER_OID") or None,
  "remote_delete_expected_oid": os.environ.get("CU_REMOTE_DELETE_EXPECTED_OID") or None,
  "remote_probed": os.environ.get("CU_REMOTE_PROBED") == "true",
  "remote_probe_failed": remote_probe_failed,
  "dry_run": os.environ["CU_DRY"] == "true",
  "base_residue": os.environ.get("CU_BASE_RESIDUE") == "true",
  "base_residue_count": int(os.environ.get("CU_BASE_RESIDUE_COUNT") or "0"),
  "actions": actions,
}
if os.environ.get("CU_WT_IDENTITY_REASON"):
    payload["worktree_identity_reason"] = os.environ["CU_WT_IDENTITY_REASON"]
if os.environ.get("CU_WT_OBSERVED_REF"):
    payload["worktree_observed_ref"] = os.environ["CU_WT_OBSERVED_REF"]
if os.environ.get("CU_WT_IDENTITY_BLOCKED") == "true":
    payload["worktree_identity_blocked"] = True
print(json.dumps(payload))
sys.exit(0 if ok else 1)
PY
