---
id: spc-12
slug: skill-gap-bridge
title: Lattice skill-gap bridge — ERP pattern adaptations
kind: feat
status: locked
mode: C
priority: P2
summary: "Borrow 6 ERP patterns as Lattice-native skills: duplicate-work precheck, batch-work, bug repro loop, two-gate deploy, ego-browser e2e-story, step-manifest deferred"
created: 2026-08-25
updated: 2026-08-25
tickets: [tkt-13, tkt-14, tkt-15, tkt-16, tkt-17]
prs: []
reviews: [rev-20260825-072540Z]
supersedes: []
superseded_by: null
---

# Spec: Lattice skill-gap bridge — ERP pattern adaptations

> **TL;DR:** Formalize 6 borrowable patterns from FlowDance ERP as Lattice-native skills or skill enhancements, per ADR-002 architectural decisions (GitHub-native, ego-browser over auto-playwright, sibling worktree batch, review-code deploy gates, step-manifest deferred).
> **Kind:** feat · **Status:** locked · **Mode:** C · **Priority:** P2
> **Path:** spc-12 → tkt-… → pr-…

## Why

A cross-comparison review (`rev-20260825-072540Z`) examined 7 FlowDance ERP skills against Lattice's 10-skill lifecycle and identified 6 patterns Lattice could borrow. The gaps are real and verified:

- **No duplicate-work detection** — create-tickets and start-work create issues/worktrees without checking for existing open duplicates. ERP's `check-duplicate-work.mjs` runs at filing and booking time.
- **No batch execution** — create-tickets defines `parallel_group` + independence gates but does not orchestrate execution. Engineers with 5+ independent tickets must run start-work one-at-a-time. ERP's `batch-implement` spawns concurrent agents with layer-barrier sync.
- **No bug reproduction loop** — start-work EXECUTE goes straight to implementation with no pre-fix reproduction or post-fix verification. ERP's implement Step 0c/1b provides a reproduce → fix → re-verify cycle.
- **No pre-deploy quality gate** — deploy-weftd-flitro is pull-image + restart-compose with infrastructure pre-flight only. ERP's fast-deploy has two-gate design with code review + tests.
- **No e2e story testing** — playwright-cli and playwright-record-demo exist but lack assertion primitives, fail-loud auth, and structured output. ego-browser (v1.2.6) provides a superior foundation to ERP's auto-playwright.
- **No step-level tracking** — Lattice's binder is artifact-level. ERP's step-manifest is tightly coupled to its 18-step pipeline. Deferred by ADR-002.

ADR-002 (`docs/adr/002-lattice-skill-gap-bridge-adaptations.md`) locks the architectural strategy: Lattice-native adaptations (not direct port), GitHub-native (not Firestore), ego-browser (not auto-playwright runtime), sibling worktree batch (not Firestore DAG), review-code deploy gates (not guard.sh), step-manifest deferred.

## In scope

- `check-duplicate-work.sh` script in `_lattice-lib/scripts/` — GitHub-native duplicate detection (3 surfaces: open issues, worktrees, open PRs) with semantic title matching
- Integration of duplicate-work precheck into create-tickets (before `gh issue create`) and start-work (before `ensure-workspace`)
- `batch-work` skill — DAG orchestration on sibling worktrees using create-tickets parallel_group + independence gates, spawning concurrent agents with layer-barrier sync and BATCH_WORK=1 merge block
- Pre-fix reproduction / post-fix verification loop for bug-class tickets in start-work CLASSIFY step (Phase 0c reproduce → Phase 1 fix → Phase 1b re-verify, max 2 cycles)
- Two-gate deploy quality sub-pipeline for deploy-weftd-flitro: diff classification (weftd / flitro+agentd / docs-only → skip) + review-code scan + available tests + Gate 1 scope confirm + Gate 2 deploy approval
- `e2e-story` reference layer on ego-browser: heredoc JS script template with goto/click/fill/assert/screenshot primitives + fail-loud auth check + structured JSON output
- Documentation of step-manifest deferral rationale in spec Decisions

## Out of scope

- Porting ERP's auto-playwright runtime, story DSL YAML parser, or profile management system
- Porting ERP's Firestore-only filing shape or `tracker-events.mjs`
- Porting ERP's guard.sh step-manifest enforcement or 18-step implement pipeline
- Porting ERP's `verify-code` 8-phase gate
- Porting ERP's `request-feature` / `report-bug` / `request-harness` as standalone skills (Lattice uses GitHub issues + create-spec/create-tickets)
- Porting ERP's `classify-reactive-surface.mjs` / `classify-effect-sink.mjs` (additivity/signal-chain audits)

## Acceptance

