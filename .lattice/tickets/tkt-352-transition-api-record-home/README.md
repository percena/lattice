# tkt-352-transition-api-record-home

> **TL;DR:** transition-api.py record resolves ledger/lock from cwd (no binder); add --home → LATTICE_HOME → git toplevel resolution and --help handling.
> **Kind:** bug · **Priority:** P3

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P3 |
| labels | bug,P3 |
| github | https://github.com/percena/lattice/issues/352 |
| status | pr-open |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T03:54:10Z |
| updated | 2026-09-02T04:36:56Z |
| adopted | false |
| summary | transition-api.py record resolves ledger/lock from cwd (no binder); add --home → LATTICE_HOME → git toplevel resolution and --help handling. |
| spec | none |
| paths | skills/_lattice-lib/scripts/transition-api.py, skills/_lattice-lib/scripts/tests/transition-api.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-352 (this issue) |
| worktree_bind | tkt-352-transition-api-record-home |
| prs | (none) |

## Acceptance

See GitHub issue #352 body.

## Approach

1. Add `resolve_default_home()`: `--home` → `LATTICE_HOME` → `git rev-parse --show-toplevel`/.lattice → `.lattice`; use it in `cmd_record`, `_binder_for_ticket`, `cmd_replay`. 2. Handle `--help`/`-h` at top level and per command. 3. Bats: record from a non-toplevel cwd lands under the repo home; --help exits 0.

## Anticipated decisions

(none — S-class; operator will implement)

## Decision journal

## Notes

- Filed as a post-spc-337 follow-up (operator-owned); surfaced by the PR #346 review / local dogfood runs on 2026-09-02.

## Lineage

- Parent issue: #352 (ticket-only, no Spec)
- Primary ticket: tkt-352
- Refs: spc-337, ADR-012 §4

## Finish

- (none yet)
