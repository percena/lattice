# tkt-287-migration-doc-amendment-adr011-accepted

> **TL;DR:** One-shot migrate in-repo relocated files; amend ADR-008/spc-186 A1 location ref; fix stale flow.md prose; flip ADR-011 Accepted.
> **Kind:** docs · **Status:** open · **Priority:** P3
> **Path:** spc-282 → tkt-287 → (pr-…)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P3 |
| labels | docs,P3 |
| github | https://github.com/percena/lattice/issues/287 |
| status | open |
| adopted | false |
| summary | Migrate relocated in-repo files; amend ADR-008/spc-186 A1 gate-location ref; fix flow.md stale prose; flip ADR-011 Accepted |
| spec | spc-282 — Consumer-repo footprint hygiene (path: ../../specs/spc-282-consumer-repo-footprint-hygiene.md) |
| covers | A7 |
| blocked_by | tkt-283, tkt-284 (needs final layout) |
| parallel_group | wave-3 (last) |
| paths | skills/_lattice-lib/scripts/migrate-relocated-runtime-state.sh (new), docs/adr/008-batch-work-process-isolation-spawn.md, .lattice/specs/spc-186-hard-limit-closure.md, skills/batch-work/references/flow.md, docs/adr/011-consumer-repo-footprint-hygiene.md, docs/adr/README.md |
| solo_merge | yes |
| primary_ticket | tkt-287 |
| related_tickets | tkt-283 (relocation), tkt-284 (gitignore) |
| worktree_bind | spc-282-consumer-repo-footprint-hygiene |
| prs | (none yet) |
| created | 2026-08-31T00:00:00Z |
| updated | 2026-08-31T00:00:00Z |

## Why

Existing clones (Lattice monorepo + any consumer repos that ran batch-work before the upgrade) have in-repo `.batch-work-active` / `.batch-merge-authorized` / `.coordinator/` that must be migrated (removed) on first run after upgrade, else they linger as dead untracked files. `ADR-008` + `spc-186` A1 "single gate point" location reference still points at `<MAIN>/.lattice/` and must be amended to the state dir. `skills/batch-work/references/flow.md:168` "MAIN `.lattice/.gitignore` tolerates it" prose is stale. `ADR-011` flips Proposed → Accepted once the ticket set lands.

## Scope

- One-shot migration script: remove now-relocated in-repo files (`.batch-work-active`, `.batch-merge-authorized`, `.coordinator/`) from existing clones on first run after upgrade (read-then-delete; runtime state, no data loss). Idempotent.
- Amend `ADR-008` + `spc-186` A1 "single gate point" location reference → state dir (location only; spawn-mode law unchanged).
- Fix stale `skills/batch-work/references/flow.md:168` "MAIN `.lattice/.gitignore` tolerates it" prose.
- Flip `ADR-011` Status: Proposed → Accepted; update `docs/adr/README.md` index row.

## Approach

1. `migrate-relocated-runtime-state.sh` (idempotent `rm -f` of relocated files if present under `.lattice/`); triggered by `ensure-lattice.sh` on first run after upgrade (one-shot, marker-guarded).
2. Edit `docs/adr/008-batch-work-process-isolation-spawn.md`: amend "single gate point at `<MAIN>/.lattice/`" → "at `$XDG_STATE_HOME/lattice/<fingerprint>/`".
3. Edit `.lattice/specs/spc-186-hard-limit-closure.md` A1: same location amendment.
4. Edit `skills/batch-work/references/flow.md:168`: replace stale "MAIN `.lattice/.gitignore` tolerates it" with state-dir recipe.
5. Edit `docs/adr/011-…md`: Status Proposed → Accepted; `docs/adr/README.md` index row status flip.

## Anticipated decisions

- `pre-resolved` — read-then-delete migration (runtime state, no data loss) per ADR-011.
- `pre-resolved` — ADR-011 Accepted flip lands here (last ticket in the set).
- `pre-resolved` — ADR-008 spawn-mode law unchanged; only gate location amended.
- `agent-decides` — migration trigger point (`ensure-lattice.sh` first-run vs explicit `lattice-migrate` subcommand): reversible.

## Pending decisions

(none)

## blocked_by

tkt-283, tkt-284 (needs final state-dir layout + gitignore bootstrap before migration + doc amendment are accurate)
