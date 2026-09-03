---
id: spc-441
slug: hardening-sweep
title: "Project-wide hardening — security, CI, test & maintainability sweep"
kind: chore
status: locked
mode: C
priority: P2
summary: "Fix expression injection, eliminate eval+python3, add macOS CI, test untested hook, add CODEOWNERS, refactor duplication"
created: 2026-09-03
updated: 2026-09-03
tickets: [tkt-442, tkt-443, tkt-444, tkt-445, tkt-446, tkt-447, tkt-448, tkt-449]
prs: []
reviews: []
supersedes: []
superseded_by: null
---

# Spec: Project-wide hardening sweep

> **TL;DR:** Full-project review surfaced 2 security issues (GHA expression injection, fragile eval+python3), CI gaps (no macOS matrix, untested hook), and maintainability debt (CODEOWNERS, code duplication, large hook file, missing docs). This spec covers all confirmed findings.
> **Kind:** chore · **Status:** locked · **Mode:** C · **Priority:** P2
> **Path:** spc-441 → tkt-442..449 → pr-…

## Why

A systematic project review against industry best practices identified 12 findings across 4 dimensions (shell quality, test coverage, architecture, GitHub/CI). After manual verification, 2 were false positives (the `set -euo pipefail` gap was overstated — 52/69 scripts have it; the "legacy backtick" is inside a heredoc). The remaining findings are real and range from a concrete security vulnerability (expression injection in CI) to maintainability improvements.

## In scope

- Fix GHA expression injection in `finish-stamp.yml`
- Eliminate `eval "$(python3 ...)"` pattern (8 call sites across 4 files)
- Add macOS runner to CI matrix
- Test `intercept-gh-issue-create.sh` (only untested hook)
- Add `.github/CODEOWNERS`
- Extract duplicated `_lattice-home.sh` walk-up loop into shared function
- Split `intercept-shippable-write.sh` L3 status-row guard into own file
- Add `evals/routing/README.md`

## Out of scope

- Adding `set -euo pipefail` to hooks/plugin scripts (by design: hooks must exit 0)
- ShellCheck linting `.bats` files (low priority, no confirmed bugs)
- Python-specific test job (bats wrappers are adequate)
- Lifecycle e2e negative paths (documented follow-up in the test file itself)

## Acceptance

- [ ] **A1** `finish-stamp.yml` routes `inputs.repo` and `inputs.base` through env vars, not direct `${{ }}` interpolation in `run:` blocks
- [ ] **A2** All 8 `eval "$(python3 ...)"` sites replaced with `read`-based or `jq`-based variable assignment; no `eval` on external data remains
- [ ] **A3** CI runs bats suites on both `ubuntu-latest` and `macos-latest`
- [ ] **A4** `intercept-gh-issue-create.sh` has a bats test file covering block/allow paths
- [ ] **A5** `.github/CODEOWNERS` exists with entries for `plugins/lattice/hooks/`, `.github/workflows/`, and `tools/`
- [ ] **A6** The `_lattice-home.sh` walk-up pattern in `alignment-check.sh`, `ci-gate-check.sh`, `queue-health.sh` is replaced by a single shared function
- [ ] **A7** `intercept-shippable-write.sh` L3 status-row guard is in a separate file; existing tests still pass
- [ ] **A8** `evals/routing/README.md` documents the eval tiers and how to run them

## Decisions (principal, user-confirmed)

1. Full sweep scope confirmed by user — all verified findings, not just security-only.
2. `eval` elimination uses `read`-based assignment (not `jq`) where the Python script already exists — avoids adding a new dependency pattern.
3. CODEOWNERS targets the three most security-sensitive directories, not every skill.

## Risks / open questions

- A2 (eval elimination) touches 4 files in the finish-work hot path — needs thorough bats coverage before merge.
- A3 (macOS CI) may surface BSD vs GNU flag differences that need fixing — accept as follow-up if non-trivial.
- A7 (hook split) changes the plugin hook structure — needs plugin version bump consideration.

## References

- Review artifact: Lattice Project Review (2026-09-03, this session)
- ADR-007: hard-limit scope law (relevant to hook guarantee boundaries)

## Links / bloodline (L0)

- Primary: [#441](https://github.com/percena/lattice/issues/441)
- Tickets: (pending create-tickets)
- PRs: (pending)
- Reviews: (none)
