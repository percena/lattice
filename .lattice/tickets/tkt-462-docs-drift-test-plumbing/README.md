# tkt-462-docs-drift-test-plumbing

> **TL;DR:** Documentation drift and test-plumbing gaps surfaced by the review.
> **Kind:** docs · **Priority:** P2
> **Path:** spc-458 → tkt-462 → (pr-…)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P2 |
| labels | docs, P2 |
| github | https://github.com/percena/lattice/issues/462 |
| status | in-progress |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-03T16:51:19Z |
| updated | 2026-09-03T17:26:29Z |
| adopted | false |
| summary | Fix skill-count/co-install/script-table drift, phantom deep-review state, broken links, CHANGELOG gaps, orphan bats suite, root guards |
| spec | spc-458 — Review follow-up (path: ../../specs/spc-458-review-followup.md) |
| covers | A12, A13, A14 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | (serial) |
| paths | skills/_lattice-lib/SKILL.md, plugins/lattice/README.md, llms.txt, README.md, CHANGELOG.md, docs/workflow-fsm.md (deep-review wording only), skills/*/SKILL.md + skills/*/references/**/*.md (link fixes only), skills/finish-work/tests/docs-truth.bats → skills/finish-work/scripts/tests/docs-truth.bats, tools/tests/ci-local.bats, skills/_lattice-lib/scripts/tests/check-installed-skill-drift.bats |
| solo_merge | yes |
| autonomy | 3 |
| **primary_ticket** | tkt-462 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-462-docs-drift-test-plumbing` |
| worktree | sibling `…/lattice.worktrees/tkt-462-docs-drift-test-plumbing/` |
| prs | (none) |

## Acceptance (this slice)

- [x] **A12** one true count (15 user-facing + `_lattice-lib`) in `_lattice-lib/SKILL.md`, `llms.txt`, `plugins/lattice/README.md`; co-install list includes `review-lineage`; script table includes `transition-api.py`; `docs/workflow-fsm.md` describes `deep-review` as a triage class (mermaid note), not an M2 state.
- [x] **A13** every relative link in `skills/**/SKILL.md` and `skills/**/references/**/*.md` resolves from the file's own directory (link-check command + output pasted in PR Verification); `CHANGELOG.md` gains `[0.4.0]` and `[0.5.0]` sections from the release commits and `[Unreleased]` bullets for spc-433 (#438), #440, #450, spc-458.
- [x] **A14** `docs-truth.bats` lives under `skills/finish-work/scripts/tests/` (depth-adjusted, 8/8 green) so CI discovers it; `ci-local.bats` and `check-installed-skill-drift.bats` chmod-000 tests `skip` when `[ "$(id -u)" -eq 0 ]`.

## Approach

1. Counts: grep `fourteen|Fifteen|15 units|14 user-facing`; align to `validate-skills.sh --list-user-facing` output (15). Keep keyword parity (validate-skills errors on drift).
2. Link check: one-off bash loop over `\]\((\.\.?/[^)#]+)` targets resolved relative to the file; fix wrong-depth (`../_lattice-lib` → `../../_lattice-lib` from `references/`), missing `references/` segments, and wrong script paths; leave documented examples (`lib/errors.py`) alone with an explicit "illustrative" marker if needed.
3. CHANGELOG: sections from `git show 6228f3b`/`5ed9329`/`8f1d375` + the merged PR titles; Keep-a-Changelog compare links.
4. `git mv` the suite; change `SKILL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." …)"` to `../..`; run it.
5. Root guards: `[ "$(id -u)" -eq 0 ] && skip "chmod 000 is ineffective for root"` before the chmod.

## Anticipated decisions

- Whether skill-root-relative links inside `references/*.md` are a convention to document or bugs to fix — disposition: agent-decides (reversible; fix to file-relative, which is what every Markdown renderer and the README "self-contained" claim assume).
- CHANGELOG `[Unreleased]` policy (write at landing vs at release) — disposition: must-ask → parked; this ticket writes bullets for the current unreleased set only.

## Decision journal

<!-- Append-only during execution. -->
- 2026-09-04 link convention → file-relative (what Markdown renderers and the README "self-contained" claim assume); 7 backtick path refs corrected (batch-work SKILL, create-pr SKILL ×2, ticket-binder template, start-work policy, lineage-audit template ×2); generate-wiki template placeholders (`{{PATH}}`, consumer `../README.md`) left as-is — they are rendered into the consumer repo (source: agent-judgment, reversible).
- 2026-09-04 `deep-review` in docs/workflow-fsm.md → mermaid `note right of rework` + table row without an arrow, so the parity test's arrow parser skips it and the diagram no longer draws a state that `status_vocab.py` lacks (source: agent-judgment).
- 2026-09-04 CHANGELOG `[Unreleased]` → written now for spc-433/#440/spc-441/spc-458 and compare links added; the per-landing vs at-release policy stays a Pending decision for ADR-005 (source: pre-resolved must-ask → parked).
- 2026-09-04 orphan suite → `git mv` to `skills/finish-work/scripts/tests/` with `SKILL_DIR` depth +1; CI glob untouched (source: pre-resolved spc-458 D4).

## Pending decisions

- ADR-005 amendment: is `[Unreleased]` written per landing PR (lint-heavy check) or reconstructed at release? · default-if-unanswered: per landing, no CI check yet.

## Attempts

- attempt 1 · 2026-09-04 · direct fix per Approach · link scan 0 unresolved (excluding generate-wiki placeholders), transition-parity 8/8, batch-work docs-truth 4/4, moved finish-work docs-truth 8/8 (now under the CI glob), root-guard tests skip as uid 0, validate-skills OK

## Notes

- Warning baseline growth (229 lines, never shrank) NOTICED — separate ratchet ticket.

## References

- Spec: `spc-458` · ADR-005 · `tools/validate-skills.sh`

## Lineage

- Parent spec: **spc-458** · Parent issue: **#458** · Primary ticket: **tkt-462** · Covers: **A12, A13, A14** · Blocked by: none · Worktree bind: `tkt-462-docs-drift-test-plumbing`

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
