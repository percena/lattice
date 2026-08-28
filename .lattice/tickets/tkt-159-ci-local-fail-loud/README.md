# tkt-159-ci-local-fail-loud

> **TL;DR:** ci-local must fail loud on unresolvable `--base-ref` (never silent-skip the version gate) and print a truthful `--help`.
> **Kind:** bug · **Priority:** P2
> **Path:** repo-review 2026-08-28 → tkt-159 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P2 |
| labels | bug, P2 |
| github | https://github.com/percena/lattice/issues/159 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| adopted | false |
| summary | ci-local base-ref fail-loud + usage() rewrite + first ci-local bats suite |
| spec | (none — ticket-only) |
| covers | A1, A2, A3 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | tools/ci-local.sh; tools/tests/ci-local.bats (new) |
| solo_merge | yes |
| **primary_ticket** | tkt-159 |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-159-ci-local-fail-loud` |
| worktree | sibling `…/lattice.worktrees/tkt-159-ci-local-fail-loud/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A1** Unresolvable `--base-ref` → plugin-versions step FAILs with explicit error and nonzero exit (never recorded as clean `skip`).
- [ ] **A2** `--help` prints clean text (no shebang leak), fully documents `--release-check` and `--fast`, no mid-sentence truncation.
- [ ] **A3** `tools/tests/ci-local.bats` covers arg parsing, the skip/fail distinction, and exit-code aggregation.

## Notes

- Dev-lenient / main-strict split is intentional (ADR-005, #119) — do NOT change the default mode.
- Evidence: `tools/ci-local.sh:152-166` (process-substitution diff swallows bad ref), `:31` (usage strips shebang, 18-line cap).

## References

- ADR-005 `docs/adr/005-version-bump-at-release-boundary.md`
- #119 — introduced `--release-check`

## Lineage

- Parent issue: none (ticket-only)
- Primary ticket: **tkt-159**
- Covers: A1, A2, A3
- Blocked by: (none)
- Parallel group: G1
- Worktree bind: `tkt-159-ci-local-fail-loud`

## Finish

- (none yet)
