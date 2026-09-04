# tkt-463-ci-bats-sha-pin-baseline

> **TL;DR:** CI hardening that must land after #451 (macOS matrix) because it edits the same bats install step.
> **Kind:** chore · **Priority:** P3
> **Path:** spc-458 → tkt-463 → (pr-…)

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P3 |
| labels | chore, P3 |
| github | https://github.com/percena/lattice/issues/463 |
| status | pr-open |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-03T16:51:19Z |
| updated | 2026-09-04T00:06:18Z |
| adopted | false |
| summary | Pin bats-core by commit SHA in both workflows; ci-local mirrors the artifacts base-baseline comparison |
| spec | spc-458 — Review follow-up (path: ../../specs/spc-458-review-followup.md) |
| covers | A15 |
| blocked_by | #444 |
| merge_blocked_by | #444 |
| parallel_group | (serial) |
| paths | .github/workflows/lattice-scripts.yml, .github/workflows/plugin-hooks.yml, tools/ci-local.sh, tools/tests/ci-local.bats |
| solo_merge | yes |
| autonomy | 3 |
| **primary_ticket** | tkt-463 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-463-ci-bats-sha-pin-baseline` |
| worktree | sibling `…/lattice.worktrees/tkt-463-ci-bats-sha-pin-baseline/` |
| prs | pr-466 — https://github.com/percena/lattice/pull/466 |

## Acceptance (this slice)

- [x] **A15** both workflows clone bats-core, `git checkout <pinned-sha>` and fail if `git rev-parse v1.13.0` ≠ pin before `install.sh`; `ci-local.sh` fetches `origin/<base>:tools/.validator-warning-baseline.txt` and passes `--baseline` like `artifacts.yml`; `ci-local.bats` covers the new step.

## Approach

1. Resolve the v1.13.0 commit SHA once (`git ls-remote https://github.com/bats-core/bats-core.git refs/tags/v1.13.0^{}`), pin it in a single `env:` at workflow level, verify then install.
2. `ci-local.sh`: mirror `artifacts.yml:37-52` under the resolved `BASE_REF`; skip with a note when the base ref is unavailable.
Touch-set: see `paths`. Wait for #451 (macOS matrix) to merge, then rebase.

## Anticipated decisions

- Pin location (workflow `env:` vs a repo file read by both workflows and ci-local) — disposition: agent-decides (reversible; prefer `tools/.bats-pin` read by all three so the pin is single-sourced).

## Decision journal

<!-- Append-only during execution. -->
- 2026-09-04 pin location → `tools/.bats-pin` (`tag=` + `sha=`) read by both workflows (verify `git rev-parse HEAD` == sha before `sudo install.sh`) and by ci-local.sh for BATS_PIN (source: agent-judgment per Anticipated decisions; single-sourced, reversible).
- 2026-09-04 NOTICED-drain folded in (blocking): the macOS bats matrix (#451) hung every lattice-scripts run since 16:49Z at `next-artifact-id.bats` "rev claim collision" — BSD `tr -dc … </dev/urandom | head -c 3` never exits when SIGPIPE is ignored (GitHub macOS runner) → 20-min job timeout → required `bats` check red on every PR touching skills/tools. Fixed `rand_suffix` with a bounded `od -N6` producer + a portable watchdog regression test (source: agent-judgment; spc-441 Risks anticipated "BSD vs GNU differences" as a follow-up).

## Pending decisions

- (none)

## Attempts

- attempt 3 · 2026-09-04 · `--print-output-on-failure` revealed the macOS cause: `timeout "$PROBE_TIMEOUT_SEC" bash helper --probe` — no GNU `timeout` on macOS → every probe 'dead' → spawned-but-dead. Added `run_with_timeout` (timeout → gtimeout → bash watchdog) in run-process-wave.sh + 2 tests (watchdog kill, probe without timeout(1) on PATH). Product-code portability bug surfaced by the spc-441 macOS matrix, drained here as it blocks the required check.

- attempt 2 · 2026-09-04 · PR #466 CI: macOS job now completes (hang fixed) but batch-work wave tests A1/A2/A6 + coordinator A5 wiring failed on BOTH runners — surrogate `nohup sleep 1` vs several python3 startups before the 0.3s grace probe → `spawned-but-dead` on slow runners (never reproducible locally, incl. bats 1.13 + non-root). Surrogates now sleep 4s. Also carried the two dev reds (spc-441 spec done-state, SC2154) so this PR can be the first to merge.

- attempt 1 · 2026-09-04 · pin file + workflow sha verify + ci-local base-baseline step + macOS hang fix · suites: next-artifact-id 12/12 (+1), ci-local (tkt-463 tests) 2/2, shellcheck OK, ci-local --fast all green (bats parity degraded: local 1.2.1)

## Notes

- #451 merged 2026-09-03T16:49Z, so this ticket proceeded (spc-458 Decision 5 not needed). It is the critical path for every other spc-458 PR because of the macOS hang.

## References

- Spec: `spc-458` · spc-441 A3 (#451)

## Lineage

- Parent spec: **spc-458** · Parent issue: **#458** · Primary ticket: **tkt-463** · Covers: **A15** · Blocked by: #444 · Merge blocked by: #444 · Worktree bind: `tkt-463-ci-bats-sha-pin-baseline`

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
