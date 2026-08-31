---
id: spc-254
slug: executable-workflow-contracts
title: Executable workflow contracts — transition replay, recoverable DAG coordination, and evidence proof
kind: feat
status: locked
mode: C
priority: P1
summary: "Compile cross-stage orchestration, mutation proof, and evidence/lineage into a machine-checked, recoverable execution layer — constrain the path, not the model."
created: 2026-08-31
updated: 2026-08-31
tickets: []
prs: []
reviews: [rev-20260830-141357Z]
supersedes: []
superseded_by: null
---

# Spec: Executable workflow contracts

> **TL;DR:** Lattice's atomic mutations are already scripted, but cross-stage orchestration, mutation proof, and runtime/lineage evidence still depend on host discipline. This Spec compiles them into a versioned, machine-checked, recoverable execution layer — keeping "constrain the path, not the model" while moving the path itself out of LLM context.
> **Kind:** feat · **Status:** locked · **Mode:** C · **Priority:** P1
> **Path:** spc-254 → tkt-… → pr-…

## Why

Lattice has evolved from a pure-prompt workflow into a delivery system with reliable atomic scripts and a static contract (spc-186 marker gate, status vocabulary, CI gate, fix-cycle cap). But `rev-20260830-141357Z` (workflow-orchestration-contract-audit) found that the cross-stage contract layer is still incomplete and host-assembled:

- **False-success (F1/F2):** `spc-213` A4 requires `process`-mode nodes classified `ok|failed|timeout` via `claude agents --json` + PID liveness, but `run-process-wave.sh` reports only `completed|timeout` and defers PR/mutation verification to the host — a worker that runs long, then fails without opening a PR, is still first marked `completed`. The canonical `create-pr` path requires "host verifies" but never wires `verify-mutation.sh` into the short path; the dogfood retrospective (`rev-20260829-140444Z` F1/F5) recorded real phantom issue/PR/push/merge incidents from swallowed output.
- **No transition-as-data (F3):** the FSM has a vocabulary SoT (`status_vocab.py`) but no machine model of the full transition table (from/to/owner/guard/reason/escape/trace/metric). The validator only checks snapshots, not illegal edges between two legal snapshots. Each new writer or host-orchestration path requires humans to keep docs, Skill prose, scripts, and validator consistent.
- **Recovery is host-bound (F4):** batch/finish DAG protocols are complete and readable, but the durable execution core (DAG, layer/wave barrier, fuse, Kahn sort, retarget, halt/resume, batch id, node state, resume cursor, failure class) lives in host LLM context. A host restart or context compaction loses the recovery point and re-derives it by re-interpreting artifacts.
- **Evidence/lineage not closed (F6):** the feature-map validator checks columns/non-empty oracle/status enum but does not prove a `pass` story row has a story with consistent oracle/mutations and a `status=pass` result JSON. The L0 validator checks ticket→Spec single edges but does not require a `done` Spec's `prs` to contain the child binder PR union — `spc-186` is `status: done` with `prs: []` while its retrospective declares all 9 tickets/PRs merged. The validator emits 101 lazy-migration/format warnings at exit 0; without a baseline/ratchet, regressions hide in historical noise.
- **Over-claimed invariant (F5):** README's "chain never skips a step" reads as unconditional, but the guarantee actually depends on call path and install mode (scripted `finish-work` = fail-closed hard gate; strict Claude PreToolUse hook = defense-in-depth; advisory/uninstalled = detection only; missing `python3` → strict fail-opens).

Continuing to stack Skill prose widens the implementation/statement drift surface. The fix is not more scripts or more prose — it is to compile the cross-stage contract into a versioned, machine-checked, recoverable layer.

## In scope

