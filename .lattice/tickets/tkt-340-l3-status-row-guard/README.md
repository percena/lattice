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
| status | closed |
| fix_cycles | 1 |
| wait_reason | (none) |
| created | 2026-09-02T02:29:15Z |
| updated | 2026-09-02T03:03:38Z |
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
| prs | pr-344 — https://github.com/percena/lattice/pull/344 |

## Acceptance (this slice)

See GitHub issue #340 for the full slice text; Spec ids owned by this slice:

- [x] **A4** Status-row change via Edit/Write on `.lattice/tickets/*/README.md` denied with the transition command named; other-row edits, new-binder creation, unchanged-status Write and malformed input allowed; bats cover all five.

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

- 2026-09-02 — **Regex host: bash `sed -E`, not a python3 import.** `binder_rows.py` carries no status regex (only `prs`/`updated`); the row grammar of record is `transition-api.py` `_FIELD_RE_TMPL` (`^\| status \| (.+?) \|`). The hook already depends on `jq`+`git` only, so the cell is extracted with `sed -n -E 's/^\| *status *\| *([^|]*[^| ]) *\|.*$/\1/p'` (same family, tolerant of cell padding; empty cell = no row) and python3 is not a new hook dependency. Source: chain #1 (binder "Anticipated decisions": agent-decides) + #5 codebase convention (hook is bash+jq). Reversible, ticket-local.
- 2026-09-02 — **Removed status row counts as a change.** Edit whose `old_string` has a status cell and `new_string` has none (or Write whose content drops the row an on-disk binder has) is denied, else a two-step delete-then-insert bypasses the guard. Source: chain #3 — ADR-012 §2 ("denies any edit that changes a ticket binder's status value"). Reversible, ticket-local (one `[[ ... ]]` in the hook + one bats).
- 2026-09-02 — **Unparseable hook JSON now exits 0 (advisory), not jq's rc 4.** Pre-existing: `tool_name=$(… | jq …)` under `set -e` aborted the hook with rc 4 on truncated input, contradicting its own header ("Fail OPEN on … parse failure"). Fixed in-paths with an `if ! tool_name=$(…)` guard + one stderr line. Source: chain #1 (Approach step 5: "parse error → advisory stderr + exit 0"). Reversible, ticket-local.
- 2026-09-02 — **`plugins/lattice/hooks/README.md` created (did not exist).** The declared `paths` row names it; the only existing hooks table is in `plugins/lattice/README.md` (out-of-paths, and already missing the `intercept-shippable-write`/`intercept-git-branch-create` rows — NOTICED below). New file: one row per hook file, two rows for `intercept-shippable-write.sh` (location gate + `L3-status-row` with the transition escape). Source: chain #1 (binder `paths`) + fallback-policy scope-escape rule (do not widen into `plugins/lattice/README.md`). Reversible, ticket-local.
- 2026-09-02 — **Fix cycle 1: partial-line Edits are simulated on disk.** Fast path (both sides carry a full row) is kept for the no-disk-read case; otherwise `result="${disk/"$old"/"$new"}"` (`//` with `replace_all`) and the first status cells of `disk` vs `result` decide; `_status_row_count` adds the duplicate-row denial (review LOW, implemented — one `grep -c`). Source: review of pr-344 (HIGH finding) + chain #3 ADR-012 §2 ("any edit that changes … the status value"). Reversible, ticket-local.
- 2026-09-02 — **Not guarded in this slice (follow-up):** `wait_reason`/`fix_cycles` rows (pre-resolved by spc-337 A4: status only); an Edit that inserts a status row into a legacy binder that has none (nothing to compare → allow); Spec/Review front matter (spc-337 non-goal).
- 2026-09-02T02:54:11Z — fix cycle 1: `pr-open` → rework (fix_cycles 1; cap ≤2; ADR-004 §5) — brief: review Hold (PR #344): HIGH — partial-line Edit bypass: an Edit whose old_string/new_string lack a full '| status | X |' row (e.g. 'status | queued' → 'status | closed') passes the guard and flips status (hook :171-181 returns 0 without consulting disk). Fix: when a side lacks a full row, simulate the edit on the on-disk file (replace first occurrence) and compare the resulting first status cell with the on-disk cell — same as the Write branch; add bats for the partial-line case. LOW (optional): deny when the resulting text carries >1 status row.

## Pending decisions

(none)

## Attempts

<!-- Fallback ledger (ADR-004 §5). -->

- 2026-09-02 — **Fix cycle 1 (review of pr-344, HIGH).** *Believed cause:* the Edit branch only compared complete `| status | X |` lines from `old_string`/`new_string`; a minimal-context Edit (`status | queued` → `status | closed`, or `queued |\n| prs` → `closed |\n| prs`) carried no full row on either side, so the guard returned 0 without consulting the file — and minimal `old_string`s are the Edit tool's common case, not an adversarial one. *What differs:* when either side lacks a complete row the hook now simulates the edit on the on-disk text (first occurrence, or every occurrence when `replace_all` is true) and compares the RESULT's first status cell with the on-disk cell (same semantics as the Write branch); a result with more status rows than the file (duplicate-row insert) is also denied. Fail-open kept for unreadable/missing file, empty `old_string`, `old_string` absent on disk, malformed input. Bats: +9 cases (two partial-line deny shapes, replace_all deny, first-occurrence allow, same-region allow, duplicate-row deny for Edit and Write, two fail-open cases).

## Notes

- NOTICED: plugins/lattice/README.md — § Hooks table lists six hooks but omits `intercept-shippable-write` (L3) and `intercept-git-branch-create` (L1); the new `plugins/lattice/hooks/README.md` is the complete per-hook reference until that table is synced (out-of-paths, 2026-09-02)
- NOTICED: skills/start-work/references/policy.md — L3 row (line ~85) describes only the location gate; it does not mention the `L3-status-row` rule / transition escape landed by tkt-340 (out-of-paths, 2026-09-02)
- NOTICED: skills/_lattice-lib/scripts/transition-api.py — `commit --help` / `--help` is not handled (`unknown command: --help`; `commit --help` raises an unpacking ValueError traceback instead of usage) (out-of-paths, 2026-09-02)

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


- pr-344 merged: 2026-09-02T03:03:22Z — https://github.com/percena/lattice/pull/344 (base merge)
- issue #340 closed: 2026-09-02T03:03:30Z (reason: completed) — https://github.com/percena/lattice/issues/340
