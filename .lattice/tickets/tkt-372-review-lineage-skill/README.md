# tkt-372-review-lineage-skill

> **TL;DR:** SKILL.md + method/taxonomy/template: the three-layer mining protocol, verify-then-report, insight ranking, rev output with a Proposed-tickets table.
> **Kind:** feat · **Priority:** P1

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | feat,P1 |
| github | https://github.com/percena/lattice/issues/372 |
| status | rework |
| fix_cycles | 1 |
| wait_reason | (none) |
| created | 2026-09-02T07:21:07Z |
| updated | 2026-09-02T08:24:05Z |
| adopted | false |
| summary | SKILL.md + method/taxonomy/template: the three-layer mining protocol, verify-then-report, insight ranking, rev output with a Proposed-tickets table. |
| spec | spc-369 — review-lineage (path: ../../specs/spc-369-review-lineage.md) |
| covers | A3 |
| blocked_by | #370, #371 |
| merge_blocked_by | #370, #371 |
| parallel_group | (serial) |
| paths | skills/review-lineage/SKILL.md, skills/review-lineage/references/method.md, skills/review-lineage/references/insight-taxonomy.md, skills/review-lineage/references/templates/lineage-audit.md |
| solo_merge | yes |
| **primary_ticket** | tkt-372 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-372-review-lineage-skill |
| worktree | sibling `…/lattice.worktrees/tkt-372-review-lineage-skill/` |
| prs | pr-377 — https://github.com/percena/lattice/pull/377 |

## Acceptance (this slice)

- [x] **A3** — see GitHub issue #372 and Spec spc-369 A3. Evidence: `skills/review-lineage/SKILL.md` (167 lines, anatomy footers, `agents: claude-code,codex`, `domain: quality-side-path`) + `references/{method,insight-taxonomy}.md` + `references/templates/lineage-audit.md`; dry run → `.lattice/reviews/rev-20260902-080545Z-lineage-audit-baseline.md` (kind audit, `spawn_tickets`, Proposed-tickets table in create-tickets §2 column shape); `tools/validate-skills.sh` OK, `validate-lattice-artifacts.py` exit 0 (0 errors).

## Approach

1. SKILL.md modelled on review-delivery's shape (frontmatter with `domain: quality-side-path`, Load-on-demand table, When to use/NOT, Invariants, Inputs, Process 0–5, Outputs, anatomy footers); Step 0 runs `lineage-metrics.sh --md`, `claim-probes.sh --md`, `validate-lattice-artifacts.py`, optional `reconcile-state.sh`.
2. method.md: L1/L2/L3 commands and the ranking rubric (impact × decidability), fan-out guidance citing orchestration-patterns.md, verify-then-report with dropped-claim accounting (audit-recipe §2).
3. insight-taxonomy.md: modelled-but-unwalked, claim-without-enforcement, done-without-evidence, silent-bypass, recurrence, invisible-queue, prose-vs-script ratio, artifact-truth (checked box ≠ proven) — each with detection hint + example from rev-20260902-015425Z.
4. templates/lineage-audit.md: rev frontmatter (kind audit), Metrics delta, Probe failures, Findings (≤7), Insights, Proposed tickets (title | kind | priority | covers | paths | blocked_by | why), Outcome, Method (sweeps, dropped claims), References.
5. Dry-run the skill on this repo; the produced rev is NOT committed by this ticket (it is evidence in the PR body), or committed under .lattice/reviews/ if the operator wants the first baseline.

## Anticipated decisions

- Whether the dry-run rev is committed — must-ask (default: commit it as the first baseline; it is a real audit).

## Decision journal

