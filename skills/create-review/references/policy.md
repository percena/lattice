# create-review policy (portable)

Shipped with `create-review`. No monorepo docs required at runtime.

## Lattice Review ≠ PR code review

PR comments stay on GitHub. This artifact is research / design / dogfood under `.lattice/reviews/`.

## Problem Audit (DEFAULT — before Findings)

Before writing solution-oriented **Findings** / **Recommendations**, run a short **Problem Audit** (Deep Discuss–style gate). Goal: do **not** solutionize on an invalid or under-specified problem.

| Layer | Ask |
| --- | --- |
| **Validity** | Is the stated problem real? Could this be expected behavior? Is the user's causal story reliable? |
| **Information sufficiency** | What is known vs missing? Label gaps: **must-have** / nice-to-have. If must-have gaps remain → **stop** (keep `status: open`, or conclude only with explicit “blocked on info” as the primary finding — do **not** invent solutions). |
| **Hidden issues** | Related risks or deeper root causes the prompt did not name (or “none found”). |
| **Existing solution** | Is there an existing solution that already meets the stated goal? If yes, surface it as the **status-quo comparison row** before proposing alternatives — the single question that surfaces a redundant replacement. |

**Comparison matrix (DEFAULT — decision-support reviews):** for reviews of kind `design` / `audit` that compare options, Findings must include a **multi-dimensional comparison matrix**: rows = proposed option / status quo / alternatives; columns = cost, code-delta, risk, constraints, capability/feature tradeoffs. Without it, options are weighed by vibes / confirmation bias. Other review kinds (`dogfood`, `research`) stay free-form.

**Explicit skip (allowed):** the question is already crisp (e.g. locked compare of two known designs, pure dogfood of a finished path) **and** you write one line under Problem Audit: `Skipped — <reason>`. Do **not** silent-skip on fuzzy “help me think / something feels wrong” prompts.

**Not:** one-question-per-turn grilling; not a 7-phase discussion skill; not PR code review.

Template section: `references/templates/review.md` → `## Problem Audit`.

## Conclude contract

When `status: concluded`, front matter **must** set exactly one:

`outcome: inform_only | needs_decision | spawn_spec | spawn_tickets | spawn_fix | needs_grill`

## Homes

| State | Path |
| --- | --- |
| State | Path |
| --- | --- |
| All reviews (in-flight + historical) | `.lattice/reviews/rev-YYYYMMDD-HHMMSSZ-slug.md` (legacy `rev-n-slug`) |
| Forbidden | Paths other than `.lattice/reviews/` |

## Team base vs shippable cwd

| Situation | Write Review on team base? |
| --- | --- |
| **Review-only** (no Spec / ticket binder / new ADR in same request) | **Yes** — decision support; may commit on `main`/`master`/`dev` |
| **Same-pass co-create** Review + Spec and/or tickets and/or new ADR | **No** — open **one** shippable worktree first (`spc-`/`tkt-` bind), write Review **with** delivery artifacts there |
| Spec / ticket binders / product code / new ADR alone | **No** — `assert-shippable-cwd` HARD; bound worktree first |

**Review-only Step 0:** `ensure-lattice` only — **not** `assert-shippable-cwd`.  
**Co-create Step 0:** `ensure-workspace` + `cd` + `assert-shippable-cwd`, then write `rev` + Spec/ADR/tickets in that tree. Do not land Review on base and open a second tree for Spec/tickets in the same pass.

Deferred handoff (Review already on base, later `spawn_spec` / `spawn_tickets` / `spawn_fix` / `needs_grill`) still uses the standard Spec/ticket + worktree path. Never bind a shippable worktree to `rev-` alone.

## Lineage

- `related_specs` / `related_tickets` / `related_prs`: bare ids  
- Keep L0 related_* edges; no mandatory rebuild  
- Reviews are **research** edges — not delivery spine

## Scripts

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh")
"$LIB/next-artifact-id.sh"
"$LIB/_lattice-home.sh"
```

## Orchestration

Subagents may feed findings or draft an explicitly assigned, non-overlapping part. One accountable owner must validate the final Review body and outcome.

Portable rules: `skills/_lattice-lib/references/orchestration-patterns.md` (co-installed sibling path).

- Default pattern = **fan-out + merge** into one `outcome`; bounded alternatives are allowed with explicit ownership
- Avoid duplicate writers, hidden scope expansion, and accepting delegated evidence without verification

## Template

`references/templates/review.md`
