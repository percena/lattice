#!/usr/bin/env bash
# verify-main-chain.sh — mutation-proof the canonical create-pr → merge chain.
#
# spc-254 A2 / D5: Normal, batch, and delegated paths share ONE verify-mutation
# helper contract. Every durable mutation in the main chain is followed by a
# proof probe; any proof failure HALTS cleanup/ledger and leaves structured
# recovery info so the operator (not the agent) adjudicates the recovery.
#
# The dogfood retrospective (rev-20260829-140444Z F1/F5) recorded real phantom
# push/PR/merge incidents where a "Command failed" with zero output was read as
# "ambiguous, proceed". This helper closes that gap by compiling the three
# main-chain proofs into one callable contract:
#
#   --stage push    after `git push`       → verify remote OID == local HEAD
#   --stage pr      after `gh pr create`   → verify repo/base/head/body/head-OID
#   --stage merge   after `gh pr merge`     → verify PR MERGED + base OID stable
#
# Each stage delegates the remote/PR/merge-state probe to verify-mutation.sh
# (the foundation from tkt-255), then layers the richer field comparison
# (base/head/body for the PR stage) on top. A failure emits a structured JSON
# recovery blob to stderr (machine-parseable) + a human line, and exits 1.
# Exit 0 = verified (prints "verified: <stage> <detail>").
#
# Usage:
#   verify-main-chain.sh --stage push  --branch <name> --expected-oid <local HEAD>
#   verify-main-chain.sh --stage pr    --pr <N> --expected-oid <HEAD> --repo <owner/name>
#                                  [--expected-base <base>] [--expected-head <head>]
#                                  [--expected-body-file <path>]
#   verify-main-chain.sh --stage merge --pr <N> --expected-oid <base OID>
#                                  [--repo <owner/name>]
#   verify-main-chain.sh --help
#
# Exit: 0 = verified (stdout); 1 = proof FAILED (stderr recovery JSON + halts);
#       2 = usage error.
#
# bash 3.2 portable (no mapfile/readarray; [ ] guards throughout).

set -euo pipefail

usage() {
  cat <<EOF
usage: verify-main-chain.sh --stage push|pr|merge <stage-args> [--help]

Mutation-proof the canonical create-pr → merge chain (spc-254 A2/D5).
Any proof failure halts cleanup/ledger and emits structured recovery JSON.

  --stage push  --branch <name> --expected-oid <local HEAD>
  --stage pr    --pr <N> --expected-oid <HEAD> --repo <owner/name>
                [--expected-base <base>] [--expected-head <head>]
                [--expected-body-file <path>]
  --stage merge --pr <N> --expected-oid <base OID> [--repo <owner/name>]
EOF
}

STAGE=""
BRANCH=""
PR=""
EXPECTED_OID=""
REPO=""
EXPECTED_BASE=""
EXPECTED_HEAD=""
EXPECTED_BODY_FILE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --stage) STAGE="${2:-}"; [ -n "$STAGE" ] || { usage >&2; exit 2; }; shift 2;;
    --branch) BRANCH="${2:-}"; [ -n "$BRANCH" ] || { usage >&2; exit 2; }; shift 2;;
    --pr) PR="${2:-}"; [ -n "$PR" ] || { usage >&2; exit 2; }; shift 2;;
    --expected-oid) EXPECTED_OID="${2:-}"; [ -n "$EXPECTED_OID" ] || { usage >&2; exit 2; }; shift 2;;
    --repo) REPO="${2:-}"; [ -n "$REPO" ] || { usage >&2; exit 2; }; shift 2;;
    --expected-base) EXPECTED_BASE="${2:-}"; shift 2;;
    --expected-head) EXPECTED_HEAD="${2:-}"; shift 2;;
    --expected-body-file) EXPECTED_BODY_FILE="${2:-}"; [ -n "$EXPECTED_BODY_FILE" ] || { usage >&2; exit 2; }; shift 2;;
    --help|-h) usage; exit 0;;
    *) echo "Error: unknown argument: $1" >&2; usage >&2; exit 2;;
  esac
done

if [ -z "$STAGE" ]; then
  echo "Error: --stage is required" >&2
  usage >&2
  exit 2
fi

OID_RE='^[0-9a-f]{7,40}$'
OWNER_REPO_RE='^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'

# Resolve the sibling verify-mutation.sh (foundation from tkt-255).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY_MUTATION="$SCRIPT_DIR/verify-mutation.sh"
if [ ! -f "$VERIFY_MUTATION" ]; then
  echo "Error: verify-mutation.sh not found beside this script at $VERIFY_MUTATION" >&2
  exit 2
