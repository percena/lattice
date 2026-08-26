# tkt-63-batch-ergonomics

> **TL;DR:** check-pr-context whitelists the batch marker; new stamp-pr-open.sh does binder prs/status + issue-body acceptance sync in one idempotent step
> **Kind:** feat · **Priority:** P2
> **Path:** (ticket-only) → tkt-63 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/63 |
| status | queued |
| adopted | false |
| summary | marker warning whitelist + pr-open stamp helper (binder + GH issue acceptance sync); kills the two-commit dance and the alignment sync gap |
| spec | none — enhancement from dogfood review |
| covers | rev-20260826-145922Z-18p Finding 4, Addendum A1/A2 |
| blocked_by | (none) |
| parallel_group | G1 (parallel) |
| paths | skills/create-pr/scripts/check-pr-context.sh, skills/create-pr/SKILL.md, skills/_lattice-lib/scripts/stamp-pr-open.sh, skills/_lattice-lib/scripts/tests/stamp-pr-open.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-63 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-63-batch-ergonomics |
| worktree | sibling …/lattice.worktrees/tkt-63-batch-ergonomics/ |
| prs | (none) |

## Acceptance (this slice)

- [ ] check-pr-context no longer warns when the only dirt is `.lattice/.batch-work-active`
- [ ] stamp-pr-open.sh: binder `prs` row (`pr-N — URL`) + `status: pr-open` + GitHub issue-body acceptance checkbox sync (Lattice-template issues only; adopted bodies untouched) — one idempotent call; bats green
- [ ] create-pr SKILL.md: DEFAULT line invoking the helper when a binder exists; marker lifecycle note (finish-work removes at merge; never `git add -A` it)

## Approach

check-pr-context: filter the untracked list against the marker path before counting. stamp-pr-open: locate binder by branch bind or `--binder`; edit prs/status rows in the field table; read binder checked `- [x]` acceptance ids, mirror into the issue body via `gh issue edit --body-file` (guard `adopted: true` → skip body, comment instead); finish-ledger-style locking + idempotency. Follow finish-ledger.sh code conventions. Evidence: the alignment gate HARD-blocked PR #52's merge on exactly this sync gap.

## Anticipated decisions

- Acceptance mirroring granularity (by A* id match vs check-all) — disposition: pre-resolved(id-match; check-all is what the orchestrator did manually and is too blunt for partial slices)
- Whether create-pr auto-invokes vs documents the helper — disposition: agent-decides (DEFAULT auto when binder exists, escape flag)

## Decision journal

## Pending decisions

## Attempts

## Notes

- Do NOT gitignore the marker (its untracked-dirt visibility is part of the cleanup guard); the whitelist is warning-level only

## References

- Review: `rev-20260826-145922Z-18p` Finding 4, A1, A2

## Lineage

- Parent spec: none (ticket-only)
- Primary ticket: **tkt-63** · Covers: Finding 4 + A1/A2 · Parallel group: **G1** · Worktree bind: `tkt-63-batch-ergonomics`
- Child PRs: (none yet)

## Finish

- (none yet)
