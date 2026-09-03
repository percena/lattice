---
id: spc-270
slug: workflow-proof-closure-followup
title: Workflow proof closure follow-up
kind: feat
status: done
mode: C
priority: P1
summary: "Close the remaining spc-254 proof/recovery gaps with atomic transitions, deterministic process proof, resumable orchestration, and strict evidence ratchets."
created: 2026-08-31
updated: 2026-08-31
tickets: [tkt-271, tkt-272, tkt-273, tkt-274, tkt-275, tkt-276]
prs: [pr-296, pr-312, pr-316, pr-318, pr-320, pr-321, pr-322]
reviews: [rev-20260831-073033Z]
supersedes: []
superseded_by: null
---

# Spec: Workflow proof closure follow-up

> **TL;DR:** Preserve `spc-254` as historical delivery, then close its remaining proof/recovery gaps through six fault-injection slices whose production paths—not artifact checkboxes—prove completion.
> **Kind:** feat · **Status:** done · **Mode:** C · **Priority:** P1
> **Path:** rev-20260831-073033Z → spc-270 → tkt-271..276 → pr-…

## Why

`spc-254` delivered substantial infrastructure and correctly closed capability-matrix/environment-parity work, but a 24-hour code-path recheck found that A1–A5/A7/A8 are partial or incomplete. Process failures can leave binder state active, transition replay trusts self-reported edges, the coordinator is not wired into real batch/finish recovery and has stale-state races, multi-PR mutation proof uses the wrong verifier, runtime pass evidence is shallow, and warning baselines can grow or hide repeated warnings.

Reopening historical tickets would destroy delivery truth; marking the gaps informational would preserve false closure. This Spec is the correction edge: it keeps `spc-254/tkt-255..261` closed while requiring fault-injection evidence before the remaining claims may be considered closed.

## In scope

- Atomic transition mutation and replay completeness across every M2 status writer.
- Deterministic process-mode result classification and binder fail-close.
- Production wiring and concurrency safety for durable batch/finish coordinator state.
- One mutation-proof contract for single-PR and multi-PR create/push/merge paths.
- Versioned runtime evidence payload validation.
- True one-way validator warning ratchet and warning→error migration schedule.
- Correction lineage from `spc-254` to this Spec without rewriting historical issue/ticket state.

## Out of scope

- Rebuilding `spc-254` A6 capability matrix or A9 environment parity.
- Reopening or reusing `tkt-255..261` as new delivery tickets.
- General-purpose workflow platforms, model deliberation policy, or business-decision encoding.
- Remote artifact-ID claim service and unrelated validator warning cleanup.

## Acceptance

- [x] **A1** — **Atomic transition contract.** One guarded transition API reads the real binder prior state under lock, validates the versioned schema edge and coupled fields, atomically updates `status`/`wait_reason`/`updated`, appends a ticket-bound ledger entry, and fails without partial mutation. Every production M2 writer uses it. Replay rejects discontinuity, wrong ticket identity, illegal edge, missing final snapshot agreement, or omitted required transition. Schema↔docs parity is bidirectional and covers owner/guard/reason/escape/trace/metric.
- [x] **A2** — **Deterministic process proof.** Worker result artifacts plus bounded PID/session-correlated probes classify `ok|failed|timeout|unknown`; PID disappearance alone is never success. `failed|timeout|unknown` use A1 to stamp `stuck + wait_reason: unblock`; transition failure prevents settle. Wave output/exit status is machine-decidable, and crash/hang/no-PR/global-agent-noise fault tests terminate deterministically.
- [x] **A3** — **Recoverable coordinator.** Real batch-work initializes and persists the complete DAG, marker owner, layer/wave cursor, attempts, PID/PR/OID and failure class; finish-work consumes the same state. State commands lock before read or use revisioned CAS, never regress settled nodes, increment attempts, and are idempotent. `resume` actually continues the next eligible node after host restart without re-deriving the DAG.
- [x] **A4** — **Mutation proof convergence.** Normal, delegated, batch and multi-PR paths use one expected-OID proof contract. Push proves remote OID; PR create proves repo/base/head/body/head OID; merge proves the target PR is MERGED and its merge commit/content is reachable from the intended base before cleanup/ledger. Concurrent unrelated base advancement, wrong PR state and OID drift fail closed with structured recovery state.
- [x] **A5** — **Versioned runtime evidence.** A feature-map `pass` requires a matching versioned story/result identity, oracle/mutations parity, valid last-verified/run freshness, non-empty passing assertions, existing screenshots, and mutation round-trip/leftover disclosure; destructive runs require authorization trace. Handwritten shallow pass, stale result, mismatched identity and missing evidence all fail validator tests.
- [x] **A6** — **True warning ratchet.** Warning identity uses stable entity + occurrence/detail semantics so same-file repeated findings cannot hide. Missing/corrupt baseline fails closed in ratchet mode. CI compares against the base-branch baseline, forbids additions or baseline growth, permits verified removals, reports stale entries, and enforces a versioned warning→error schedule for done-Spec PR union and reciprocal edges.

