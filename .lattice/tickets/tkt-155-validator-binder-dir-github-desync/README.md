# tkt-155-validator-binder-dir-github-desync

<!-- Binder is a thin recovery card (not a second issue tracker).
     required: kind, priority, github, status, acceptance, primary_ticket / worktree_bind when shipping
     recommended: covers, spec, summary/TL;DR, Path
     optional (parallel / C): blocked_by, parallel_group, paths, solo_merge, related_tickets -->

> **TL;DR:** Validator does not check binder-dir-N vs github-field-N — phantom binders accumulate when operators skip gh issue create and guess numbers
> **Kind:** bug · **Priority:** P1
> **Path:** (ticket-only) → tkt-155 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/155 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| adopted | false |
| summary | validate-lattice-artifacts.py never parses github field — phantom binder dirs with guessed N go undetected |
| spec | (none — ticket-only) |
| covers | A1, A2, A3, A4, A5 |
| blocked_by | (none) |
| parallel_group | (serial) |
| paths | tools/validate-lattice-artifacts.py, skills/create-tickets/references/templates/ticket-binder.md, skills/create-tickets/references/flow.md |
| solo_merge | yes |
| **primary_ticket** | tkt-155 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-155-validator-binder-dir-github-desync` |
| worktree | sibling `…/lattice.worktrees/tkt-155-validator-binder-dir-github-desync/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A1** `validate-lattice-artifacts.py` parses the `github` field row from every ticket binder and extracts the issue number (or detects a pending/placeholder value).
- [ ] **A2** If the binder `github` field contains a real issue URL, the validator checks that the issue number in the URL matches the N in the directory name `tkt-N-<slug>`. Mismatch → error `binder_dir_github_mismatch`.
- [ ] **A3** If the `github` field is a pending/placeholder value (e.g., `(to be created)`, `pending`, empty), the validator emits a warning `binder_github_pending` (not an error — deferred creation is allowed, but should be visible).
- [ ] **A4** The validator detects the core phantom-binder smell: numeric `tkt-N` dir + pending/placeholder `github` field = likely phantom (warn or error depending on policy).
- [ ] **A5** Full `bash tools/ci-local.sh` passes with the new checks.

## Approach

Add a `GITHUB_TABLE_RE` regex to `validate-lattice-artifacts.py` alongside the existing `STATUS_TABLE_RE`, `PRS_TABLE_RE`, etc. For each binder under `.lattice/tickets/tkt-N-*/`:
1. Parse the `github` field value.
2. If it's a real URL → extract the trailing issue number → compare to N from the dir name.
3. If it's a placeholder/empty → emit `binder_github_pending` warning.
4. If dir N is numeric (not `pending`) AND github field is placeholder → emit `phantom_binder_smell` warning (the core desync signal).

Also update `ticket-binder.md` template to document accepted `github` values and strengthen `flow.md` guidance on `tkt-pending` usage.

## Anticipated decisions

- Should `phantom_binder_smell` be an error (blocks CI) or warning (advisory)? — disposition: agent-decides (warning first, can harden later)
- Should the validator call `gh issue view` to verify the issue exists? — disposition: pre-resolved (no — validator is offline-first; online check belongs to #152 reconcile-state.sh)

## Decision journal

<!-- Append-only during execution. -->

## Pending decisions

<!-- (none yet) -->

## Attempts

<!-- (none yet) -->

## Notes

Real-world case: StockVise project accumulated 19 phantom binders (tkt-254..272) because operators created binder dirs with predicted numbers instead of using `tkt-pending-<slug>`. When the next 4 GitHub issues were actually created, they were assigned #263–266, not the predicted #273–276 — requiring a full rename + rebind.

The `ensure-workspace.sh` runtime gate (lines 122–130) catches non-numeric/zero ids at bind time, but does not validate existing binder directories on disk. The validator is the right place for a static check.

## References

- GitHub issue body is SoT for long prose: https://github.com/percena/lattice/issues/155
- `tools/validate-lattice-artifacts.py` lines 49–68 (field parsers), 312–323 (ticket id extraction)
- `skills/create-tickets/references/flow.md` lines 141, 174, 180, 182
- `skills/_lattice-lib/scripts/ensure-workspace.sh` lines 122–130 (runtime bind gate)
- `skills/_lattice-lib/scripts/lib/binder_rows.py` lines 18–30 (placeholder grammar — `prs` only)
- Related (NOT duplicate): #152 (state reconciliation — broader, explicitly excludes validator replacement)

## Lineage

- Parent spec: **(none — ticket-only)**
- Parent issue: **none** (ticket-only)
- Primary ticket: **tkt-155**
- Related / sub-tickets: (none)
- Covers: **A1, A2, A3, A4, A5**
- Blocked by: (none)
- Parallel group: (serial)
- Worktree bind: `tkt-155-validator-binder-dir-github-desync`
- Child PRs: (none yet)

## Assets

(none)

## Finish

- (none yet)