- **F1 false-success closure (process mode):** redefine process-node final state from exit/result artifact + `claude agents --json` + PID + `verify-mutation --expected-oid`; classify `ok|failed|timeout|unknown` with `unknown` fail-closed → binder `stuck + wait_reason: unblock`. Never name "PID disappeared" as success.
- **F2 mutation proof in canonical main chain:** push→verify remote OID; PR create→verify repo/base/head/body/head OID; merge→verify PR merged state + base OID. Any proof failure stops cleanup/ledger and leaves structured recovery info. Same helper contract for normal, batch, and delegated paths.
- **F3 versioned transition contract:** machine-readable schema (`from/to/owner/guard/reason/escape/trace/metric`); all status writers go through one transition API; append a minimal transition ledger for validator replay.
- **F4 recoverable coordinator minimal slice:** a coordinator that does no model inference — it persists DAG, layer, node attempt, PID/PR/OID, marker owner, failure class, and resume cursor. Skills keep scope/brief/exception interpretation.
- **F5 capability matrix:** document guarantee strength per call path (scripted = hard gate; strict Claude hook = defense-in-depth; advisory/uninstalled = detection only). No global-invariant overclaim.
- **F6 evidence/lineage proof + validator migration:** story-header + result-JSON schema; `pass` must prove story path / oracle / mutations / last-verified / result status / assertions / screenshots; destructive story needs auth trace. Backfill `spc-186.prs`; done Spec must contain child binder PR union; reciprocal edges migrate warning→error over a window; baseline + only-decrease ratchet; new warnings fail CI separately; error messages give actionable fix suggestions.
- **F7 environment parity:** two CIs pin same Bats version; `ci-local` states degraded/fail on version mismatch; installed-skill drift check runs only in Lattice dev mode (does not overwrite installed tree).
- **Migration + compatibility policy:** how existing artifacts move from warning to error; compat strategy for old data during the migration window.

## Out of scope

- Changing model deliberation or encoding business judgment as hard rules.
- Replacing existing Skill UX or the human-adjudicated exception channel.
- Building a general-purpose workflow platform.
- Establishing a remote ID-claim service for cross-clone Review/ADR/Spec races (defer until multi-clone conflict data appears — `rev-20260830-141357Z` Rec 9).

## Acceptance

Acceptance is fault-injection centered — each criterion is demonstrated by injecting a failure and showing the system detects, classifies, and recovers correctly.

- [ ] **A1 (F1 false-success closure)** — A `process`-mode worker that exits non-zero, or whose PID disappears without an opened PR, is classified `failed` or `unknown` (never `completed`). `unknown` fail-closes the binder to `stuck + wait_reason: unblock`. `ok` requires exit/result artifact + `claude agents --json` + `verify-mutation --expected-oid` agreement.
- [ ] **A2 (F2 mutation proof in main chain)** — push mismatch (remote OID ≠ local), PR create with wrong repo/base/head/body/head, and a merge whose base OID drifts each halt cleanup/ledger and emit structured recovery info. Normal, batch, and delegated paths share one `verify-mutation` helper contract.
- [ ] **A3 (F3 transition contract)** — a machine-readable schema (`from/to/owner/guard/reason/escape/trace/metric`) is the SoT; all status writers go through one transition API that appends a ledger entry; the validator replays the ledger and rejects an illegal edge between two legal snapshots.
- [ ] **A4 (F3 schema↔docs parity)** — `docs/workflow-fsm.md`'s transition table is generated from, or passes a parity test against, the schema. Manually editing one without the other fails CI.
- [ ] **A5 (F4 recoverable coordinator)** — a host restart mid-batch/finish resumes from the persisted DAG/layer/node-attempt/PID/PR/OID/marker-owner/failure-class/resume-cursor without re-deriving state from artifacts. The coordinator performs no model inference.
- [ ] **A6 (F5 capability matrix)** — README + `docs/workflow-fsm.md` state guarantee strength per call path (scripted = hard gate; strict Claude hook = defense-in-depth; advisory/uninstalled = detection only). No text claims an unconditional global invariant.
- [ ] **A7 (F6 evidence proof)** — a `pass` story row with no matching story header, inconsistent oracle/mutations, or missing `status=pass` result JSON fails the validator. A destructive story without an authorization trace fails. `spc-186.prs` is backfilled; a `done` Spec missing the child binder PR union fails.
- [ ] **A8 (F6 validator migration)** — the 101 current warnings are snapshotted as a baseline; only-new warnings fail CI separately; the baseline is a one-way ratchet (only-decrease). New checks (done-Spec PR union, reciprocal edges) start as warning and migrate to error on a documented schedule.
- [ ] **A9 (F7 environment parity)** — both CIs pin the same Bats version; `ci-local` reports degraded or fails on version mismatch; installed-skill drift check runs in Lattice dev mode without overwriting the installed tree.

