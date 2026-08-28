---
# status: draft | locked | done | superseded
id: spc-116
slug: retire-release-train
title: Retire release-train mechanism — version-bump enforcement moves to dev→main release boundary
kind: refactor
status: done
mode: C
priority: P1
summary: "Move plugin version-bump gate from per-PR (dev) to dev→main release boundary; retire train_cut_shared + --no-train + orchestrator cut"
created: 2026-08-27
updated: 2026-08-27
tickets: [tkt-117, tkt-118, tkt-119, tkt-120]
prs: []
reviews: []
supersedes: []
superseded_by: null
---

# Spec: Retire release-train mechanism — version-bump enforcement moves to dev→main release boundary

> **TL;DR:** The strict per-landing version law fires only at the dev→main release boundary (where user caches exist), not on every dev merge; the entire train compensation mechanism (`train_cut_shared`, `--no-train`, linear-push guard, orchestrator unified-cut, spawn-brief item 6) is retired.
> **Kind:** refactor · **Status:** done · **Mode:** C · **Priority:** P1
> **Path:** spc-116 → tkt-… → pr-…

## Why

Claude Code plugins use the manifest `version` field as a cache-busting key: cache paths are `~/.claude/plugins/cache/{marketplace}/{name}/{version}`. If bundled content changes but the version stays the same, a cached user silently consumes stale content. This makes "content changed ⟹ version must increase" a hard invariant — but only at the point content reaches users.

`validate-plugin-versions.py` currently enforces this invariant on **every PR/push landing on dev** (the "strict per-landing law"). This conflicts structurally with batch parallel delivery: N train PRs share one version cut → after the first merges, later heads compare equal-version against the bumped base and go red. The project compensated with an increasingly complex release-train mechanism:

- **tkt-60 / PR #68** — `train_cut_shared()`: accept equal-version when version-file blobs are byte-identical between head and base.
- **tkt-114 / PR #115** — linear-push guard: accept equal-version when base already carries an unreleased train bump vs `origin/main`.
- **batch-work spawn-brief contract item 6** — orchestrator commits ONE byte-identical version cut to every train branch.
- **batch-work flow §stacked deps** — octopus-merge prohibition motivated by version-cut conflicts.

`dev` is an integration branch with **no cache consumers** — `dev→main` promotion is manually triggered. Enforcing the cache-busting invariant on dev landings is false-positive pressure against a state that never reaches a user's cache. The train mechanism exists solely to suppress these false positives. **ADR-005** locks the fix: enforce at the dev→main boundary; dev landings enforce only the non-decrease hard bottom.

## In scope

1. **`validate-plugin-versions.py`** — delete `train_cut_shared()` (~45 lines), `--no-train` flag, linear-push guard; strict "bundled content changed without increment" fires only when base-ref resolves to `origin/main`/`main`/release tag; dev landings (fork-point base) enforce only non-decrease; update docstring
2. **`tools/tests/plugin-versions.bats`** — delete 6 train test fixtures (`train_cut_fixture` + 3 shared-cut tests, `linear_train_fixture` + 3 linear-push tests); add dev-mode-passes + release-boundary-fails + non-decrease-enforced tests
3. **`.github/workflows/lint-heavy.yml`** — base-ref context-sensitive: PR→dev uses fork point (lenient), PR→main / push→main uses `origin/main` (strict)
4. **`tools/ci-local.sh`** — default dev-mode (lenient: non-decrease only); add `--release-check` flag for strict release-boundary simulation
5. **`skills/batch-work/SKILL.md`** — delete spawn-brief contract item 6 (release-train version policy)
6. **`skills/batch-work/references/flow.md`** — delete `[Release train only] VERSION POLICY` block (L146–149), delete orchestrator unified-cut step (§stacked deps point 3, L205), fix octopus-merge rationale (L203) to not reference version cuts
7. **`skills/finish-work/references/flow.md`** — rewrite §3.4 (remove "Merge trains" / train semantics), delete "train-transient red" concept (L225), add new dev→main pre-merge version-bump check step
8. **`skills/create-tickets/references/policy.md`** — rewrite implicit shared files paragraph (L113): version/changelog no longer per-PR coordination, deferred to release boundary
9. **`CONTRIBUTING.md`** — rewrite step 14 (L62) to "Version bump at dev→main merge, not per-PR"; clarify base-ref semantics (L37)
10. **`tools/README.md`** — update validator description (L11) to note release-boundary enforcement
11. **`CHANGELOG.md`** (root + `plugins/lattice/CHANGELOG.md`) — add train retirement entry under Unreleased

## Out of scope

- Historical artifacts (tkt-60, tkt-114 binders, Reviews) — unchanged as audit trail
- ADR-005 body — already written, not modified by this Spec
- No new automatic bump script — version bump remains a manual file edit; the gate is automated (finish-work detects, operator edits)
- No version number change to the plugin itself (this is a tools/workflow refactor, not a bundled-content change)

## Non-goals

