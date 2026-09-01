# tkt-301-state-reason-rest-fix

> **TL;DR:** state_reason REST fetch in finish-ledger uses GH_TARGET_REPO_ID (includes host) → 404 on all runs; error JSON captured as state_reason → binder data corruption; close-fixed-issues has same variable-not-cleared pattern
> **Kind:** bug · **Priority:** P1

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/301 |
| status | pr-open |
| adopted | true |
| summary | Fix finish-ledger: use $REPO not $GH_TARGET_REPO_ID for gh api repos/ path; clear variable in if-failure handlers; validate state_reason against known set; clean corrupted binder ledger lines |
| spec | none |
| covers | A1–A4 |
| paths | skills/_lattice-lib/scripts/finish-ledger.sh, skills/finish-work/scripts/close-fixed-issues.sh |
| solo_merge | no (co-delivered with tkt-302) |
| **primary_ticket** | tkt-301 (this issue) |
| **related_tickets** | tkt-302 (co-delivered — GHE URL + reason_map) |
| **worktree_bind** | tkt-301-state-reason-rest-fix |
| prs | (pending), pr-303 — https://github.com/percena/lattice/pull/303 |

## Acceptance

- [x] **A1** finish-ledger.sh: use `$REPO` (owner/repo) instead of `$GH_TARGET_REPO_ID` for `gh api repos/` URL path — GH_TARGET_REPO_ID is `host/owner/repo` (for `--repo` flag), not valid as a `repos/` path segment
- [x] **A2** Both finish-ledger.sh + close-fixed-issues.sh: in the `if !` failure handler, explicitly clear the variable to empty (`GH_ISSUE_STATE_REASON=""` / `close_reason=""`) before printing the WARNING — `gh api --jq` outputs error JSON to stdout on 404, captured by command substitution
- [x] **A3** Defense-in-depth: validate `state_reason` against the known set (`completed`, `not_planned`, `reopened`, `duplicate`, `out_of_date`) before using it in ledger/anomaly/report logic; discard anything else as "unavailable"
- [x] **A4** Clean up corrupted binder ledger lines in tkt-293 and tkt-294 binders (error JSON as reason/anomaly from PR #295 finish-work)

## Reproduction

```bash
# Malformed API call (what finish-ledger currently does):
$ gh api "repos/github.com/percena/lattice/issues/293" --jq '.state_reason' 2>/dev/null
{"message":"Not Found","documentation_url":"https://docs.github.com/rest","status":"404"}
# exit=1, but stdout captured the error JSON → used as state_reason

# Correct call:
$ gh api "repos/percena/lattice/issues/293" --jq '.state_reason'
completed
```

## Approach

1. finish-ledger.sh: change `gh api "repos/${GH_TARGET_REPO_ID}/issues/${ISSUE_M}"` to `gh api "repos/${REPO}/issues/${ISSUE_M}"` (or strip host from GH_TARGET_REPO_ID)
2. Both scripts: add explicit `VAR=""` in the `if !` handler before the WARNING echo
3. Both scripts: after fetching state_reason, validate against known set; if not in set, set to ""
4. Re-stamp corrupted binder ledger lines (or remove the error-JSON lines)

## Decision journal

- 2026-09-01T07:26:05Z — direct jump: queued → pr-open (in-progress stamp skipped; PR #303) [WARN — signal logged, not silently lost]
