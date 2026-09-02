---
id: spc-337
slug: fsm-conformance-closure
title: FSM conformance closure — transitions stamped by the path, ledger coverage as CI metric
kind: feat
status: done
mode: C
priority: P1
summary: "Move every M2 status stamp into the script step the ticket already passes through, refuse hand edits, make ledger coverage a CI metric, and repair the drifted finish/batch prose."
created: 2026-09-02
updated: 2026-09-02
tickets: [tkt-338, tkt-339, tkt-340, tkt-341, tkt-342, tkt-349, tkt-350, tkt-352, tkt-353, tkt-356, tkt-357]
prs: [pr-343, pr-344, pr-345, pr-346, pr-347, pr-348, pr-354, pr-355]
reviews: [rev-20260902-015425Z]
supersedes: []
superseded_by: null
---

# Spec: FSM conformance closure

> **TL;DR:** The M2 state machine models 8 states and 21 edges; this repo's 150 binders walked 5 edges and 119 of them have no ledger. This Spec makes the walked path and the modelled path converge by stamping status at the path points the agent cannot skip, refusing direct status edits, fixing the ledger-path bug, removing the `any → closed` wildcard, measuring ledger coverage in CI, and repairing the finish-work / batch-work prose that drifted from the scripts.
> **Kind:** feat · **Status:** done · **Mode:** C · **Priority:** P1
> **Path:** rev-20260902-015425Z → ADR-012 → spc-337 → tkt-… → pr-…

## Why

`rev-20260902-015425Z` audited the FSM from the running data instead of from the docs and found: only 5 of 21 legal edges ever occur in production ledgers; `queued → in-progress` was recorded once; 119/150 closed binders have no ledger; tkt-325/326/327 were closed by hand-editing the status row (commits `45d18c8`, `d17e1ca`), invisible to CI; 6 merged tickets carry a `queued → closed` ledger entry labelled `guard: cancel` / `trace: no mergedAt` although `mergedAt` was stamped; and `transition-api.py` resolves the ledger file from cwd while its four callers stage it from the binder path, so tkt-335's finish stamp flipped status but committed no ledger.

The cause is structural, not disciplinary: the most-walked edges have no script writer, while the steps every ticket passes through (`ensure-workspace --bind`, `gh pr create`, batch barrier, triage) are already scripts that do not stamp. ADR-012 turns this into law; this Spec is its first delivery slice. The finish-work and batch-work prose also drifted from the scripts they describe (wrong verifier after multi-PR merge, stale marker location, coordinator never activated, `failed` nodes left `in-progress`).

## In scope

- Ledger path resolved from the binder's Lattice home; `closed_without_ledger` validator check with a 2026-09-02 legacy cutoff; ledger coverage + direct-jump counts in queue-health.
- Explicit terminal edges replacing the `any → closed` wildcard; `anomaly:` + `direct-jump` metric for merges from `queued`/`in-progress`; docs + vendored validator parity.
- Path-point writers: `ensure-workspace --bind tkt` stamps `in-progress`; create-pr script step + plugin PostToolUse hook stamp `pr-open`; morning-triage edges as `transition-api.py commit` commands.
- L3 Write/Edit hook refuses status-row edits on ticket binders.
- finish-work prose repair: multi-PR merge verifier, marker location, `ci-gate-check.sh` in the short path, pre-merge base capture.
- batch-work coordinator wired by default; `failed` fail-closes to `stuck`; marker `--create` + heartbeat touch; ADR-011 amendment note.

## Out of scope

- GitHub Action bot for the Finish ledger and the single `finish-work.sh` orchestrator (ADR-012 §5 — follow-up Spec after one dogfood cycle).
- Spec-level transition API / guarded `done` (ADR-012 §6 — follow-up).
- Binder front-matter migration (ADR-012 §7 — follow-up).
- Rewriting historical binders or ledgers (spc-270 D1); legacy binders are baselined, not edited.
- M1/M3 transition modelling; hook behaviour for non-Claude agents beyond the portable script step.

## Acceptance

