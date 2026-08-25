---
id: rev-20260825-072540Z
slug: lattice-vs-erp-skill-cross-compare
title: Lattice vs FlowDance ERP skill cross-comparison — borrowable patterns
kind: research
status: concluded
outcome: spawn_spec
summary: "Cross-compare 7 ERP skills vs Lattice; ego-browser supersedes auto-playwright; batch-implement + duplicate-work precheck are top gaps"
created: 2026-08-25
updated: 2026-08-25
related_specs: [spc-12]
related_tickets: [tkt-13, tkt-14, tkt-15, tkt-16]
related_prs: []
---

# Review: Lattice vs FlowDance ERP skill cross-comparison

> **TL;DR:** Cross-compared 7 FlowDance ERP skills (request-feature/report-bug/request-harness/implement/batch-implement/auto-playwright/fast-deploy) against Lattice's 10 skill lifecycle. ego-browser already supersedes ERP's auto-playwright. Top borrowable gaps: DAG-orchestrated batch execution, duplicate-work precheck, pre/post-fix reproduction loop, two-gate deploy pattern. Recommend a Spec to formalize these as Lattice-native skills.
> **Kind:** research · **Status:** concluded · **Outcome:** spawn_spec
> **Next:** create-spec → ADR → create-tickets

## Context

The user asked to cross-compare the current Lattice project's skills with 7 important skills from the FlowDance ERP project (`/Users/mxue/GitRepos/FlowDance/erp`), focusing on: `request-feature`, `report-bug`, `request-harness`, `implement`, `batch-implement`, `auto-playwright`, `fast-deploy`. The goal is to identify patterns Lattice could borrow. Two Explore agents inventoried both skill sets in detail; two further verification agents confirmed all technical claims against the actual SKILL.md files and the ego-browser skill at `/Users/mxue/GitRepos/infra/ego-lite/skills/ego-browser/SKILL.md`.

**Two skill systems at a glance:**

| Dimension | Lattice | FlowDance ERP |
| --- | --- | --- |
| Skill count | 10 user-facing + 1 internal lib | ~134 |
| Artifact SoT | GitHub issues + `.lattice/` binders | Firestore event log + `_harness/tracker/` folders |
| Lifecycle | create-spec → create-tickets → start-work → create-pr → finish-work | request-* → book-* → implement (unified 18-step pipeline) |
| `/implement` | Intentionally absent (EXECUTE is a state inside start-work) | Unified end-to-end delivery with step-manifest + guard.sh |
| Batch/parallel | create-tickets defines parallel_group but does not orchestrate execution | batch-implement: DAG + `claude --bg` concurrent spawning |
| Browser automation | playwright-cli + playwright-record-demo | auto-playwright: 3 modes + story DSL + persistent auth |
| Deploy | deploy-weftd-flitro (pull image + restart compose) | fast-deploy: incremental detection + review + tests + two gates |

## Problem Audit

| Layer | Notes |
| --- | --- |
| Validity | Problem is real — Lattice's skill pipeline is deliberately lean (6 lifecycle pipeline skills out of 10 total user-facing) and has acknowledged gaps (start-work explicitly states "No `/implement` skill"). ERP operates at ~134 skills with heavier operational surface. The comparison is apples-to-oranges in scale but valid for pattern-borrowing. |
| Information | Sufficient. All 7 ERP skills read in full via Explore agent. All 6 Lattice claims verified against actual SKILL.md files + `_lattice-lib/scripts/` listing. ego-browser SKILL.md read in full (frontmatter, workflow, auth model, primitives, output contract). No must-have info gaps. |
| Hidden issues | (1) ERP uses Firestore as tracker SoT — the "Firestore-only filing" pattern doesn't directly translate to GitHub-native Lattice; the *principle* (cheap filing, expensive booking) does. (2) ERP's auto-playwright cross-port auth (HARNESS-421) is a workaround for a problem ego-browser solves natively — porting it would be cargo-culting. (3) Step-manifest + guard.sh is tightly coupled to ERP's 18-step pipeline; Lattice's lighter binder model may not need this granularity. |

## Findings

### 1. No duplicate-work precheck — borrowable pattern from ERP's `check-duplicate-work.mjs`

