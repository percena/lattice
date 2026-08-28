# tkt-148-interactive-escape-docs

> **TL;DR:** Document machine-enforced strict default + interactive-confirmation escape in policy.md and a new always-loaded project CLAUDE.md.
> **Kind:** docs · **Status:** open · **Priority:** P2
> **Path:** spc-145 -> tkt-148 -> (pr-…)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P2 |
| labels | docs, P2 |
| github | https://github.com/percena/lattice/issues/148 |
| status | open |
| adopted | false |
| summary | Interactive-confirmation escape docs + policy.md + project CLAUDE.md |
| spec | spc-145 — PreToolUse hard-enforcement stack (path: ../../specs/spc-145-worktree-discipline-gate.md) |
| covers | A6, A8 |
| blocked_by | #147 |
| parallel_group | (serial) |
| paths | `skills/start-work/references/policy.md`, `CLAUDE.md`, `plugins/lattice/hooks/**` (denial messages) |
| solo_merge | yes |
| **primary_ticket** | tkt-146 (ship owner) |
| **related_tickets** | tkt-146, tkt-147 (same PR) |
| **worktree_bind** | `spc-145-worktree-discipline-gate` |
| worktree | sibling `…/lattice.worktrees/spc-145-worktree-discipline-gate/` |
| prs | (none yet) |

## Acceptance (this slice)

- [x] **A6** A non-standard flow requires the agent to ask the user and receive explicit confirmation before routing through the `--reason` escape; drift (no confirmation) is blocked at L1/L3. Reason records "user-authorized". (Documented + denial messages instruct the escape.)
- [x] **A8** (docs) Strict default + interactive-confirmation escape documented in policy.md and always-loaded CLAUDE.md.

## Notes

- Verify L1/L3 denial messages name the escape and the "ask the user" step (cross-ref tkt-146/147).

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-145` (path above)
- ADR: `ADR-006` -> `docs/adr/006-worktree-discipline-hard-enforcement.md`

## Lineage

- Parent spec: **spc-145**
- Parent issue: **#145**
- Primary ticket: **tkt-146**
- Related / sub-tickets: tkt-146, tkt-147
- Covers: **A6, A8**
- Blocked by: **#147**
- Parallel group: (serial)
- Worktree bind: `spc-145-worktree-discipline-gate`
- Child PRs: (none yet)

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
