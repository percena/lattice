# tkt-62-ci-local

> **TL;DR:** One-command local CI-parity runner (`tools/ci-local.sh`) wired into the batch-work evidence contract
> **Kind:** feat · **Priority:** P2
> **Path:** (ticket-only) → tkt-62 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/62 |
| status | queued |
| adopted | false |
| summary | ci-local.sh runs everything CI runs; batch briefs cite it as the required evidence command |
| spec | none — enhancement from dogfood review |
| covers | rev-20260826-145922Z-18p Finding 3 |
| blocked_by | (none) |
| parallel_group | G1 (parallel) |
| paths | tools/ci-local.sh, tools/README.md, skills/batch-work/references/flow.md |
| solo_merge | yes |
| **primary_ticket** | tkt-62 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-62-ci-local |
| worktree | sibling …/lattice.worktrees/tkt-62-ci-local/ |
| prs | (none) |

## Acceptance (this slice)

- [ ] `bash tools/ci-local.sh` reproduces every CI verdict locally on a clean tree (validate-skills, artifacts, plugin-versions with default base ref, shellcheck, all bats with the BATS_TEST_TMPDIR shim); summary table; nonzero exit on any failure; itself shellcheck-clean
- [ ] batch-work evidence contract names it

## Approach

Read `.github/workflows/*.yml` to enumerate exactly what CI runs; wrap each as a step function with pass/fail capture; default `--base-ref` = `origin/dev` fork-point (overridable); print a final table and exit max(status). Update the flow.md EVIDENCE CONTRACT block to require `ci-local` output instead of the two-validator subset. tools/README row.

## Anticipated decisions

- Whether ci-local skips plugin-versions when no bundled paths changed — disposition: agent-decides (mirror CI path filters)

## Decision journal

## Pending decisions

## Attempts

## Notes

- Root cause context: agents ran 2/5 validators; the train red was discovered only on GitHub
- Keep runtime reasonable — bats is the slow step; a `--fast` flag skipping bats is acceptable if default stays full

## References

- Review: `rev-20260826-145922Z-18p` Finding 3

## Lineage

- Parent spec: none (ticket-only)
- Primary ticket: **tkt-62** · Covers: Finding 3 · Parallel group: **G1** · Worktree bind: `tkt-62-ci-local`
- Child PRs: (none yet)

## Finish

- (none yet)
