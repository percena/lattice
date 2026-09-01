# tkt-311-finish-work-p3-followup

> **TL;DR:** Three P3 issues in the finish-work close-reason feature chain: GHE host gap in gh api calls, TOCTOU between base branch/SHA, and gh pr view stderr noise
> **Kind:** bug · **Priority:** P3

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P3 |
| labels | bug, P3 |
| github | https://github.com/percena/lattice/issues/311 |
| status | pr-open |
| adopted | true |
| summary | GHE host gap (gh api --hostname) + TOCTOU (single REST call for base ref+sha) + stderr noise (capture-then-emit-on-failure) |
| spec | none |
| covers | A1–A3 |
| paths | skills/finish-work/scripts/alignment-check.sh, skills/finish-work/scripts/close-fixed-issues.sh, skills/_lattice-lib/scripts/finish-ledger.sh, skills/finish-work/scripts/update-pr-base.sh |
| solo_merge | yes |
| **primary_ticket** | tkt-311 (this issue) |
| **related_tickets** | tkt-293 (baseRefOid fix), tkt-294 (close-reason awareness), tkt-301 (state_reason REST fix), tkt-302 (GHE URL parsing) |
| worktree_bind | tkt-311-finish-work-p3-followup |
| prs | pr-315 — https://github.com/percena/lattice/pull/315 |
| created | 2026-09-01T07:40:00Z |
| updated | 2026-09-01T09:17:46Z |

## Acceptance

- [x] **A1** GHE host gap: pass hostname to `gh api` calls (via `--hostname` flag or full API URL) in alignment-check.sh, close-fixed-issues.sh, finish-ledger.sh — extract hostname from PR URL or GH_TARGET_REPO_ID
- [x] **A2** TOCTOU: fetch both `baseRefName` and base SHA from a single `gh api repos/.../pulls/...` REST call (returns `.base.ref` + `.base.sha`), or add consistency check verifying SHA belongs to branch
- [x] **A3** stderr noise: capture stderr to temp var, emit only on failure (not unconditionally) — preserves tkt-293's error-surfacing intent without leaking noise

## Approach

1. **GHE host (A1):** Extract hostname from the PR URL (alignment-check, close-fixed-issues) or `GH_TARGET_REPO_ID` host prefix (finish-ledger). Pass `--hostname {host}` to `gh api`, or construct full URL `https://{host}/api/v3/repos/{owner}/{repo}/issues/{N}`.
2. **TOCTOU (A2):** Replace the separate `gh pr view` + `gh api repos/.../pulls/...` pattern with a single `gh api repos/.../pulls/{PR}` call that returns both `.base.ref` (branch name) and `.base.sha` (commit SHA). This makes the snapshot atomic.
3. **stderr noise (A3):** Use a temp-file or variable capture pattern: `view_err=$(mktemp); view_json=$(gh pr view ... 2>"$view_err") || { cat "$view_err" >&2; exit 1; }; rm -f "$view_err"`. Errors surface; noise doesn't leak.

## Anticipated decisions

- GHE hostname source — pre-resolved: extract from PR URL (alignment-check, close-fixed-issues) or GH_TARGET_REPO_ID host prefix (finish-ledger). Source: existing URL parsing + repo_identity_from_url. Reversible, ticket-local.
- TOCTOU fix approach — pre-resolved: single REST call returning both base.ref and base.sha (atomic snapshot). Alternative (consistency check) adds complexity for no atomicity gain. Source: issue #311 fix approach. Reversible, ticket-local.
- stderr capture pattern — pre-resolved: temp-file capture (mktemp) is the standard bash pattern. Variable capture (`2>&1` into var) mixes stdout/stderr on failure. Source: issue #311 fix approach. Reversible, ticket-local.

## Decision journal

- 2026-09-01T09:17:46Z — direct jump: queued → pr-open (in-progress stamp skipped; PR #315) [WARN — signal logged, not silently lost]