- [x] **A1** — **Ledger path + coverage metric.** `transition-api.py` resolves the per-ticket ledger from the binder's Lattice home (the `.lattice` directory containing the binder), never from cwd; `finish-ledger.sh`, `stamp-pr-open.sh`, `ratify.sh`, `bump-fix-cycle.sh` stage that same path. Fault test: a finish stamp run from a non-toplevel cwd lands the ledger under the binder's home and stages it. `validate-lattice-artifacts.py` emits `closed_without_ledger` for a terminal binder with no ledger file — error when the binder `created` row is ≥ `2026-09-02T00:00:00Z`, warning (baselined) otherwise. `queue-health.sh --section` prints a ledger-coverage row (`n/N terminal binders with ledger`) and a direct-jump count.
- [x] **A2** — **Explicit terminal edges.** `transition_table.py` has no `any → closed` edge; it lists `pr-open → closed` (merge), `queued → closed` and `in-progress → closed` (merge, `metric: direct-jump`), and cancel edges from every working state (`reason: cancel`, trace must carry a reason). `finish-ledger.sh` writes a merge from `queued`/`in-progress` with `reason: merge` (not `cancel`) and appends an `anomaly:` binder line. The vendored validator copy, `docs/workflow-fsm.md` §2, `workflow-fsm-reference.md`, and `transition-parity.bats` agree; replay of the existing 31 ledgers stays green.
- [x] **A3** — **Path-point writers.** `ensure-workspace.sh --bind tkt --id N` commits `queued → in-progress` through the transition API when a `queued` binder exists (idempotent on re-bind; other statuses untouched; `--no-stamp` opt-out; no binder → no-op). `create-pr` gains a scripted post-open step that chains `verify-main-chain --stage pr` and `stamp-pr-open`; the plugin gains a PostToolUse hook that runs the same stamp after a successful `gh pr create` (fail-open, advisory on error). `docs/morning-triage.md` expresses `deferred|stuck → queued` and cancel as `transition-api.py commit` commands. Fault tests: bind a queued binder → one `queued → in-progress` ledger entry; bind again → no second entry; a `pr-open` binder is not touched by bind.
- [x] **A4** — **Status-row guard.** `intercept-shippable-write.sh` denies a Write/Edit on `.lattice/tickets/*/README.md` whose result changes the `| status |` row value, with a message naming `transition-api.py commit`; edits to other rows/sections and creation of a new binder are allowed. Bats fault tests cover deny, allow-other-row, allow-create, and malformed input (fail-open).
- [x] **A5** — **finish-work prose repair.** `references/flow.md` §7 verifies each multi-PR merge with `verify-main-chain.sh --stage merge` (not `verify-mutation.sh --pr`); `SKILL.md` names the out-of-repo state-home marker location (no "MAIN clone `.lattice/`"); `ci-gate-check.sh` appears in the SKILL short path and Finish-cycle checklist; the pre-merge base tip capture is one explicit command in the short path. A docs-truth bats asserts all four.
- [x] **A6** — **Coordinator wired + `failed` fail-close.** `batch-work/SKILL.md` and `flow.md` invoke `run-process-wave.sh` with `--batch-id` (the marker's batch id) so the coordinator spine is active in the canonical path; `coordinator.py record-node --status failed` commits `in-progress → stuck` (`wait_reason: unblock`) before settle, same as `unknown|timeout`; the contradictory "opt-in"/"DEFAULT-ON" comments are reconciled; `batch-merge-gate.sh --create --batch-id <id>` replaces the raw `printf` in prose; the wave touches the marker mtime at each barrier (heartbeat, ADR-011 amendment). Fault test: a `failed` node leaves the binder `stuck`.

## Non-goals

- No status transition or validation rule based on chat/transcript state.
- No change to model deliberation, decision policy, or fallback policy prose.
- No new binder enum values.

## Decisions (principal, user-confirmed)

1. **D1 — Path-point law (ADR-012 §1–§4).** Stamps ride the script steps the ticket already passes through; prose never instructs an agent to edit `status`; direct edits are refused by the L3 hook; wildcard edges are removed; coverage is measured.
2. **D2 — Bookkeeping direction: GitHub Action bot + single-script fallback (ADR-012 §5).** Recorded as law now; implemented in a follow-up Spec after this slice soaks one dogfood cycle.
3. **D3 — Binder front matter migration deferred (ADR-012 §7).** This Spec does not change the storage format; `binder_rows.py` stays the single parser.
4. **D4 — Legacy cutoff, no rewrite.** Binders created before 2026-09-02 enter the warning baseline for `closed_without_ledger`; nothing historical is rewritten (spc-270 D1).
5. **D5 — Proof is production-path evidence (spc-270 D3 carried).** Each A* names a fault test that runs the canonical script, not a unit helper alone.

## Agent-assumed (secondary)

- The PostToolUse stamp hook is Claude-specific defense-in-depth; the create-pr script step is the portable path (capability matrix row unchanged).
- The `ensure-workspace` stamp uses `owner: system`, `reason: spawn` on the existing `queued → in-progress` edge.
- Ledger coverage counts terminal binders only (in-flight binders legitimately may not have reached a scripted edge yet).

## Risks / open questions

- `ensure-workspace.sh` is on every shippable path; the new stamp must be strictly no-op when no binder exists or status ≠ `queued`, and must never fail the bind (stamp failure → warning, bind still succeeds).
- The PostToolUse hook must not double-stamp when the create-pr script step already ran (`stamp-pr-open` is idempotent — verified by A3 fault test).
- Removing `any → closed` changes replay semantics; the parity test and a replay over the committed ledgers guard the migration.

## Delivery plan

| Wave | Ticket | Covers | Blocked by | Parallel group | Path boundary |
| --- | --- | --- | --- | --- | --- |
| W0 | tkt-338 | A1, A2 | none | (serial) | transition-api/table, four status writers' staging lines, validator + baseline, queue-health, FSM docs |
| W1 | tkt-339 | A3 | tkt-338 | G1 | ensure-workspace, create-pr skill + scripts, plugin PostToolUse hook + hooks.json, morning-triage.md |
| W1 | tkt-340 | A4 | none | G1 | intercept-shippable-write.sh + plugin bats |
| W1 | tkt-341 | A5 | none | G1 | finish-work SKILL.md + references/flow.md + docs-truth bats |
| W1 | tkt-342 | A6 | none | G1 | batch-work skill/scripts/tests, finish-work/scripts/batch-merge-gate.sh, ADR-011 amendment |

Independence gates (G1): file-level disjoint touch-sets — tkt-339 owns `plugins/lattice/hooks/hooks.json` and a new hook file; tkt-340 owns only `intercept-shippable-write.sh`; tkt-341 owns finish-work SKILL/flow prose; tkt-342 owns batch-work plus `finish-work/scripts/batch-merge-gate.sh`. Ship: multi-PR, one sibling worktree per ticket.

## Status history

- 2026-09-02: locked (operator sign-off) → all six acceptance criteria delivered via tkt-338..342 (pr-344..348), each PR independently reviewed, fix cycles: tkt-338 ×1, tkt-340 ×1, tkt-341 ×1, tkt-342 ×2, tkt-339 ×1. Status stays `locked` until one dogfood cycle has passed (ADR-012 §6 — `done` is guarded and soaked); follow-ups filed: tkt-349 (ci-gate-check gh field), tkt-350 (batch brief prose).
- 2026-09-02: locked → **done**. Dogfood/soak cycle passed (ADR-012 §6 done-gate): (a) all child binders closed (#338..342 CLOSED); (b) `prs` list = child PR union (pr-344..348 + follow-up pr-354, pr-355); (c) one dogfood cycle passed since last child merge — 4 follow-up bugs (#349 ci-gate-check gh JSON field, #350 batch-work prose stamp, #352 transition-api ledger-from-cwd, #353 env-dependent bats) surfaced from exercising the shipped machinery and were fixed + closed. CI all-green on dev (artifacts, lattice-scripts, plugin-hooks, lint, lint-heavy — success post pr-355 merge). Conformance metrics on real repo: `validate-lattice-artifacts.py` OK (219 `closed_without_ledger_legacy` baseline warnings, 0 errors); `queue-health.sh --section` ledger coverage 42/145 terminal binders (29%), direct jumps 10. One new local-only follow-up filed: #356 (macOS BSD sed/grep partial-line A4 env-portability — CI green, local red; same class as #353). Spec flipped to `done` via tkt-357.

## References

- Review: `rev-20260902-015425Z` → `.lattice/reviews/rev-20260902-015425Z-fsm-conformance-and-path-scripting.md`
- ADR: `ADR-012` → `docs/adr/012-transitions-stamped-by-the-path.md`
- Prior Specs: `spc-186`, `spc-254`, `spc-270`
- GitHub primary: https://github.com/percena/lattice/issues/337

## Links / bloodline (L0)

- Tickets: `tkt-338`, `tkt-339`, `tkt-340`, `tkt-341`, `tkt-342` (GitHub children #338–#342, native sub-issues of #337); follow-ups: `tkt-349`, `tkt-350`, `tkt-352`, `tkt-353`, `tkt-356`, `tkt-357`
- PRs: `pr-343` (planning), `pr-346` (tkt-338), `pr-344` (tkt-340), `pr-345` (tkt-341), `pr-347` (tkt-342), `pr-348` (tkt-339); follow-up PRs: `pr-354` (tkt-349), `pr-355` (tkt-350, tkt-352, tkt-353)
- Reviews: `rev-20260902-015425Z`
