# tkt-65-template-debts

> **TL;DR:** LOW debts batch — binder header-status dedup, canonical prs format, fsm fuse wording, label taxonomy, ensure-lattice symlink alignment, find-spec helper
> **Kind:** chore · **Priority:** P3
> **Path:** (ticket-only) → tkt-65 → (pr-…)

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P3 |
| labels | chore, P3 |
| github | https://github.com/percena/lattice/issues/65 |
| status | pr-open |
| adopted | false |
| summary | six small template/validator/docs debts from the batch run, landed or explicitly deferred each |
| spec | none — hygiene from dogfood review |
| covers | rev-20260826-145922Z-18p Finding 6 (residual items) |
| blocked_by | (none) |
| parallel_group | G1 (parallel) |
| paths | skills/create-tickets/references/templates/ticket-binder.md, tools/validate-lattice-artifacts.py, tools/tests/lattice-artifacts.bats, docs/workflow-fsm.md, docs/github-surface.md, skills/create-tickets/scripts/sync-github-labels.sh, skills/_lattice-lib/scripts/ensure-lattice.sh, skills/_lattice-lib/scripts/find-spec.sh, skills/_lattice-lib/scripts/tests/ |
| solo_merge | yes |
| **primary_ticket** | tkt-65 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-65-template-debts |
| worktree | sibling …/lattice.worktrees/tkt-65-template-debts/ |
| prs | pr-71 — https://github.com/percena/lattice/pull/71 |

## Acceptance (this slice)

- [x] Binder template: header `**Status:**` copy dropped/derived (field table SoT); canonical filled `prs` format documented
- [x] validate-lattice-artifacts: warn on header/table status contradiction; ~~optional prs-format check~~ (deferred, see Notes); bats green
- [x] workflow-fsm.md: fuse-edge clarifying sentence (fused → stay `queued`; `deferred` = human deschedule stamp)
- [x] Label taxonomy reconciled (docs/github-surface.md + sync-github-labels)
- [ ] ensure-lattice SCRIPT_DIR symlink resolution aligned with lattice-init (done); preferences.md in managed-paths list (deferred — lattice-init.sh out of paths row, see Notes)
- [x] New find-spec.sh (spec file by N regardless of slug); bats

## Approach

Six independent micro-changes; land in one PR, each item its own commit or clearly separated. Any item that turns out non-trivial → defer with a note in this binder rather than expanding scope.

## Anticipated decisions

- Header status: drop entirely vs keep-derived — disposition: agent-decides (dropping is simpler; template comment can say "status lives in the table")
- Label canon: rename repo label vs update docs — disposition: must-ask → parked default: update docs to match live labels (least disruptive), flag rename option in PR body

## Decision journal

- Label taxonomy direction → docs follow live labels; no repo label renames (source: pre-resolved — parked must-ask ratified by default per batch brief; rename option flagged in PR body)
- Header `**Status:**` drop vs keep-derived → drop, terse template comment points at the field table (source: pre-resolved — binder anticipated-decision, agent-decides)
- header_status_mismatch check: legacy-coarse `open` headers exempt → 12 pre-FSM binders carry `**Status:** open` against FSM table values; that is lazy-migration territory (legacy_open_status owns it), not dual-maintenance drift — exempting keeps the real repo at 0 new warnings (source: agent-judgment)
- header check scoped to TL;DR blockquote lines above the binder card → full-text regex would match prose mentions of the literal marker (this very binder's acceptance line would have yielded status "copy") (source: agent-judgment)
- Optional prs-row format validator check → deferred: live prs rows are heterogeneous historical ledger (`pr-11`, `#37 · pr-37 — URL`, `pr-9 (URL, …)`); canonical format now documented in the template — a warning without a migration is pure noise (source: agent-judgment, P3 timebox)

## Pending decisions

- ~~Label taxonomy direction (docs-follow-labels vs labels-follow-docs)~~ — ratified by default 2026-08-26: docs follow live labels

## Attempts

## Notes

- P3: schedule after the P2 row; safe to batch with them in one night run (paths disjoint from tkt-60…64)
- Deferred: optional validator prs-row format check — canonical `pr-N — <URL>` documented in the template instead; existing rows too heterogeneous to warn on without a migration
- Deferred (out of paths row): add `preferences.md` to lattice-init's `assert_managed_paths_safe` list — lattice-init.sh not in this ticket's paths; ensure-lattice already refuses a symlinked preferences.md itself; follow-up flagged in PR body

## References

- Review: `rev-20260826-145922Z-18p` Finding 6

## Lineage

- Parent spec: none (ticket-only)
- Primary ticket: **tkt-65** · Covers: Finding 6 · Parallel group: **G1** · Worktree bind: `tkt-65-template-debts`
- Child PRs: pr-71 — https://github.com/percena/lattice/pull/71

## Finish


- pr-71 merged: 2026-08-26T16:56:50Z — https://github.com/percena/lattice/pull/71 (base merge)
- issue #65 closed: 2026-08-26T16:56:55Z — https://github.com/percena/lattice/issues/65
