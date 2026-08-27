# tkt-121-validator-hardening

<!-- Binder is a thin recovery card (not a second issue tracker). -->

> **TL;DR:** three latent defects in validate-lattice-artifacts.py — unscoped status fallback, narrow finish-placeholder exemption, skipped acceptance-heading A-ids
> **Kind:** bug · **Priority:** P2 <!-- status lives in the field table -->
> **Path:** (no Spec) → tkt-121 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P2 |
| labels | bug, P2 |
| github | https://github.com/percena/lattice/issues/121 |
| status | pr-open | working: queued \| in-progress \| parked \| stuck \| pr-open \| rework \| deferred · terminal: closed (finish-ledger stamps it) · legacy: open (coarse — validator warns) |
| adopted | false |
| summary | validate-lattice-artifacts.py: 3 latent defects (status fallback scope, finish-placeholder family, acceptance-heading A-ids) |
| spec | (none — standalone process-hardening bug) |
| covers | (none) |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | tools/validate-lattice-artifacts.py, tools/tests/lattice-artifacts.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-121 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-121-validator-hardening` |
| worktree | sibling `…/lattice.worktrees/tkt-121-validator-hardening/` (default for shippable) |
| prs | pr-126 — https://github.com/percena/lattice/pull/126 |

## Acceptance (this slice)

- [ ] **A1** `ticket_status()` fallback no longer searches the whole text — it reuses the scoped `tldr_header_status()` (blockquote lines before the first table) when the binder card has no `| status |` row.
- [ ] **A2** `has_finish_ledger()` exempts the whole `(none…)` placeholder family (reuse `PRS_PLACEHOLDER_RE.fullmatch(content)`), not just the literal `(none yet)` — so a `status: closed` binder with `- (none — rides tkt-5 PR)` correctly fires `closed_without_finish`.
- [ ] **A3** `spec_acceptance_ids()` collects `**A-N**` ids written inline on the Acceptance heading line (e.g. `## Acceptance — **A1**, **A2**`) before continuing.
- [ ] **A4** Regression fixtures in `lattice-artifacts.bats` cover: no-table-status + body-prose-`**Status:**`; `(none …)` finish placeholder; inline-heading A-ids.
- [ ] **A5** `validate-lattice-artifacts.py` + existing bats stay green; no new false positives on the live `.lattice/` tree.

## Reproduction Steps (bug-class)

1. **A1:** a binder whose first table omits `| status |`, with body prose `- [ ] The binder **Status:** field must be rework` → `ticket_status()` returns `"field"` → false `invalid_ticket_status`.
2. **A2:** a binder with `status: closed` and `## Finish` body `- (none — rides tkt-5 PR)` → `has_finish_ledger()` returns True → `closed_without_finish` does not fire.
3. **A3:** a Spec with `## Acceptance — **A1**, **A2**` heading + a ticket `covers: A1` → `spec_acceptance_ids()` skips the heading ids → false `covers_not_on_spec`.

## Approach

- A1: replace line 128 `STATUS_TLDR_RE.search(text)` with `hs = tldr_header_status(text); if hs is not None: return hs`.
- A2: line 156 — `if content and PRS_PLACEHOLDER_RE.fullmatch(content) is None: return True` (import `PRS_PLACEHOLDER_RE` already in scope).
- A3: lines 188–191 — collect A-ids from the heading line before `continue` (move `ids.update(...)` before the `continue`, or drop `continue` and fall through).
- Tests: add 3 fixture binders under `tools/tests/fixtures/lattice-artifacts/` mirroring the existing status-fsm/prs-row fixture pattern.

## Anticipated decisions

- Test-fixture placement — disposition: pre-resolved (existing pattern `tools/tests/fixtures/lattice-artifacts/<case>/tickets/tkt-N/README.md`).
- Whether A3 fix changes the section-exit semantics — disposition: agent-decides (verify the `in_section`/`level` logic still closes correctly when the heading carries ids; reversible + local).

## Decision journal

<!-- append-only -->

## Pending decisions

<!-- (none) -->

## Attempts

<!-- (none) -->

## Notes

- Self-check note: an initially-scoped FSM-5 item (merged Finish ledger + working status = error) was **dropped** — `finish_without_terminal_status` at line 391 already enforces it. Avoid re-filing.
- Shares `tools/validate-lattice-artifacts.py` with tkt-123 (stacked after this).

## References

- GitHub issue body is SoT for long prose: https://github.com/percena/lattice/issues/121
- No Spec (standalone process-hardening bug).
- Worktree policy: one tree ↔ one PR; tkt open bind.

## Lineage

- Parent spec: (none)
- Parent issue: (none — ticket-only)
- Primary ticket: **tkt-121**
- Related / sub-tickets: tkt-123 (blocked_by this)
- Covers: (none)
- Blocked by: (none)
- Parallel group: G1
- Worktree bind: `tkt-121-validator-hardening`

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
