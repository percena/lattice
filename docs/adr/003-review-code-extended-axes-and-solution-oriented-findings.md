# ADR 003: review-code skill — CI/CD, syntax/lint, docs-sync, interface-impact axes + solution-oriented findings

- **Status:** Accepted
- **Date:** 2026-08-25
- **Deciders:** maintainers
- **Related:** `tkt-35`, `pr-N` (to be opened)
- **Related ADRs:** —

## Context

The `review-code` skill (Quality side-path) historically reviewed only **material correctness/regression** findings on a change set — logic errors, high-cost failure paths, test gaps, and privacy/secrets. Four gaps emerged from real usage:

1. **No CI/CD feedback** — a PR could have red CI but the review would not surface it or offer to fix.
2. **No syntax/lint** — basic compile/parse errors in changed files were invisible unless the reviewer happened to notice them in the diff.
3. **No docs-sync** — code changed behavior but README, docs, wiki, CLAUDE.md, or ADRs were left stale; the review did not flag the gap.
4. **No interface-impact tracing** — a change could rename a function param or remove an export, breaking every caller, but the review only looked at the diff files themselves, not adjacent consumers.

Additionally, the finding contract was **problem-only**: each finding described what could go wrong and a vague "recommendation direction", leaving the operator to research the fix. And the hard-stop interaction risked **per-finding or per-axis AskUserQuestion confirmations** — a poor UX pattern where the user is asked repeatedly.

## Decision Drivers

- **Review comprehensiveness** — a dedicated review pass should catch what a quick diff read misses (CI, lint, docs, interface breakage).
- **UX quality** — findings should include concrete best-practice solutions + alternatives, not bare problems. Confirmations should be batched into one AskUserQuestion, never per-finding.
- **Scope discipline** — new axes must stay change-set scoped; interface tracing is one hop, not a full call-graph audit. Whole-repo depth belongs to `review-production` or `create-review`.
- **Hard-stop invariant** — the review-only hard stop (present → STOP → fix only after user confirms) must not be broken. Auto-fixing without consent is forbidden.
- **Mini-review isolation** — `finish-work`'s embedded mini-review must stay a bounded 5-axis projection; the new capabilities live in the full `review-code` skill only.

## Considered Options

- **Option A — Add to review-code only** (chosen) — full skill gains 4 new axes + solution-oriented findings + batch confirmation. Mini-review unchanged. Good: comprehensive dedicated review; bad: slightly heavier full-skill process.
- **Option B — Add to finish-work mini-review too** (rejected) — mini-review is a merge-decision point, not a full review; adding CI/lint/docs/interface would bloat it and slow the merge gate.
- **Option C — Create a new skill** (rejected) — `review-code` already owns the change-set quality contract; a second skill would duplicate scope boundaries, finding format, and hard-stop policy. Unnecessary proliferation.
- **Option D — Auto-fix CI failures (break hard-stop)** (rejected) — breaking the hard-stop invariant for one axis creates a slippery slope; the batch AskUserQuestion pattern makes intent explicit without auto-fixing.

## Decision

We will add four new axes to the **full `review-code` skill** only (not `finish-work` mini-review):

1. **CI/CD** — fetch PR/branch CI status via `gh pr checks` / `gh run list`; surface failures with log excerpts; classify real vs flaky.
2. **Syntax/Lint** — run language-appropriate tools (ruff, shellcheck, node --check, jq, yaml.safe_load) on **changed files only**; skip gracefully if tool unavailable.
3. **Docs sync** — detect stale README/docs/wiki/CLAUDE.md/SKILL.md/ADRs when code alters behavior/interface/config.
4. **Interface/contract impact** — trace **one hop** from changed signatures/exports/endpoints/config keys to consumers via `git grep`; flag breaking changes.

We will upgrade the **finding contract** from problem-only to **solution-oriented**: every material finding must include a recommended best-practice solution (with rationale) + 1–2 alternatives (with trade-offs). The output template gains a `### Solutions` subsection.

We will upgrade the **hard-stop interaction** to a **single batch AskUserQuestion**: all findings (all axes) are presented in one output, then one `AskUserQuestion` asks what to fix (`Apply all recommended` / `Apply high-severity recommended` / `Choose per-finding` / `Skip`). Never per-finding or per-axis.

The `finish-work` mini-review stays a bounded 5-axis projection (Correctness, High-cost failure, Tests, Dig deeper, Privacy/Secrets) — no new axes leak in.

## Consequences

- **Positive:**
  - Dedicated review passes now catch CI failures, syntax errors, stale docs, and interface breakage — not just diff-internal logic.
  - Findings come with actionable solutions, reducing operator cognitive load.
  - Single batch confirmation eliminates the worst UX pattern (repeated per-finding prompts).
  - Interface tracing catches breaking changes that pure diff review misses.

- **Negative / trade-offs:**
  - Full `review-code` process is heavier (7 steps, 8 axes, 7 reference files). Operators who want a quick diff scan may find it slower.
  - Interface tracing reads files outside the diff (one hop) — slightly broader scope, though bounded.
  - Syntax/lint depends on tool availability; if tools are missing, checks are skipped (transparent, not silent).

- **Follow-ups:**
  - `tkt-35` — implement the changes (this ticket).
  - Consider adding a `--quick` flag or stance that skips CI/lint/docs/interface for operators who only want correctness review (future ticket if needed).

- **Verification:**
  - `bash tools/validate-skills.sh` passes (skill structure valid).
  - `skills/review-code/evals/evals.json` has 9 cases covering all new axes + solution-oriented findings + batch confirmation.
  - `finish-work` mini-review (lines 113–162 of its SKILL.md) still shows original 5 axes — no CI/lint/docs/interface leaked.

## Status history

- 2026-08-25: Proposed → Accepted

## Notes

- The batch confirmation pattern was inspired by `finish-work`'s mini-review, which already uses a single AskUserQuestion at the merge decision point.
- Interface tracing is explicitly **one hop** — direct callers/consumers only. Full call-graph or dependency analysis belongs to `review-production` or architecture review via `create-review`.
- The `review-context.py` script was intentionally left unchanged — it stays a pure git-context gatherer. CI/lint/docs/interface checks are agent-executed steps guided by reference files, avoiding coupling to tool availability.

---

_Not a Lattice bloodline/graph node. Cite from Spec/PR/Review with `ADR-003` or this path._
