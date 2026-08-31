#!/usr/bin/env bash
# verify-mutation.sh — confirm a gh/git mutation actually landed.
#
# The spc-186 dogfood (rev-20260829-140444Z) hit a harness output-swallowing
# anomaly where compound Bash commands returned "Command failed" with zero
# output, and absent output was treated as "ambiguous, proceed" — causing a
# cascade of false-success misreads (a non-existent PR was "merged"; commit
# objects that never existed were "pushed"). This helper closes that gap:
# after every gh pr create / gh pr merge / git push, run this to confirm the
# durable result. Absence or mismatch is HARD failure (exit 1), never silent.
#
# Mutation kinds + their scope (tkt-237 LM5):
#   --pr     verifies the PR exists + state + headRefOid via gh (remote truth).
#   --branch verifies the remote ref via `git ls-remote origin` — THIS is the
#            post-push check (confirms the commit landed on the remote).
#   --commit verifies ONLY the local object database (`git cat-file -e`).
#            It succeeds the moment the commit exists locally, regardless of
#            `git push` — it CANNOT confirm a push landed on the remote. Do
#            NOT use --commit to verify a push; route push verification
#            exclusively through --branch.
#
# ADR-007 §5a framing: this is a compiled check — part of the rule
# "transitions fire only on durable artifacts" — not an escape. Silent
# false-success is the failure mode this detects.
#
# Usage:
#   verify-mutation.sh --pr N [--expected-oid OID] [--repo owner/name] [--allow-merged]
#   verify-mutation.sh --commit OID
#   verify-mutation.sh --branch NAME [--expected-oid OID]
#   verify-mutation.sh --help
#
# Exit: 0 = verified present (prints "verified: <kind> <id> <detail>" to stdout)
#       1 = absent / mismatch (prints "FAILED: <reason>" to stderr)
#       2 = usage error
#
# bash 3.2 portable (no mapfile/readarray; [[ ]] only inside [ ]-compatible
# guards — but this script uses [ ] throughout for tkt-167 ergonomics).

set -euo pipefail

