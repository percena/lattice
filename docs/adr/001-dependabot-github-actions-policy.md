# ADR 001: Dependabot GitHub Actions upgrade policy

- **Status:** Accepted
- **Date:** 2026-08-01
- **Deciders:** maintainers
- **Related:** `spc-4`, `rev-20260801-072719Z`
- **Related ADRs:** —

## Context

This repo (the Lattice tooling repo) uses GitHub Actions for CI (`shellcheck`, `symlink-integrity`, `skill-quality`, `plugin-validate`, `bats`) across `.github/workflows/lint.yml`, `lattice-scripts.yml`, `plugin-hooks.yml`. Dependabot runs weekly on the `github-actions` ecosystem with `open-pull-requests-limit: 5`.

Three forces require a policy decision:

1. **Pin style is undeclared.** Workflows already pin to commit SHA with a ` # vN.N.N` trailing comment, but nothing prevents a future contributor from switching to tag-pins (`actions/checkout@v7`) which weakens supply-chain integrity.
2. **Per-action PR churn.** `dependabot.yml` has no `groups:` block, so each action gets its own PR. A single weekly cycle opened 3 PRs (#1, #2, #3) that all edit `.github/workflows/lint.yml`, forcing sequential rebases and review noise.
3. **Major-bump validation gate is implicit.** Dependabot bumps majors (v4/v5 → v7) as eagerly as minors. Green CI on the bump PR is necessary but only exercises the lint/bats suite, not the action's full input surface.

## Decision Drivers

- Supply-chain integrity: SHA pins are non-negotiable; tag pins are mutable.
- Reviewer cost: one grouped PR per cycle is cheaper than N.
- Major-bump safety: a major bump must be checked against the repo's *actual* `with:` surface, not just CI.

## Considered Options

- **Option A — SHA-pin + grouped + weekly + major-bump-validation (chosen).** Good: strongest integrity, lowest PR noise, explicit major gate. Bad: grouped PRs must be reviewed as a whole.
- **Option B — Tag-pin (`@v7`).** Good: readable. Bad: mutable ref → supply-chain risk. Rejected.
- **Option C — Pin + no grouping (status quo).** Good: none over A. Bad: per-action PR churn recurs. Rejected.
- **Option D — Auto-merge bot for minors, manual for majors.** Good: less toil. Bad: adds a bot dependency; out of scope for this ADR. Deferred.

## Decision

We will:

1. **Pin every GitHub Actions `uses:` to a commit SHA** with a trailing ` # vN.N.N` version comment. No tag-pins (`@v7`), no branch-pins.
2. **Group the `github-actions` Dependabot ecosystem** (`groups: { patterns: ["*"] }`) so all action bumps arrive as **one PR per weekly cycle**.
3. **Keep the weekly cadence** (`schedule: interval: weekly`) and `open-pull-requests-limit: 5`.
4. **Gate major bumps** (`vN → vN+1`) on a manual check against the repo's actual `with:` input surface before merge — green CI alone does not authorize a major bump. Minor/patch bumps may merge on green CI.

## Consequences

- **Positive:** One reviewable Dependabot PR per week instead of N; supply-chain integrity codified; major bumps get a deliberate human gate.
- **Negative / trade-offs:** Grouped PRs bundle several actions into one change set — a single broken action cannot be deferred without dropping others from the group (acceptable; re-pin the broken one in the same PR or close the group). SHA pins require Dependabot to resolve commits (it does).
- **Follow-ups:** `spc-4` lands the first v7 batch + adds the `groups:` block; closes Dependabot PRs #1, #2, #3.
- **Verification:** `grep -nE 'uses: actions/[a-z-]+@v[0-9]' .github/workflows/` returns empty (no tag-pins); `grep -n 'groups:' .github/dependabot.yml` matches; the weekly Dependabot cycle produces ≤1 `github_actions`-labeled PR.

## Status history

- 2026-08-01: Proposed → Accepted (first ADR; locked via `spc-4` + `rev-20260801-072719Z`).

## Notes

Supersedes the implicit (undocumented) status-quo policy. If Dependabot grouping proves to hide broken actions, supersede with an ADR-002 that scopes groups more narrowly — do not edit this ADR in place.

---

_Not a Lattice bloodline/graph node. Cite from Spec/PR/Review with `ADR-001` or this path._