fi

# emit_failure <stage> <failed> <expected> <actual> <extra-json-kv...>
# Prints a structured JSON recovery blob to stderr + a human line, exit 1.
# The JSON is single-line so callers can capture it with \$(...) and persist it
# to a recovery file. extra key/value pairs are appended verbatim (already
# JSON-quoted by callers via json_escape).
emit_failure() {
  local stage="$1" failed="$2" expected="$3" actual="$4"
  shift 4
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")
  local extra=""
  while [ "$#" -ge 2 ]; do
    extra="$extra,\"$1\":$2"
    shift 2
  done
  printf '{"stage":"%s","failed":"%s","expected":"%s","actual":"%s","ts":"%s"%s}\n' \
    "$stage" "$failed" "$expected" "$actual" "$ts" "$extra" >&2
  printf 'FAILED: %s proof — %s (expected=%s actual=%s); cleanup/ledger HALTED; see recovery JSON above\n' \
    "$stage" "$failed" "$expected" "$actual" >&2
  exit 1
}

json_escape() {
  # Minimal JSON string escape for field values that may contain quotes/backsplash.
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1] if len(sys.argv)>1 else ""))' "$1" 2>/dev/null \
    || printf '"%s"' "$1"
}

require_oid() {
  local label="$1" val="$2"
  if [ -z "$val" ]; then
    echo "Error: $label is required for stage $STAGE" >&2
    usage >&2
    exit 2
  fi
  if ! printf '%s' "$val" | grep -qE "$OID_RE"; then
    echo "Error: $label must be a hex OID (7-40 chars), got: $val" >&2
    exit 2
  fi
}

# --- stage push -------------------------------------------------------------
# After `git push -u origin <branch>`: capture local HEAD BEFORE the push, then
# verify the remote ref head matches it via verify-mutation.sh --branch. A
# mismatch means the push landed a different commit (concurrent force-push,
# rebase, or silent push failure) — halt before PR create.
stage_push() {
  require_oid "--expected-oid" "$EXPECTED_OID"
  [ -n "$BRANCH" ] || { echo "Error: --branch is required for stage push" >&2; usage >&2; exit 2; }
  if ! bash "$VERIFY_MUTATION" --branch "$BRANCH" --expected-oid "$EXPECTED_OID" 2>.vm.err; then
    local err
    err=$(cat .vm.err 2>/dev/null || echo "verify-mutation --branch failed")
    rm -f .vm.err
    emit_failure push remote_oid_mismatch "$EXPECTED_OID" "<absent-or-different>" \
      "branch" "$(json_escape "$BRANCH")" \
      "verify_error" "$(json_escape "$err")" \
      "next_action" "$(json_escape "re-push: git push -u origin $BRANCH; re-run verify-main-chain --stage push --branch $BRANCH --expected-oid <local HEAD>")"
  fi
  rm -f .vm.err
  echo "verified: push branch=$BRANCH remote_oid=$EXPECTED_OID"
}

