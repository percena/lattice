# tkt-340-l3-status-row-guard

> **TL;DR:** L3 Write/Edit hook denies edits that change a ticket binder's status row and names transition-api.py commit.
> **Kind:** feat · **Priority:** P1
> **Path:** spc-337 → tkt-340 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | feat,P1 |
| github | https://github.com/percena/lattice/issues/340 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T02:29:15Z |
| updated | 2026-09-02T02:29:15Z |
| adopted | false |
| summary | L3 Write/Edit hook denies edits that change a ticket binder's status row and names transition-api.py commit. |
| spec | spc-337 — FSM conformance closure (path: ../../specs/spc-337-fsm-conformance-closure.md) |
| covers | A4 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | G1 |
| paths | plugins/lattice/hooks/intercept-shippable-write.sh, plugins/lattice/scripts/tests/intercept-shippable-write*.bats, plugins/lattice/hooks/README.md |
| solo_merge | yes |
| **primary_ticket** | tkt-340 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-340-l3-status-row-guard |
| worktree | sibling `…/lattice.worktrees/tkt-340-l3-status-row-guard/` |
| prs | (none) |

## Acceptance (this slice)

See GitHub issue #340 for the full slice text; Spec ids owned by this slice:

- [ ] **A4** Status-row change via Edit/Write on `.lattice/tickets/*/README.md` denied with the transition command named; other-row edits, new-binder creation, unchanged-status Write and malformed input allowed; bats cover all five.

## Approach

1. In `intercept-shippable-write.sh`, after the existing location/assert logic (only when the write is otherwise allowed): parse `tool_input.file_path`; if it matches `/\.lattice/tickets/[^/]+/README\.md$` → status-row check.
2. Edit: extract the status value from `old_string` and `new_string` with the same regex as `binder_rows.py` (`^\| *status *\| *([^|]+?) *\|`); if both present and differ → deny; if only new_string has a status row and the file's current status differs → deny.
3. Write: extract status from `content`; if the file exists and its on-disk status differs → deny; file absent → allow (creation).
4. Deny message: rule id `L3-status-row`, why (ADR-012 §2), the legal command `python3 <lib>/transition-api.py commit <tkt> <to> <owner> <reason> --binder <path>`.
5. Fail-open: jq/python3 missing or parse error → advisory stderr + exit 0 (consistent with the rest of the hook).
6. Bats in `plugins/lattice/scripts/tests/intercept-shippable-write-status-row.bats`; README hooks table updated.

## Anticipated decisions

- Whether to also guard `wait_reason`/`fix_cycles` rows — disposition: pre-resolved(spc-337 A4): status only in this slice; others journaled as follow-up.
- Regex sharing with binder_rows.py — disposition: agent-decides (python3 one-liner importing binder_rows when available; fallback regex).

## Decision journal

<!-- Append-only during execution. -->

## Pending decisions

(none)

## Attempts

<!-- Fallback ledger (ADR-004 §5). -->

## Notes

## References

- Spec: `spc-337` → `.lattice/specs/spc-337-fsm-conformance-closure.md`
- ADR: `ADR-012` → `docs/adr/012-transitions-stamped-by-the-path.md`
- Review: `rev-20260902-015425Z`

## Lineage

- Parent spec: **spc-337**
- Parent issue (GH sub-issue of Spec primary): **#337**
- Primary ticket: **tkt-340**
- Covers: **A4**
- Blocked by: (none)
- Merge blocked by: (none)
- Parallel group: G1
- Worktree bind: tkt-340-l3-status-row-guard

## Assets

(none)

## Finish

- (none yet)
