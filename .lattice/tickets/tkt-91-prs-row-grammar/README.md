# tkt-91-prs-row-grammar

> **TL;DR:** One prs-row grammar owned in one shared helper — writers emit the tkt-74 canon (comma joiner, `pr-N — URL`), the reader's placeholder predicate matches every `(none…)` variant, the validator's regex is test-asserted equal
> **Kind:** fix · **Priority:** P1
> **Path:** (ticket-only) → tkt-91 → (pr-…)

| Field | Value |
| --- | --- |
| kind | fix |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/91 |
| status | closed |
| adopted | false |
| summary | binder_rows shared definition + writer canon emission + build-review-context predicate fix |
| spec | none — audit rev-20260827-033352Z F4 |
| covers | audit F4 (+ F8 build-review-context --from-heads ADR scan, same file) |
| blocked_by | tkt-90 (#90 — same files: finish-ledger.sh, validator) |
| parallel_group | (serial — wave 2, stacked on tkt-90) |
| paths | skills/_lattice-lib/scripts/stamp-pr-open.sh, skills/_lattice-lib/scripts/finish-ledger.sh, skills/_lattice-lib/scripts/build-review-context.sh, skills/_lattice-lib/scripts/lib/** (new), tools/validate-lattice-artifacts.py, skills/_lattice-lib/scripts/tests/**, tools/tests/** |
| solo_merge | yes (after tkt-90) |
| **primary_ticket** | tkt-91 (this issue) |
| **related_tickets** | tkt-90 (base), tkt-74 (canon author), tkt-80 (warning cleanup this protects) |
| **worktree_bind** | tkt-91-prs-row-grammar |
| worktree | sibling …/lattice.worktrees/tkt-91-prs-row-grammar/ |
| prs | pr-103 — https://github.com/percena/lattice/pull/103 |

## Acceptance (this slice)

- [x] **A1** single shared definition (`_lattice-lib/scripts/lib/binder_rows.py`) owns placeholder predicate + canonical entry + joiner; both writers emit comma-joined canon on the append path; no bare `pr-N` emission
- [x] **A2** `build-review-context.sh` placeholder check accepts any `(none…)` variant
- [x] **A3** validator canon asserted equal to the shared definition (test-enforced)
- [x] **A4** bats: multi-PR append yields zero `prs_row_format` warnings; existing suites green; full `ci-local` green

## Approach

New `lib/binder_rows.py` exporting the placeholder regex, entry format string, joiner, and canon regex; both shell writers' embedded python imports it via a `PYTHONPATH`/`sys.path` line resolved from the script dir (mirrors `closing_directives.py` precedent). `build-review-context.sh:409` swaps the literal comparison for the same predicate (grep -E against the shared pattern, or a tiny python call). Validator keeps its own constants but a bats/python test asserts byte-equality with the lib (validator must stay standalone-runnable in consumer repos). Bonus in-paths fix: `--from-heads` ADR scan uses the head snapshots (`scan_files`) instead of local binders.

## Anticipated decisions

- Lib consumption form (import vs regex-equality test) — pre-resolved: validator stays dependency-free, equality is test-asserted (consumer repos run the validator without _lattice-lib on sys.path)
- No-URL fallback — disposition: agent-decides (resolve URL via gh at stamp time; if unavailable, leave the row untouched and print a journaled warning rather than emitting non-canon; journal)

## Decision journal

- Lib consumption: writers import `lib/binder_rows.py` via a `BINDER_ROWS_LIB` env + `sys.path` insert (resolved from `BASH_SOURCE` dirname — survives the plugin symlink because the whole scripts/ dir is one link); the validator keeps standalone regex copies with a cross-ref comment, and a bats test asserts pattern byte-equality (consumer repos vendor the validator alone) — chain source 1 (binder Anticipated decisions, pre-resolved); reversible.
- No-URL fallback: with no resolvable PR URL both writers now leave the prs row untouched and print a WARNING (previously finish-ledger emitted off-canon bare `pr-N`) — real flows always resolve a URL via gh or the `--repo` slug; a silent off-canon write is worse than a loud skip — chain source 1 (agent-decides); reversible.
- Bonus in-paths fix (binder covers row): `--from-heads` now resolves each ticket's source file once up front (SRC_FILES), so the ADR scan reads head snapshots instead of always-local binders (round-4 digest Finding 2) — same file, journaled here.

## Pending decisions

## Attempts

## Notes

- The append-path bug is self-reinforcing: tkt-80 zeroed the warnings, the next multi-PR ticket re-creates them

## References

- rev-20260827-033352Z F4 · tkt-74 decision journal (`·` rejected) · `closing_directives.py` (shared-lib precedent)

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: **tkt-91** · Parallel group: **(serial, wave 2)** · Worktree bind: `tkt-91-prs-row-grammar`

## Finish

- pr-103 merged: 2026-08-27T05:30:14Z — https://github.com/percena/lattice/pull/103 (base merge)
- issue #91 closed: 2026-08-27T05:30:18Z — https://github.com/percena/lattice/issues/91
