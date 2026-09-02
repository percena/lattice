---
# status: draft | locked | done | superseded
id: spc-398
slug: ci-cd-structural-fixes
title: CI/CD structural fixes — branch protection + PreToolUse hook + ci-local.sh bats gate
kind: feat
status: locked
mode: C
priority: P1
summary: "Break the recurring bats CI failure cycle: dev branch protection, PreToolUse .bats hook, ci-local.sh --fast fix, finish-ledger backfill automation"
created: 2026-09-02
updated: 2026-09-02
tickets: []
prs: []
reviews: [rev-20260902-080545Z]
supersedes: []
superseded_by: null
---

# Spec: CI/CD structural fixes

> **TL;DR:** Dev branch has no required status checks — PRs merge with bats=FAILURE 20+ times. Fix: branch protection + PreToolUse hook for .bats writes + ci-local.sh --fast no longer silently skips bats + finish-ledger pr-open→closed backfill.
> **Kind:** feat · **Status:** locked · **Mode:** C · **Priority:** P1
> **Path:** rev-20260902-080545Z CI/CD deep dive → spc-398 → tkt-…

## Why

The `bats` CI check has been red on dev for 20+ PRs. Each time a new `.bats` file introduces a banned `[[ ]]` assertion (exempt from `set -e`), `check-bats-assertions.py` catches it in CI, but the PR merges anyway — polluting CI for every subsequent PR until someone fixes it manually. The tactical fix (PR #397, tkt-390) cleared the current violation, but without structural changes the cycle will repeat on the next `.bats` file.

Root cause analysis (verified by code review + CI log inspection):

1. **No branch protection on dev** — `required_status_checks: {}`. A PR can be `gh pr merge --squash`'d regardless of CI status. This is the single biggest enabler.
2. **No repo-level PreToolUse Write hook for .bats files** — authors writing a new `.bats` file never see the assertion guard until CI runs.
3. **`ci-local.sh --fast` silently skips bats** — a local escape hatch that means `ci-local.sh --fast` never runs the assertion guard, so the violation is invisible locally.
4. **finish-ledger pr-open→closed gap** — `finish-ledger.sh` stamps the binder to `closed` but never appends the `pr-open→closed` transition ledger entry, causing a recurring `transition_ledger_snapshot_mismatch` validator error on every merged ticket.

## In scope

- dev branch protection: add `bats` and `lattice-artifacts` as required status checks
- PreToolUse Write hook: `.claude/settings.json` entry that runs `check-bats-assertions.py` on any `.bats` file write
- `ci-local.sh` `--fast`: warn (not silently skip) that bats is skipped, or run a quick assertion-only sub-check
- finish-ledger: append the `pr-open→closed` transition entry (or document why the ledger gap is acceptable and backfill at merge time)

## Out of scope

- Rewriting `check-bats-assertions.py` or the bats test framework
- Adding branch protection to `main` (dev is the integration branch; main merges are rare and operator-driven)
- Removing `ci-local.sh --fast` entirely (useful for quick non-bats checks)
- Rewriting `finish-ledger.sh` (the backfill is a targeted fix, not a rewrite)

## Acceptance

- [ ] **A1** dev branch has required status checks (`bats`, `lattice-artifacts`) — a PR with a failing check cannot merge via `gh pr merge`
- [ ] **A2** PreToolUse Write hook for `.bats` files runs `check-bats-assertions.py` on the staged file before the write lands — catches banned assertion forms at authoring time
- [ ] **A3** `ci-local.sh --fast` no longer silently skips bats — either warns loudly or runs a quick `check-bats-assertions.py` sub-check (the assertion guard is fast: <1s on 75 files)
- [ ] **A4** finish-ledger stamps the `pr-open→closed` transition ledger entry (or an equivalent backfill runs at merge time) — no more recurring `transition_ledger_snapshot_mismatch` on merged tickets

## Non-goals

- Making the assertion guard a pre-commit hook (PreToolUse is the Lattice-native enforcement; pre-commit is a separate concern)
- Changing the `empty_step` waiver loophole in `ci_failure_classify.py` (verified: it doesn't apply to real bats failures with logs — the merges happened due to no branch protection, not the waiver)

## Decisions (principal, user-confirmed)

1. Branch protection on dev (not main) — dev is the integration branch where PRs land; main merges are rare and operator-driven.
2. PreToolUse Write hook scoped to `.bats` files only — not all skill scripts (avoids false positives on sourced `.sh` files).
3. `ci-local.sh --fast` keeps the fast path but adds a quick assertion-only sub-check (not a full bats run) — the guard runs in <1s on 75 files.
4. finish-ledger backfill is a targeted fix in `finish-ledger.sh` (append the transition entry), not a `transition-api.py` rewrite.

## Agent-assumed (secondary)

- The PreToolUse hook uses `tools/check-bats-assertions.py <file>` (already exists, single-file mode supported).
- Branch protection is configured via `gh api` (no GitHub UI needed).
- `ci-local.sh --fast` adds `python3 tools/check-bats-assertions.py` before the skip, not a full `bats` run.

## References

- Root cause analysis: `rev-20260902-080545Z` CI/CD deep dive (spc-369 lineage audit)
- Tactical fix: PR #397 (tkt-390 — `hotspot-metrics.bats:55` `[[ ]]` → `grep -qE`)
- Guard: `tools/check-bats-assertions.py` (tkt-167)
- CI workflow: `.github/workflows/lattice-scripts.yml`
- Validator: `tools/validate-lattice-artifacts.py`
- Classifier: `skills/finish-work/scripts/lib/ci_failure_classify.py`
- Local CI: `tools/ci-local.sh` (`--fast` flag)
- ADR-007 §5a (CI gate classification — compiled corner cases)