**Evidence:**
- ERP: `tools/check-duplicate-work.mjs` invoked at two points — filing time (`--skip-remote --skip-pr`, advisory) and booking time (`--item {ID}`, four surfaces: local worktrees, remote branches, open PRs, open tracker queue). Runs *before* `reserve-id` because the ID transaction permanently consumes a number. Semantic title matching: ≥2 shared significant tokens or CJK run ≥3 chars. `ℹ️ no file-shaped token` is a coverage gap, never a clean bill of health.
- Lattice: grep for "duplicate", "already.*open issue", "existing.*PR", "existing.*worktree", "dedup" across `skills/` returned only idempotency / anti-overwrite references. The 14 scripts in `_lattice-lib/scripts/` (`_lattice-home.sh`, `assert-shippable-cwd.sh`, `check-base-residue.sh`, `ensure-lattice.sh`, `ensure-workspace.sh`, `finish-ledger.sh`, `github-issue-parent-add.sh`, `github-project-add.sh`, `lattice-init.sh`, `list-board-items.sh`, `next-artifact-id.sh`, `resolve-integration-branch.sh`, `resolve-lattice-lib.sh`, `upload-github-asset.sh`) — none is a pre-create duplicate detector. Closest: `github-issue-parent-add.sh` has link dedup (detects "already exists|duplicate" to avoid re-linking), not work-level dedup. `ADOPT_CHECK` in start-work handles an *existing* issue when supplied as input — adoption, not proactive detection.
- **Lattice-native adaptation:** GitHub-native implementation is simpler than ERP's Firestore version: `gh issue list --state open --search "keywords"` + `git worktree list` + `gh pr list --state open` — three surfaces (Lattice has no separate tracker queue). Integrate as a pre-flight step in create-tickets (before `gh issue create`) and start-work (before `ensure-workspace`).

### 2. No batch execution orchestration — biggest capability gap

**Evidence:**
- ERP: `batch-implement` (71-line SKILL.md) — `--ids ID1,ID2,...` → `tools/build-program-dag.mjs --batch-items` derives dependency DAG → execution layers → per-layer spawn `claude --bg` agents with `--permission-mode acceptEdits` + `BATCH_IMPLEMENT=1` env (guard.sh Rule 21 blocks hosting deploys). Layer-barrier synchronization; one agent crash doesn't block peers or subsequent layers; RAM threshold gate (default 10 GB).
- Lattice: `create-tickets` defines `parallel_group` as a grouping/labeling concept (SKILL.md line 45, INVARIANT 3: "Independence gates before any `parallel_group`"). But grep for "batch execut", "orchestrat.*execut", "execute.*group", "run.*parallel.*ticket" across create-tickets returned zero matches. Short path step 6 (line 105-106): "Handoff issue #s + binder paths for `start-work`." — execution is one-at-a-time via start-work. No batch execution exists.
- **Lattice-native adaptation:** Lattice's sibling worktree model (one worktree per tkt) + create-tickets' parallel_group + independence gates naturally support a batch orchestrator. Write a `batch-work` skill: read parallel_groups from tickets → spawn agents per group (one worktree each) → layer-barrier sync → `BATCH_WORK=1` env blocks finish-work merge (only create-pr, human reviews then finish-work). RAM check before spawn. This is the single highest-value borrow.

### 3. No pre-fix reproduction / post-fix verification loop for bug tickets

**Evidence:**
- ERP: implement Step 0c (Pre-Fix Reproduction, BUG-only, HARNESS-970) — re-execute plan.md § Reproduction, capture pre-fix evidence in `reproduction-evidence.md`; if bug no longer reproduces, consider wont-fix. Step 1b (Post-Fix Verification, BUG-only) — re-execute same reproduction, append post-fix evidence with cross-comparison table, loop back to Step 1 if symptom persists (max 2 cycles).
- Lattice: start-work SKILL.md lines 82-93 — EXECUTE goes straight to implementation. Line 91: "DEFAULT: no forced TDD." The only verify is a generic DoD check at step 8 (line 93): "VERIFY with fresh command evidence" — "tests pass with fresh output this session," not a bug-specific reproduce-then-fix-then-verify loop.
- **Lattice-native adaptation:** Add a bug-type classification to start-work's CLASSIFY step. For bug-class tickets: Phase 0c (reproduce, capture evidence) → Phase 1 (fix) → Phase 1b (re-verify, cross-compare, max 2 cycles). This is lighter than ERP's 18-step manifest — just two extra phases gated on ticket type.

