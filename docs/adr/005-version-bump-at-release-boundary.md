# ADR 005: Version bump enforced at dev→main release boundary, not per-PR on dev

- **Status:** Accepted
- **Date:** 2026-08-27
- **Deciders:** maintainer (M1n9X)
- **Related:** `tools/validate-plugin-versions.py`, `tools/ci-local.sh`, `.github/workflows/lint-heavy.yml`, `skills/batch-work/`, `skills/finish-work/`, tkt-60, tkt-114, rev-20260826-145922Z-18p
- **Related ADRs:** (none)

## Context

Claude Code plugins use the manifest `version` field as a **cache-busting key**: the plugin loader resolves cache paths as `~/.claude/plugins/cache/{marketplace}/{name}/{version}`. If bundled content changes but the version stays the same, a downstream user who already cached that version will never re-fetch — they silently consume stale content. This makes **"content changed ⟹ version must increase"** a hard invariant imposed by the plugin mechanism, not a project preference.

`validate-plugin-versions.py` currently enforces this invariant on **every PR/push landing on `dev`** (the "strict per-landing law"): `bundle_changed and manifest_version == previous_version ⟹ error`. This enforcement granularity created a structural conflict with `batch-work` parallel delivery. When N train PRs ship the same version cut, after the first merges, later heads compare equal-version against the already-bumped base and go red — "bundled content changed without a version increment."

The project compensated with an increasingly complex **release-train** mechanism:

1. **tkt-60 / PR #68** — `train_cut_shared()`: accept equal-version when version-file blobs are byte-identical between head and base (a shared cut), with SemVer still increased since the fork.
2. **tkt-114 / PR #115** — linear-push guard: when `merge_base == base_oid` (dev push events), accept the equal version iff base already carries an unreleased train bump relative to `origin/main`; restore strict law post-promotion.
3. **batch-work spawn-brief contract item 6** — the orchestrator commits ONE byte-identical version cut to every train branch so sequential merges auto-resolve.
4. **batch-work flow §stacked dependencies** — octopus-merge prohibition motivated by "byte-identical version cuts across train branches abort an octopus."

Each layer compensates for a rule whose granularity (per-PR on an integration branch that does not face any user's cache) does not match the actual release model. `dev` is an integration branch; `dev→main` promotion is **manually triggered**. No downstream consumer ever pulls a `dev` version's cache path. Enforcing the cache-busting invariant on `dev` landings is therefore enforcing it against a state that has no cache consumers — pure false-positive pressure.

## Decision Drivers

- The cache-busting invariant is real and must hold **at the point content reaches users** — the dev→main release boundary.
- `dev→main` promotion is manually triggered; the operator controls release cadence and can batch multiple PRs into one release.
- Per-PR enforcement on `dev` has no cache consumer to protect and generates recurring CI red that the train mechanism was built solely to suppress.
- The train mechanism (tkt-60 + tkt-114 + orchestrator cut + flow prose) is ~3 layers of complexity compensating for one over-granular rule.
- Machine-checkability: the gate must be deterministic, not subjective ("is this change complex enough to bump?").

## Considered Options

- **Option A — Enforce at dev→main boundary (chosen).** Validator strict law fires only when `--base-ref` resolves to `origin/main` / last release; `dev` landings enforce only "version must not decrease." Retire the entire train mechanism. Good: eliminates 3 compensation layers, matches the release model, keeps the invariant where it matters. Bad: requires reworking CI base-ref logic and finish-work gate (new surface area).
- **Option B — Per-PR bump keyed on change complexity (rejected).** Let the operator decide whether a PR is "complex enough" to warrant a version bump. Bad: subjective, not machine-checkable, and will miss cache-invalidating changes that look small (e.g. a one-line manifest fix) — violating the hard invariant.
- **Option C — Pure manual, no gate (rejected).** Trust the operator to bump at dev→main with no automated check. Bad: relies on human memory; the validator exists precisely because this was unreliable.

## Decision

We will enforce the version-increment invariant **only at the dev→main release boundary**. Concretely:

1. `validate-plugin-versions.py` strict law ("bundled content changed without a version increment") fires only when the base-ref resolves to the default branch (`origin/main` / `main`) or a release tag. On `dev` (base-ref is a fork point / dev ancestor), the validator enforces only the **non-decrease** hard bottom: `manifest_version < previous_version ⟹ error`.
2. **Retire the release-train mechanism in full:** delete `train_cut_shared()`, the `--no-train` flag, the linear-push guard, and all train-related test fixtures.
3. **batch-work** loses its spawn-brief contract item 6 (release-train version policy) and the orchestrator's unified-cut step; parallel tickets no longer coordinate on version/changelog — bump is deferred to release.
4. **finish-work** gains a new dev→main pre-merge step: when the PR targets `main` and bundled paths changed, check that version increased relative to the last release before merging; surface to the operator on failure.
5. **ci-local** defaults to dev-mode (lenient: non-decrease only); `--release-check` flag simulates the main-boundary strict pass.
6. The cache-busting invariant's single enforcement point is the dev→main edge, which is manually triggered — the operator controls release cadence and batches bumps naturally.

## Consequences

- **Positive:** Eliminates ~3 layers of compensation complexity (`train_cut_shared`, linear-push guard, orchestrator unified-cut, spawn-brief contract item 6, train flow prose). CI red on dev during batch delivery disappears by construction — no transient to suppress. The invariant holds exactly where it has a consumer.
- **Negative / trade-offs:** CI base-ref semantics in `lint-heavy.yml` become context-sensitive (PR→dev vs PR→main) — the highest-risk change. finish-work gains a new gate (new surface to maintain). ci-local's dual-mode adds a flag. Historical artifacts (tkt-60, tkt-114 binders, Reviews) record the old mechanism — they stay as audit trail, not updated.
- **Follow-ups:** Spec + tickets to implement (cite forthcoming spc-N / tkt-N). CHANGELOG entry recording the train retirement.
- **Verification:** `tools/tests/plugin-versions.bats` — dev-mode equal-version-with-bundle-change passes; release-boundary equal-version-with-bundle-change fails; non-decrease still enforced on dev. `lint-heavy.yml` green on dev merges and on main-target PRs.

## Status history

- 2026-08-27: Proposed

## Notes

Origin of the per-landing law: `validate-plugin-versions.py` initial baseline (commit `cc91bac`, docstring L5–6). The train mechanism was introduced by tkt-60 / PR #68 (rev-20260826-145922Z-18p Finding 1) and patched by tkt-114 / PR #115 (rev-20260827-033352Z-post-round4-verified-audit). The 0.3.0 release used the train cut ("#105 owns the bump and this entry; the round's other bundled PRs carry byte-identical version files" — `CHANGELOG.md`). This ADR supersedes the design intent behind those tickets; the ticket binders remain as historical record.

---

_Not a Lattice bloodline/graph node. Cite from Spec/PR/Review with `ADR-005` or this path._
