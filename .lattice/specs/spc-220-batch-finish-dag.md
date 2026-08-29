---
id: spc-220
slug: batch-finish-dag
title: finish-work multi-PR DAG-aware merge (batch finish)
kind: feat
status: locked
mode: C
priority: P2
summary: "Add DAG-aware multi-PR merge to finish-work: merge-order layers from merge_blocked_by, halt-on-failure, marker-once."
created: 2026-08-30
updated: 2026-08-30
tickets: [tkt-223, tkt-224]
prs: [pr-230]
reviews: []
supersedes: []
superseded_by: null
---

# Spec: finish-work multi-PR DAG-aware merge (batch finish)

> **TL;DR:** Add a multi-PR mode to `finish-work` that builds a merge-order DAG from a new `merge_blocked_by` binder field (fallback `blocked_by`), then runs the existing per-PR finish flow in layer order with halt-on-failure + a layer barrier — so stacked/dependent PRs land base-first.
> **Kind:** feat · **Status:** locked · **Mode:** C · **Priority:** P2
> **Path:** spc-220 → tkt-… → pr-…

## Why

Lattice has **batch-work** (DAG-orchestrated fan-out that *starts* many tickets in parallel) vs **start-work** (single-ticket start), but for *closing* work there is only **finish-work** (single-PR merge). PR landing order also forms a DAG:

- **Stacked PRs** — B stacked on A must merge A-first or B's diff won't clean (B contains A's commits until A lands).
- **Logical deps** — B's code calls a symbol A introduces; landing B before A breaks the base.

Today the operator runs `finish-work` per PR manually, ignoring merge order. This forces manual ordering and risks landing a stacked PR before its base, leaving a broken diff. There is no batch finish.

## In scope

- New `merge_blocked_by` ticket-binder field (merge-order DAG; parallel to `blocked_by` = work-start order).
- `finish-work` multi-PR mode: `--ids ID1,ID2,…` | `--groups` | `spc N` (resolving ≥2 open PRs) → build merge-order DAG, land in layer order.
- Kahn topological sort into merge-order layers; layer 0 = no within-batch merge dep; layer k = all `merge_blocked_by` deps in layers < k.
- Layer barrier: all layer-0 PRs merge before any layer-1 PR begins (so layer-1 `update-pr-base` sees layer-0's landed work; stacked diffs clean).
- Marker gate: remove `.batch-work-active` **once** at batch start after human ack; the batch owns the whole merge window.
- Halt-on-failure: stop the batch on first failure (alignment gap / CI real red / merge conflict / cleanup `ok:false`); dependents → `blocked-by-failure`; remaining independents → `halted`.
- Stacked-PR base retarget: `gh pr edit N --base <integration-branch>` when deps all merged + `baseRefName` ≠ integration branch.
- Multi-PR report (Markdown table: ticket, layer, PR, status, binder, mergedAt) to stdout + `--report <path>`.
- Fallback: `merge_blocked_by` absent → fall back to `blocked_by` (usually the same → existing binders work without edits).
- Single-target path unchanged.

## Out of scope

- A separate `batch-finish` skill (decided against: merges are serial; batch-work's parallel/worktree/RAM/watchdog/fuse machinery does not apply).
- Parallel/background merge agents (merges serialize on the base branch).
- New scripts (all multi-PR logic is host-agent prose calling existing finish-work + lattice-lib scripts).
- Work-start DAG changes (`blocked_by` semantics unchanged; `merge_blocked_by` is a new, distinct field).

## Acceptance

- [x] **A1** `merge_blocked_by` field exists in the ticket-binder template + create-tickets policy, documented as merge-order (not work-start), with fallback-to-`blocked_by` noted.
- [x] **A2** `finish-work --ids ID1,ID2,…` (no deps between them) merges all PRs in id order through the full finish cycle; each binder reaches `status: closed` with a `## Finish` ledger line.
- [x] **A3** `finish-work --groups --dry-run` prints the merge-order DAG (layers + PR numbers + binder paths) and exits before any marker/merge.
- [x] **A4** Two PRs where B `merge_blocked_by A` land in order L0=[A], L1=[B]; after A merges, B's `update-pr-base` pulls A's work; if B's `baseRefName` was A's branch, the retarget to the integration branch fires; B's diff cleans; B merges; ledger stamped.
- [x] **A5** A failure (alignment gap / CI red / merge conflict / cleanup `ok:false`) on the first PR halts the batch; dependents stamp `deferred` + `wait_reason: blocked-by-failure`; independents stay `pr-open` (`halted`); marker already removed; partial report emitted; re-run resumes.
- [x] **A6** Single-target `finish-work pr N` is unchanged (existing path, no behavior change).
- [x] **A7** Mutual `merge_blocked_by` (cycle) → fail closed, no merge.
- [x] **A8** `.batch-work-active` absent (no prior batch-work) → marker gate no-ops; multi-PR merges proceed.

## Decisions (principal, user-confirmed)

1. **DAG source = new `merge_blocked_by` binder field**, falling back to `blocked_by` when absent. Rationale: merge-order and work-start order are usually but not always the same; a dedicated field keeps the two DAGs auditable, while the fallback means existing binders need no edits. (Alternative rejected: reuse `blocked_by` only — conflates the two; infer from PR bases — can't express non-stacked logical deps; explicit `--layers` arg — DAG not version-controlled.)
2. **Marker gate = remove once at batch start** (human-acknowledged); the batch owns all merges in the window. Rationale: the whole batch is one authorized merge session; per-PR marker dance defeats the batch purpose. (Alternatives rejected: swap to a finish-specific marker — more plumbing for no semantic gain; remove per-PR — re-prompts each merge.)
3. **Failure handling = halt on first failure.** Stop the batch; dependents → `blocked-by-failure`; remaining independents → `halted`. Rationale: a mid-batch failure may mean the base is in an unexpected state; halting is safest for merges (unlike batch-work's failure isolation, which is justified by independent worktrees). No fuse, no timebox, no RAM check — merges are serial and host-owned.
4. **Integrate into finish-work, not a separate skill.** batch-work is separate only because it spawns parallel agents/worktrees/RAM-watchdog-fuse machinery; finish has none of that. finish-work already has a "Sequential merge queue" (§3.4) — this makes it DAG-aware.

## Risks / open questions

- Stacked-PR retarget (`gh pr edit N --base`) is the only new sub-step touching GitHub state beyond existing finish-work calls; must only fire when deps have merged (never retarget a PR whose deps haven't landed — would orphan the stack). Covered in A4.
- `merge_blocked_by` fallback to `blocked_by`: if the two differ for a ticket, the merge order uses `blocked_by` silently. Documented as the chosen behavior; operators who need divergence set `merge_blocked_by` explicitly.

## References

- Prior Spec: (none)
- ADR: (none — feature-local; cross-feature ADR not warranted)
- Related: `batch-work` (the start-side DAG orchestration this mirrors, minus parallel machinery); `finish-work` §3.4 Sequential merge queue (extended here).

## Links / bloodline (L0)

- Tickets: (to be split via `create-tickets` — tkt-N set)
- PRs: (prefer GitHub `Fixes`/`Refs`; Spec.prs is recovery)
- Reviews: (none yet)
- Primary issue: **#220** — https://github.com/percena/lattice/issues/220
