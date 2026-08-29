# tkt-224-finish-work-multi-pr-dag-merge

<!-- Binder is a thin recovery card (not a second issue tracker).
     required: kind, priority, github, status, created/updated, acceptance, primary_ticket / worktree_bind when shipping
     recommended: covers, spec, summary/TL;DR, Path
     optional (parallel / C): blocked_by, parallel_group, paths, solo_merge, related_tickets, merge_blocked_by -->

> **TL;DR:** Add DAG-aware multi-PR merge mode to finish-work (--ids/--groups/multi-PR spc): Kahn layers, halt-on-failure, marker-once, stacked retarget.
> **Kind:** feat · **Priority:** P2 <!-- status lives in the field table -->
> **Path:** spc-220 → tkt-224 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/224 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-08-30T00:00:00Z |
| updated | 2026-08-30T00:00:00Z |
| adopted | false |
| summary | finish-work multi-PR DAG-aware merge: merge_blocked_by DAG, layer order, halt-on-failure |
| spec | spc-220 — finish-work multi-PR DAG-aware merge (path: ../../specs/spc-220-batch-finish-dag.md) |
| covers | A2, A3, A4, A5, A6, A7, A8 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | (serial) |
| paths | skills/finish-work/SKILL.md, skills/finish-work/references/flow.md |
| solo_merge | yes |
| **primary_ticket** | tkt-224 (this issue) — owner of the ship when this tree has one PR |
| **related_tickets** | tkt-223 (same one-PR ship: merge_blocked_by binder field) |
| **worktree_bind** | `spc-220-batch-finish-dag` |
| worktree | sibling `…/lattice.worktrees/spc-220-batch-finish-dag/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A2** `finish-work --ids ID1,ID2,…` (no deps between them) merges all PRs in id order through the full finish cycle; each binder reaches `status: closed` with a `## Finish` ledger line.
- [ ] **A3** `finish-work --groups --dry-run` prints the merge-order DAG (layers + PR numbers + binder paths) and exits before any marker/merge.
- [ ] **A4** Two PRs where B `merge_blocked_by A` land in order L0=[A], L1=[B]; after A merges, B's `update-pr-base` pulls A's work; if B's `baseRefName` was A's branch, the retarget to integration branch fires; B's diff cleans; B merges; ledger stamped.
- [ ] **A5** A failure (alignment gap / CI red / merge conflict / cleanup `ok:false`) on the first PR halts the batch; dependents stamp `deferred` + `wait_reason: blocked-by-failure`; independents stay `pr-open` (`halted`); marker already removed; partial report emitted; re-run resumes.
- [ ] **A6** Single-target `finish-work pr N` is unchanged (existing path, no behavior change).
- [ ] **A7** Mutual `merge_blocked_by` (cycle) → fail closed, no merge.
- [ ] **A8** `.batch-work-active` absent (no prior batch-work) → marker gate no-ops; multi-PR merges proceed.

## Approach

Edit `skills/finish-work/SKILL.md` (frontmatter arg-hint, Arguments table, Load-on-demand, Finish cycle, Short path, Relationship, Verification, Rationalizations/Red Flags) + `skills/finish-work/references/flow.md` (new §7).

### SKILL.md changes
- `argument-hint`: add `--ids ID1,ID2,… | --groups` + `--report <path>`.
- Arguments table: rows for `--ids`, `--groups`, `--report`; clarify `spc N` expands to all open PRs under the Spec (≥2 → DAG; 1 → single).
- Load-on-demand row: "Multi-PR DAG build, layer loop, stacked retarget, halt mapping, report shape" → `references/flow.md` §7.
- Finish cycle checkbox after sequential-merge-queue: multi-PR mode summary.
- Short path branch note: multi-target → multi-PR mode (§7); else single-PR path.
- Relationship: add `batch-work` row.
- Verification: multi-PR checkboxes.
- Rationalizations/Red Flags/Anti-patterns: batch-finish entries.

### flow.md §7 (new, on-demand)
- Arg parsing: `--ids`/`--groups` mutually exclusive w/ single positional; `spc N` multi-PR only if ≥2 open PRs.
- RESOLVE PRs: reuse §1 target resolution per id; require OPEN PR; no-PR → `no-pr` skip; parse `merge_blocked_by` (fallback `blocked_by`).
- BUILD DAG: Kahn (nodes = tickets-w-open-PRs; edges = `merge_blocked_by` fallback `blocked_by`); layer 0 = no within-batch dep; cycle → fail closed. Host-owned prose (no script).
- DRY-RUN: print DAG layers + PRs + binders; exit before marker/merge.
- MARKER GATE (once): `batch-merge-gate.sh --remove --reason "user-authorized: batch-finish <batch-id>"` after `AskUserQuestion` ack; absent → no-op.
- LAYER LOOP: per-PR finish-work short path (steps 3–11) inline minus marker gate; stacked retarget (`gh pr edit N --base <integration-branch>` when deps merged + `baseRefName` ≠ integration branch); halt-on-failure (dependents → `deferred`/`blocked-by-failure`; independents → `halted`/`pr-open`); layer barrier (serial — automatic).
- Never-merged reason mapping table: `no-pr`/`halted`/`blocked-by-failure`/`failed`.
- REPORT: Markdown table (ticket, layer, PR, status, binder, mergedAt) + summary + handoff.

## Anticipated decisions

- Host-owned DAG (no script) — disposition: pre-resolved (mirrors batch-work host-owned DAG).
- Halt-on-failure (not fuse) — disposition: pre-resolved (spc-220 Decision 3).
- Marker removed once (not per-PR) — disposition: pre-resolved (spc-220 Decision 2).

## Decision journal

<!-- Append-only during execution. -->

## Pending decisions

<!-- -->

## Attempts

<!-- -->

## Notes

- Ships in one PR with tkt-223 (merge_blocked_by binder field). This ticket is primary_ticket for the combined PR.
- No new scripts: all multi-PR logic is host-agent prose calling existing finish-work + lattice-lib scripts.

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-220` (path above)
- batch-work SKILL.md (the start-side DAG this mirrors, minus parallel machinery)
- finish-work §3.4 Sequential merge queue (extended here)
- Worktree policy: one tree ↔ one PR; spc|tkt open binds

## Lineage

- Parent spec: **spc-220**
- Parent issue: **#220**
- Primary ticket: **tkt-224**
- Related / sub-tickets: **tkt-223**
- Covers: **A2, A3, A4, A5, A6, A7, A8**
- Blocked by: (none)
- Merge blocked by: (none)
- Parallel group: (serial)
- Worktree bind: spc-220-batch-finish-dag
- Child PRs: (none yet)

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