## Non-goals

- We will not build a general workflow platform reusable beyond Lattice's own delivery loop.
- We will not remove the human-adjudicated exception/escape channel — escape remains human, only the transition API and ledger are machine-checked.
- We will not encode product/business judgment as hard rules; "constrain the path, not the model" is preserved.

## Decisions (principal, user-confirmed)

1. **D1 — Tiered capability matrix (user-confirmed).** Guarantee strength is documented per call path: scripted path = hard gate; strict Claude PreToolUse hook = defense-in-depth; advisory/uninstalled = detection only. We do NOT claim an unconditional global invariant. If a future product decision requires global enforcement, that needs a portable wrapper/CLI — not renaming an optional hook as a hard guarantee. (Resolves F5 / Rec 8.)
2. **D2 — Transition schema is SoT; docs are parity-tested (user-confirmed).** The machine-readable transition schema is the source of truth; `docs/workflow-fsm.md`'s transition table is generated from it or covered by a parity test. We stop hand-copying the FSM into markdown, prose, and validator separately. (Resolves F3 / Rec 5.)
3. **D3 — Validator migration via baseline + ratchet (user-confirmed).** Existing 101 warnings are snapshotted as a baseline; only-new warnings fail CI separately; the baseline is a one-way ratchet (only-decrease). New checks start as warning and migrate to error on a documented schedule. Hard-error-immediately is rejected (forces fixing all 101 + spc-186 backfill before any merge — too high a blast radius). Permanent-warning is rejected (regressions hide in noise). (Resolves F6 / Rec 3.)
4. **D4 — Coordinator constrains the path, not the model.** The recoverable coordinator persists DAG/node/attempt/cursor state and performs no model inference; scope, brief, and exception interpretation stay in the Skills. This preserves the Lattice posture while moving the path out of LLM context. (Resolves F4 / Rec 6.)
5. **D5 — Mutation proof is one shared helper contract.** Normal, batch, and delegated paths use the same `verify-mutation` contract (expected OID + remote/PR/merge-state probes). No path is exempt. (Resolves F2 / Rec 2.)

## Risks / open questions

- Transition schema may prove to be a cross-feature long-term law. If so, promote to a standalone `docs/adr/NNN` after the Spec stabilizes (defer the ADR until the schema survives one delivery cycle).
- `claude agents --json` schema stability across CLI versions — mitigate by treating PID liveness as ground truth and `agents --json` as enrichment (carry forward spc-213 D-secondary).
- Migration window length for warning→error needs to balance noise vs. regression-hiding; revisit after the first ratchet cycle.

## References

- Review: `rev-20260830-141357Z` — workflow-orchestration-contract-audit (`.lattice/reviews/rev-20260830-141357Z-workflow-orchestration-contract-audit.md`)
- Prior Specs: `spc-104` (runtime verification), `spc-186` (hard-limit closure), `spc-213` (batch-work process spawn), `spc-220` (batch-finish DAG), `spc-226` (run-e2e platform dispatcher)
- Retrospective: `rev-20260829-140444Z` (spc-186 dogfood — F1/F3/F5 false-success incidents)
- Prior Review: `rev-20260829-160834Z` (workflow-fsm-hardlimit)
- ADR: (none yet — D4 schema may promote; see Risks)

## Links / bloodline (L0)

- Tickets: (to be split — `create-tickets` will populate `tkt-N` under `tickets: []`)
- PRs: (none yet)
- Reviews: `rev-20260830-141357Z`