- **Dry-run rev committed as the first baseline** — binder must-ask default ("commit it as the first baseline; it is a real audit") applied unattended; `.lattice/reviews/rev-20260902-080545Z-lineage-audit-baseline.md` + snapshot `.lattice/reviews/metrics/lineage-20260902-080132Z.json` are in this PR. Source: binder `## Anticipated decisions`; `create-review` rule 8 (Review-only write); spc-369 D3 (committed baseline). Operator may drop the two files at merge if they prefer PR-body evidence only.
- **Proposed-tickets column shape = `create-tickets` §2 columns verbatim, then `kind | priority | why` appended** (`| # | title | covers | paths (approx) | blocked_by | parallel_group | solo-merge | kind | priority | why |`). The A3 acceptance says the table "parses into create-tickets' section-2 batch without edits", so the seven §2 columns come first and unchanged; the issue body's title/kind/priority/covers/paths/blocked_by set is a superset satisfied by the three extra trailing columns. Source: spc-369 A3; `skills/create-tickets/references/flow.md` §2; issue #372 Scope.
- **`--gh` input maps to `reconcile-state.sh --binder <path>` per named binder, not a whole-tree flag** — the script has no `--gh` option (`reconcile-state.sh --help`: `--binder` required). SKILL documents the real contract and keeps the audit offline by default. Source: spc-369 Out of scope ("optional sensor"); `skills/_lattice-lib/scripts/reconcile-state.sh` usage.
- **Validator invoked as `tools/validate-lattice-artifacts.py` when present, else skipped with a note** — no vendored copy exists under `_lattice-lib/scripts/`; `review-delivery/references/axes.md:55` uses the same path. Source: `ls skills/_lattice-lib/scripts/`; spc-369 D5 (reuse, no second validator).
- **Comparison matrix included in the lineage template and the baseline rev** — `create-review` rule 1b / `audit-recipe.md` Composition require it for `kind: audit`; the ticket's template list omitted it. Source: `skills/create-review/SKILL.md` rule 1b.
- **Findings order = impact then decidability; F6 carried as a needs-decision row inside `spawn_tickets`** rather than a second outcome (create-review rule 2: exactly one outcome). Source: `references/method.md` rubric; ADR-007 §3.
- **Spec `spc-369` `reviews:` list not edited** — `.lattice/specs/` is outside this ticket's `paths`; the rev carries `related_specs: [spc-369, spc-337]` so the L0 edge exists from the review side. Left for finish-work / tkt-373 to add `rev-20260902-080545Z` to the Spec. Source: binder `paths`; create-review rule 4.
- 2026-09-02T08:24:05Z — fix cycle 1: `pr-open` → rework (fix_cycles 1; cap ≤2; ADR-004 §5) — brief: review Hold (PR #377): M1 MED — F4 evidence undercounts (3 retired-path hits, not 1: also review-code/SKILL.md:122 and review-code/references/ci-check.md:14; probe evidence truncates at 200 chars — Step 2 must re-run the probe command); ticket 4 must cover all three files. M2 MED — Proposed-tickets blocked_by '#1' collides with the GH-issue grammar (policy.md:108 blocked_by = none | #N issue); use none + prose. M3 LOW — 4 citations do not reproduce (grep list 9 not 10 / regex misses d17e1ca, includes wrong hashes; 356.jsonl added by e160dc6 not 5fc6b63; ensure-workspace.sh:670 not :669; fix( count 84 not 88). M4 LOW — ticket 3 mode lint overbroad (scope to SKILL-named entry points). M5 LOW — SKILL.md:76 cwd-relative validator call silently no-ops; print a skipped note.

## Pending decisions

(none)

## Attempts

- (none — single pass; sensors ran first try: metrics 0.9 s, probes 0.7 s)

## Notes

- NOTICED: skills/_lattice-lib/scripts/reconcile-state.sh — spc-369 Out-of-scope and the tkt-372 brief describe an optional `reconcile-state.sh --gh` sensor, but the script only accepts `--binder <path> [--repo] [--json]`; the SKILL documents the per-binder form (out-of-paths, 2026-09-02)
- NOTICED: skills/review-lineage/scripts/claim-probes.sh — `--json` truncates the `evidence` field the same way `--md` does (200 chars + `…`), so a consumer that wants the full drift list must re-run the probe one-liner; an `--evidence-full` flag or untruncated JSON would let Step 2 skip the re-run (out-of-paths, 2026-09-02)
- NOTICED: skills/review-lineage/scripts/lineage-metrics.sh — usage line says `--since <ref|ISO|Nd>` but the L3 archaeology commands in method.md need the git-native form (`--since='30 days ago'`); `_since_to_args` converts `Nd` internally, fine, but a `--print-git-args` (or documenting the conversion) would keep the SKILL's git commands and the sensor's window identical (out-of-paths, 2026-09-02)
- NOTICED: docs/adr/011-consumer-repo-footprint-hygiene.md:74 — Verification bullet "a fresh-clone simulation test … lands in the test suite" names no bats file; `adr-verification-refs-resolve` cannot probe an unnamed test, so the claim is unguarded (rev-20260902-080545Z Appendix A1) (out-of-paths, 2026-09-02)

## References

- Spec: `spc-369` → `.lattice/specs/spc-369-review-lineage.md`
- Review: `rev-20260902-015425Z` (method origin)

## Lineage

- Parent spec: **spc-369**
- Parent issue (GH sub-issue of Spec primary): **#369**
- Primary ticket: **tkt-372**
- Covers: **A3**
- Blocked by: #370, #371
- Parallel group: (serial)
- Worktree bind: tkt-372-review-lineage-skill

## Finish

- (none yet)