# --- stage pr ---------------------------------------------------------------
# After `gh pr create`: verify the PR exists OPEN, belongs to the right repo,
# its headRefOid matches the pushed HEAD, and (when supplied) base/head branch
# + body match intent. A wrong repo/base/head/body is a phantom-PR / wrong-
# target incident (rev-20260829-140444Z F5) — halt before stamp/binder/ledger.
stage_pr() {
  require_oid "--expected-oid" "$EXPECTED_OID"
  [ -n "$PR" ] || { echo "Error: --pr is required for stage pr" >&2; usage >&2; exit 2; }
  case "$PR" in
    ''|*[!0-9]*) echo "Error: --pr must be a positive integer, got: $PR" >&2; exit 2;;
  esac
  [ "$PR" -gt 0 ] 2>/dev/null || { echo "Error: --pr must be > 0, got: $PR" >&2; exit 2; }
  [ -n "$REPO" ] || { echo "Error: --repo is required for stage pr (repo identity binding)" >&2; usage >&2; exit 2; }
  if ! printf '%s' "$REPO" | grep -qE "$OWNER_REPO_RE"; then
    echo "Error: --repo must be owner/name, got: $REPO" >&2; exit 2
  fi

  # 1. state + headRefOid + repo identity (delegated to the shared contract).
  if ! bash "$VERIFY_MUTATION" --pr "$PR" --expected-oid "$EXPECTED_OID" --repo "$REPO" 2>.vm.err; then
    local err
    err=$(cat .vm.err 2>/dev/null || echo "verify-mutation --pr failed")
    rm -f .vm.err
    emit_failure pr pr_probe_failed "$EXPECTED_OID" "<absent-or-mismatch>" \
      "pr" "$PR" \
      "repo" "$(json_escape "$REPO")" \
      "verify_error" "$(json_escape "$err")" \
      "next_action" "$(json_escape "re-create or re-view: gh pr view $PR; confirm repo/base/head, then re-run verify-main-chain --stage pr")"
  fi
  rm -f .vm.err

  # 2. Richer field comparison: base/head/body. Fetch once, compare each.
  if [ -n "$EXPECTED_BASE" ] || [ -n "$EXPECTED_HEAD" ] || [ -n "$EXPECTED_BODY_FILE" ]; then
    if ! command -v gh >/dev/null 2>&1; then
      echo "Error: gh not found; cannot fetch PR $PR fields for stage pr" >&2
      exit 1
    fi
    local json
    if ! json=$(gh pr view "$PR" --repo "$REPO" --json baseRefName,headRefName,body 2>/dev/null); then
      emit_failure pr pr_view_failed "$EXPECTED_OID" "<gh-error>" \
        "pr" "$PR" "repo" "$(json_escape "$REPO")" \
        "next_action" "$(json_escape "gh pr view $PR failed; check gh auth + repo, then re-run")"
    fi
    local actual_base actual_head actual_body
    if command -v python3 >/dev/null 2>&1; then
      actual_base=$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("baseRefName") or "")' 2>/dev/null) || actual_base=""
      actual_head=$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("headRefName") or "")' 2>/dev/null) || actual_head=""
      actual_body=$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("body") or "")' 2>/dev/null) || actual_body=""
    else
      actual_base=$(printf '%s' "$json" | grep -oE '"baseRefName": *"[^"]*"' | head -1 | sed 's/.*": *"//; s/"$//')
      actual_head=$(printf '%s' "$json" | grep -oE '"headRefName": *"[^"]*"' | head -1 | sed 's/.*": *"//; s/"$//')
      actual_body=$(printf '%s' "$json" | sed 's/.*"body": *"//; s/" *}$//')
    fi

    if [ -n "$EXPECTED_BASE" ] && [ "$actual_base" != "$EXPECTED_BASE" ]; then
      emit_failure pr base_mismatch "$EXPECTED_BASE" "$(json_escape "$actual_base")" \
        "pr" "$PR" "repo" "$(json_escape "$REPO")" \
        "next_action" "$(json_escape "wrong base — gh pr edit $PR --base $EXPECTED_BASE, then re-run")"
    fi
    if [ -n "$EXPECTED_HEAD" ] && [ "$actual_head" != "$EXPECTED_HEAD" ]; then
      emit_failure pr head_branch_mismatch "$EXPECTED_HEAD" "$(json_escape "$actual_head")" \
        "pr" "$PR" "repo" "$(json_escape "$REPO")" \
        "next_action" "$(json_escape "wrong head branch — re-create the PR from the intended branch, then re-run")"
    fi
    if [ -n "$EXPECTED_BODY_FILE" ]; then
      [ -f "$EXPECTED_BODY_FILE" ] || { echo "Error: --expected-body-file not found: $EXPECTED_BODY_FILE" >&2; exit 2; }
      local expected_body
      expected_body=$(cat "$EXPECTED_BODY_FILE" 2>/dev/null) || expected_body=""
      if [ "$actual_body" != "$expected_body" ]; then
        emit_failure pr body_mismatch "<body-file>" "<gh-body>" \
          "pr" "$PR" "repo" "$(json_escape "$REPO")" \
          "next_action" "$(json_escape "body drift — gh pr edit $PR --body-file $EXPECTED_BODY_FILE, then re-run")"
      fi
    fi
  fi

  echo "verified: pr-$PR repo=$REPO head_oid=$EXPECTED_OID"
}

