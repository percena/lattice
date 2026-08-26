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
| status | pr-open |
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
| prs | pr-72 — https://github.com/percena/lattice/pull/72 |

## Acceptance (this slice)

- [x] update-pr-base.sh JSON carries `diff_changed` (+ conflict flag); bats green
- [x] finish-work documents: train guidance (--no-update-branch when clean mergeable; superset rule for train files), file-explicit conflict law (`git checkout --ours/--theirs <named path>` only; `git add -A` during conflict resolution forbidden), post-merge conflict-marker sweep in the Verification checklist
- [x] mini-review text single-sourced (flow.md authoritative; SKILL.md summary + pointer)
- [x] **(comment scope)** CI-checks gate in the train loop — `gh pr checks <N>` rollup before each train merge, fail/pending surfaced, train-transient version reds distinguished from real failures, never merge on `mergeable` alone (flow.md §3.4 rule 1; SKILL.md checklist + Verification + rationalization row)
- [x] **(comment scope)** orphaned-run hygiene at branch deletion — wait for new head's checks or `gh run cancel` in-flight runs before `--delete-branch` (observed runs 32984498741 / 32984662279) (flow.md §3.4 rule 4; SKILL.md checklist + Verification)

## Approach

update-pr-base: after merge/rebase, compare pre/post `git diff base...HEAD` hashes → `diff_changed`; surface conflict occurrence. finish-work flow.md gains a "Merge trains" subsection with the three rules; Verification gains `grep -rn '<<<<<<<' <touched paths>` post-merge. Collapse the duplicated mini-review section: flow.md keeps the full text, SKILL.md keeps the contract summary + load-on-demand pointer. Incident evidence: conflict markers reached dev via PR #59's merge automation on 2026-08-26 (repaired commit `628e4cb`).

## Anticipated decisions

- diff_changed granularity (any byte vs hunk-level materiality) — disposition: pre-resolved(any-change flag + separate `conflict` flag; materiality judgment stays with the operator/mini-review per A8)

## Decision journal

- 2026-08-26 — **diff probe source split:** rebase path compares local `git diff base...HEAD` pre/post (base/head refs already explicitly fetched); GitHub `update_branch` path compares `gh pr diff <N>` captured before/after the mutation — server-side truth, no side-effect fetch into the operator's cwd repo, works without local PR objects. Any probe failure degrades to `diff_changed:true` (conservative: unknown diff voids the verdict).
- 2026-08-26 — **conflict flag semantics:** success JSON always `conflict:false` (a conflicted update never completes in this script); conflict-shaped failure JSONs (`conflicting`, `rebase_failed`, `conflicting_after_update`) carry `conflict:true`. `rebase_failed` distinguishes a conflicted rebase (in-flight `rebase-merge`/`rebase-apply` state detected before abort) from a rebase that failed to start (dirty worktree → `conflict:false`).
- 2026-08-26 — **conflict bats case:** harness supports it (real git + bare origin) — covered with a real conflicting-rebase test asserting `reason:rebase_failed` + `conflict:true`; no absence documentation needed. `update_branch` path also covered via a stateful `gh pr diff` stub (pre/post fixtures).
- 2026-08-26 — **single-source direction:** Privacy/Secrets axis + privacy-override decision bullets existed only in the SKILL.md duplicate — merged INTO flow.md §2.7 before collapsing SKILL.md to summary+pointer, so the authoritative text loses no invariant. Merge trains placed as flow.md §3.4 (between merge §3 and close-fixes §3.5).

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


- pr-72 merged: 2026-08-26T16:57:11Z — https://github.com/percena/lattice/pull/72 (base merge)
- issue #64 closed: 2026-08-26T16:57:16Z — https://github.com/percena/lattice/issues/64
