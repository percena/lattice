---
id: rev-20260801-072719Z
slug: gh-actions-v7-pr-triage
title: GitHub Actions v7 Dependabot PR triage
kind: research
status: concluded
outcome: spawn_spec
summary: "3 open Dependabot v7 major bumps (checkout/setup-node/setup-python) — all CI green, low risk; batch-land + lock grouped-deps policy as Spec/ADR"
created: 2026-08-01
updated: 2026-08-01
related_specs: [spc-4]
related_tickets: []
related_prs: [1, 2, 3]
---

# Review: GitHub Actions v7 Dependabot PR triage

> **TL;DR:** All three open Dependabot PRs (#1 setup-python v7, #2 setup-node v7, #3 checkout v7.0.1) are safe major bumps with green CI and no breaking trigger changes for this repo; worth landing as a batch, and the per-action PR churn reveals a missing grouped-deps policy that should be locked as Spec spc-4 + ADR.
> **Kind:** research · **Status:** concluded · **Outcome:** spawn_spec
> **Next:** create-spec (spc-4) → ADR-001 → create-tickets → start-work

## Context

Three Dependabot PRs are open against `main`, each bumping one pinned GitHub Action to a v7 major:

| PR | Action | From → To | File touched | CI |
| --- | --- | --- | --- | --- |
| #1 | `actions/setup-python` | v5.6.0 → v7.0.0 | `.github/workflows/lint.yml` (tier-1 skill lint job) | shellcheck, symlink-integrity, skill-quality, plugin-validate ✅ |
| #2 | `actions/setup-node` | v4.4.0 → v7.0.0 | `.github/workflows/lint.yml` (claude-code job) | shellcheck, symlink-integrity, skill-quality, plugin-validate ✅ |
| #3 | `actions/checkout` | v4.2.2 → v7.0.1 | `lattice-scripts.yml`, `lint.yml` (4 jobs), `plugin-hooks.yml` | bats, shellcheck, symlink-integrity, skill-quality, plugin-validate ✅ |

Question: do these PRs need processing, and if so how? This Review drives that decision and the downstream Spec/ADR/ticket decomposition.

## Problem Audit

| Layer | Notes |
| --- | --- |
| Validity | Real — these are v4/v5 → v7 **major** bumps of CI-critical actions in the Lattice tooling repo; major bumps can carry breaking input/behaviour changes that green CI may not surface (CI only runs the lint/bats suite, not the full action surface). |
| Information | Sufficient. Diffs inspected (SHA-pin + `# vN.N.N` comments, disjoint line ranges per PR). CI status captured for all 3. Workflow trigger audit done. Dependabot config read. `dev` and `main` share baseline `cc91bac` (single commit repo). |
| Hidden issues | (1) `dependabot.yml` has no `groups:` block → each action spawns its own PR → the 3 PRs overlap on `lint.yml` and force sequential rebase churn. (2) No durable policy doc for the SHA-pin + bump cadence; this is the first ADR-worthy cross-cutting decision. (3) `checkout` v7.0.0 blocks fork-PR checkout for `pull_request_target`/`workflow_run` — but this repo only uses `pull_request:` triggers, so N/A. |

## Findings

1. **All three bumps are safe for this repo's actual action surface.** Evidence: each `with:` key in use (`python-version: "3.12"`, `node-version: 20`, plain `checkout` + `fetch-depth: 0`) is unchanged across the v7 releases; CI is green on every PR. `.github/workflows/lint.yml:48,80`; `.github/workflows/lattice-scripts.yml:30`; `.github/workflows/plugin-hooks.yml:26`.
2. **`checkout` v7's security change is not in scope here.** v7.0.0 blocks checking out fork PRs for `pull_request_target`/`workflow_run`. Grep of `.github/workflows/` shows only `pull_request:` triggers (no `pull_request_target`, no `workflow_run`) → behaviour identical for this repo. Safe to merge.
3. **PRs are line-disjoint on `lint.yml`.** PR #3 edits `checkout@…` lines (`lint.yml:20,31,45,79`); #1 edits the `setup-python@…` line (`lint.yml:48`); #2 edits the `setup-node@…` line (`lint.yml:80`). No same-line collision → git auto-merges, but Dependabot still rebases each branch on the others' merge, so a single batch/combined commit is cleaner than 3 sequential squash-merges.
4. **`dependabot.yml` lacks a `groups:` block.** `.github/dependabot.yml` is weekly, `open-pull-requests-limit: 5`, `directory: /`, ecosystem `github-actions` — no grouping. Adding `groups: { github-actions: { patterns: ["*"] } }` collapses future bumps into one PR/cycle, eliminating the overlap-churn that produced these 3 separate PRs.
5. **Repo already follows SHA-pin best practice** (commit SHA + ` # vN.N.N` comment on every `uses:`). This is the durable policy to codify — not a change, just documentation. ADR-worthy because it outlives any single Spec.
6. **Merge target alignment.** PRs target `main` (Dependabot default). Active dev branch is `dev`; both share baseline `cc91bac` (single-commit repo), so landing on `main` then fast-forwarding `dev` is conflict-free. Per merge-target convention, the PR base follows the user's branch; here `main` is correct since CI files are identical on both refs.
7. **No hidden must-have info gap.** Major-bump risk for inputs *not* exercised by CI is theoretical here (only `python-version`/`node-version`/`fetch-depth` are used), so the analysis is not blocked.

## Recommendations

1. **Land the three bumps as one batch** — prefer a single combined upgrade commit on `spc-4-gh-actions-v7-upgrade` over 3 sequential Dependabot squash-merges, to avoid rebase churn and give one reviewable change set. Close the 3 Dependabot PRs after the combined commit lands (or merge them in order #3 → #1 → #2 if batch-rebase is preferred).
2. **Add `groups:` to `dependabot.yml`** so future GitHub-Actions bumps arrive as one grouped PR, killing the per-action overlap problem at the source.
3. **Record the policy as `docs/adr/ADR-001`** — SHA-pin + version comment, weekly cadence, grouped updates, and a "major bumps validated against the repo's actual action surface before merge" rule. This outlives the Spec.
4. **Lock as Spec `spc-4`** with acceptance: all 3 actions at v7 on `dev`, CI green on `dev`, `dependabot.yml` grouped, `ADR-001` merged.

## Outcome (required to conclude)

`spawn_spec` — a locked Spec (`spc-4`, GitHub issue #4) is needed before ticket slicing so the delivery contract (batch-land + grouped-deps + ADR) is explicit. ADR-001 is co-created in the same pass as a cross-cutting system law.

### Follow-ups

- [x] Spec `spc-4` (issue #4 created; Spec file written this pass)
- [ ] ADR-001 (this pass)
- [ ] Tickets (this pass)
- [ ] start-work (this pass)

## References

- Workflows examined: `.github/workflows/lint.yml`, `.github/workflows/lattice-scripts.yml`, `.github/workflows/plugin-hooks.yml`
- Config: `.github/dependabot.yml`
- PRs: #1 #2 #3 ( Dependabot, target `main`)
- Baseline commit: `cc91bac` (shared by `dev` + `main`)
