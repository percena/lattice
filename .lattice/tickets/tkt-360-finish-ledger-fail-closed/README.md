# tkt-360-finish-ledger-fail-closed

> **TL;DR:** finish-ledger must fail closed when the ledger entry is not staged/committed — two finishes (tkt-356, tkt-357) flipped binder→closed but committed no ledger entry, turning dev artifacts CI red.
> **Kind:** bug · **Priority:** P2
> **Path:** (none — post-spc-337 leftover audit, 2026-09-02) → tkt-360 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P2 |
| labels | bug, P2 |
| github | https://github.com/percena/lattice/issues/360 |
| status | pr-open |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T05:59:14Z |
| updated | 2026-09-02T06:16:57Z |
| adopted | true |
| summary | finish-ledger must fail closed when the ledger entry is not staged/committed (dev CI red twice) |
| spec | (none — post-spc-337 leftover audit) |
| covers | A1, A2, A3 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | (serial) |
| paths | skills/_lattice-lib/scripts/finish-ledger.sh, skills/_lattice-lib/scripts/tests/finish-ledger.bats, skills/finish-work/SKILL.md, skills/finish-work/references/flow.md |
| solo_merge | yes |
| **primary_ticket** | tkt-360 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-360-finish-ledger-fail-closed |
| worktree | sibling `…/lattice.worktrees/tkt-360-finish-ledger-fail-closed/` |
| prs | pr-366 — https://github.com/percena/lattice/pull/366 |

## Acceptance (this slice)

- [ ] **A1** After staging, finish-ledger verifies `git diff --cached --name-only` contains the ledger path when a flip happened; otherwise exits non-zero with the recovery command (never a silent WARNING).
- [ ] **A2** A helper `finish-commit.sh` (or a documented one-liner in SKILL step 10) commits the staged set and fails if `git status --porcelain .lattice` is non-empty afterwards — the "index clean" assertion becomes a command, not prose.
- [ ] **A3** bats: flip + ledger not stageable (e.g. ledger path gitignored) → non-zero.

## Approach

1. Read `skills/_lattice-lib/scripts/finish-ledger.sh` — locate the `commit_transaction` / ledger-append path and the `git add` that stages the binder + ledger; confirm where a flip is detected (status before vs after).
2. Add a post-stage assertion: after `git add`, run `git diff --cached --name-only` and require the `.transition-ledger/<tkt>.jsonl` path to be present when a status flip occurred; exit non-zero with the recovery command (re-run finish-ledger) if missing (A1).
3. Introduce `finish-commit.sh` (or documented one-liner in finish-work SKILL step 10) that commits the staged set and asserts `git status --porcelain .lattice` is empty afterwards (A2).
4. Add bats cases: (a) normal merge path still stamps + commits cleanly; (b) flip-but-ledger-not-staged (e.g. ledger path gitignored or write fails) → non-zero (A3); (c) cancel path still works.
5. Tighten finish-work prose (SKILL.md:123 + flow.md:383/471) to point at the now-commandified index-clean assertion.

## Anticipated decisions

- **Helper vs one-liner (A2)** — disposition: agent-decides (reversible; both are low-risk; prefer `finish-commit.sh` if the assertion logic is non-trivial, else a documented one-liner).
- **Assertion location (A1)** — disposition: pre-resolved (inside `finish-ledger.sh` post-stage, where the flip is already known; cheaper than a separate validator).
- **Ledger path detection** — disposition: agent-decides (how to know "a flip happened" — compare pre/post status, or gate on any ledger append attempt; read code to pick the cleanest signal).
- **Failure message format** — disposition: agent-decides (must include the recovery command; mirror existing finish-ledger error style).

## Decision journal

<!-- Append-only during execution. -->
- 2026-09-02T06:16:57Z — direct jump: queued → pr-open (in-progress stamp skipped; PR #366) [WARN — signal logged, not silently lost]

## Pending decisions

<!-- (none so far) -->

## Attempts

<!-- Fallback ledger. -->

## Notes

- Context: tkt-356 finish (b5ff5a8) flipped binder→closed but committed no ledger entry → `transition_ledger_snapshot_mismatch` → dev artifacts CI red. Same pattern hit tkt-357 (f4d1fba). #364 backfilled tkt-356's entry to restore CI green; this ticket prevents the next occurrence.
- Related memory: [[finish-ledger-cancel-entry-bug]] (same bug class).
- CI is currently green on dev (post-#364).

## References

- GitHub issue body is SoT for long prose: https://github.com/percena/lattice/issues/360
- Worktree policy: one tree ↔ one PR; tkt open binds
- Related: #356 (the original macOS-portability bug whose finish surfaced this), #364 (the backfill that restored CI green)

## Lineage

- Parent spec: **(none)**
- Parent issue: **none** (ticket-only)
- Primary ticket: **tkt-360**
- Related / sub-tickets: (none)
- Covers: **A1, A2, A3**
- Blocked by: (none)
- Merge blocked by: (none)
- Parallel group: (serial)
- Worktree bind: `tkt-360-finish-ledger-fail-closed`
- Child PRs: (none yet)

## Assets

(none)

## Finish

- (none yet)
