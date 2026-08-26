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
| status | queued |
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
| prs | (none) |

## Acceptance (this slice)

- [ ] Binder template: header `**Status:**` copy dropped/derived (field table SoT); canonical filled `prs` format documented
- [ ] validate-lattice-artifacts: warn on header/table status contradiction; optional prs-format check; bats green
- [ ] workflow-fsm.md: fuse-edge clarifying sentence (fused → stay `queued`; `deferred` = human deschedule stamp)
- [ ] Label taxonomy reconciled (docs/github-surface.md + sync-github-labels)
- [ ] ensure-lattice SCRIPT_DIR symlink resolution aligned with lattice-init; preferences.md in managed-paths list
- [ ] New find-spec.sh (spec file by N regardless of slug); bats

## Approach

Six independent micro-changes; land in one PR, each item its own commit or clearly separated. Any item that turns out non-trivial → defer with a note in this binder rather than expanding scope.

## Anticipated decisions

- Header status: drop entirely vs keep-derived — disposition: agent-decides (dropping is simpler; template comment can say "status lives in the table")
- Label canon: rename repo label vs update docs — disposition: must-ask → parked default: update docs to match live labels (least disruptive), flag rename option in PR body

## Decision journal

## Pending decisions

- Label taxonomy direction (docs-follow-labels vs labels-follow-docs) — default if unanswered: docs follow live labels

## Attempts

## Notes

- P3: schedule after the P2 row; safe to batch with them in one night run (paths disjoint from tkt-60…64)

## References

- Review: `rev-20260826-145922Z-18p` Finding 6

## Lineage

- Parent spec: none (ticket-only)
- Primary ticket: **tkt-65** · Covers: Finding 6 · Parallel group: **G1** · Worktree bind: `tkt-65-template-debts`
- Child PRs: (none yet)

## Finish

- (none yet)
