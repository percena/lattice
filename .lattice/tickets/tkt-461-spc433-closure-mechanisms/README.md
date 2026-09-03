# tkt-461-spc433-closure-mechanisms

> **TL;DR:** spc-433 closure: mechanisms for A1/A2/A6, one budget semantics, FSM docs carry budget-exhausted.
> **Kind:** feat · **Priority:** P2
> **Path:** spc-458 → tkt-461 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | feat, P2 |
| github | https://github.com/percena/lattice/issues/461 |
| status | in-progress |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-03T16:51:19Z |
| updated | 2026-09-03T17:20:37Z |
| adopted | false |
| summary | Give spc-433 the validator check, gitignore generator, autonomy filter script and one consistent budget semantics it promised |
| spec | spc-458 — Review follow-up (path: ../../specs/spc-458-review-followup.md) |
| covers | A8, A9, A10, A11 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | (serial) |
| paths | tools/validate-lattice-artifacts.py, tools/tests/lattice-artifacts.bats, tools/tests/fixtures/**, skills/_lattice-lib/scripts/lattice-init.sh, skills/_lattice-lib/scripts/tests/lattice-init.bats, skills/create-tickets/references/templates/ticket-binder.md, skills/start-work/SKILL.md, skills/start-work/references/full-flow.md, skills/_lattice-lib/references/{fallback-policy,autonomy-rubric,workflow-fsm-reference}.md, docs/workflow-fsm.md, skills/batch-work/scripts/autonomy-filter.py, skills/batch-work/scripts/tests/**, skills/batch-work/references/flow.md, .lattice/specs/spc-433-vibe-coding-flow-optimization.md |
| solo_merge | yes |
| autonomy | 2 |
| **primary_ticket** | tkt-461 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-461-spc433-closure-mechanisms` |
| worktree | sibling `…/lattice.worktrees/tkt-461-spc433-closure-mechanisms/` |
| prs | (none) |

## Acceptance (this slice)

- [x] **A8** validator: `autonomy` present and not an integer 0–4 → error `autonomy_out_of_range`; absent on a `mode: C` Spec-bound ticket → warning `autonomy_missing` (baselined for existing binders); pass/fail fixtures; ticket-binder template claim now true.
- [x] **A9** `lattice_dotlattice_gitignore()` emits `snapshots/`; `lattice-init.bats` asserts a fresh init ignores `.lattice/snapshots/x.md`.
- [x] **A10** `skills/batch-work/scripts/autonomy-filter.py --min-autonomy N --home <lattice-home> <tkt-ids…>` prints JSON `{selected:[], skipped:[{id, autonomy, reason:"autonomy-below-threshold"}]}`; missing row → 2; `--min-autonomy 0` selects all; bats coverage; `flow.md` RESOLVE TICKETS step 4 names it as the scripted step.
- [x] **A11** start-work `--budget` (per-ticket → `stuck`/`unblock`) and batch-work `--budget` (per-batch → `deferred`/`budget-exhausted`) are each stated once, cross-referenced, without contradiction; `budget-exhausted` added to `docs/workflow-fsm.md` (M2 rows + Trip-time stamping) and `workflow-fsm-reference.md` (+ `deferred` in the side-state guard list); the Chinese prompt block in `start-work/SKILL.md` is English; `full-flow.md` §7 carries the three spc-433 bullets; spc-433 Risks section gets a dated resolution note.

## Approach

1. Validator: locate the ticket field parser (`_parse_field_rows`-style) and mode detection (spec `mode:` via the `spec` row → spec front matter); add two finding codes; extend `tools/tests/fixtures/` with `autonomy-{pass,fail}` trees; baseline `autonomy_missing` for current binders via the ratchet file if the run turns red.
2. `lattice-init.sh`: add `snapshots/` (with the spc-433 comment) to the heredoc; bats: init in a tmp repo, `git check-ignore .lattice/snapshots/x.md`.
3. `autonomy-filter.py`: stdlib; regex `^\|\s*autonomy\s*\|\s*(\S+)\s*\|`; resolve `tkt-N` → `tickets/tkt-N-*/README.md`; JSON out; exit 0 always (advisory sensor) except usage 2.
4. Prose: rewrite the start-work `--budget` bullet to cite the watchdog edge; rewrite fallback-policy budget section to cross-reference; autonomy-rubric batch section unchanged; workflow-fsm.md rows 126/127/207 + mermaid line 49; reference doc lines 21 and 48-51.
5. spc-433: append `**Resolution (2026-09-03, spc-458/tkt-461):** …` under Risks — no acceptance rewrite (supersede law).

## Anticipated decisions

- `autonomy_missing` severity — disposition: pre-resolved(spc-458 Agent-assumed): warning, baselined.
- C-mode detection source (spec front matter vs binder) — disposition: agent-decides (reversible; prefer spec front matter via the `spec` row, fall back to skip when spec unresolvable).
- Should `budget-exhausted` also be a legal `in-progress → deferred` reason in prose? — disposition: pre-resolved(`transition_table.py:70` already lists it): yes, mirror the table.

## Decision journal

<!-- Append-only during execution. -->
- 2026-09-03 `autonomy_missing` severity → warning, scoped to C-mode Spec-bound tickets with `created` ≥ 2026-09-03T12:00:00Z (source: pre-resolved spc-458 Agent-assumed + agent-judgment on the boundary: the baseline file forbids adding new warnings, and tkt-428 — created 10:30Z by an in-flight create-tickets run — was the last pre-template binder; the noon cutoff exempts it without baselining).
- 2026-09-03 C-mode detection → Spec front matter `mode:` reached through the binder `| spec | spc-N … |` row; no spec row or unresolvable spec → no warning (source: agent-judgment, reversible).
- 2026-09-03 `budget-exhausted` on `in-progress → deferred` in prose → mirrored from `transition_table.py:70` (source: pre-resolved).
- 2026-09-03 `autonomy-filter.py` placement → `skills/batch-work/scripts/` (self-contained stdlib regex, same first-table rule as the validator) rather than `_lattice-lib/lib` (source: agent-judgment; batch-work already co-installs the lib but the filter has no other consumer).
- 2026-09-03 `--budget` semantics → start-work per-ticket (`stuck`/`unblock`), batch-work per-batch (`deferred`/`budget-exhausted`), stated in both skills + fallback-policy + FSM docs; spc-433 Risks gets a dated Resolution note instead of an acceptance rewrite (source: pre-resolved spc-458 D2 + create-spec supersede law).

## Pending decisions

- (none)

## Attempts

- attempt 1 · 2026-09-03 · direct fix per Approach · suites: lattice-artifacts 71/71 (+2), lattice-init 18/18 (+1), autonomy-filter 5/5 (new), transition-parity 8/8, batch-work docs-truth 4/4, finish-work docs-truth 8/8, validate-skills OK, routing evals OK; repo validator OK (217 baselined, 0 new)

## Notes

- `.lattice/blocked/` hook gating NOTICED (owned by #456 file) — follow-up.

## References

- Spec: `spc-458` · spc-433 · ADR-011 · ADR-012 · `status_vocab.py` DEFERRED_REASONS/STUCK_REASONS

## Lineage

- Parent spec: **spc-458** · Parent issue: **#458** · Primary ticket: **tkt-461** · Covers: **A8, A9, A10, A11** · Blocked by: none · Worktree bind: `tkt-461-spc433-closure-mechanisms`

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
