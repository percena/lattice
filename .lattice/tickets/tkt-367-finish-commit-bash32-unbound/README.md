# tkt-367-finish-commit-bash32-unbound

> **TL;DR:** finish-commit.sh (tkt-360 A2) hits `unbound variable` on bash 3.2 when `GIT_DIR_ARGS` is empty under `set -u` — same BSD portability class as tkt-356; fix with the `+` guard.
> **Kind:** bug · **Priority:** P2
> **Path:** (none — follow-up to tkt-360) → tkt-367 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P2 |
| labels | bug, P2 |
| github | https://github.com/percena/lattice/issues/367 |
| status | pr-open |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T06:37:24Z |
| updated | 2026-09-02T06:40:25Z |
| adopted | false |
| summary | finish-commit.sh bash-3.2 unbound-variable on empty GIT_DIR_ARGS under set -u (tkt-360 A2 dogfood) |
| spec | (none — follow-up to tkt-360) |
| covers | A1, A2, A3 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | (serial) |
| paths | skills/_lattice-lib/scripts/finish-commit.sh, skills/_lattice-lib/scripts/tests/finish-commit.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-367 (this issue) |
| **related_tickets** | tkt-360 (the A2 deliverable this fixes) |
| **worktree_bind** | tkt-367-finish-commit-bash32-unbound |
| worktree | sibling `…/lattice.worktrees/tkt-367-finish-commit-bash32-unbound/` |
| prs | pr-368 — https://github.com/percena/lattice/pull/368 |

## Acceptance (this slice)

- [x] **A1** `finish-commit.sh --message "..."` (no `--repo`) runs without `unbound variable` on bash 3.2.
- [x] **A2** bats test covers the no-`--repo` invocation (the dogfood scenario that caught the bug).
- [x] **A3** no other `set -u` + empty-array pitfalls remain in `finish-commit.sh` (only `GIT_DIR_ARGS` is an array; audited).

## Approach

1. Read `finish-commit.sh:48-50` — `GIT_DIR_ARGS=(); [[ -n "$REPO_ROOT" ]] && GIT_DIR_ARGS=(-C "$REPO_ROOT"); REPO_ROOT=$(git "${GIT_DIR_ARGS[@]}" rev-parse ...)`.
2. Replace `${GIT_DIR_ARGS[@]}` with `${GIT_DIR_ARGS[@]+"${GIT_DIR_ARGS[@]}"}` (the `+` expansion emits nothing when unset/empty, satisfying `set -u`).
3. Add a bats case asserting `finish-commit.sh --message "..."` (no `--repo`) succeeds against a tmp repo whose cwd resolves the root.
4. Grep `finish-commit.sh` for other `${[A-Z_]+[@]}` and apply the same guard where the array may be empty.

## Anticipated decisions

- **Guard form** — disposition: pre-resolved (`${ARR[@]+"${ARR[@]}"}`; the established codebase pattern at `finish-ledger.sh:264`).
- **Test approach** — disposition: agent-decides (run under bash 3.2 if `/bin/bash` is 3.2, else assert the no-`--repo` path explicitly under the bats bash — the latter is CI-portable).

## Decision journal

<!-- Append-only during execution. -->
- 2026-09-02T06:40:25Z — direct jump: queued → pr-open (in-progress stamp skipped; PR #368) [WARN — signal logged, not silently lost]

## Pending decisions

<!-- (none so far) -->

## Attempts

<!-- Fallback ledger. -->

## Notes

- Dogfood provenance: running `finish-commit.sh` to stamp tkt-360's own Finish ledger failed with `GIT_DIR_ARGS[@]: unbound variable`; fell back to plain `git commit` to land the ledger. The A1 guard in finish-ledger.sh works on bash 3.2 — only finish-commit.sh is affected.
- Same bug class as tkt-356 (PR #359 fixed `${GH_ARGS[@]}` → `${GH_ARGS[@]+"${GH_ARGS[@]}"}` in finish-ledger.sh).
- Related memory: [[finish-ledger-cancel-entry-bug]] (broader ledger bug class).

## References

- GitHub issue body is SoT for long prose: https://github.com/percena/lattice/issues/367
- Related: #360 (the A2 deliverable), #356 (same bug class in finish-ledger.sh)
- Worktree policy: one tree ↔ one PR; tkt open binds

## Lineage

- Parent spec: **(none)**
- Parent issue: **none** (ticket-only)
- Primary ticket: **tkt-367**
- Related / sub-tickets: tkt-360 (the A2 deliverable this fixes)
- Covers: **A1, A2, A3**
- Blocked by: (none)
- Merge blocked by: (none)
- Parallel group: (serial)
- Worktree bind: `tkt-367-finish-commit-bash32-unbound`
- Child PRs: (none yet)

## Assets

(none)

## Finish

- (none yet)
