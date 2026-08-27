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
| status | pr-open |
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
| prs | pr-89 — https://github.com/percena/lattice/pull/89 |

## Acceptance (this slice)

- [x] stamp-pr-open: usage-header ordering hint + `--check-all` (check binder acceptance boxes, then mirror); bats
- [x] finish-ledger: replaces a `(none…)` prs placeholder instead of appending beside it; bats regression
- [x] build-review-context: `--from-heads` reads binder state from each ticket's open PR head (local fallback); bats
- [x] batch-work flow spawn-brief template: "never `git add -A`; stage named paths" line
- [x] 0.2.3 bump (plugin.json + marketplace.json) + CHANGELOG entry in this PR

## Approach

Each helper change is additive and small; reuse each script's existing test harness (fake-gh stubs, self-managed mktemp). `--from-heads`: `git fetch` the PR head ref (read-only) and `git show <ref>:<binder path>`; never checkout. Version: standard single-PR bump (only bundled-touching ticket this round).

## Anticipated decisions

- `--check-all` semantics when some boxes are deliberately unchecked (deferrals) — disposition: must-ask parked with default: `--check-all` refuses when the binder contains a "deferred" note line, forcing explicit per-box checking (safe default)

## Decision journal

- `--check-all` × deferral notes: implemented the parked default — REFUSE (exit 1, before any mutation) when the binder Acceptance section contains a line matching "defer" — **ratified-by-default** (parked in Anticipated/Pending decisions, unobjected overnight; source: binder parked default, decision-policy chain #1 ticket AC)
- Deferral-note match is case-insensitive (`defer`, `Deferred`, `DEFER…`): the spec said "a line containing 'defer'"; the safe direction is the broader match (refusing too often beats blanket-checking a deferred box) — reversible + ticket-local (source: 5 — default heuristic, safety-first)
- stamp-pr-open's prs row got the same `(none…)`-placeholder replacement law as finish-ledger (scope letter (b) named only finish-ledger, but stamp-pr-open is in the paths row, had the identical `("", "(none)", "(none yet)")` tuple gap, and is the same F4 duplication class) — reversible + ticket-local (source: covers digest F4)
- `--from-heads` bats use a REAL fixture remote: a bare repo on a local path (`git init --bare` + push), so `git fetch`/`git show FETCH_HEAD:` run for real and no documented skip is needed — cheap (~1s), deterministic, no network (source: ticket AC option 1 of 2)
- `--from-heads` PR-number gh fallback searches `--state open` (not the manifest fallback's `--state all`): only an open PR has a head worth fetching; non-open PRs report `local (pr-N is <STATE> — not an open head)` — reversible + ticket-local (source: 5 — default heuristic)
- head `headRefName` is validated (`^[A-Za-z0-9][A-Za-z0-9._/-]*$`) before reaching the `git fetch` command line — gh output is external input; same identifier-hygiene law the sibling helpers apply to --pr/--repo (source: sibling-script convention, finish-ledger.sh)

## Pending decisions

- ~~`--check-all` vs deferred-note interaction — default if unanswered: refuse when deferral notes present~~ resolved 2026-08-27: default ratified by silence; implemented + journaled above

## Attempts

- single path per item, no fallback-ledger entries: all three suites green on first run (56/56 across stamp-pr-open 12, finish-ledger 28, build-review-context 16); one test-authoring slip (sed delimiter colliding with `|` in the prs-row pattern) caught and fixed before the run

## Notes

- Evidence source: two independent night agents hit the stamp ordering; 2/3 hit the add -A reflex — all self-caught, so these are ergonomics, not correctness

## References

- Digest: `rev-20260826-172600Z` Findings 3–6

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: **tkt-81** · Parallel group: **G1** · Worktree bind: `tkt-81-helper-polish`

## Finish

- (none yet)