### 4. deploy-weftd-flitro lacks pre-deploy quality gate and diff classification — **OUT OF SCOPE (not a Lattice skill)**

**Evidence:**
- ERP: `fast-deploy` (549 lines) — two-gate design: Gate 1 (environment checks + sync remote + read last deployed version + classify diff via `tools/classify-diff.mjs` → confirm scope) → Steps 1-4 unattended (code review + full test suite, parallel) → Gate 2 (comprehensive summary with review findings + test results + deploy plan → final approval) → Steps 6-7 auto (execute deploys + post-deploy verify). Hosting and Functions deploy independently (HARNESS-1061) with separate baselines; already-deployed functions skipped. `classify-diff.mjs` maps diff to deploy targets (frontend → hosting, api → functions, docs/skill/tool → no deploy, early exit).
- Lattice: `deploy-weftd-flitro` (at `/Users/mxue/.claude/skills/deploy-weftd-flitro/SKILL.md`, also mirrored in weftd repo `/Users/mxue/GitRepos/MVP/weftd/`) — grep for "code.review", "test run", "diff classif", "changed component", "only deploy.*changed" returned zero matches. The only pre-deploy checks are infrastructure pre-flight (project dir, compose file, `.env`, GHCR auth, port bind sanity). There IS a WS-5 schema gate (operator must confirm `sessions.token_epoch` column exists on prod Supabase before rolling weftd) — but this is a DB schema precondition, not a code-review/test quality gate. There IS a manual `SERVICE` selector (`all | weftd | agentd`) — but manual selection, not automatic diff-based detection.
- **OUT OF SCOPE:** `deploy-weftd-flitro` is NOT a Lattice project skill — it lives in the weftd repo (`/Users/mxue/GitRepos/MVP/weftd/`), not in the lattice repo. Deploy quality improvements belong in a weftd-repo spec, not a Lattice spec. Finding retained as research context; does NOT spawn a Lattice delivery ticket. (tkt-17 was closed as scope error; ADR-002 §5 documents this exclusion.)

### 5. Auto-playwright should NOT be ported — ego-browser already provides a superior foundation

**Evidence:**
- ERP: `auto-playwright` (481 lines) — three modes (visible CLI, `--logs`, `--story`). Cross-port auth (HARNESS-421) solves Firebase web auth's IndexedDB-partition-by-origin problem via `newContext({storageState})` rewriting origin. Story DSL (YAML): open/goto/click/fill/select/press/wait/screenshot/assert/evaluate/tab/usb/serial/firestore_get. Device emulation (HARNESS-1047) at context level. Output: stdout JSON, exit 0 always.
- ego-browser: `/Users/mxue/GitRepos/infra/ego-lite/skills/ego-browser/SKILL.md` (v1.2.6) — provides Playwright-shaped API (`page`, `page.locator`, `browser`, `taskSpaces`, `fetch`, `cdp`) via `ego-browser nodejs` heredoc. **Login state inheritance via task spaces** — agents reuse user's live login state without auth fixtures, solving ERP's cross-port auth problem natively. Isolated space (no human competition). One Bash invocation per task with in-process adaptation. `screencast` (VP8 WebM), `screenshot`, `evaluate`, full locator chain. `cdp` escape hatch. Output: stdout JSON via `console.log`. No process spawn overhead (reuses running ego lite Chromium).
- **Comparison:** ego-browser eliminates ERP's entire cross-port auth engineering (HARNESS-421/243/275), profile management, and device-emulation complexity. The task-space isolation model is architecturally superior to Playwright's per-run browser launch. The only thing worth borrowing from ERP is the **story DSL concept** — but implemented as ego-browser heredoc JS script templates (with assertion primitives and structured output), not a separate YAML runner.
- **Lattice-native adaptation:** Build a thin `e2e-story` skill (or reference template) on ego-browser: heredoc JS script pattern with goto/click/fill/assert/screenshot primitives + fail-loud auth check (expected auth but landed on login → FAIL) + structured JSON output. No separate runtime, no YAML parser, no profile management. Leverage ego-browser's `page.evaluate` for assertions, `page.screenshot` for evidence, `taskSpaces` for auth.

