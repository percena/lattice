---
# status: draft | locked | done | superseded
id: spc-212
slug: python3-friendly-guard
title: Make python3 dependency explicit and user-friendly across Lattice skills
kind: chore
status: done
mode: M
priority: P1
summary: "Add ensure-python3.sh guard + hook advisory so missing python3 fails with a friendly install hint instead of a cryptic mid-script error"
created: 2026-08-29
updated: 2026-08-29
tickets: [tkt-213]
prs: [pr-214]
reviews: []
supersedes: []
superseded_by: null
---

# Spec: Make python3 dependency explicit and user-friendly across Lattice skills

> **TL;DR:** Keep Python (stdlib-only, not removable); add a guard helper so missing `python3` prints a platform-specific install command and exits cleanly, add a fail-open advisory to plugin hooks, and document the prerequisite — instead of today's cryptic mid-script `command not found`.
> **Kind:** chore · **Status:** done · **Mode:** M · **Priority:** P1
> **Path:** spc-212 → tkt-… → pr-…

## Why

Lattice skills and plugin hooks invoke `python3` in ~28 inline `python3 -c` calls across `skills/*.sh` plus 18 stdlib-only `.py` files. `python3` is **not** guaranteed present on every platform Claude Code supports:

- **macOS without Xcode CLT** — `/usr/bin/python3` is a stub that triggers a GUI dialog; it fails silently in non-interactive / SSH / Claude Code Bash-tool contexts.
- **Arch Linux** — `python3` was removed from the `base` meta-package (~mid-2024).
- **Alpine Linux / minimal Docker images** — no python by default.
- Claude Code itself is a native binary and does **not** bring python3 along on any platform.

Current behavior splits cleanly into two cases:

1. **Plugin PreToolUse hooks** (`plugins/lattice/hooks/intercept-*.sh`) already fail-open on missing python3 (via `|| exit 0` and inline `command -v python3`). Good — they never block git/gh ops. But the degradation is **silent**: in strict profile a bare `gh pr merge` with no python3 is allowed with no warning, so the user does not know their guardrail is inactive.
2. **Skill `.sh` scripts** call `python3` inconsistently. A few guard well (`ensure-workspace.sh`, `alignment-check.sh`, `ci-gate-check.sh` hard-exit; `check-duplicate-work.sh` degrades gracefully). But ~13 scripts call `python3` with **no guard** (finish-ledger, stamp-pr-open, ratify, spec-supersede, reconcile-state, bump-fix-cycle, queue-health, upload-github-asset, build-review-context, ensure-lattice, close-fixed-issues, update-pr-base, cleanup-workspace). When python3 is absent these emit a bare `python3: command not found` mid-execution and leave a half-finished operation with zero guidance — the worst UX outcome.

## In scope

- New `ensure-python3.sh` helper under `_lattice-lib/scripts/` — standalone-callable, detects `command -v python3`, prints a platform-specific install command, exits nonzero on absence and 0 silently on presence.
- One-call guard at entry of each currently-unguarded python3-using skill script (fail-closed path), or graceful degrade where the script can meaningfully degrade.
- Plugin PreToolUse hook fail-open **advisory** stderr warning (one-time per invocation) when python3 is absent — never block ops.
- README + skill install docs add a one-line prerequisite.

## Out of scope

- Rewriting the 18 `.py` files to bash.
- Replacing the inline `python3 -c` JSON blocks with `jq`.
- Changing already-graceful scripts (`check-duplicate-work.sh`) or already-hard-guarding scripts (`ensure-workspace.sh`, `alignment-check.sh`, `ci-gate-check.sh`).

## Acceptance

- [x] **A1** — `ensure-python3.sh` exists under `_lattice-lib/scripts/`; `command -v python3` present → exit 0 silently; absent → print a platform-specific install command (macOS / Arch / Alpine / Debian·Ubuntu·Fedora) to stderr and exit nonzero.
- [x] **A2** — No previously-unguarded python3-using skill script remains that emits a bare "command not found": each either calls `ensure-python3.sh` (fail-closed) or degrades gracefully.
- [x] **A3** — Plugin PreToolUse hooks emit a one-time stderr advisory when python3 is absent ("Lattice guardrails degraded: strict-profile protections inactive. Install python3: …") and still allow the tool call (fail-open preserved).
- [x] **A4** — README + skill install docs state: "Requires bash + python3 (stdlib only, no pip)."
- [x] **A5** — No regression: already-graceful scripts unchanged; already-hard-guarding scripts still guard; hook fail-open semantics preserved.

## Decisions (principal, user-confirmed)

1. **D1 — Keep Python; do not rewrite to bash.** The 18 `.py` files are stdlib-only and do regex shell-command normalization, transcript-DAG traversal, and a 1106-line contract validator; bash reimplementations would be impractical and would lose the vendoring posture ("consumer repo can vendor it alone").
2. **D2 — Do not replace inline `python3 -c` JSON blocks with `jq`.** Replacing them does not eliminate the python3 requirement (the `.py` files and plugin hooks still need it), adds `jq` as a net-new dependency, and splits the multi-field JSON parse consistency that the inline python blocks preserve.
3. **D3 — Guard behavior split.** Skill scripts that need python3 to do real work → fail-closed with the friendly install message. Plugin guardrail hooks → fail-open with a one-time advisory; **never** block git/gh ops (blocking user operations because a guardrail's own python is missing is hostile).
4. **D4 — Helper is standalone-callable, not a sourced lib.** No single sourced common file reaches all python3 call sites today (`_lattice-home.sh` is sourced by ~11 scripts but not all, and even those still make unguarded python3 calls elsewhere), so a sourced guard would not reach everywhere.

## Risks / open questions

- Verify each of the ~13 unguarded scripts: some may be able to degrade gracefully rather than fail-closed (e.g. `queue-health.sh` is advisory). Decide per-script during ticket implementation.
- Ensure the plugin-hook advisory fires **once** per hook invocation, not once per python3 subprocess call, to avoid noise.

## References

- Issue: #212 (primary, `epic`)
- Prior Spec: none
- ADR: none

## Links / bloodline (L0)

- Tickets: (to be split by `create-tickets`)
- PRs: (prefer GitHub `Fixes`/`Refs`)
- Reviews: (none yet)
