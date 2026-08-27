# tkt-96-observation-capture

> **TL;DR:** The tkt-84 capture pattern applied to agent observations — an out-of-paths defect noticed mid-ticket becomes a grep-able `NOTICED:` queue entry at notice time, and review-delivery sweeps the queue into every digest with dispositions
> **Kind:** feat · **Priority:** P2
> **Path:** (ticket-only) → tkt-96 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/96 |
| status | closed |
| adopted | false |
| summary | decision-policy "Observation duty" (DEFAULT) + NOTICED: canonical form + 3-skill wiring + review-delivery sweep step |
| spec | none — audit rev-20260827-033352Z process observation #3 |
| covers | audit process observation #3 (out-of-paths leak) |
| blocked_by | (none) |
| parallel_group | G1 (wave 1) |
| paths | skills/_lattice-lib/references/decision-policy.md, skills/start-work/SKILL.md, skills/finish-work/SKILL.md, skills/batch-work/SKILL.md, skills/review-delivery/SKILL.md, skills/review-delivery/references/** |
| solo_merge | yes |
| **primary_ticket** | tkt-96 (this issue) |
| **related_tickets** | tkt-84 (pattern precedent — operator-preference capture duty, pr-88) |
| **worktree_bind** | tkt-96-observation-capture |
| worktree | sibling …/lattice.worktrees/tkt-96-observation-capture/ |
| prs | pr-102 — https://github.com/percena/lattice/pull/102 |

## Acceptance (this slice)

- [x] **A1** decision-policy.md: "Observation duty" subsection (DEFAULT; canonical `NOTICED: <path> — <one line>` form; in-paths → fix now, out-of-paths → capture; never blocks the ticket)
- [x] **A2** start-work / finish-work / batch-work SKILL.md: one style-matched line each
- [x] **A3** review-delivery digest recipe: sweep `NOTICED:` lines from the round's binders into Findings with per-item disposition (ticket | one-liner | wontfix)
- [x] **A4** validate-skills green; full `ci-local` green

## Approach

Mirror pr-88's shape exactly: a short subsection in decision-policy beside "Capture duty" (same table style), one DEFAULT-severity line at each skill's natural point (start-work EXECUTE notes, finish-work checks-gate area, batch-work spawn-brief/orchestrator duties), and one step in review-delivery's digest recipe (`grep -rn '^- NOTICED:' .lattice/tickets/` over the round's binders → Findings rows). No new files, no template restructuring.

## Anticipated decisions

- Queue location — pre-resolved: binder `## Notes` `NOTICED:` lines (grep-able, zero new state files); direct `gh issue create` stays optional when cheap+authorized
- Sweep scope — disposition: agent-decides (round's binders only vs repo-wide; prefer round-scoped with a repo-wide flag; journal)

## Decision journal

- 2026-08-27 — Placement: "Observation duty — DEFAULT" sits directly after "Capture duty — INVARIANT" in decision-policy.md, opening with "Capture duty's twin", same prose + routes-table shape. Source: 1 — ticket AC/Approach ("beside Capture duty, same table style"). Reversible, ticket-local.
- 2026-08-27 — start-work legacy marker: replaced the old `NOTICED BUT NOT TOUCHING:` bullet (step 7) and its Rationalizations echo with pointers to the canonical `NOTICED:` form — two competing markers would split the grep-able queue (`grep '^- NOTICED:'` misses the legacy form). Source: 5 — heuristic: minimal public surface (one canonical marker). Reversible, ticket-local; start-work/SKILL.md is in declared paths.
- 2026-08-27 — finish-work numbering: new duty appended as DEFAULT rule 16 per ticket brief; HINT rules renumbered 16→17, 17→18, 18→19 (no cross-references to old HINT numbers found repo-wide). Source: 1 — ticket brief. Reversible, ticket-local.
- 2026-08-27 — Sweep scope (pre-flagged in Anticipated decisions): round-scoped by default — `grep -rn '^- NOTICED:'` over the reviewed set's binder dirs only; the recipe notes the queue drains only through dispositions, and repo-wide sweeping stays a manual extra (no new flag machinery — review-delivery has no CLI to hang it on). Source: 5 — heuristic: most reversible option. Reversible, ticket-local.
- 2026-08-27 — Digest template: NOTICED sweep added as a small subsection (3-row table incl. a "(none — sweep ran clean)" row) inside the existing "Findings" section, before "Artifact insufficiency" — per-item dispositions need a table, not one line; no restructuring. Source: 1 — ticket AC ("add it minimally"). Reversible, ticket-local.

## Pending decisions

## Attempts

## Notes

- Evidence of the leak: finish-work numbering "noticed twice", ~25 stale headers noticed in tkt-73 and never filed, README tier count noticed in tkt-82's zh work and left on the EN side

## References

- rev-20260827-033352Z process observation #3 · tkt-84 binder + pr-88 (pattern) · decision-policy.md Capture duty

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: **tkt-96** · Parallel group: **G1 (wave 1)** · Worktree bind: `tkt-96-observation-capture`

## Finish

- pr-102 merged: 2026-08-27T05:30:26Z — https://github.com/percena/lattice/pull/102 (base merge)
- issue #96 closed: 2026-08-27T05:30:32Z — https://github.com/percena/lattice/issues/96