- [ ] **A1** `check-duplicate-work.sh` exists in `_lattice-lib/scripts/`, checks 3 surfaces (open GitHub issues via `gh issue list`, local worktrees via `git worktree list`, open PRs via `gh pr list`), uses semantic title matching (≥2 shared significant tokens or CJK run ≥3 chars), always advisory (exits 0), and is integrated into create-tickets pre-flight and start-work pre-flight
- [ ] **A2** `batch-work` skill exists with `--ids` / `--groups` input, reads parallel_group from ticket binders, spawns one worktree per tkt via `ensure-workspace.sh`, layer-barrier sync (waits for all agents in a group before next), `BATCH_WORK=1` env blocks finish-work merge (agents create-pr only), RAM threshold check before spawn, dry-run mode, and failure isolation (one agent crash doesn't block peers)
- [ ] **A3** start-work CLASSIFY step identifies bug-class tickets and runs Phase 0c (reproduce from ticket Reproduction Steps, capture evidence in binder) → Phase 1 (fix) → Phase 1b (re-verify, cross-comparison table, max 2 cycles, consider wont-fix if no longer reproduces)
- [ ] **A4** deploy-weftd-flitro has a pre-deploy quality sub-pipeline: diff classification (changed files → weftd frontend / flitro+agentd / docs-only → skip deploy), review-code scan on the diff (advice), available test run, Gate 1 (scope + classification confirm), Gate 2 (review findings + test results + deploy plan → final approval), post-deploy health check
- [ ] **A5** `e2e-story` reference template exists (heredoc JS pattern for ego-browser) with goto/click/fill/select/press/screenshot/assert primitives, fail-loud auth check (expected auth but landed on login → FAIL), structured JSON output via `console.log`, and at least one example story for weftd or flitro
- [x] **A6** step-manifest deferral is documented in spec Decisions with rationale (Lattice binder is artifact-level; lightweight per-worktree progress file may be added if batch-work needs layer-barrier sync, but no global guard.sh enforcement) — **done: see Decisions §5**

## Non-goals

- Will not build a separate YAML story DSL parser — ego-browser heredoc JS is the format
- Will not create a global step-manifest enforcement system
- Will not adopt Firestore as a tracking layer
- Will not port ERP's 18-step implement pipeline as a single skill

## Decisions (principal, user-confirmed)

1. **GitHub-native, not Firestore-native** (ADR-002 §1) — duplicate-work precheck uses `gh issue list` + `git worktree list` + `gh pr list` (3 surfaces), not ERP's 4-surface Firestore + git hybrid. Lattice has no separate tracker queue.
2. **ego-browser is the browser automation foundation** (ADR-002 §2) — not ERP's auto-playwright runtime. ego-browser's task-space login-state inheritance eliminates cross-port auth engineering. e2e-story layer uses heredoc JS, not YAML runner.
3. **Batch orchestration reuses sibling worktree model** (ADR-002 §3) — batch-work reads parallel_group from create-tickets binders, spawns one worktree per tkt, layer-barrier sync. Not ERP's Firestore-based DAG.
4. **Deploy quality gates reuse review-code contract** (ADR-002 §4) — advice-only scan, not ERP's guard.sh step-manifest enforcement. Two-gate pattern borrowed in shape only.
5. **Step-manifest explicitly deferred** (ADR-002 §5) — Lattice's binder stays artifact-level. If batch-work needs per-worktree progress for layer-barrier sync, a lightweight progress file (not global manifest) will suffice.
6. **Pre-fix reproduction / post-fix verification is a process enhancement** (not architectural) — added to start-work CLASSIFY for bug-class tickets, max 2 cycles. Not a separate skill.

## Risks / open questions

- ego-browser requires the ego lite app running (headed, not headless) — may not fit CI environments without a display. Mitigation: e2e-story is for local/dev verification, not CI gate. If CI e2e is needed later, revisit.
- batch-work orchestrator is new code — less proven than ERP's batch-implement. Mitigation: dry-run mode first, `BATCH_WORK=1` prevents unattended merge.
- Duplicate-work precheck has 3 surfaces vs ERP's 4 (no separate tracker queue) — slightly lower coverage for filed-but-never-booked duplicates. Acceptable: Lattice's GitHub issue IS the tracker queue (not separate).
- batch-work agent spawning requires `claude --bg` or equivalent — need to verify this works in the Lattice environment.

## References

- Review: `rev-20260825-072540Z` → `.lattice/reviews/rev-20260825-072540Z-lattice-vs-erp-skill-cross-compare.md`
- ADR: `ADR-002` → `docs/adr/002-lattice-skill-gap-bridge-adaptations.md`
- ERP skills examined: `/Users/mxue/GitRepos/FlowDance/erp/.claude/skills/` (request-feature, report-bug, request-harness, implement, batch-implement, auto-playwright, fast-deploy)
- ego-browser: `/Users/mxue/GitRepos/infra/ego-lite/skills/ego-browser/SKILL.md` (v1.2.6)
- Lattice scripts: `_lattice-lib/scripts/` (14 scripts, verified no duplicate-work detector)
- Lattice skills: `skills/start-work/SKILL.md`, `skills/create-tickets/SKILL.md`, `skills/finish-work/SKILL.md`, `skills/review-code/SKILL.md`

## Links / bloodline (L0)

- Tickets: tkt-13, tkt-14, tkt-15, tkt-16, tkt-17
- PRs: (to be created)
- Reviews: `rev-20260825-072540Z`