## Delivery plan

| Wave | Ticket | Covers | Blocked by | Parallel group | Path boundary |
| --- | --- | --- | --- | --- | --- |
| W0 | tkt-271 | A1 | none | foundation | transition schema/API, shared status writers, replay/parity |
| W1 | tkt-272 | A4 | none | proof-wave-1 | create/push/single+multi PR mutation proof |
| W1 | tkt-273 | A2 | tkt-271 | proof-wave-1 | process runner/result classification; no coordinator edits |
| W1 | tkt-274 | A5 | none | proof-wave-1 | runtime evidence parser/templates/fixtures only |
| W2 | tkt-275 | A3 | tkt-271,tkt-272,tkt-273 | proof-wave-2 | coordinator plus batch/finish integration |
| W2 | tkt-276 | A6 | tkt-274 | proof-wave-2 | warning ratchet/baseline/CI/migration only |

Independence gates: W1 tickets have disjoint batch-process, mutation-proof, and evidence-parser surfaces. W2 tickets separate coordinator integration from validator ratchet. Where a shared file contains distinct owned sections, later waves—not concurrent execution—preserve the boundary.

## Non-goals

- No rewrite of completed GitHub history or `spc-254` delivery artifacts into an artificial in-progress state.
- No status transition or validation rule based on chat/transcript state.
- No requirement that coordinator perform model inference.

## Decisions (principal, operator-directed)

1. **D1 — Correction edge, not historical rewrite.** `spc-254` remains done; this Review + Spec carry the durable qualification and new work gets new issue IDs.
2. **D2 — Transition foundation precedes dependent fixes.** A1 is the only serial foundation; A2/A3 depend on it. A4/A5/A6 are independent and may proceed in parallel subject to path gates.
3. **D3 — Proof is production-path evidence.** A helper or unit test alone does not close Acceptance unless the canonical Skill path invokes it and fault tests prove failure behavior.
4. **D4 — Coordinator remains non-inferential.** It persists/advances execution state; Skills retain scope, brief and exception interpretation.
5. **D5 — Migration is fail-visible.** Compatibility may stage warnings, but ratchet configuration absence or corruption is never silently treated as clean.

## Agent-assumed (secondary)

- JSON/JSONL remain acceptable dependency-free persistence formats; implementation may replace them only if tests and portability remain equivalent.
- Existing CLI surfaces remain backward compatible unless a fail-closed correction requires an explicit new flag or exit code.

## Risks / open questions

- Migrating all writers through A1 touches safety-critical lifecycle scripts; ticket must keep per-writer regression tests and avoid a flag-day artifact migration.
- Finish coordinator integration may expose historical batches without durable state; define an explicit legacy/manual recovery path rather than guessing.

## References

- Review: `rev-20260831-073033Z` → `.lattice/reviews/rev-20260831-073033Z-spc254-24h-closure-recheck.md`
- Prior Review: `rev-20260830-141357Z`
- Prior Spec: `spc-254`
- GitHub primary: https://github.com/percena/lattice/issues/270
- ADR: none; existing ADR-007/ADR-008 laws remain authoritative.

## Links / bloodline (L0)

- Tickets: `tkt-271`, `tkt-272`, `tkt-273`, `tkt-274`, `tkt-275`, `tkt-276`
- PRs: pending delivery
- Reviews: `rev-20260831-073033Z`
- GitHub children: #271, #272, #273, #274, #275, #276 (native sub-issues of #270)
