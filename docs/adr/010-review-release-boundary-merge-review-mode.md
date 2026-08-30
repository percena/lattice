# ADR 010: review-code + review-production release-boundary merge-review mode

- **Status:** Accepted
- **Date:** 2026-08-30
- **Deciders:** maintainer (M1n9X)
- **Related:** `skills/review-code/`, `skills/review-production/`, `tools/ci-local.sh`, tkt-243, pr-244
- **Related ADRs:** `ADR-005` (release-boundary version-increment gate), `ADR-003` (review-code axes + mini-review isolation)

## Context

Both `review-code` and `review-production` are explicitly **PR-scoped**. Their HARD-scope tables forbid a "Portfolio of unrelated PRs," and `review-code`'s target-order refuses default-branch "review everything" with no change set. `review-production` inherits the same one-PR law ("Same law as `review-code`").

A **dev→main release merge** is structurally a portfolio of PRs — the integration branch (`dev`) bundles every PR that landed since the last release, and the operator promotes it to `main` in one manual act. ADR-005 sanctions this act as the release boundary and designates `ci-local.sh --release-check` as its canonical version-increment gate. So the review skills refuse exactly the unit that the release model produces.

This gap surfaced during the post-merge dev→main review of the 0.3.0 release: a 182-commit merge had no owning review-skill mode. The operator worked around it by partitioning the logic diff into subsystem slices, tiering risk by file class (`.lattice/**` process artifacts vs high-risk logic), running `--release-check` as a first-class axis, and carrying a coarser finding bar — but that strategy was **undocumented and undiscoverable**. An operator invoking `/review-code` or `/review-production` on the merge gets refused, not guided.

## Decision Drivers

- **Sanctioned release unit** — ADR-005 establishes dev→main as the release boundary; the merge diff is a real, bounded change set, not unbounded "review everything."
- **Explicit opt-in distinguishes from unbounded review** — a release-boundary review must be *asked for*, not inferred; unbounded default-branch "review everything" with no change set stays refused.
- **Partitioning works** — a large release diff is only reviewable when sliced into subsystem pieces; one shallow linear pass skips material findings.
- **Risk tiering** — not every file in a release diff deserves the same depth (`.lattice/**` binders/specs/fixtures + docs/ADRs are low-risk bulk; `tools/`, `skills/**/scripts/`, hooks, and CI YAML are high-risk logic).
- **First-class gate** — `ci-local.sh --release-check` is already the ADR-005 version-increment invariant; it must be a named axis in release review.
- **Coarser finding bar** — a release boundary needs release-blocking vs ship-as-is classification, not per-PR nit-picking.
- **Mini-review isolation** — mirroring ADR-003, the merge-review mode lives in the full review skills, not in the `finish-work` merge-decision mini-review.

## Considered Options

- **Option A — Sanctioned exception in both full skills** (chosen) — add a release-boundary merge-review mode (explicit opt-in) to `review-code` and `review-production`, back it with this ADR. Good: discoverable, matches the release model, keeps the one-PR default unchanged. Bad: two skills to maintain in parallel (mirrored policy).
- **Option B — New dedicated `review-release` skill** (rejected) — a third review skill duplicates scope boundaries, finding format, and hard-stop policy already owned by the two existing skills; proliferation.
- **Option C — Relax the HARD scope to allow unbounded review** (rejected) — removing the "portfolio of unrelated PRs" refusal destroys the scope discipline that makes these skills change-set bounded; unbounded "review everything" re-appears.
- **Option D — Put the mode in `finish-work`'s mini-review** (rejected) — the finish-work mini-review is a bounded merge-decision projection (ADR-003); a full release-boundary review with partitioning, risk tiers, and `--release-check` would bloat it past its purpose.

## Decision

We will add a **release-boundary merge-review mode** to the **full `review-code` and `review-production` skills** only (not `finish-work` mini-review), as a sanctioned exception to the one-PR default:

1. **Sanctioned unit.** `origin/main...dev` (or `<last-release>...dev`) is an **allowed** larger-than-one-PR unit when the operator explicitly opts in via `--release-merge` / `--merge-review`, or by resolving the change set as `base=<release>`. It is **not** refused as a "portfolio of unrelated PRs." Unbounded default-branch "review everything" with no change set / no opt-in **remains refused**.
2. **Partition, don't linear-scan.** Partition the diff into subsystem slices (validator / scripts / CI / hooks / routing / skills / docs); review each slice's logic rather than one shallow linear pass.
3. **Tier risk by file class.** `.lattice/**` process artifacts (binders/specs/fixtures) + `docs/`/ADRs = low-risk bulk (skim for coherence/privacy only); `tools/`, `skills/**/scripts/`, `plugins/lattice/hooks/`, `.github/workflows/` = high-risk logic (full material review).
4. **First-class axis.** Run `bash tools/ci-local.sh --release-check` as a release-boundary axis — the ADR-005 version-increment gate — alongside CI/CD, syntax/lint, docs-sync, interface-impact (review-code) and security/perf/tests/ship (review-production).
5. **Coarser finding bar.** Classify findings **release-blocking** (must fix before dev→main merge) vs **ship-as-is** (document residual and merge). The single-PR vocabularies (`ship-as-is | fix-first | unclear` for review-code; `go | go-with-risks | no-go` for review-production) still apply, with release-blocking findings forcing `fix-first` / `no-go`.
6. **`review-production` release-boundary checklist.** Add axes a single-PR pass de-emphasizes: version/changelog coherence across the whole merge diff; secrets/privacy sweep across the whole merge diff (many PRs accumulate surface area); `ci-local.sh --release-check` as a first-class gate.
7. **Mini-review isolation (mirrors ADR-003).** The `finish-work` embedded mini-review stays a bounded projection; the release-boundary mode lives only in the full review skills.

## Consequences

- **Positive:**
  - A dev→main release review now has an owning, discoverable skill mode — an operator invoking `/review-code` or `/review-production` on the merge is guided, not refused.
  - The proven workaround (partition + risk tiers + `--release-check` + coarser bar) is now documented policy, not tacit knowledge.
  - The one-PR default and the refusal of unbounded "review everything" are both preserved — the exception requires explicit opt-in.

- **Negative / trade-offs:**
  - Two skills carry a mirrored exception block; policy drift between them is possible (mitigated by cross-references and this ADR as the single decision record).
  - A release-boundary review is heavier than a one-PR pass; operators must opt in deliberately.

- **Follow-ups:**
  - `tkt-243` — implement the changes (this ticket).

- **Verification:**
  - `bash tools/validate-skills.sh` passes (skill structure valid).
  - `bash tools/ci-local.sh --fast --base-ref dev` green.
  - `python3 tools/run-routing-evals.py` rank-1 parity unchanged (description routing tokens not altered).
  - `finish-work` mini-review unchanged (no release-boundary axes leaked in).

## Status history

- 2026-08-30: Proposed → Accepted

## Notes

- Relationship to ADR-005: ADR-005 defines the release boundary and `ci-local.sh --release-check` as its gate; this ADR makes that gate a first-class review axis and the release diff a sanctioned review unit.
- Relationship to ADR-003: ADR-003 isolates the full review axes from the `finish-work` mini-review; this ADR mirrors that isolation — the merge-review mode lives in the full review skills, not the merge-decision mini-review.
- The explicit opt-in (`--release-merge` / `--merge-review`, or `base=<release>`) is the hinge that distinguishes a sanctioned release-boundary review from unbounded "review everything." Without it, the refusal stands.

---

_Not a Lattice bloodline/graph node. Cite from Spec/PR/Review with `ADR-010` or this path._
