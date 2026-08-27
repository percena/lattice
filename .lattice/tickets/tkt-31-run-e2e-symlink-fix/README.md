# tkt-31-run-e2e-symlink-fix

> **TL;DR:** Fix broken plugin symlink (4→3 levels) + dead ego-browser markdown link in run-e2e SKILL.md
> **Kind:** fix · **Status:** open · **Priority:** P1

| Field | Value |
| --- | --- |
| kind | fix |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/31 |
| status | closed |
| adopted | false |
| summary | fix broken run-e2e plugin symlink + dead ego-browser doc link |
| spec | (none — review-fix, not Spec-driven) |
| covers | A1, A2 |
| blocked_by | (none) |
| parallel_group | (none) |
| paths | plugins/lattice/skills/run-e2e, skills/run-e2e/SKILL.md |
| solo_merge | yes (primary of one-PR with tkt-32, tkt-33, tkt-34) |
| **primary_ticket** | tkt-31 (this issue) |
| **related_tickets** | tkt-32, tkt-33, tkt-34 (same PR) |
| **worktree_bind** | tkt-31-run-e2e-symlink-fix |
| prs | pr-36 — https://github.com/percena/lattice/pull/36 |

## Acceptance (this slice)

- [x] **A1** `realpath plugins/lattice/skills/run-e2e` resolves to the actual `skills/run-e2e` directory; `SKILL.md` reachable through the symlink
- [x] **A2** `skills/run-e2e/SKILL.md` no longer contains a dead relative link to `../../ego-lite/`; ego-browser referenced by name or external URL

## Notes

- Source: review-code pass on dev→main change set (2026-08-25)
- Symlink uses `../../../../skills/run-e2e` (4 levels) — all 8 siblings use `../../../` (3 levels)
- One-PR batch with tkt-32, tkt-33, tkt-34 (all review-fix items, small blast radius)

## References

- GitHub issue body is SoT for long prose

## Finish

- pr-36 merged: 2026-08-25T09:45:49Z — https://github.com/percena/lattice/pull/36 (base merge)
- issue #31 closed: 2026-08-25T09:46:35Z — https://github.com/percena/lattice/issues/31
