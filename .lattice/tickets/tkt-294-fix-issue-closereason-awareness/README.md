# tkt-294-fix-issue-closereason-awareness

> **TL;DR:** finish-work treats an already-closed `Fixes` issue as delivered without checking its close reason; a `NOT_PLANNED`-while-delivered closure passes silently — surface the close-reason as WARN and record `stateReason` in the ledger
> **Kind:** enhancement · **Priority:** P3

| Field | Value |
| --- | --- |
| kind | enhancement |
| priority | P3 |
| labels | enhancement, P3 |
| github | https://github.com/percena/lattice/issues/294 |
| status | pr-open |
| adopted | true |
| summary | Fetch `stateReason` for closed Fixes issues via `gh api`; emit WARN in alignment-check when NOT_PLANNED/DUPLICATE/OUT_OF_DATE while PR delivers; record `stateReason` in finish-ledger (anomaly line when != COMPLETED); include reason in close-fixed-issues already_closed report |
| spec | none |
| covers | A1–A3 |
| blocked_by | (none) |
| parallel_group | (none — serial with tkt-293, one PR) |
| paths | skills/finish-work/scripts/alignment-check.sh, skills/_lattice-lib/scripts/finish-ledger.sh, skills/finish-work/scripts/close-fixed-issues.sh |
| solo_merge | no (co-delivered with tkt-293) |
| **primary_ticket** | tkt-294 (this issue) |
| **related_tickets** | tkt-293 (co-delivered in same PR — baseRefOid field fix) |
| **worktree_bind** | tkt-293-finish-work-baserefoid-closereason |
| worktree | sibling …/lattice.worktrees/tkt-293-finish-work-baserefoid-closereason/ |
| prs | (pending), pr-295 — https://github.com/percena/lattice/pull/295 |

## Acceptance (this slice)

- [x] **A1** `alignment-check.sh` — when a `Fixes`/`Closes` issue is already CLOSED, fetch its `stateReason` (via `gh api repos/{owner}/{repo}/issues/{n}` `.state_reason`). If `stateReason` is `NOT_PLANNED` (or `DUPLICATE`/`OUT_OF_DATE`) while the PR `Fixes`/`Closes` it, emit a WARN: "issue #N is closed as NOT_PLANNED but PR #M Fixes #N — reconcile close-reason vs the delivering PR". Gate stays HARD on Acceptance; this is awareness-only.
- [x] **A2** `finish-ledger.sh` — when stamping a `Fixes` issue's `closedAt`, also record `stateReason` (e.g. `issue #354 closed: <ts> (reason: NOT_PLANNED)`). If `stateReason != COMPLETED` for a `Fixes` issue that a merged PR delivers, append an `anomaly:` ledger line (the ledger already has an `anomaly:` vocabulary for unexpected states).
- [x] **A3** `close-fixed-issues.sh` — include `stateReason` in the `already_closed` report line so the operator sees the reason in stdout.

## Approach

1. **alignment-check.sh** — in the issue loop (~line 327, `if data.get("state") == "CLOSED"`), add a `gh api` fetch for `state_reason`. When `state_reason` is in the contradiction set (`NOT_PLANNED`, `DUPLICATE`, `OUT_OF_DATE`) and `iid in closing_ids`, append a WARN. Soft-fail on API error (don't block).
2. **finish-ledger.sh** — in the issue-state resolution block (~line 326), extend the `gh issue view --json` to also fetch `stateReason`. Since `stateReason` is NOT a `gh issue view --json` field (same asymmetry as #293's `baseRefOid`), use `gh api repos/{owner}/{repo}/issues/{n} --jq '.state_reason'`. Stamp the reason alongside `closedAt`; append `anomaly:` line when `state_reason != completed` for Fixes issues.
3. **close-fixed-issues.sh** — in the `already_closed` path, fetch and include `state_reason` in the report.

## Anticipated decisions

- stateReason fetch channel — pre-resolved: REST `gh api repos/{owner}/{repo}/issues/{n}` exposes `state_reason` (snake_case); GraphQL exposes `stateReason` (camelCase). REST is simpler and consistent with tkt-293's REST fix. `gh issue view --json` does NOT expose it (same field asymmetry). Source: issue #294 note on `stateReason` not being a `gh issue view --json` field. Reversible, ticket-local.
- Contradiction set scope — `NOT_PLANNED` is the primary case; `DUPLICATE` and `OUT_OF_DATE` are included because they also contradict "delivered by this PR". `REOPENED` and `COMPLETED` do not contradict. Source: issue #294 proposed enhancement §1. Reversible, ticket-local.

## Decision journal

- 2026-09-01T02:54:07Z — direct jump: queued → pr-open (in-progress stamp skipped; PR #295) [WARN — signal logged, not silently lost]

## Pending decisions

## Attempts

## Notes

- Issue body is the SoT (adopted: true) — do not rewrite the GitHub issue body
- NOT a HARD gate — the operator may close-as-NOT_PLANNED deliberately (e.g. superseded); surface as WARN/INFO for deliberate visible choice
- Concrete case: issue #354 closed as NOT_PLANNED ~11h before PR #355 (`Fixes #354`) merged; alignment-check passed `ok=True` after ACs checked
- Pairs with the existing `anomaly:` ledger vocabulary (unexpected prior state)

## References

- Issue: https://github.com/percena/lattice/issues/294
- Anchors: `skills/finish-work/scripts/alignment-check.sh:328`, `skills/_lattice-lib/scripts/finish-ledger.sh:326`, `skills/finish-work/scripts/close-fixed-issues.sh` (already_closed path)
