# tkt-410-git-branch-op-misclassify

> **TL;DR:** Reported misclassification of `git branch -f` (as op=none) and `git checkout <treeish> -- <path>` (as branch-switch) — **already fixed by tkt-324**; regression tests exist at detect-git-branch-op.bats:115-128. Wont-fix (close as already-fixed).
> **Kind:** bug · **Priority:** P3
> **Path:** tkt-410 → (closed, no PR)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P3 |
| labels | bug, P3 |
| github | https://github.com/percena/lattice/issues/410 |
| status | closed |
| adopted | true |
| summary | wont-fix: both misclassifications were fixed by tkt-324 and are locked by regression tests |
| spec | none |
| covers | (none — no code change) |
| blocked_by | none |
| parallel_group | (serial — batch with tkt-409/411/412) |
| paths | plugins/lattice/scripts/detect-git-branch-op.py (no change) |
| solo_merge | no (no PR — close with comment) |
| **primary_ticket** | tkt-410 |
| **related_tickets** | tkt-324 (the fix), tkt-409/411/412 (batch siblings) |
| **worktree_bind** | tkt-409-noticed-drain-fixes |
| worktree | sibling …/lattice.worktrees/tkt-409-noticed-drain-fixes/ |
| prs | none (closed as already-fixed) |

## Acceptance (this slice)

- [x] **A1** Confirm `git branch -f <name>` → op=create (force-create is drift) — reproduced 2026-09-02: returns `{"op":"create","target":"feature-x"}`.
- [x] **A2** Confirm `git checkout <treeish> -- <path>` → op=none (file restore) — reproduced 2026-09-02: returns `{"op":"none"}`.
- [x] **A3** Regression tests exist: detect-git-branch-op.bats:115-128 (tkt-324 set covers -f, --force, treeish --, -f -d).

## Approach

No code change. Phase 0c reproduction confirmed the reported symptoms do not reproduce against current dev (03b3db8). Both edge cases were fixed by tkt-324 (code comments at detect-git-branch-op.py:168-171, 194-196 cite tkt-324). Regression tests at detect-git-branch-op.bats:113-128 lock the behavior. Close the issue with a comment pointing to tkt-324 + the test lines.

## Reproduction evidence

Pre-fix (reported): `git branch -f` → op=none (bypass); `git checkout <treeish> -- <path>` → op=switch (block).
Post-fix (current dev, 2026-09-02):
- `git branch -f feature-x` → `{"op": "create", "target": "feature-x"}` ✓
- `git checkout abc123 -- src/file.py` → `{"op": "none"}` ✓
- `git branch -f -d oldbranch` → `{"op": "none"}` ✓ (force-delete, not drift)
- sanity: `git checkout -b new` → create; `git switch main` → switch.

## Decision journal

- Wont-fix: already fixed by tkt-324; regression tests lock it. Operator-confirmed close-as-already-fixed (2026-09-02).

## Pending decisions

## Attempts

## Notes

- NOTICED in tkt-275. Filed by tkt-386 NOTICED backlog drain. Stale relative to tkt-324 fix.

## References

- tkt-324 (the fix) · detect-git-branch-op.py:168-171,194-196 · detect-git-branch-op.bats:113-128

## Lineage

- Parent spec: none · Primary ticket: tkt-410 · Parallel group: (serial NOTICED-drain batch) · Worktree bind: `tkt-409-noticed-drain-fixes`

## Finish

- closed: 2026-09-02 — wont-fix (already fixed by tkt-324; regression tests exist)
