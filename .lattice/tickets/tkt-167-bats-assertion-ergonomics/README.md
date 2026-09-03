# tkt-167-bats-assertion-ergonomics

> **TL;DR:** bash `set -e` never fires on failing `[[ ]]` or `! cmd` — audit every bats suite for mid-body assertions in those forms and convert to errexit-effective ones.
> **Kind:** bug · **Priority:** P1
> **Path:** tkt-163 implementation evidence → tkt-167 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/167 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| adopted | false |
| summary | Audit + fix non-terminal [[ ]] / ! cmd assertions across all bats suites; document the rule |
| spec | (none — ticket-only) |
| covers | A1, A2, A3 |
| blocked_by | (none) |
| parallel_group | (serial — touches nearly every bats file) |
| paths | skills/*/scripts/tests/*.bats; plugins/lattice/scripts/tests/*.bats; tools/tests/*.bats; CONTRIBUTING.md |
| solo_merge | yes |
| **primary_ticket** | tkt-167 |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-167-bats-assertion-ergonomics` |
| worktree | sibling `…/lattice.worktrees/tkt-167-bats-assertion-ergonomics/` |
| prs | pr-182 — https://github.com/percena/lattice/pull/182 |

## Acceptance (this slice)

- [x] **A1** Every existing bats test's pass/fail outcome is gated by at least one effective assertion (no test whose only discriminating assertions are non-terminal `[[ ]]` / `! cmd`).
- [x] **A2** Rule documented (CONTRIBUTING or test doc) + optional lint guard proven against a planted-bug fixture.
- [x] **A3** Full `bash tools/ci-local.sh` green after the sweep.

## Notes

- Mechanism + minimal repros: `tkt-163` binder `reproduction-evidence.md` ("Side discovery").
- Scale estimate at filing: ~660 `[[ ]]` assertion lines across 39 bats files / 744 tests.
- Discovered because a tkt-163 regression test passed 3× against the pre-fix (buggy) script while the output was demonstrably wrong — the mid-body `[[ ]]` failure was masked by a trailing passing `[ ]`.
- Effective assertion forms: plain `[ … ]`, `grep -q`/`grep -qF`, or a terminal-position assertion as the body's last command.

## References

- tkt-163 (where discovered), tkt-107 (escaped-defect metric — same class)

## Lineage

- Parent issue: none (ticket-only)
- Primary ticket: **tkt-167**
- Covers: A1, A2, A3
- Blocked by: (none)
- Parallel group: (serial)

## Finish


- pr-182 merged: 2026-08-28T15:14:51Z — https://github.com/percena/lattice/pull/182 (base merge)
- issue #167 closed: 2026-08-28T15:14:58Z — https://github.com/percena/lattice/issues/167
