# tkt-160-tools-validators-hardening

> **TL;DR:** Remove the last Python 3.9+ API from tools/ (README floor is 3.8) and give routing evals a per-skill zero-positives guard.
> **Kind:** bug · **Priority:** P2
> **Path:** repo-review 2026-08-28 → tkt-160 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P2 |
| labels | bug, P2 |
| github | https://github.com/percena/lattice/issues/160 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| adopted | false |
| summary | validate-plugin-versions 3.8 compat + routing per-skill positive floor + bats |
| spec | (none — ticket-only) |
| covers | A1, A2, A3 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | tools/validate-plugin-versions.py; tools/run-routing-evals.py; tools/tests/ |
| solo_merge | yes |
| **primary_ticket** | tkt-160 |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-160-tools-validators-hardening` |
| worktree | sibling `…/lattice.worktrees/tkt-160-tools-validators-hardening/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A1** No Python 3.9+-only runtime API remains in `tools/*.py` (replace `removeprefix` at `validate-plugin-versions.py:236`); a test or lint assertion guards the 3.8 floor.
- [ ] **A2** Routing evals fail loudly when any catalog skill's case file has zero positive prompts; per-skill rank-1 stats printed.
- [ ] **A3** Bats coverage for both behaviors.

## Notes

- Same defect class as tkt-143 (binder_rows.py 3.9 compat) — this occurrence was missed.
- Path-disjoint from in-flight tkt-151/tkt-155 (they touch `validate-lattice-artifacts.py` + `lattice-artifacts.bats`, not these files).

## References

- tkt-143 / #144 — prior same-class fix
- README Requirements — `python3` ≥ 3.8 floor

## Lineage

- Parent issue: none (ticket-only)
- Primary ticket: **tkt-160**
- Covers: A1, A2, A3
- Blocked by: (none)
- Parallel group: G1
- Worktree bind: `tkt-160-tools-validators-hardening`

## Finish

- (none yet)
