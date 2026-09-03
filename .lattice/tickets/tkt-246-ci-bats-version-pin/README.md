# tkt-246 — CI bats 1.10.0 vs local 1.13.0 pin

> **Status:** closed · kind bug · priority P1 · ticket-only (no Spec parent)

## Field table

| Field | Value | Notes |
| --- | --- | --- |
| kind | bug | CI environment / test infra |
| priority | P1 | blocks clean finish-work on every PR |
| labels | bug, P1, github_actions | |
| github | https://github.com/percena/lattice/issues/246 | |
| status | closed | |
| summary | Pin CI bats to bats-core v1.13.0 (matches local homebrew + ci-local) instead of Ubuntu apt's 1.10.0, so the bats-assertion-ergonomics "semantics proof" meta-test passes on CI and finish-work's ci-gate stops seeing a settled real failure on every PR. | |
| spec | (none — ticket-only) | |
| covers | (none — ticket-only) | |
| blocked_by | (none) | standalone CI fix; unblocks the #236–#243 batch |
| parallel_group | (none) | standalone |
| paths | .github/workflows/lattice-scripts.yml | disjoint |
| solo_merge | true | one PR |
| primary_ticket | true | |
| related_tickets | #236–#243 (this fix unblocks their finish-work) | |
| worktree_bind | tkt-246 | |
| created | 2026-08-30T00:00:00Z | |
| updated | 2026-08-30T10:18:40Z | |

## Acceptance (this slice)

- `.github/workflows/lattice-scripts.yml` "Install bats" step installs bats-core v1.13.0 (deterministic — git tag + install.sh, no apt/npm version drift) instead of `apt-get install bats` (1.10.0).
- `bats --version` in CI prints 1.13.0.
- The `bats-assertion-ergonomics.bats` "semantics proof" meta-test passes on CI (it already passes on local 1.13.0).
- `ci-local --fast` green (the workflow file is not exercised by ci-local beyond YAML presence; no shellcheck target).

## Why

CI bats 1.10.0 (apt) mismatches local bats 1.13.0 (homebrew) + `tools/ci-local.sh`. The 1.10.0 `[[ ]]`-masking + recursive test-name handling differs, making the `tools/tests/bats-assertion-ergonomics.bats:39` meta-test fail on every PR (#233, #235, #244, #245 all show `bats fail` on this one test). finish-work's ci-gate then sees a settled real failure and blocks. Pinning CI to 1.13.0 restores the "green here predicts green on GitHub" contract (#239 ci-local-parity theme).

## Finish

- pr-247 merged: 2026-08-30T10:18:03Z — https://github.com/percena/lattice/pull/247 (base merge)
- issue #246 closed: 2026-08-30T10:18:17Z — https://github.com/percena/lattice/issues/246
