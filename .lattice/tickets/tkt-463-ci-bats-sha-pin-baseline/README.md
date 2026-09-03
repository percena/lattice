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
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-03T16:51:19Z |
| updated | 2026-09-03T16:51:19Z |
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
| prs | (none) |

## Acceptance (this slice)

- [ ] **A15** both workflows clone bats-core, `git checkout <pinned-sha>` and fail if `git rev-parse v1.13.0` ≠ pin before `install.sh`; `ci-local.sh` fetches `origin/<base>:tools/.validator-warning-baseline.txt` and passes `--baseline` like `artifacts.yml`; `ci-local.bats` covers the new step.

## Approach

1. Resolve the v1.13.0 commit SHA once (`git ls-remote https://github.com/bats-core/bats-core.git refs/tags/v1.13.0^{}`), pin it in a single `env:` at workflow level, verify then install.
2. `ci-local.sh`: mirror `artifacts.yml:37-52` under the resolved `BASE_REF`; skip with a note when the base ref is unavailable.
Touch-set: see `paths`. Wait for #451 (macOS matrix) to merge, then rebase.

## Anticipated decisions

- Pin location (workflow `env:` vs a repo file read by both workflows and ci-local) — disposition: agent-decides (reversible; prefer `tools/.bats-pin` read by all three so the pin is single-sourced).

## Decision journal

<!-- Append-only during execution. -->

## Pending decisions

- (none)

## Attempts

- (none)

## Notes

- Stacked after #451; if #451 has not merged when tkt-459..462 ship, this ticket stays `queued` (spc-458 Decision 5).

## References

- Spec: `spc-458` · spc-441 A3 (#451)

## Lineage

- Parent spec: **spc-458** · Parent issue: **#458** · Primary ticket: **tkt-463** · Covers: **A15** · Blocked by: #444 · Merge blocked by: #444 · Worktree bind: `tkt-463-ci-bats-sha-pin-baseline`

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
