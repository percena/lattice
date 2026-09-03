# tkt-353-env-dependent-bats

> **TL;DR:** Four bats cases depend on host environment (root ignores chmod-000; claude on PATH) and are red on the dogfood host, green in CI.
> **Kind:** bug · **Priority:** P3

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P3 |
| labels | bug,P3 |
| github | https://github.com/percena/lattice/issues/353 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T03:54:10Z |
| updated | 2026-09-02T04:54:14Z |
| adopted | false |
| summary | Four bats cases depend on host environment (root ignores chmod-000; claude on PATH) and are red on the dogfood host, green in CI. |
| spec | none |
| paths | skills/_lattice-lib/scripts/tests/transition-api.bats, skills/_lattice-lib/scripts/tests/finish-ledger.bats, skills/batch-work/scripts/tests/coordinator.bats, skills/batch-work/scripts/tests/spawn-ticket-process.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-353 (this issue) |
| worktree_bind | tkt-353-env-dependent-bats |
| prs | pr-355 — https://github.com/percena/lattice/pull/355 |

## Acceptance

See GitHub issue #353 body.

## Approach

1. chmod-000 fault tests: inject the write failure by replacing the ledger dir with a regular file (open() fails for any uid) or by pointing `LATTICE_HOME` at a path whose parent is a file. 2. claude-on-PATH tests: build a controlled `PATH=$STUB_BIN:/usr/bin:/bin` with and without a `claude` stub instead of asserting the host PATH. 3. Verify all four suites green as root with claude installed, and in CI.

## Anticipated decisions

(none — S-class; operator will implement)

## Decision journal

## Notes

- Filed as a post-spc-337 follow-up (operator-owned); surfaced by the PR #346 review / local dogfood runs on 2026-09-02.

## Lineage

- Parent issue: #353 (ticket-only, no Spec)
- Primary ticket: tkt-353
- Refs: spc-337, ADR-012 §4

## Finish


- pr-355 merged: 2026-09-02T04:53:10Z — https://github.com/percena/lattice/pull/355 (base merge)
- issue #353 closed: 2026-09-02T04:53:49Z (reason: completed) — https://github.com/percena/lattice/issues/353
