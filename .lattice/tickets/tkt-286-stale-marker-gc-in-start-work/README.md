# tkt-286-stale-marker-gc-in-start-work

> **TL;DR:** start-work GCs stale state-dir marker entries by mtime so a crashed batch doesn't leave a permanent open merge gate.
> **Kind:** chore · **Status:** queued · **Priority:** P2
> **Path:** spc-282 → tkt-286 → (pr-…)

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P2 |
| labels | chore,P2 |
| github | https://github.com/percena/lattice/issues/286 |
| status | pr-open |
| adopted | false |
| summary | start-work scans state dir for stale markers (mtime > threshold) and removes them as orphan-batch residue |
| spec | spc-282 — Consumer-repo footprint hygiene (path: ../../specs/spc-282-consumer-repo-footprint-hygiene.md) |
| covers | A6 |
| blocked_by | tkt-283 (needs state dir layout) |
| parallel_group | wave-2 |
| paths | skills/start-work/SKILL.md, skills/_lattice-lib/scripts/state-dir-gc.sh (new), skills/_lattice-lib/scripts/lattice-state-home.sh (from tkt-283) |
| solo_merge | yes |
| primary_ticket | tkt-286 |
| related_tickets | tkt-283 (provides state-home helper) |
| worktree_bind | spc-282-consumer-repo-footprint-hygiene |
| prs | pr-291 — https://github.com/percena/lattice/pull/291 |
| created | 2026-08-31T00:00:00Z |
| updated | 2026-08-31T15:15:11Z |

## Why

A crashed batch leaves the relocated gate marker in the state dir (`$XDG_STATE_HOME/lattice/<fingerprint>/.batch-work-active`), permanently opening the merge gate until manual cleanup. `start-work` (the natural batch-entry skill) should GC stale entries by mtime so an orphaned batch does not leave a permanent fail-open.

## Scope

- New `state-dir-gc.sh` in `_lattice-lib`: scans the state dir for marker entries whose mtime predates a configurable threshold (default 24h, `LATTICE_STALE_MARKER_HOURS` override); removes `.batch-work-active`, `.batch-merge-authorized`, stale `.coordinator/` entries, stale `.transition-ledger/*.lock`.
- `start-work` SKILL.md: calls `state-dir-gc.sh` on entry (before spawning).
- GC only removes stale entries; never creates markers. Fail-closed-by-absence is unchanged.
- Tests: `state-dir-gc.bats` — stale marker (mtime > threshold) removed; fresh marker (mtime < threshold) untouched.

## Approach

1. `state-dir-gc.sh`: `find "$STATE_HOME" -name .batch-work-active -mmin +"$((LATTICE_STALE_MARKER_HOURS*60))" -delete` (+ same for `.batch-merge-authorized`, `.coordinator/` json with mtime > threshold, `.transition-ledger/*.lock` stale). Uses `lattice-state-home.sh` from tkt-283.
2. `start-work` SKILL.md: add a "stale-marker GC" step in the setup phase (after ensure-workspace, before classify).
3. bats: `touch -d "2 days ago"` a marker → start-work GC removes it; `touch` a fresh marker → untouched.

## Anticipated decisions

- `pre-resolved` — GC in `start-work` (batch-entry skill), mtime-based, default 24h per ADR-011.
- `pre-resolved` — GC only removes, never creates; fail-closed-by-absence unchanged.
- `agent-decides` — GC script name + threshold env var name: reversible.

## Decision journal

- 2026-08-31T15:15:11Z — direct jump: queued → pr-open (in-progress stamp skipped; PR #291) [WARN — signal logged, not silently lost]

## Pending decisions

(none)

## blocked_by

tkt-283 (provides the state-home helper + fingerprint layout)
