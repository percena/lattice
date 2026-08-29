# tkt-189 — Single-source status vocabulary + stamp-pr-open side-state guard

> **Status:** queued · kind feat · priority P0 · covers spc-187 A2,A8

## Field table

| field | value |
| --- | --- |
| kind | feat |
| priority | P0 |
| labels | feat, P0 |
| github | https://github.com/percena/lattice/issues/189 |
| status | queued |
| adopted | false |
| summary | Eliminate the 4-copy status vocabulary drift; stop stamp-pr-open from silently overwriting parked/stuck/rework |
| spec | spc-187 |
| covers | A2, A8 |
| blocked_by | (none) |
| parallel_group | g1 |
| paths | skills/_lattice-lib/scripts/**, tools/validate-lattice-artifacts.py, skills/create-tickets/references/templates/ticket-binder.md |
| solo_merge | true |
| primary_ticket | true |
| related_tickets | tkt-190 (blocked by this), tkt-191 |
| worktree_bind | (pending start-work) |
| prs | (none) |

## Acceptance (this slice)

- [ ] A2: Single machine-readable source for ticket status vocabulary + coupled-field rules; reconcile-state.sh, finish-ledger.sh, stamp-pr-open.sh, validate-lattice-artifacts.py all derive from it (validator via vendored copy + byte-equality bats test, the `lib/binder_rows.py` pattern)
- [ ] A2: stamp-pr-open.sh refuses parked/stuck/rework → pr-open without explicit override flag + journal trace
- [ ] A2: queued→pr-open direct-jump policy decided, documented in workflow-fsm.md, enforced (recommended: allow + WARN journal entry)
- [ ] A8: five-piece contract for the new guard (check/message/escape/trace/metric)
- [ ] bats: side-state overwrite refused; vocabulary parity green

## Approach

Follow the binder_rows.py precedent: canonical Python module under `skills/_lattice-lib/scripts/lib/` holding status sets + coupled-field rules; shell scripts source/derive via a small helper; validator keeps its vendored copy with the existing byte-equality bats pattern. stamp-pr-open: read current status before flip; parked/stuck/rework → refuse with message naming the override flag; override requires --reason, writes a Decision journal entry. Jump policy: allow queued→pr-open with WARN journal entry (in-progress stamp remains DEFAULT), documented in workflow-fsm.md §2.

## Anticipated decisions

| Decision | Disposition | Notes |
| --- | --- | --- |
| Source format (py module vs yaml) | pre-resolved | py module + byte-equality test, binder_rows.py precedent |
| queued→pr-open jump policy | pre-resolved | allow + WARN journal; in-progress stamp stays DEFAULT |
| Override flag name | agent-decides | reversible, ticket-local |

## Decision journal

- 2026-08-29 — Created from spc-187 POST_SPLIT; approach pre-resolved at split time (spc-42 A5). Resolution source: rev-20260829-160834Z + ADR-007.

## Pending decisions

(none)

## Attempts

(none yet)

## Notes

## References

- Spec: `.lattice/specs/spc-187-hard-limit-closure.md` (A2, A8)
- Review: `.lattice/reviews/rev-20260829-160834Z-workflow-fsm-hardlimit-review.md` (F1/F7 findings)
- Law: `docs/adr/007-hard-limit-scope-law.md`
- Guard site: `skills/_lattice-lib/scripts/stamp-pr-open.sh:346-348`

## Lineage

- Parent spec: spc-187 — https://github.com/percena/lattice/issues/187
- Origin review: rev-20260829-160834Z
- GitHub issue: #189
