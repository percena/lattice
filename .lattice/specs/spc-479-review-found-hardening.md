---
# status: draft | locked | done | superseded
id: spc-479
slug: review-found-hardening
title: Review-found hardening sweep — alignment-gate --home, autonomy regex case, artifacts CI trigger
kind: bug
status: locked
mode: C
priority: P1
summary: "Fix three dev-landed review-found defects: alignment-check --home clobber, autonomy regex case mismatch, artifacts.yml PR path filter"
created: 2026-09-05
updated: 2026-09-05
tickets: [tkt-480]
prs: []
reviews: []
supersedes: []
superseded_by: null
---

# Spec: Review-found hardening sweep

> **TL;DR:** Three independent, dev-landed defects surfaced by a full review of `80f3701..origin/dev` — a merge-gate `--home` clobber regression (tkt-447), a validator/filter autonomy-regex case disagreement, and an artifacts.yml PR path-filter that structurally blocks all code/docs-only PRs from merging.
> **Kind:** bug · **Status:** locked · **Mode:** C · **Priority:** P1
> **Path:** spc-479 → tkt-… → pr-…

<!-- required -->
## Why

A complete review of the `80f3701..origin/dev` changeset (post round-2 follow-up) found three small, independent defects already landed on `dev`. None are caught by current tests (the alignment-check bats `setup()` masks A1; the autonomy template is lowercase so conformant binders mask A2; branch protection masks A3 as a "missing check" rather than a failure). Left in place, A1 silently breaks the finish-work merge-gate integrity (scans the wrong binders when `--home` is passed with `LATTICE_HOME` unset), A2 makes the autonomy filter and validator disagree on the same binder row (so `batch-work --min-autonomy` can skip a genuinely-qualifying ticket), and A3 permanently blocks every code/docs-only PR from merging (already blocking PR #478).

<!-- recommended -->
## In scope

- **A1 — `skills/finish-work/scripts/alignment-check.sh:70`**: restore the `if [[ -z "$HOME_DIR" ]]` guard around `source_lattice_home_and_resolve`, mirroring the sibling `ci-gate-check.sh:84` which kept it through the tkt-447 refactor (PR #457). A caller-supplied `--home` must not be clobbered by `lattice_default_home` (which only honors `LATTICE_HOME` / `$git_root/.lattice`).
- **A2 — `skills/batch-work/scripts/autonomy-filter.py:30`**: add `re.I` to `AUTONOMY_ROW_RE` so it matches `tools/validate-lattice-artifacts.py:322` (`AUTONOMY_TABLE_RE`), which already has `re.I | re.M`. The two consumers of the same row must not silently disagree on case.
- **A3 — `.github/workflows/artifacts.yml`**: broaden the `pull_request` trigger so the required `lattice-artifacts` branch-protection check runs on every PR, not only when `.lattice/**` / the validator / the workflow file itself changes. Drop the `pull_request` path filter (the validator already validates the whole `.lattice` tree; running it broadly is cheap and correct).

<!-- recommended: what this delivery will not do -->
## Out of scope

- #470 / #471 red-PR failures (bare `! cmd` assertions in `finish-stamp-ci.bats`; coordinator heartbeat/refused-transition tests 610/612/613/614) — those belong to their own tickets/branches.
- #478's five unmet acceptance items (#472 items 4,5,6,7 + #474 item 4) — Track B, handled via Refs + follow-up tickets, not here.
- The `lattice-scripts.yml` bats push-trigger coverage question (separate, non-blocking) — flagged in the review, not addressed here.

<!-- required (C: use stable A* ids for light RTM; tickets declare covers) -->
## Acceptance

- [ ] **A1** `alignment-check.sh --pr N --home /some/worktree/.lattice` (with `LATTICE_HOME` unset) resolves HOME_DIR to the supplied path, not to `$git_root/.lattice`; the merge gate scans the binders at the supplied home. Mirrors `ci-gate-check.sh:84`. Regression test covers the `LATTICE_HOME`-unset + `--home`-set case (the gap that let the original regression land).
- [ ] **A2** `autonomy-filter.py` matches `| Autonomy | 4 |` (capital A) the same as `| autonomy | 4 |`; a bats test asserts both forms resolve to score 4, and asserts the filter and `validate-lattice-artifacts.py` agree on the same row.
- [ ] **A3** A PR that touches only `skills/**` / `docs/**` / `tools/**` (no `.lattice/**`) triggers the `lattice-artifacts` workflow on `pull_request`; the check passes (validator exits 0, legacy baseline warnings unchanged). A static regression test asserts the `artifacts.yml` `pull_request` trigger has no path filter (or a path set that includes the code/docs paths).

<!-- optional -->
## Non-goals

- Rewriting `lattice_default_home` to consult the caller's `--home` — the fix is the guard at the call site, not changing the shared resolver's contract.
- Making `lattice-artifacts` required on `main` — only the `dev` protection (the integration branch) is in scope; `main` policy is out of scope.

<!-- recommended: feature-local only. Cross-feature / system-shape → docs/adr/NNN -->
## Decisions (principal, user-confirmed)

1. **One ticket / one worktree / one PR** for all three defects — they are small, independent, dev-landed, low-coupling, same review-found-hardening theme. Bundling respects worktree discipline (no serial single-branch) without over-splitting.
2. **A3 fix = drop the `pull_request` path filter** (run the validator on every PR), not "add `skills/**`/`docs/**` to the path filter" — the validator already validates the whole `.lattice` tree, so running it on every PR is correct and cheaper than maintaining a path allowlist that will drift. User-confirmed (Track A selection).
3. **A1 fix mirrors the sibling, does not refactor the shared `source_lattice_home_and_resolve`** — the shared resolver's unconditional `HOME_DIR=$(lattice_default_home …)` is correct for callers that did not supply `--home`; the guard belongs at the `alignment-check.sh` call site to preserve the pre-tkt-447 behavior.

<!-- optional -->
## Agent-assumed (secondary)

- A3: the `push` trigger path filter on `artifacts.yml` is left intact (push only needs to run when artifacts actually change); only the `pull_request` trigger is broadened. Correct me if push should also be broadened.

<!-- optional; empty or explicitly accepted before status: locked; set done when delivery complete -->
## Risks / open questions

- Broadening A3 means `lattice-artifacts` runs on every PR (≤10 min timeout, ubuntu-latest). Cost is acceptable; if PR volume spikes, revisit.

<!-- recommended -->
## References

- Review: full review of `80f3701..origin/dev` (this session, not a durable rev- artifact)
- Regression source: tkt-447 / PR #457 (`refactor(tkt-447): extract shared resolve_lattice_lib_scripts function`)
- Related Spec: spc-475 (round-2 follow-up epic) — Track A is **not** under spc-475 (different scope); listed only for context.
- ADR: (none)

<!-- required lists in front matter; body is recovery -->
## Links / bloodline (L0)

- Primary issue: #479 (epic)
- Tickets: (to be created via create-tickets — bare ids in front matter)
- PRs: (to be created via create-pr)
- Reviews: (none durable)
