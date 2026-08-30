# tkt-232-dev-ci-red

<!-- Binder is a thin recovery card (not a second issue tracker). -->

> **TL;DR:** Harden the lone remaining dev bats flake — verify-mutation `--branch` network-failure (#406). The rest of #232's scope (spc-226 hygiene, #329, #13) was cleared by #217 while this ticket was in flight.
> **Kind:** chore · **Status:** open · **Priority:** P2
> **Path:** spc-226 (hygiene link) → tkt-232 → pr-233

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P2 |
| labels | bug, chore, P2 |
| github | https://github.com/percena/lattice/issues/232 |
| status | closed |
| adopted | true |
| summary | Harden verify-mutation #406 network flake (ls-remote failure → exit 1 with accurate diagnostic, not exit 128 crash) |
| spec | spc-226 — run-e2e platform dispatcher + confirm-first preflight (hygiene link; path: ../../specs/spc-226-run-e2e-platform-dispatcher.md) |
| covers | verify-mutation.bats #406 (branch nonexistent remote — network flake) |
| blocked_by | (none) |
| parallel_group | (serial) |
| paths | skills/_lattice-lib/scripts/verify-mutation.sh, .lattice/specs/spc-226-run-e2e-platform-dispatcher.md |
| solo_merge | yes |
| **primary_ticket** | tkt-232 |
| **related_tickets** | tkt-227 (spc-226 delivery, pr-229) |
| **worktree_bind** | tkt-232-dev-ci-red |
| worktree | sibling `…/lattice.worktrees/tkt-232-dev-ci-red/` |
| prs | pr-233 — https://github.com/percena/lattice/pull/233 |

## Acceptance (this slice)

- [x] **A1** `verify-mutation.sh --branch <name>`: a simply-absent ref (ls-remote succeeds, empty output) → exit 1 "does not exist on origin"; a real ls-remote failure (network/auth/unreachable → exit 128) → exit 1 "cannot verify ... ls-remote errored". Both fail-closed; never a raw exit-128 crash under `set -e`/pipefail.
- [x] **A2** `bats skills/_lattice-lib/scripts/tests/verify-mutation.bats` all green (incl. #16 "branch: nonexistent remote branch fails"), both in isolation and the full _lattice-lib suite.

## Notes

- **ADOPT_CHECK:** issue #232 body is SoT for long prose; binder is the recovery card. Do not rewrite the issue body.
- **Scope shift mid-flight:** #232 originally bundled spc-226 Spec hygiene + 3 bats failures (#231: #329, #13, assertion-ergonomics). While this ticket was in flight, **#217 (`fix(tkt-216): post-review batch`)** merged to dev and cleared the bulk of that scope:
  - spc-226 hygiene (A1–A5 checked, TL;DR `done`).
  - #329 — fixed test-side: `reconcile-state.bats` NOGH_BIN now symlinks all PATH executables except `gh`.
  - #13 — fixed test-side: `close-fixed-issues.bats` recreates the relative dir layout so `ensure-python3.sh` resolves.
  This PR (#233) was rebased onto post-#217 dev; the redundant SUT-side fixes for #329/#13/spc-226-hygiene were dropped (dev's test-side fixes are canonical). Only the #406 fix remains — #217 did not touch `verify-mutation.sh`.
- **#406** was flaky (passes in isolation; `git ls-remote origin` is a real network call that intermittently fails in the full suite). The fix makes it deterministic: any ls-remote failure routes to a fail-closed exit 1 with an accurate diagnostic, instead of `set -e`/pipefail killing the script with exit 128.
- **`bats-assertion-ergonomics`** (the third #231 item) passes locally (bats 1.13.0); #231 noted it fails only in CI. Not addressed here.
- **#411** (`resolver ignores a caller-controlled --from`) observed failing locally is a macOS `/tmp → /private/tmp` symlink-resolution artifact (resolver uses `pwd -P`, the test's REPO_ROOT uses `pwd`); passes in the real repo. Not a dev CI failure.

## References

- GitHub issue body is SoT: https://github.com/percena/lattice/issues/232
- #231 — the pre-existing bats failures: https://github.com/percena/lattice/issues/231
- #217 — cleared #329/#13/spc-226-hygiene on dev (commit 84e410c)
- Spec hygiene link: `spc-226` (path above)
- Delivery proof: pr-229 (spc-226 workstream, merged)

## Lineage

- Parent spec (hygiene link): **spc-226**
- Primary ticket: **tkt-232**
- Related tickets: **tkt-227** (spc-226 delivery, pr-229 merged)
- Covers: verify-mutation.bats #406
- Blocked by: (none)
- Parallel group: (serial)
- Worktree bind: tkt-232-dev-ci-red
- Child PRs: pr-233 — GitHub `Fixes #232` / `Closes #231` is SoT

## Assets

Local files in `./assets/`.

## Finish



- pr-233 merged: 2026-08-30T03:42:13Z — https://github.com/percena/lattice/pull/233 (base merge)
- issue #232 closed: 2026-08-30T03:42:36Z — https://github.com/percena/lattice/issues/232