- Will not change the plugin cache mechanism itself (that is Claude Code's contract)
- Will not introduce per-PR complexity-based bumping (subjective, not machine-checkable — rejected in ADR-005)

## Acceptance

- [x] **A1** — validator strict law ("bundled content changed without a version increment") fires only when base-ref resolves to `origin/main`/`main`/release tag; when base-ref is a fork point / dev ancestor (dev landing), equal-version-with-bundle-change passes
- [x] **A2** — non-decrease bottom enforced on both modes: `manifest_version < previous_version ⟹ error` (existing logic L517–529 preserved)
- [x] **A3** — `train_cut_shared()` function, `--no-train` CLI flag, linear-push guard branch, and `train_cut` output field all deleted; no train code remains in `validate-plugin-versions.py`
- [x] **A4** — bats suite: dev-mode equal-version-with-bundle-change **passes**; release-boundary equal-version-with-bundle-change **fails**; non-decrease enforced on both modes; all non-train tests unchanged
- [x] **A5** — `lint-heavy.yml` green on dev merges (lenient, no false red) AND on main-target PRs (strict, catches missing bump)
- [x] **A6** — `ci-local.sh` default is lenient (dev-mode: non-decrease only); `--release-check` flag triggers strict release-boundary validation against `origin/main`
- [x] **A7** — `skills/batch-work/SKILL.md`, `skills/batch-work/references/flow.md`, `skills/finish-work/references/flow.md`, `skills/create-tickets/references/policy.md` contain zero references to "release-train", "train_cut", "train mode", "--no-train", or "version cut"
- [x] **A8** — `skills/finish-work/references/flow.md` has a new dev→main pre-merge step: when PR targets `main` and bundled paths changed, check version increased relative to last release before merging; surface to operator on failure (bump is manual, gate is automated)
- [x] **A9** — `CONTRIBUTING.md` step 14 and base-ref examples reflect release-boundary enforcement; `tools/README.md` validator description updated
- [x] **A10** — CHANGELOG (root + plugin) has a train-retirement entry under Unreleased

> Land-stamp (2026-08-27, tkt-151): A1–A10 shipped 2026-08-27 via PR #125 (base `dev`); issues #117–#120 closed the same minute (tkt-117 validator core, tkt-118 skill docs, tkt-119 CI+ci-local, tkt-120 project docs). Validator code verified train-free (0 `train_cut`/`--no-train`/linear-push matches); listed docs verified train-term-free; `ci-local.sh` carries `--release-check`; finish-work §3.4.1 carries the dev→main pre-merge check; CONTRIBUTING step 14 + root+plugin CHANGELOG entries present. Stamped retroactively under tkt-151 (spec drift repair) — the front-matter `status: done` was set at landing but the TL;DR display and Acceptance checkboxes had drifted to stale `locked`/unchecked.

## Decisions (principal, user-confirmed)

1. **ADR-005** — Enforce version-increment invariant at dev→main release boundary only; dev landings enforce non-decrease. `--base-ref` pointing to `origin/main`/`main` = strict mode; fork point / dev ancestor = lenient mode. (user-confirmed)
2. **finish-work auto-detect gate** — finish-work checks bundle-changed-without-bump before merging to main. The bump itself remains a manual file edit (no new bump script); the gate is automated and surfaces to the operator. (user-confirmed)
3. **ci-local default lenient** — `ci-local.sh` defaults to dev-mode (non-decrease only); `--release-check` flag simulates the main-boundary strict pass. (user-confirmed)

## Agent-assumed (secondary)

- Validator distinguishes dev-mode vs release-mode by inspecting whether the resolved base-ref is reachable from `origin/main` (release boundary) or is a fork-point/ancestor within dev (integration). Implementation detail; reversible.
- `--release-check` in ci-local maps to `--base-ref origin/main` on the validator. Implementation detail; reversible.

## Risks / open questions

- **CI base-ref semantics (highest risk):** `lint-heavy.yml` L44 currently uses `github.event.pull_request.base.sha || github.event.before`. Making this context-sensitive (dev vs main) requires careful GitHub Actions expression logic — a bug here could either suppress real reds on main or reintroduce false reds on dev. Mitigation: bats-level CI simulation + careful review.
- **finish-work gate placement:** the new version-bump check must slot into finish-work's existing merge flow without conflicting with the CI-checks gate (§3.4 rule 1). The check runs after CI green, before the merge commit.
- **Transition state:** any in-flight train PRs (if batch-work is mid-run when this lands) would lose the train acceptance path. Mitigation: land this when no batch is in flight, or document the transition.

## References

- ADR: `ADR-005` → `docs/adr/005-version-bump-at-release-boundary.md`
- Prior tickets: tkt-60 (train mode origin, PR #68), tkt-114 (linear-push fix, PR #115)
- Reviews: `rev-20260826-145922Z-18p` (Finding 1 — original train red), `rev-20260827-033352Z-post-round4-verified-audit` (train-mode evidence + recurring red class)

## Links / bloodline (L0)

- Tickets: tkt-117 (validator core, G1), tkt-118 (skill docs, G1), tkt-119 (CI+ci-local, G2, blocked_by tkt-117), tkt-120 (project docs, G2, blocked_by tkt-117+tkt-118)
- PRs: (to be opened)
- Reviews: `rev-20260826-145922Z-18p`, `rev-20260827-033352Z-post-round4-verified-audit`
