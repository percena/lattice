# tkt-439-binder-dir-mismatch-fix

> **TL;DR:** Fix tkt-35 dir/github mismatch + duplicate_ticket_id + header_status_mismatch causing CI red
> **Kind:** bug · **Priority:** P1
> **Path:** (none) → tkt-439 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/439 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-03T10:15:47Z |
| updated | 2026-09-03T10:15:47Z |
| adopted | false |
| summary | Fix tkt-35/38 dir mismatch + duplicate_ticket_id + 3 header_status_mismatch |
| covers | (none — ticket-only) |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | (serial) |
| paths | .lattice/tickets/tkt-35-review-code-extended-axes/**, .lattice/tickets/tkt-201-*/**, .lattice/tickets/tkt-211-*/**, .lattice/tickets/tkt-246-*/** |
| solo_merge | yes |
| autonomy | 4 |
| **primary_ticket** | tkt-439 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-439-binder-dir-mismatch-fix |
| worktree | sibling |
| prs | pr-440 — https://github.com/percena/lattice/pull/440 |

## Acceptance (this slice)

- [x] **A1** `tkt-35-review-code-extended-axes/` renamed to `tkt-38-review-code-extended-axes/` (dir matches github #38)
- [x] **A2** `tkt-38-review-code-extended-axes/README.md` has created/updated timestamp rows
- [x] **A3** tkt-201, tkt-211, tkt-246 TL;DR header status matches field-table status (all `closed`)
- [x] **A4** `python3 tools/validate-lattice-artifacts.py` passes (0 errors, 0 new warnings)

## Approach

1. `git mv .lattice/tickets/tkt-35-review-code-extended-axes .lattice/tickets/tkt-38-review-code-extended-axes`
2. Add `| created |` and `| updated |` rows to the renamed binder
3. Fix TL;DR header on tkt-201 (`Status: queued` → `Status: closed`)
4. Fix TL;DR header on tkt-211 (`Status: in-progress` → `Status: closed`)
5. Fix TL;DR header on tkt-246 (`Status: in-progress` → `Status: closed`)
6. Run validator to confirm

## Decision journal

- rename target: tkt-38 (github issue #38 confirmed CLOSED) — source: gh issue view 38

## Notes

Pre-existing CI failure on dev. Not introduced by spc-433.

## Finish


- pr-440 merged: 2026-09-03T10:15:20Z — https://github.com/percena/lattice/pull/440 (base merge)
- anomaly: direct jump — prior status `queued` before terminal merge; in-progress/pr-open stamps were skipped (ADR-012 §3; metric direct-jump)
- issue #439 closed: 2026-09-03T10:15:36Z (reason: completed) — https://github.com/percena/lattice/issues/439
