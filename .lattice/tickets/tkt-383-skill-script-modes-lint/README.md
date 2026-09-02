# tkt-383-skill-script-modes-lint

> **TL;DR:** `chmod +x` two SKILL-named scripts (`stamp-pr-open.sh`, `review-context.py`); add mode lint scoped to SKILL-named scripts only.
> **Kind:** chore · **Priority:** P2
> **Path:** rev-20260902-080545Z F3 → tkt-383 → (pr-…)

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P2 |
| labels | chore, P2 |
| github | https://github.com/percena/lattice/issues/383 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T09:20:35Z |
| updated | 2026-09-02T09:20:35Z |
| adopted | false |
| summary | chmod +x stamp-pr-open.sh / review-context.py + mode lint for SKILL-named scripts |
| spec | (none — spawned from rev-20260902-080545Z) |
| covers | (none) |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | G2 |
| paths | skills/_lattice-lib/scripts/stamp-pr-open.sh, skills/review-code/scripts/review-context.py, tools/validate-skills.sh, tools/tests/ |
| solo_merge | yes |
| primary_ticket | tkt-383 |
| related_tickets | (none) |
| worktree_bind | tkt-383-skill-script-modes-lint |
| worktree | sibling `…/<repo>.worktrees/tkt-383-skill-script-modes-lint/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A1** `stamp-pr-open.sh` and `review-context.py` are `100755` in git.
- [ ] **A2** `validate-skills.sh` mode lint catches SKILL-named scripts at `100644` (planted-drift test).
- [ ] **A3** `skill-scripts-exist` probe passes (no `high` fail row for this class).

## Approach

`git update-index --chmod=+x` both files. Add a mode lint block in `tools/validate-skills.sh` that: (1) greps each `SKILL.md` for script-path references (the same resolution `skill-scripts-exist` probe uses), (2) checks each resolved path's git mode via `git ls-files -s`, (3) errors when a SKILL-named script is `100644`. Scope is critical: 16 `scripts/*` files are legitimately `100644` (sourced `_lattice-home.sh`, `lib/*.py`, `transition-api.py`, `verify-mutation.sh`) — the lint must only apply to scripts named as executables in a `SKILL.md`, not every file under `scripts/`.

**Touch-set:** `skills/_lattice-lib/scripts/stamp-pr-open.sh` (chmod), `skills/review-code/scripts/review-context.py` (chmod), `tools/validate-skills.sh` (new mode lint block), `tools/tests/` (planted-drift test).

## Anticipated decisions

- lint scope — pre-resolved (rev F3 mechanism): SKILL-named scripts only (the `skill-scripts-exist` set); 16 files legitimately `100644`.
- lint placement — agent-decides: `tools/validate-skills.sh` (existing skill validator; mode check fits the anatomy rules already enforced there).
- planted-drift test shape — agent-decides: create a temp `100644` script named in a fixture SKILL.md, assert lint catches it.

## Decision journal

## Pending decisions

## Attempts

## Notes

- Origin: `rev-20260902-080545Z` F3 (lineage-audit baseline, spc-369 dry run).

## References

- GitHub issue: #383
- Review: `rev-20260902-080545Z` Finding F3
- Spec: `spc-369` (review-lineage — produced the finding)
- Probe: `skill-scripts-exist` in `skills/review-lineage/references/probes.md`

## Lineage

- Parent spec: (none — spawned from review)
- Parent issue: none (ticket-only)
- Primary ticket: tkt-383
- Related / sub-tickets: (none)
- Covers: (none)
- Blocked by: (none)
- Merge blocked by: (none)
- Parallel group: G2
- Worktree bind: tkt-383-skill-script-modes-lint
- Child PRs: (none yet)

## Assets

## Finish

- (none yet)
