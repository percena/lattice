# tkt-64-merge-train-hardening

> **TL;DR:** finish-work train guidance (file-explicit conflict law, marker sweep, --no-update-branch) + machine-readable diff_changed in update-pr-base + mini-review single-source
> **Kind:** feat · **Priority:** P2
> **Path:** (ticket-only) → tkt-64 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/64 |
| status | queued |
| adopted | false |
| summary | merge-train hardening: prevent the add -A conflict-marker incident class; make the A8 verdict-void rule checkable |
| spec | none — hardening from dogfood review |
| covers | rev-20260826-145922Z-18p F20, Addendum A3 |
| blocked_by | (none) |
| parallel_group | G1 (parallel) |
| paths | skills/finish-work/SKILL.md, skills/finish-work/references/flow.md, skills/finish-work/scripts/update-pr-base.sh, skills/finish-work/scripts/tests/update-pr-base.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-64 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-64-merge-train-hardening |
| worktree | sibling …/lattice.worktrees/tkt-64-merge-train-hardening/ |
| prs | (none) |

## Acceptance (this slice)

- [ ] update-pr-base.sh JSON carries `diff_changed` (+ conflict flag); bats green
- [ ] finish-work documents: train guidance (--no-update-branch when clean mergeable; superset rule for train files), file-explicit conflict law (`git checkout --ours/--theirs <named path>` only; `git add -A` during conflict resolution forbidden), post-merge conflict-marker sweep in the Verification checklist
- [ ] mini-review text single-sourced (flow.md authoritative; SKILL.md summary + pointer)

## Approach

update-pr-base: after merge/rebase, compare pre/post `git diff base...HEAD` hashes → `diff_changed`; surface conflict occurrence. finish-work flow.md gains a "Merge trains" subsection with the three rules; Verification gains `grep -rn '<<<<<<<' <touched paths>` post-merge. Collapse the duplicated mini-review section: flow.md keeps the full text, SKILL.md keeps the contract summary + load-on-demand pointer. Incident evidence: conflict markers reached dev via PR #59's merge automation on 2026-08-26 (repaired commit `628e4cb`).

## Anticipated decisions

- diff_changed granularity (any byte vs hunk-level materiality) — disposition: pre-resolved(any-change flag + separate `conflict` flag; materiality judgment stays with the operator/mini-review per A8)

## Decision journal

## Pending decisions

## Attempts

## Notes

- Keep every existing HARD gate untouched; this ticket adds signals and documentation, not new gates

## References

- Review: `rev-20260826-145922Z-18p` F20 + A3 · repair commit `628e4cb`

## Lineage

- Parent spec: none (ticket-only)
- Primary ticket: **tkt-64** · Covers: F20 + A3 · Parallel group: **G1** · Worktree bind: `tkt-64-merge-train-hardening`
- Child PRs: (none yet)

## Finish

- (none yet)