### 6. Step-manifest concept absent — lower priority

**Evidence:**
- ERP: `implement` maintains `{TRACKER_DIR}/step-manifest.json` after each step (status/artifact/checkpoint/classifier_result/required_artifacts/unobtainable_artifacts). guard.sh Rule 6 blocks `gh pr create` if any required step is pending. Required artifacts that are genuinely unobtainable are declared with `reason_code` + `substitute` (HARNESS-814), never silently dropped.
- Lattice: case-insensitive grep for "step-manifest", "step_manifest", "stepmanifest" across entire tree returned zero matches. Ticket progress tracked via binder README + Acceptance checkboxes (closed by finish-work via `close-fixed-issues.sh`) and `## Finish` ledger — artifact-level, not step-level.
- **Assessment:** Lower priority. Lattice's binder is artifact-level by design (lighter, more flexible). Step-level manifest enforcement is tightly coupled to ERP's 18-step pipeline and guard.sh. If Lattice's lighter model needs finer-grained tracking, it can be added per-ticket in the binder without a global guard.sh. Defer unless the batch-work skill (Finding 2) needs step-level progress for layer-barrier sync — in which case a lightweight per-worktree progress file (not a full manifest) would suffice.

## Recommendations

1. **Create a Spec** (spc-12) formalizing these borrowable capabilities as Lattice-native skills or skill enhancements. Five findings map to deliverable work items; Finding 4 (deploy gates) is out-of-scope (not a Lattice skill).
2. **Write an ADR** documenting the architectural decision: Lattice stays GitHub-native (not Firestore), ego-browser supersedes auto-playwright, batch orchestration reuses sibling worktree model.
3. **Priority order for tickets:** batch-work (Finding 2) > duplicate-work precheck (Finding 1) > ego-browser e2e story runner (Finding 5) > pre/post-fix reproduction loop (Finding 3) > step-manifest (Finding 6, deferred).
4. **Explicitly reject:** porting ERP's auto-playwright runtime, porting ERP's Firestore-only filing shape, porting ERP's guard.sh step-manifest enforcement as-is, modifying deploy-weftd-flitro (not a Lattice skill).

## Outcome (required to conclude)

| outcome | When |
| --- | --- |
| `spawn_spec` | Need a locked Spec before tickets ✓ |

**Outcome:** `spawn_spec` — proceed to create-spec (spc-12) to lock scope, then ADR, then create-tickets for delivery breakdown.

### Follow-ups

- [x] Spec `spc-12` — created in same-pass worktree
- [x] ADR-002 — cross-feature architecture decision (`docs/adr/002-lattice-skill-gap-bridge-adaptations.md`)
- [x] Tickets — tkt-13 (A1), tkt-14 (A3), tkt-15 (A2), tkt-16 (A4); A5 deferred (documented in spec Decisions); tkt-17 closed (deploy-weftd-flitro scope error)

## References

- Lattice skills: `/Users/mxue/GitRepos/MVP/lattice/skills/` (start-work, finish-work, create-spec, create-tickets, create-pr, create-review, review-code, review-production, create-adr, generate-wiki, _lattice-lib)
- Lattice scripts: `/Users/mxue/.claude/skills/_lattice-lib/scripts/` (14 scripts, verified no duplicate-work detector)
- ERP skills: `/Users/mxue/GitRepos/FlowDance/erp/.claude/skills/` (~134 skills, SKILLS-MAP.md catalogue)
- ERP priority skills: `request-feature/SKILL.md` (255 lines), `report-bug/SKILL.md` (280 lines), `request-harness/SKILL.md` (296 lines), `implement/SKILL.md` (361 lines + 18 reference files), `batch-implement/SKILL.md` (71 lines), `auto-playwright/SKILL.md` (481 lines), `fast-deploy/SKILL.md` (549 lines)
- ego-browser: `/Users/mxue/GitRepos/infra/ego-lite/skills/ego-browser/SKILL.md` (v1.2.6, 2026-07-20)
- deploy-weftd-flitro: `/Users/mxue/.claude/skills/deploy-weftd-flitro/SKILL.md`

## Links

Bare ids in front matter lists only — `spc-12` linked; tickets tkt-13…tkt-16 linked (tkt-17 closed, scope error).
