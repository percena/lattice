# ADR 002: Lattice skill-gap bridge — ERP pattern adaptation strategy

- **Status:** Proposed
- **Date:** 2026-08-25
- **Deciders:** maintainers
- **Related:** `spc-12`, `rev-20260825-072540Z`
- **Related ADRs:** (none)

## Context

A cross-comparison review (`rev-20260825-072540Z`) examined 7 FlowDance ERP skills (`request-feature`, `report-bug`, `request-harness`, `implement`, `batch-implement`, `auto-playwright`, `fast-deploy`) against Lattice's 10-skill lifecycle. The review identified 6 borrowable patterns but also identified patterns that should NOT be directly ported because Lattice's architecture is fundamentally different (GitHub-native vs Firestore-native, lighter binder vs 18-step manifest).

The key forces driving this decision:

1. **Lattice is GitHub-native.** GitHub issues are the team SoT for `spc-N` and `tkt-N`. ERP's Firestore-only filing shape (HARNESS-548) — where the `created` event is the durable record and the folder is hydrated into git later — doesn't directly translate. The *principle* (cheap filing, expensive booking) does.
2. **ego-browser already exists** as a Lattice-available skill (`/Users/mxue/GitRepos/infra/ego-lite/skills/ego-browser/SKILL.md`, v1.2.6). Its task-space model inherits the user's live login state without auth fixtures, eliminating the cross-port auth problem (ERP HARNESS-421) that ERP's `auto-playwright` required significant engineering to solve.
3. **Lattice's sibling worktree model** (one worktree per tkt, `ensure-workspace.sh --mode worktree`) already supports concurrent work. `create-tickets` already defines `parallel_group` + independence gates. The infrastructure for batch orchestration exists — the orchestration layer does not.
4. **Lattice's quality side-path** (`review-code`, advice-only) is deliberately lighter than ERP's `guard.sh` step-manifest enforcement (18 steps, required artifacts, `unobtainable_artifacts` declarations). Lattice's binder is artifact-level, not step-level.

## Decision Drivers

- Stay GitHub-native — no new persistence layer for tracking
- Reuse existing Lattice infrastructure (worktree model, review-code contract, alignment-check.sh)
- Avoid cargo-culting ERP patterns that solve problems Lattice doesn't have
- ego-browser is already available and superior to ERP's auto-playwright runtime
- Keep Lattice's lighter binder model — do not import step-level manifest enforcement

## Considered Options

- **Option A — Direct port ERP skills** (Firestore filing, auto-playwright runtime, guard.sh manifest). Good: proven, feature-complete. Bad: architectural mismatch (Firestore vs GitHub, 18-step pipeline vs 6-skill lifecycle), significant rework, cargo-culting patterns that solve non-existent problems.
- **Option B — Lattice-native adaptations** (GitHub-native duplicate-work check, ego-browser e2e story layer, sibling-worktree batch orchestrator, review-code-based deploy gate). Good: reuses existing infrastructure, architecturally consistent, lighter. Bad: less battle-tested than ERP's mature patterns, needs new code.
- **Option C — Hybrid: port ERP scripts, adapt Lattice skills.** Good: leverage ERP's tooling. Bad: ERP scripts are Firestore-coupled (`tracker-events.mjs`, `build-program-dag.mjs`), thin portability.

## Decision

We will adopt **Option B — Lattice-native adaptations.** Specifically:

1. **GitHub-native, not Firestore-native.** Lattice does NOT adopt ERP's Firestore-only filing shape. Duplicate-work precheck will use `gh issue list --state open --search` + `git worktree list` + `gh pr list --state open` — three surfaces (Lattice has no separate tracker queue). The principle of "check before creating" applies; the implementation is GitHub-native.

2. **ego-browser is the approved browser automation foundation.** Lattice does NOT port ERP's `auto-playwright` runtime. ego-browser's task-space login-state inheritance eliminates the cross-port auth problem (HARNESS-421) natively. A thin `e2e-story` reference layer will be built on ego-browser heredoc JS scripts (goto/click/fill/assert/screenshot primitives + fail-loud auth check + structured JSON output), NOT a separate YAML runner or profile management system.

3. **Batch orchestration reuses sibling worktree model.** A `batch-work` skill will read `parallel_group` from create-tickets binders → spawn agents per group (one worktree each, via `ensure-workspace.sh`) → layer-barrier sync → `BATCH_WORK=1` env blocks finish-work merge (only create-pr; human reviews then finish-work). This is NOT ERP's Firestore-based DAG (`build-program-dag.mjs`) — it reuses Lattice's existing worktree + independence-gate infrastructure.

4. **Deploy quality gates reuse review-code contract.** A deploy quality sub-pipeline for `deploy-weftd-flitro` will use `review-code` scan (advice-only) + available tests + diff classification (weftd frontend / flitro+agentd / docs-only → skip), NOT ERP's `guard.sh` step-manifest enforcement or `verify-code` 8-phase gate. The two-gate pattern (Gate 1: scope confirm; unattended review+test; Gate 2: deploy approval) is borrowed in shape.

5. **Step-manifest concept is explicitly deferred.** Lattice's binder stays artifact-level (binder README + Acceptance checkboxes + Finish ledger), NOT step-level. If the `batch-work` skill needs per-worktree progress for layer-barrier sync, a lightweight per-worktree progress file (not a global manifest) will suffice. ERP's `step-manifest.json` + `guard.sh` enforcement is NOT adopted.

## Consequences

- **Positive:**
  - Architectural consistency — all new skills use GitHub as SoT, ego-browser as browser runtime, sibling worktree as workspace model
  - Reuses existing infrastructure (review-code, alignment-check, ensure-workspace, create-tickets parallel_group)
  - ego-browser eliminates an entire category of auth engineering (no storageState rewriting, no profile management, no per-port auth fixtures)
  - Lighter than ERP's equivalent — no Firestore, no guard.sh, no 18-step manifest

- **Negative / trade-offs:**
  - Less battle-tested than ERP's mature patterns (ERP has ~134 skills, HARNESS-XXX iterations)
  - Duplicate-work precheck has 3 surfaces vs ERP's 4 (no separate tracker queue) — slightly lower coverage for filed-but-never-booked duplicates
  - batch-work orchestrator is new code, not proven in production like ERP's batch-implement
  - ego-browser requires the ego lite app running (not headless) — may not fit CI environments without a display

- **Follow-ups:** `spc-5` (skill-gap bridge Spec), tickets to be created via create-tickets
- **Verification:** ADR cited in `spc-5` References; review `rev-20260825-072540Z` Findings 1-6 map to delivery items

## Status history

- 2026-08-25: Proposed (stemming from `rev-20260825-072540Z` cross-comparison review)

## Notes

- ERP's `check-duplicate-work.mjs` semantic matching (≥2 shared significant tokens or CJK run ≥3 chars) is worth borrowing as a matching heuristic, even though the storage layer changes.
- ERP's pre-fix reproduction / post-fix verification loop (implement Step 0c/1b) is a process improvement, not an architectural decision — it goes in `spc-5` Spec Decisions, not this ADR.
- ego-browser's `cdp` escape hatch provides a path to capabilities not covered by facades (e.g. `Page.handleJavaScriptDialog`), matching ERP's escape-hatch philosophy.

---
