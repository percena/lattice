# tkt-81-helper-polish

> **TL;DR:** Four polish items from the first unattended consumption — stamp ordering hint + --check-all, ledger placeholder replacement, context --from-heads, "never add -A" brief line — with a 0.2.3 bump
> **Kind:** chore · **Priority:** P3
> **Path:** (ticket-only) → tkt-81 → (pr-…)

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P3 |
| labels | chore, P3 |
| github | https://github.com/percena/lattice/issues/81 |
| status | queued |
| adopted | false |
| summary | helper polish batch (stamp-pr-open, finish-ledger, build-review-context, batch-work brief line) + 0.2.3 |
| spec | none — digest findings (rev-20260826-172600Z F3–F6) |
| covers | digest F3, F4, F5, F6 |
| blocked_by | (none) |
| parallel_group | G1 (parallel) |
| paths | skills/_lattice-lib/scripts/stamp-pr-open.sh, skills/_lattice-lib/scripts/finish-ledger.sh, skills/_lattice-lib/scripts/build-review-context.sh, skills/_lattice-lib/scripts/tests/, skills/batch-work/references/flow.md, plugins/lattice/.claude-plugin/plugin.json, .claude-plugin/marketplace.json, CHANGELOG.md |
| solo_merge | yes |
| **primary_ticket** | tkt-81 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-81-helper-polish |
| worktree | sibling …/lattice.worktrees/tkt-81-helper-polish/ |
| prs | (none) |

## Acceptance (this slice)

- [ ] stamp-pr-open: usage-header ordering hint + `--check-all` (check binder acceptance boxes, then mirror); bats
- [ ] finish-ledger: replaces a `(none…)` prs placeholder instead of appending beside it; bats regression
- [ ] build-review-context: `--from-heads` reads binder state from each ticket's open PR head (local fallback); bats
- [ ] batch-work flow spawn-brief template: "never `git add -A`; stage named paths" line
- [ ] 0.2.3 bump (plugin.json + marketplace.json) + CHANGELOG entry in this PR

## Approach

Each helper change is additive and small; reuse each script's existing test harness (fake-gh stubs, self-managed mktemp). `--from-heads`: `git fetch` the PR head ref (read-only) and `git show <ref>:<binder path>`; never checkout. Version: standard single-PR bump (only bundled-touching ticket this round).

## Anticipated decisions

- `--check-all` semantics when some boxes are deliberately unchecked (deferrals) — disposition: must-ask parked with default: `--check-all` refuses when the binder contains a "deferred" note line, forcing explicit per-box checking (safe default)

## Decision journal

## Pending decisions

- `--check-all` vs deferred-note interaction — default if unanswered: refuse when deferral notes present

## Attempts

## Notes

- Evidence source: two independent night agents hit the stamp ordering; 2/3 hit the add -A reflex — all self-caught, so these are ergonomics, not correctness

## References

- Digest: `rev-20260826-172600Z` Findings 3–6

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: **tkt-81** · Parallel group: **G1** · Worktree bind: `tkt-81-helper-polish`

## Finish

- (none yet)
