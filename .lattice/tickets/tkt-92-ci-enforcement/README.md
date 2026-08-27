# tkt-92-ci-enforcement

> **TL;DR:** The artifacts validator enters CI, all four workflows fire on dev pushes (post-merge tree finally verified), red runs get a disposition duty at merge time, and two vacuously-true bats tests get their tmpdir guard
> **Kind:** ci · **Priority:** P1
> **Path:** (ticket-only) → tkt-92 → (pr-…)

| Field | Value |
| --- | --- |
| kind | ci |
| priority | P1 |
| labels | chore, P1 |
| github | https://github.com/percena/lattice/issues/92 |
| status | closed |
| adopted | false |
| summary | validate-lattice-artifacts in CI + dev push triggers + red-run disposition duty in finish-work + BATS_TEST_TMPDIR guards |
| spec | none — audit rev-20260827-033352Z F3/F8 |
| covers | audit F3, F8 (bats tmpdir) |
| blocked_by | (none) |
| parallel_group | G1 (wave 1) |
| paths | .github/workflows/lint.yml, .github/workflows/lint-heavy.yml, .github/workflows/lattice-scripts.yml, .github/workflows/plugin-hooks.yml, skills/finish-work/SKILL.md, plugins/lattice/scripts/tests/strip-quoted-and-heredocs.bats, tools/ci-local.sh |
| solo_merge | yes |
| **primary_ticket** | tkt-92 (this issue) |
| **related_tickets** | tkt-62 (ci-local author; its journal named the vacuous bats lines), tkt-60 (train gate whose races surface here) |
| **worktree_bind** | tkt-92-ci-enforcement |
| worktree | sibling …/lattice.worktrees/tkt-92-ci-enforcement/ |
| prs | pr-101 — https://github.com/percena/lattice/pull/101 |

## Acceptance (this slice)

- [x] **A1** `validate-lattice-artifacts.py` runs in CI (pull_request + push)
- [x] **A2** all four workflows add `dev` to push branches
- [x] **A3** finish-work checks gate: red-run disposition duty (DEFAULT) — every failed run on the branch dispositioned in the binder before merge (transient vs real, one line), aligned with the preferences.md CI smart-retry DEFAULT
- [x] **A4** `strip-quoted-and-heredocs.bats:178,197` get the `${BATS_TEST_TMPDIR:-$(mktemp -d)}` guard; assertions can no longer no-op under bats 1.2.1
- [x] **A5** full `ci-local` green; post-merge dev push shows workflows firing

## Approach

Add an `artifacts` step to lint.yml (checkout + python + `python3 tools/validate-lattice-artifacts.py`) — cheapest workflow, no path filter (artifact drift can come from any path; `.lattice/**` edits must trigger it). Add `dev` beside `main` in the four `push.branches` lists. finish-work SKILL.md: one DEFAULT line in the checks-gate step (while in that file, fix the duplicate rule numbering — two 8s/two 12s — noted twice in digests; renumber is in-paths here). ci-local parity note documenting that CI now runs the artifacts validator (was local-only). Bats: swap the two bare expansions for the guarded idiom used by every sibling.

## Anticipated decisions

- Which workflow hosts the artifacts step — pre-resolved: lint.yml (fast, no paths filter today for its lint job? verify; if lint.yml is path-filtered, run artifacts as an unfiltered job in the same workflow)
- Red-run duty severity — pre-resolved: DEFAULT (skip with stated reason), matching the smart-retry preference's own severity

## Decision journal

- Artifacts gate placement: NEW workflow `.github/workflows/artifacts.yml` (paths: `.lattice/**` + the validator + itself) instead of a job inside path-filtered lint.yml — lint.yml's filter (skills/plugins/tools) would miss binder-only PRs, and widening it would run shellcheck on every binder edit — chain source 1 (binder Anticipated decisions, pre-resolved variant chosen on verified filter facts); reversible.
- Red-run duty severity DEFAULT, wired as finish-work Core-rules #15 + a Short-path step-3 pointer; while in the file, the pre-existing duplicate rule numbering (two 8s, two 12s — digest-noticed twice) was renumbered (DEFAULT 9–15, HINT 16–18); no live cross-references to the old numbers exist (grep-verified) — chain source 1; reversible.

## Pending decisions

## Attempts

## Notes

- Evidence runs: 33032948048 / 32988009357 (version-gate races), 32985801055 (startup_failure, empty jobs — platform event outage), 22 cancelled = concurrency cancel-in-progress noise
- Operator: "CI 时不时报错，但总是漏掉处理" — the duty in A3 is the structural answer

## References

- rev-20260827-033352Z F3/F8 · `.lattice/preferences.md` CI smart-retry DEFAULT · tkt-62 journal (bats shim rationale)

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: **tkt-92** · Parallel group: **G1 (wave 1)** · Worktree bind: `tkt-92-ci-enforcement`

## Finish

- pr-101 merged: 2026-08-27T05:19:01Z — https://github.com/percena/lattice/pull/101 (base merge)
- issue #92 closed: 2026-08-27T05:19:05Z — https://github.com/percena/lattice/issues/92