# --- stage merge ------------------------------------------------------------
# After `gh pr merge`: verify the PR is now MERGED and that the base branch tip
# matches the expected base OID (the OID captured before merge). A base-OID
# drift means another PR landed in between (race) or the merge targeted the
# wrong base — halt before finish-ledger / cleanup / branch deletion.
stage_merge() {
  require_oid "--expected-oid" "$EXPECTED_OID"
  [ -n "$PR" ] || { echo "Error: --pr is required for stage merge" >&2; usage >&2; exit 2; }
  case "$PR" in
    ''|*[!0-9]*) echo "Error: --pr must be a positive integer, got: $PR" >&2; exit 2;;
  esac
  [ "$PR" -gt 0 ] 2>/dev/null || { echo "Error: --pr must be > 0, got: $PR" >&2; exit 2; }

  # verify-mutation --pr --require-merged strictly requires state==MERGED
  # (spc-254 A2). --allow-merged would also accept OPEN — wrong for the merge
  # stage, where OPEN means the merge did not land. The --expected-oid here is
  # the PRE-merge base tip captured before `gh pr merge`; we do NOT pass it to
  # verify-mutation (the PR headRefOid is not the base tip). The base-tip-
  # advance probe below uses it to confirm the merge actually landed on the
  # remote base (the tip must have moved off the pre-merge OID).
  local vm_args=(--pr "$PR" --require-merged)
  if [ -n "$REPO" ]; then
    if ! printf '%s' "$REPO" | grep -qE "$OWNER_REPO_RE"; then
      echo "Error: --repo must be owner/name, got: $REPO" >&2; exit 2
    fi
    vm_args+=(--repo "$REPO")
  fi
  if ! bash "$VERIFY_MUTATION" "${vm_args[@]+"${vm_args[@]}"}" 2>.vm.err; then
    local err
    err=$(cat .vm.err 2>/dev/null || echo "verify-mutation --pr --allow-merged failed")
    rm -f .vm.err
    emit_failure merge merged_state_failed "MERGED" "<not-merged>" \
      "pr" "$PR" \
      "repo" "$(json_escape "${REPO:-origin}")" \
      "verify_error" "$(json_escape "$err")" \
      "next_action" "$(json_escape "PR did not reach MERGED — gh pr view $PR; if merge failed, re-merge; if closed-unmerged, do NOT run finish-ledger merged path")"
  fi
  rm -f .vm.err

  # Base-tip advance probe (spc-254 A2): the base branch tip on origin must have
  # moved OFF the pre-merge base OID. If the tip is still the pre-merge OID, the
  # merge did not land on the remote base (silent push failure / wrong base /
  # concurrent revert) — halt before finish-ledger stamps a mergedAt the remote
  # does not actually carry. The tip being non-empty but == expected is the
  # failure; absent tip is a separate failure (network/auth). The stronger
  # compare-and-delete guard in cleanup-workspace.sh handles exact OID equality
  # at branch deletion — this probe is the ledger-side gate.
  local gh_view_args=(pr view "$PR" --json baseRefName)
  if [ -n "$REPO" ]; then
    gh_view_args=(pr view "$PR" --repo "$REPO" --json baseRefName)
  fi
  local base_name base_ref
  base_name=$(gh "${gh_view_args[@]}" 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("baseRefName") or "")' 2>/dev/null || true)
  if [ -z "$base_name" ]; then
    emit_failure merge base_branch_unresolved "$EXPECTED_OID" "<no-baseRefName>" \
      "pr" "$PR" "repo" "$(json_escape "${REPO:-origin}")" \
      "next_action" "$(json_escape "could not resolve base branch from PR $PR — gh pr view; verify the PR, then re-run")"
  fi
  if ! base_ref=$(git ls-remote origin "refs/heads/$base_name" 2>/dev/null | awk '{print $1}'); then
    emit_failure merge base_tip_unreachable "$EXPECTED_OID" "<ls-remote-error>" \
      "pr" "$PR" "repo" "$(json_escape "${REPO:-origin}")" \
      "base_branch" "$(json_escape "$base_name")" \
      "next_action" "$(json_escape "git ls-remote origin failed — network/auth; re-run once origin is reachable")"
  fi
  if [ -z "$base_ref" ]; then
    emit_failure merge base_tip_absent "$EXPECTED_OID" "<absent-remote-ref>" \
      "pr" "$PR" "repo" "$(json_escape "${REPO:-origin}")" \
      "base_branch" "$(json_escape "$base_name")" \
      "next_action" "$(json_escape "base branch $base_name absent on origin post-merge — verify the merge landed; do NOT run cleanup/ledger")"
  fi
  # The advance check: a correct squash/merge commit advances the base tip past
  # the pre-merge OID. base_ref == expected means the merge did NOT land → halt.
  if [ "$base_ref" = "$EXPECTED_OID" ]; then
    emit_failure merge base_tip_not_advanced "$EXPECTED_OID" "$base_ref" \
      "pr" "$PR" "repo" "$(json_escape "${REPO:-origin}")" \
      "base_branch" "$(json_escape "$base_name")" \
      "next_action" "$(json_escape "base tip did not advance past pre-merge OID — the merge likely did not land on origin; gh pr view $PR + git ls-remote; do NOT run finish-ledger/cleanup")"
  fi

  # A4.3 target-bound merge-commit ancestry (spc-270 A4): a base-tip advance
  # alone does not prove THIS PR landed — a concurrent unrelated PR could advance
  # the base, or the base could be rewound/reverted after a stale MERGED state.
  # Prove this PR's merge_commit_sha is an ancestor of the LIVE remote base tip
  # (base_ref from ls-remote, not a stale tracking ref). Requires --repo (the
  # canonical finish path always supplies it); absent --repo the base-tip-advance
  # probe still ran and the echo notes ancestry was not checked.
  local ancestry_proven=""
  if [ -n "$REPO" ]; then
    # One gh api call returns the full PR object; python extracts both fields
    # (merge_commit_sha + headRefOid) — no triple round-trip, one failure mode.
    local pr_api_json
    if ! pr_api_json=$(gh api "repos/$REPO/pulls/$PR" 2>/dev/null); then
      emit_failure merge merge_commit_api_failed "$EXPECTED_OID" "<gh-api-error>" \
        "pr" "$PR" "repo" "$(json_escape "$REPO")" \
        "base_branch" "$(json_escape "$base_name")" \
        "next_action" "$(json_escape "gh api repos/$REPO/pulls/$PR failed (transient rate-limit/5xx/auth?) — re-run once gh is reachable; do NOT assume the merge did not land")"
    fi
    local merge_commit_sha
    merge_commit_sha=$(printf '%s' "$pr_api_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("merge_commit_sha") or "")' 2>/dev/null) || merge_commit_sha=""
    if [ -z "$merge_commit_sha" ] || [ "$merge_commit_sha" = "null" ]; then
      emit_failure merge merge_commit_unresolved "$EXPECTED_OID" "<no-merge-commit-sha>" \
        "pr" "$PR" "repo" "$(json_escape "$REPO")" \
        "base_branch" "$(json_escape "$base_name")" \
        "next_action" "$(json_escape "PR $PR has no merge_commit_sha — the merge did not produce a commit on the base; gh pr view $PR; do NOT run finish-ledger/cleanup")"
    fi
    # Fetch the EXACT live remote base tip (base_ref) so both it and the merge
    # commit (its ancestor) are in the local object DB. Fail closed on fetch
    # failure — a stale tracking ref must never satisfy the ancestry proof.
    if ! git fetch origin "$base_ref" >/dev/null 2>&1; then
      emit_failure merge base_fetch_failed "$EXPECTED_OID" "<fetch-error>" \
        "pr" "$PR" "repo" "$(json_escape "$REPO")" \
        "base_branch" "$(json_escape "$base_name")" \
        "base_tip" "$(json_escape "$base_ref")" \
        "next_action" "$(json_escape "git fetch origin $base_ref failed (network/auth?) — re-run once origin is reachable; do NOT run finish-ledger/cleanup")"
    fi
    if ! git merge-base --is-ancestor "$merge_commit_sha" "$base_ref" >/dev/null 2>&1; then
      emit_failure merge merge_commit_not_ancestor "$EXPECTED_OID" "$(json_escape "$merge_commit_sha")" \
        "pr" "$PR" "repo" "$(json_escape "$REPO")" \
        "base_branch" "$(json_escape "$base_name")" \
        "base_tip" "$(json_escape "$base_ref")" \
        "next_action" "$(json_escape "this PR merge commit $merge_commit_sha is NOT reachable from base $base_name (tip=$base_ref) — a concurrent unrelated PR advanced the base, or the merge was rewound; gh pr view $PR + git log $base_ref; do NOT run finish-ledger/cleanup")"
    fi
    ancestry_proven="; merge-commit ancestry proven"
  fi

  echo "verified: merge pr-$PR state=MERGED base=$base_name tip=$base_ref (advanced past pre-merge $EXPECTED_OID${ancestry_proven})"
}

case "$STAGE" in
  push)  stage_push ;;
  pr)    stage_pr ;;
  merge) stage_merge ;;
  *) echo "Error: unknown stage: $STAGE (push|pr|merge)" >&2; usage >&2; exit 2 ;;
esac
