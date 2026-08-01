---
id: spc-4
slug: gh-actions-v7-upgrade
title: GitHub Actions v7 upgrade + Dependabot grouping policy
kind: chore
status: locked
mode: C
priority: P2
summary: "Land v7 bumps for checkout/setup-node/setup-python as one batch + lock grouped-deps policy as ADR-001"
created: 2026-08-01
updated: 2026-08-01
tickets: [tkt-5, tkt-6, tkt-7, tkt-8]
prs: [pr-9]
reviews: [rev-20260801-072719Z]
supersedes: []
superseded_by: null
---

# Spec: GitHub Actions v7 upgrade + Dependabot grouping policy

> **TL;DR:** Land the three open Dependabot v7 major bumps (`actions/checkout`, `setup-node`, `setup-python`) as one validated batch on `dev`, add a `groups:` block to `dependabot.yml` so future actions bumps arrive as one PR, and codify the SHA-pin + grouped + weekly policy as `ADR-001`.
> **Kind:** chore · **Status:** locked · **Mode:** C · **Priority:** P2
> **Path:** rev-20260801-072719Z → spc-4 → tkt-… → pr-…

## Why

Three Dependabot PRs (#1, #2, #3) bump CI actions to v7 majors; all are green but each touches `.github/workflows/lint.yml`, producing per-action PR churn and rebase collisions. The repo already pins to SHA + version comment but has no durable policy doc, and `dependabot.yml` lacks grouping — so this churn recurs every week. This Spec locks the batch landing + the grouped-deps policy so future bumps cost one PR, not N. Driven by Review `rev-20260801-072719Z` (triage concluded `spawn_spec`).

## In scope

- Land `actions/checkout@v7.0.1`, `actions/setup-node@v7.0.0`, `actions/setup-python@v7.0.0` across `.github/workflows/lint.yml`, `lattice-scripts.yml`, `plugin-hooks.yml` (update SHA + ` # vN.N.N` comment).
- Add a `groups:` block to `.github/dependabot.yml` so all `github-actions` ecosystem bumps group into one PR per cycle.
- Write `docs/adr/ADR-001-dependabot-github-actions-policy.md` capturing the SHA-pin + version-comment, weekly, grouped, and major-bump-validation rule.
- Close the three Dependabot PRs (#1, #2, #3) once the combined upgrade lands (or merge in order if batch squash is blocked).

## Out of scope

- Changing the workflow trigger model (stays `pull_request:` only — no `pull_request_target`/`workflow_run`).
- Bumping the `python-version`/`node-version`/runner image — runtime versions stay `3.12` / `20`.
- Non-github-actions ecosystems (none exist in this repo).

## Acceptance

- [x] **A1** All `uses: actions/checkout@…` pins resolve to the v7.0.1 SHA with ` # v7.0.1` comment, in `lint.yml`, `lattice-scripts.yml`, `plugin-hooks.yml`.
- [x] **A2** `actions/setup-python@…` pins to the v7.0.0 SHA with ` # v7.0.0` comment in `lint.yml`.
- [x] **A3** `actions/setup-node@…` pins to the v7.0.0 SHA with ` # v7.0.0` comment in `lint.yml`.
- [x] **A4** CI (`shellcheck`, `symlink-integrity`, `skill-quality`, `plugin-validate`, `bats`) is green on `dev` after the combined commit lands.
- [x] **A5** `.github/dependabot.yml` contains a `groups:` block grouping the `github-actions` ecosystem (`patterns: ["*"]`).
- [x] **A6** `docs/adr/ADR-001-dependabot-github-actions-policy.md` exists, is appended to `docs/adr/README.md` index, and records the SHA-pin + weekly + grouped + major-bump-validation rule.
- [ ] **A7** Dependabot PRs #1, #2, #3 are closed (not dangling open) once the combined upgrade is on `dev`/`main`.

## Non-goals

- Will not adopt a Dependabot auto-merge bot or Mergify ruleset in this Spec.
- Will not migrate off SHA-pinning to tag-pinning (SHA-pin is the policy being codified).

## Decisions (principal, user-confirmed)

1. **Land as one combined upgrade commit** on branch `spc-4-gh-actions-v7-upgrade` rather than 3 sequential Dependabot squash-merges — avoids rebase churn on the shared `lint.yml`, gives one reviewable change set, and is the natural delivery unit for this Spec. Trade-off: closes 3 bot PRs instead of merging them (acceptable — the combined commit supersedes them).
2. **Group all `github-actions` bumps** via `groups: { patterns: ["*"] }` — collapses weekly PR volume 3→1 and removes per-action overlap. Trade-off: one grouped PR must be reviewed whole, but that is already the case.
3. **Codify policy as `ADR-001`** (consumer `docs/adr/`), not only in Spec Decisions — this rule outlives the Spec and applies to all future Dependabot github-actions bumps. Feature-local Decisions stay here; the cross-cutting law is the ADR.
4. **Target `dev`** for the combined PR (active dev branch); `dev`==`main` baseline `cc91bac` so landing on either is conflict-free, but `dev` is the integration branch per repo convention.
5. **Keep runtime versions** (`python 3.12`, `node 20`) — the v7 action bumps do not require bumping the runtime they install.

## Agent-assumed (secondary)

- Assumed the v7 action releases are API-compatible with the repo's actual `with:` surface (`python-version`, `node-version`, `fetch-depth`, plain checkout) — verified via green CI on each Dependabot PR, not via reading upstream changelogs in depth. If a maintainer objects, A1–A4 gate on `dev` CI which will catch regressions.

## Risks / open questions

- **R1:** A v7 breaking change not exercised by CI (e.g. an unused `with:` input) — low; the surface is minimal and CI is green on all 3 PRs. Mitigation: `dev` CI gate (A4) before merge.
- **R2:** Dependabot may re-open a bump PR after the combined commit if its perceived base differs — mitigated by closing #1/#2/#3 explicitly (A7) and the new `groups:` config steering future cycles to one PR.

## References

- Review: `rev-20260801-072719Z` → `.lattice/reviews/rev-20260801-072719Z-gh-actions-v7-pr-triage.md`
- ADR: `ADR-001` → `docs/adr/ADR-001-dependabot-github-actions-policy.md` (this pass)
- Workflows: `.github/workflows/lint.yml`, `.github/workflows/lattice-scripts.yml`, `.github/workflows/plugin-hooks.yml`
- Config: `.github/dependabot.yml`
- PRs superseded: #1 #2 #3

## Links / bloodline (L0)

- Tickets: `tkt-5` (land v7 bumps, primary ship), `tkt-6` (dependabot groups), `tkt-7` (ADR-001), `tkt-8` (close PRs #1/#2/#3)
- PRs: `pr-9` (https://github.com/percena/lattice/pull/9, base `dev`)
- Reviews: `rev-20260801-072719Z`
