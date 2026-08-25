# Batch-work flow recipes

Detailed step recipes for the `batch-work` skill. The `SKILL.md` is the protocol + invariants; this file holds the long scripts. Load on demand only when executing a specific phase.

## Arg parsing

```
--ids ID1,ID2,...      Comma-separated GitHub issue numbers (one layer; all parallel if gates pass)
--groups               Read parallel_group + blocked_by from each ticket binder; build DAG
--concurrency N        Max agents spawned per layer (default 3)
--report <path>        Write Markdown report to <path> (always also stdout)
--dry-run              Print DAG + layer assignment; exit before any spawn
--ram-threshold <GB>   Skip spawn if available RAM below this (default 10; 0 disables)
--base <ref>           Base ref override passed to ensure-workspace.sh
```

`--ids` and `--groups` are mutually exclusive. If neither is given, fail closed with usage.

## RESOLVE TICKETS

For each id in `--ids` (or, under `--groups`, **every** binder under `.lattice/tickets/` — not only those with a `parallel_group` set; tickets with no `parallel_group` are assigned to a default serial layer, see BUILD DAG):

1. Locate `.lattice/tickets/tkt-<id>-*/README.md`. If missing → fail closed: "ticket <id> has no binder; run create-tickets first".
2. Parse the binder frontmatter/table for: `github`, `parallel_group`, `blocked_by`, `paths`, `worktree_bind`, `primary_ticket`.
3. Derive `<slug>` from the binder directory name (`tkt-<id>-<slug>`).

## BUILD DAG

Nodes = tickets. Edges = `blocked_by` (ticket A blocked by B means B must complete before A spawns).

Layer assignment (Kahn's algorithm):

- Layer 0: tickets with no `blocked_by` (or `blocked_by` only on tickets outside the batch).
- Layer k: ticket whose every `blocked_by` target is in a layer < k.
- Within a layer, tickets sharing the same `parallel_group` are candidates for concurrent spawn (subject to independence check).
- Tickets with no `parallel_group` under `--groups` are assigned to a **default serial layer** — each such ticket is serialized (one at a time), ordered by `blocked_by` then binder id; they are never spawned concurrently with each other.

> **`--ids` still respects `blocked_by`.** Even though `--ids` is one-layer intent, if any id in the set has a `blocked_by` target that is **also in the set**, those two must be serialized (the blocker lands in an earlier sub-layer). Cross-set blockers (not in `--ids`) are treated as already-satisfied preconditions and do not force serialization.

Cycle detection: if Kahn's algorithm leaves unprocessed nodes, fail closed: "DAG has a cycle: <ids>". Do not spawn.

## VALIDATE INDEPENDENCE

For each layer, check `paths` (approx globs) across its candidate tickets:

- If any glob pair overlaps (shared file / directory), the pair cannot run in parallel.
- Resolution: demote the later-id ticket to the next layer (serial), or fail closed if the overlap cannot be serialized without violating `blocked_by`.

This reuses the `create-tickets` independence policy (`../create-tickets/references/policy.md`); do not invent a second gate.

## DRY-RUN

If `--dry-run`: print

```
batch-work dry-run
base: <resolved base>
concurrency: <N>
ram-threshold: <GB>
layers:
  L0: [tkt-1 (G1, paths: src/a/*), tkt-2 (G1, paths: src/b/*)]  parallel
  L1: [tkt-3 (serial, blocked_by: tkt-1, paths: src/a/api/*)]
worktree paths:
  tkt-1 → <WORKTREE_ROOT>/tkt-1-<slug>
  ...
```

Exit 0 before any `ensure-workspace` or `Agent` call.

## RAM CHECK

Before spawning each layer:

- macOS: available = (`pages_free` + `pages_inactive` + `pages_speculative`) × page size, from `vm_stat` + `sysctl -n hw.pagesize`. Compare to threshold × 1 GB (1 073 741 824 bytes).
- Linux: `MemAvailable` from `/proc/meminfo`.
- Below threshold → fail closed for this layer: stop the batch, emit partial report, exit non-zero.
- Threshold 0 disables the check (not recommended; record as an escape in the report).

## SPAWN LAYER

If the layer has more tickets than `--concurrency`, spawn in **waves** of `--concurrency` tickets each. Run a wave, wait at the LAYER BARRIER for all of its agents, then run the next wave (re-checking RAM between waves). Within a single wave, up to `--concurrency` tickets:

1. **Ensure worktree:**
   - Honor the binder's `worktree_bind` field if present — pass its `--bind`/`--id`/`--slug`/`--branch` values through to `ensure-workspace.sh` instead of the defaults below.
   - Default (no `worktree_bind`):
   ```bash
   bash "$LIB/ensure-workspace.sh" --mode worktree --bind tkt --id <N> --slug <slug> [--base <ref>]
   ```
   Parse JSON: `path`, `cd_hint`, `branch`, `lattice_home`. On failure → record ticket as `workspace-failed`; do not spawn an agent.

2. **Launch agent** (background):
   - `subagent_type: general-purpose` (or the repo-configured start-work agent).
   - `run_in_background: true`.
   - Prompt brief (bounded delegation):
     ```
     Worktree: <path> (branch <branch>). cd there before any work.
     Run: start-work tkt-<id>.
     Batch marker: .lattice/.batch-work-active is present in this worktree —
     finish-work merge is BLOCKED. Do not call finish-work.
     Implement to the ticket's Acceptance criteria. Then open a PR via create-pr.
     Stop after create-pr. Report the PR URL.
     ```
   - Before spawning, write the batch marker: `touch <path>/.lattice/.batch-work-active`.
   - Record agent handle + ticket id + worktree path.

## LAYER BARRIER

Wait for all agents spawned in the current **wave** to complete (background-completion channel). For each:

- Success with PR URL → `ok`, record PR URL.
- Agent reported failure / no PR → `failed`, record reason.
- Timeout (if imposed) → `failed`, record timeout.

If more waves remain in this layer, re-run the RAM CHECK and spawn the next wave. A `failed` ticket does not block peers in the same wave. Once all waves of the layer finish, proceed to the next layer.

## NEXT-LAYER DEPENDENCY CHECK

Before spawning a ticket whose `blocked_by` includes a failed ticket: mark it `blocked-by-failure` and skip. Do not spawn.

## REPORT

Markdown table emitted to stdout and `--report <path>`:

```markdown
# batch-work report

base: <resolved base>
concurrency: <N>
ram-threshold: <GB>
ran: <UTC timestamp>

| ticket | layer | worktree | status | pr | binder |
| --- | --- | --- | --- | --- | --- |
| tkt-1 | L0 | …/tkt-1-foo | ok | #12 | .lattice/tickets/tkt-1-foo/README.md |
| tkt-2 | L0 | …/tkt-2-bar | failed | — | … |
| tkt-3 | L1 | …/tkt-3-baz | blocked-by-failure | — | … |

## Summary
- spawned: 2
- ok: 1
- failed: 1
- blocked-by-failure: 1

## Handoff
Human reviews open PRs, then runs finish-work per PR.
The .lattice/.batch-work-active marker ensured no agent merged.
```

## Failure-isolation contract

- The host owns DAG + spawn + collect + report. Agents own only their ticket brief + worktree.
- Agent crash → recorded `failed`; no abort of the batch.
- Workspace-creation failure → recorded `workspace-failed`; no agent spawned for that ticket.
- Dependency failure → dependent ticket `blocked-by-failure`; skipped, not spawned.
- The host never silently re-runs a failed ticket; the report lists it for human triage.