usage() {
  cat <<EOF
usage: verify-mutation.sh --pr N [--expected-oid OID] [--repo owner/name] [--allow-merged|--require-merged]
       verify-mutation.sh --commit OID
       verify-mutation.sh --branch NAME [--expected-oid OID]
       verify-mutation.sh --help

Confirm a gh/git mutation actually landed. Exit 0 = verified (stdout);
1 = absent/mismatch (stderr); 2 = usage. Never silent.

  --pr     PR exists + state + headRefOid via gh (remote truth).
  --branch remote ref via \`git ls-remote origin\` — the post-push check.
  --commit LOCAL object database only (\`git cat-file -e\`); cannot confirm a
           push landed on the remote — use --branch for push verification.
  --allow-merged   accept OPEN or MERGED (default rejects MERGED|CLOSED).
  --require-merged strictly require state==MERGED (spc-254 A2 merge-stage proof:
                   a PR still OPEN after a claimed merge did not land).
EOF
}

PR=""
COMMIT=""
BRANCH=""
EXPECTED_OID=""
REPO=""
ALLOW_MERGED=0
REQUIRE_MERGED=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pr) PR="${2:-}"; [ -n "$PR" ] || { usage >&2; exit 2; }; shift 2;;
    --commit) COMMIT="${2:-}"; [ -n "$COMMIT" ] || { usage >&2; exit 2; }; shift 2;;
    --branch) BRANCH="${2:-}"; [ -n "$BRANCH" ] || { usage >&2; exit 2; }; shift 2;;
    --expected-oid) EXPECTED_OID="${2:-}"; [ -n "$EXPECTED_OID" ] || { usage >&2; exit 2; }; shift 2;;
    --repo) REPO="${2:-}"; [ -n "$REPO" ] || { usage >&2; exit 2; }; shift 2;;
    --allow-merged) ALLOW_MERGED=1; shift;;
    --require-merged) REQUIRE_MERGED=1; ALLOW_MERGED=1; shift;;
    --help|-h) usage; exit 0;;
    *) echo "Error: unknown argument: $1" >&2; usage >&2; exit 2;;
  esac
done

# exactly one mutation kind
kinds=0
[ -n "$PR" ] && kinds=$((kinds+1))
[ -n "$COMMIT" ] && kinds=$((kinds+1))
[ -n "$BRANCH" ] && kinds=$((kinds+1))
if [ "$kinds" -ne 1 ]; then
  echo "Error: specify exactly one of --pr / --commit / --branch" >&2
  usage >&2
  exit 2
fi

OWNER_REPO_RE='^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'
OID_RE='^[0-9a-f]{7,40}$'

# Compare OIDs with short-SHA prefix tolerance (tkt-237 M4): a 7-40 char
# expected OID matches a 40-char fetched head when it is a unique prefix
# (git short-SHA semantics). The prior exact-equality
# `[ "$head" != "$EXPECTED_OID" ]` never matched a 7-char --expected-oid
# against a 40-char headRefOid → false FAILED → stuck+unblock stamp on a PR
# that actually succeeded. Fetched heads are always full 40-char OIDs
# (gh headRefOid / git ls-remote), so prefix-match when expected is shorter
# than fetched, exact-match when lengths are equal.
oid_matches() {
  local fetched="$1" expected="$2"
  if [ "${#expected}" -lt "${#fetched}" ]; then
    case "$fetched" in
      "$expected"*) return 0 ;;
      *) return 1 ;;
    esac
  fi
  [ "$fetched" = "$expected" ]
}

verify_pr() {
  # PR number shape: positive integer
  case "$PR" in
    ''|*[!0-9]*) echo "FAILED: --pr must be a positive integer, got: $PR" >&2; return 1;;
  esac
  [ "$PR" -gt 0 ] 2>/dev/null || { echo "FAILED: --pr must be > 0, got: $PR" >&2; return 1; }

  if ! command -v gh >/dev/null 2>&1; then
    echo "FAILED: gh not found; cannot verify PR $PR" >&2; return 1
  fi

  # Fetch state + headRefOid + url. gh pr view exits nonzero if the PR doesn't exist.
  local json
  if ! json=$(gh pr view "$PR" --json state,headRefOid,url 2>/dev/null); then
    echo "FAILED: pr-$PR does not exist (gh pr view returned no PR)" >&2; return 1
  fi

  # Parse with python3 if available, else fall back to grep (state/url are simple).
  local state head url
  if command -v python3 >/dev/null 2>&1; then
    state=$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["state"])' 2>/dev/null) || state=""
    head=$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["headRefOid"])' 2>/dev/null) || head=""
    url=$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["url"])' 2>/dev/null) || url=""
  else
    state=$(printf '%s' "$json" | grep -oE '"state": *"[^"]*"' | head -1 | sed 's/.*": *"//; s/"$//')
    head=$(printf '%s' "$json" | grep -oE '"headRefOid": *"[0-9a-f]+"' | head -1 | sed 's/.*": *"//; s/"$//')
    url=$(printf '%s' "$json" | grep -oE '"url": *"[^"]*"' | head -1 | sed 's/.*": *"//; s/"$//')
  fi

  if [ -z "$state" ] || [ -z "$head" ]; then
    echo "FAILED: pr-$PR view returned unparseable JSON: $json" >&2; return 1
  fi

  # repo-identity binding when --repo given.
  # Extract owner/repo from the PR url via parameter expansion and compare exactly
  # (avoids grep -F / case-glob env quirks in some test shells).
  if [ -n "$REPO" ]; then
    if ! printf '%s' "$REPO" | grep -qE "$OWNER_REPO_RE"; then
      echo "FAILED: --repo must be owner/name, got: $REPO" >&2; return 1
    fi
    # url shape: https://github.com/<owner>/<repo>/pull/N  -> strip prefix up to github.com/,
    # then strip the /pull/N suffix, leaving <owner>/<repo>
    url_repo=${url#*github.com/}
    url_repo=${url_repo%%/pull/*}
    if [ "$url_repo" != "$REPO" ]; then
      echo "FAILED: pr-$PR belongs to a different repo (url=$url, extracted=$url_repo, expected=$REPO)" >&2; return 1
    fi
  fi

  # state check. --require-merged (spc-254 A2 merge-stage proof) strictly
  # requires state==MERGED — a PR still OPEN after a claimed merge did not
  # land. --allow-merged accepts OPEN|MERGED (idempotent finish-ledger use);
  # default rejects MERGED|CLOSED (pr-open stamp use).
  if [ "$REQUIRE_MERGED" -eq 1 ]; then
    case "$state" in
      MERGED) : ;;
      OPEN|CLOSED) echo "FAILED: pr-$PR is $state (expected MERGED; --require-merged)" >&2; return 1;;
      *) echo "FAILED: pr-$PR has unexpected state: $state" >&2; return 1;;
    esac
  elif [ "$ALLOW_MERGED" -eq 0 ]; then
    case "$state" in
      OPEN) : ;;
      MERGED|CLOSED) echo "FAILED: pr-$PR is $state (expected OPEN; pass --allow-merged to accept MERGED)" >&2; return 1;;
      *) echo "FAILED: pr-$PR has unexpected state: $state" >&2; return 1;;
    esac
  else
    case "$state" in
      OPEN|MERGED) : ;;
      *) echo "FAILED: pr-$PR has unexpected state: $state (expected OPEN or MERGED)" >&2; return 1;;
    esac
  fi

  # expected-oid check
  if [ -n "$EXPECTED_OID" ]; then
    if ! printf '%s' "$EXPECTED_OID" | grep -qE "$OID_RE"; then
      echo "FAILED: --expected-oid must be a hex OID (7-40 chars), got: $EXPECTED_OID" >&2; return 1
    fi
    if ! oid_matches "$head" "$EXPECTED_OID"; then
      echo "FAILED: pr-$PR head $head != expected $EXPECTED_OID" >&2; return 1
    fi
  fi

  echo "verified: pr-$PR $state head=$head"
  return 0
}

verify_commit() {
  if ! printf '%s' "$COMMIT" | grep -qE "$OID_RE"; then
    echo "FAILED: --commit must be a hex OID (7-40 chars), got: $COMMIT" >&2; return 1
  fi
  # tkt-237 LM5: `git cat-file -e` consults ONLY the local object database —
  # it succeeds the instant the commit exists locally, regardless of whether
  # `git push` delivered it to the remote. This verifies a local object, NOT a
  # push landing; route push verification through --branch (git ls-remote).
  if ! git cat-file -e "$COMMIT" 2>/dev/null; then
    echo "FAILED: commit object $COMMIT does not exist in the local object database" >&2; return 1
  fi
  echo "verified: commit $COMMIT exists (local object database only — push not confirmed)"
  return 0
}

verify_branch() {
  if ! command -v git >/dev/null 2>&1; then
    echo "FAILED: git not found" >&2; return 1
  fi
  # Fetch the remote ref (refs/heads/<branch>). Distinguish a real ls-remote
  # failure (network/auth/origin-unreachable → nonzero) from a simply-absent
  # ref (ls-remote succeeds with empty output): both fail-closed (exit 1), but
  # with different diagnostics so the operator chases the right cause. The `if`
  # guards the command substitution so `set -e`/pipefail can't kill the script
  # with the raw ls-remote exit (128) before this branch runs.
  local ls_out remote_ref
  if ls_out=$(git ls-remote origin "refs/heads/$BRANCH" 2>/dev/null); then
    remote_ref=$(printf '%s\n' "$ls_out" | awk '{print $1}')
    if [ -z "$remote_ref" ]; then
      echo "FAILED: remote branch $BRANCH does not exist on origin" >&2; return 1
    fi
  else
    echo "FAILED: cannot verify remote branch $BRANCH — git ls-remote origin errored (network/auth/unreachable)" >&2; return 1
  fi
  if [ -n "$EXPECTED_OID" ]; then
    if ! printf '%s' "$EXPECTED_OID" | grep -qE "$OID_RE"; then
      echo "FAILED: --expected-oid must be a hex OID (7-40 chars), got: $EXPECTED_OID" >&2; return 1
    fi
    if ! oid_matches "$remote_ref" "$EXPECTED_OID"; then
      echo "FAILED: remote $BRANCH at $remote_ref != expected $EXPECTED_OID" >&2; return 1
    fi
  fi
  echo "verified: branch $BRANCH head=$remote_ref"
  return 0
}

if [ -n "$PR" ]; then verify_pr
elif [ -n "$COMMIT" ]; then verify_commit
elif [ -n "$BRANCH" ]; then verify_branch
fi
