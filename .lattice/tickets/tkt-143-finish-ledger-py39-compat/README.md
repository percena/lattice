# tkt-143-finish-ledger-py39-compat

> **TL;DR:** binder_rows.py `int|str` union type hint fails on Python 3.9 — add `from __future__ import annotations`
> **Kind:** bug · **Priority:** P2
> **Path:** (ticket-only) → tkt-143 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P2 |
| labels | bug, P2 |
| github | https://github.com/percena/lattice/issues/143 |
| status | pr-open |
| adopted | false |
| summary | binder_rows.py int\|str union fails on Python 3.9 — add from __future__ import annotations |
| spec | none — ticket-only |
| covers | (none) |
| blocked_by | (none) |
| parallel_group | (none) |
| paths | skills/_lattice-lib/scripts/lib/binder_rows.py |
| solo_merge | yes |
| **primary_ticket** | tkt-143 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-143-finish-ledger-py39-compat |
| prs | pr-144 — https://github.com/percena/lattice/pull/144 |

## Acceptance (this slice)

- [x] **A1** binder_rows.py has `from __future__ import annotations` after the docstring
- [x] **A2** import succeeds on Python 3.9 (no TypeError)
- [x] **A3** finish-ledger.sh runs without TypeError on Python 3.9
- [x] **A4** bats still passes on Python 3.12 (no regression)

## Approach

Add `from __future__ import annotations` as the first import (after the module docstring, before `import re`). PEP 563 makes annotations lazy strings — `int | str` is never evaluated at runtime. One-line fix.

## References

- File: `skills/_lattice-lib/scripts/lib/binder_rows.py:31,39`
- Discovered: `rev-20260827-102420Z` finish-work cycle (PR #139-#142 merge)

## Lineage

- Parent spec: none · Primary ticket: tkt-143 · Worktree bind: tkt-143-finish-ledger-py39-compat

## Finish

- (none yet)
