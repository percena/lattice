---
name: batch-work
description: "DAG-orchestrated unattended batch delivery: spawn multiple start-work agents in parallel on sibling worktrees with layer-barrier synchronization. Use when a Spec/ticket set has independence-gated parallel groups and the user wants one command to fan out work. Not for single-ticket start, fuzzy product align, PR merge, or manual ticket splitting."
allowed-tools: Bash Read Grep Glob Agent AskUserQuestion
argument-hint: "[--ids ID1,ID2,... | --groups] [--concurrency N] [--report <path>] [--dry-run]"
metadata:
  agents: "claude-code,codex"
---

# Batch work

**DAG-orchestrated fan-out on sibling worktrees.** Read parallel groups + `blocked_by` from ticket binders, spawn one `start-work` agent per ticket in a sibling worktree, and wait at each layer barrier before the next group.

This skill is **not** a port of ERP's `batch-implement`. It reuses Lattice's existing `ensure-workspace.sh` worktree + independence-gate infrastructure; it only adds the orchestration layer (DAG build, layer barrier, spawn, report).

**Runtime path:** before executing skill-owned files, set `LATTICE_SKILL_ROOT` to the absolute directory containing this loaded `SKILL.md` (Claude may already provide `CLAUDE_SKILL_DIR`). Never infer it from consumer cwd.

Templates: co-installed `create-tickets` `references/templates/ticket-binder.md` (no local copy). Do **not** require monorepo `docs/` to run.

## Load on demand

| When | Read |
| --- | --- |
| DAG build, layer barrier, spawn/collect recipes | `references/flow.md` |
| Independence gates, parallel_group policy, worktree packing | `../_lattice-lib/references/orchestration-patterns.md` + `../create-tickets/references/policy.md` |
| Severity labels INVARIANT/DEFAULT/HINT | `../_lattice-lib/references/constraint-language.md` |
| Delegation and accountable ownership | `../_lattice-lib/references/orchestration-patterns.md` |
| Claiming shippable / tests green | `../_lattice-lib/references/definition-of-done.md` |

Do **not** pre-load every reference; stay on this file for the main protocol.

## When to use / When NOT

| Use | Not — use instead |
| --- | --- |
| Spec/ticket set with independence-gated `parallel_group`s; fan out in one command | Single ticket → `start-work` |
| Unattended batch delivery: one owner, many disjoint worktrees | Fuzzy product align → `create-spec` |
| `--dry-run` to inspect DAG + layer assignment before spawn | Ticket splitting / binder authoring → `create-tickets` |
| Human reviews PRs after batch, then `finish-work` per PR | Merge / cleanup → `finish-work` |
| | Open a single PR → `create-pr` |

## Invariants (must hold)

| INVARIANT | Detail |
| --- | --- |
| Independence gate | Every ticket in a parallel group must pass the `create-tickets` independence gates (disjoint `paths`, no shared API/type without Spec/ADR). Path-overlapping tickets are **serial** within one tree, not parallel |
| One worktree per tkt | Each spawned ticket gets its own sibling worktree via `ensure-workspace.sh --mode worktree --bind tkt --id N --slug <slug>`. Never share a tree across parallel tickets |
| `BATCH_WORK=1` blocks merge | Spawned agents run with `BATCH_WORK=1`, which blocks `finish-work` merge. Agents stop at `create-pr` (PR opened, human reviews, then `finish-work`) |
| RAM threshold before spawn | Before each layer spawn, check available RAM ≥ threshold (default 10 GB). Below threshold → fail closed for that layer (do not spawn); report and stop |
| Failure isolation | One agent crash does not block peers in the same layer or subsequent layers. Collect exit codes; a failed ticket is reported, not fatal |
| Accountable owner | One host owns DAG build, spawn, collect, and report. Delegated `start-work` agents own only their bounded ticket brief; host validates final PR list |
| Bound ids only | All `--ids` must resolve to real GitHub issue numbers (≥1) with a binder. `tkt-0` / fake ids remain forbidden (inherited from `ensure-workspace`) |
| No live-default PR | Agents never open PRs from the live default branch; worktrees branch off the resolved base |

## Defaults and escapes

| DEFAULT | Escape / HINT |
| --- | --- |
| `--concurrency 3` per layer | User opt-in `--concurrency N`; respect machine RAM + agent overhead |
| RAM threshold 10 GB | `--ram-threshold <GB>`; set 0 to disable (not recommended) |
| `--groups` reads `parallel_group` from binders | `--ids ID1,ID2,…` runs one layer (all parallel if gates pass) |
| `BATCH_WORK=1` → agents create-pr only | `BATCH_WORK=0` allows agents to call `finish-work` (discouraged; loses human review gate) |
| Report to stdout | `--report <path>` writes a durable Markdown report |
| Dry-run shows DAG + layers, no spawn | `--dry-run` always exits before any `ensure-workspace` / Agent call |
| Base = integration-branch resolved | `--base <ref>` override; passed through to `ensure-workspace` |

## Step 0 (every run)

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")
bash "$LIB/ensure-lattice.sh"
```

## Flow

1. **INTAKE** — parse args: `--ids`, `--groups`, `--concurrency`, `--report`, `--dry-run`, `--ram-threshold`, `--base`.
2. **RESOLVE TICKETS** — for each id, locate binder `.lattice/tickets/tkt-<id>-<slug>/README.md`; extract `parallel_group`, `blocked_by`, `paths`, `worktree_bind`, `slug`. Fail closed if a binder is missing.
3. **BUILD DAG** — nodes = tickets; edges = `blocked_by`. Topologically sort into layers: layer 0 = no blockers, layer k = all `blocked_by` satisfied by layers < k. Tickets with the same `parallel_group` and no cross-dependency share a layer.
4. **VALIDATE INDEPENDENCE** — within each layer, confirm `paths` are disjoint (no path glob overlap across tickets in the same layer). Overlap → demote to serial (next layer) or fail closed with a report.
5. **DRY-RUN EXIT** — if `--dry-run`, print DAG (layers + ticket ids + worktree paths + concurrency) and exit 0 before any spawn.
6. **RAM CHECK** — before each layer: read available RAM (macOS `vm_stat` / `sysctl hw.memsize`; Linux `/proc/meminfo`). Below threshold → fail closed for this layer; stop batch; report partial results.
7. **SPAWN LAYER** — for each ticket in the layer (up to `--concurrency`):
   - `bash "$LIB/ensure-workspace.sh" --mode worktree --bind tkt --id <N> --slug <slug> [--base <ref>]`
   - Capture `path` + `cd_hint` from JSON.
   - Launch an `Agent` (`subagent_type: general-purpose` or the configured start-work agent) with `run_in_background: true`, `BATCH_WORK=1` in the prompt, brief: "run `start-work tkt-<id>` in worktree <path>; implement to acceptance; open PR via `create-pr`; do NOT call `finish-work`."
   - Bound delegation: the agent owns only its ticket brief + worktree; host owns DAG + report.
8. **LAYER BARRIER** — wait for all agents in the layer to complete (success or fail). Collect exit status + PR URL per ticket. A failed ticket is recorded; peers and subsequent layers proceed (failure isolation).
9. **NEXT LAYER** — repeat RAM check + spawn for the next layer. A ticket whose `blocked_by` includes a failed dependency is skipped (recorded as blocked-by-failure).
10. **REPORT** — emit a Markdown table: ticket, layer, worktree path, agent status (ok/failed/blocked), PR URL, binder path. Write to `--report <path>` if given; always also print to stdout.
11. **HANDOFF** — summary: N spawned, M ok, K failed, L blocked. Human reviews open PRs, then runs `finish-work` per PR. `BATCH_WORK=1` ensured no agent merged.

Detailed recipes (DAG build, RAM probe, spawn/collect, report shape): **`references/flow.md`**.

## Safety

- **`BATCH_WORK=1` merge block.** Spawned agents are instructed that `finish-work` merge is blocked; they stop at `create-pr`. This keeps a human review gate over the batch. `BATCH_WORK=0` disables the gate — discouraged.
- **RAM threshold.** Default 10 GB available before spawn. Spawn is skipped (fail closed) when RAM is below threshold; the batch stops with a partial report rather than thrashing the machine. Override via `--ram-threshold <GB>`; `0` disables (not recommended).
- **Failure isolation.** Agent crashes are per-ticket. The host collects each agent's result via the background-completion channel; a crash is recorded as `failed` for that ticket and does not block peers in the same layer or tickets in later layers (except tickets `blocked_by` the failed one, which are marked `blocked-by-failure`).
- **No live-default PR.** All work happens in sibling worktrees branched off the resolved base. The main checkout stays on base for orchestration.
- **No unbound ids.** `--ids` must be real GitHub issue numbers with binders. `ensure-workspace` still rejects `tkt-0` / fake ids.

## Relationship

| Skill | Role in batch-work |
| --- | --- |
| `start-work` | Spawned per ticket in its worktree; implements to acceptance |
| `create-tickets` | Source of `parallel_group` + `blocked_by` + `paths` in binders |
| `finish-work` | **Not** called by spawned agents (`BATCH_WORK=1`); human runs per PR after review |
| `create-pr` | Called by spawned agents to open the PR (stop point) |
| `create-review` | Optional: host may write one `rev` summarizing the batch outcome |

## Anti-patterns

| Don’t | Why |
| --- | --- |
| Spawn agents without independence gates / path overlap check | Shared paths → merge conflicts + violated disjoint-write rule |
| Allow spawned agents to call `finish-work` (merge) | Loses the human review gate; `BATCH_WORK=1` blocks this |
| Skip RAM check before a layer | Machine thrash → all agents fail; worse than a stopped batch |
| Reuse one worktree for multiple parallel tickets | Violates one-tree-per-PR + disjoint-write invariants |
| Treat batch as unattended merge | Batch fans out to PRs; merge is a separate human-owned step |
| Re-create Spec / re-grill product scope inside batch | Scope must be locked before batch; fuzzy → `create-spec` first |
| One agent crash blocks the whole batch | Failure isolation: collect, report, continue |
| Dry-run that spawns | `--dry-run` exits before any `ensure-workspace` / Agent call |
| Fan out on `--ids` that lack binders | Binder is recovery SoT; fail closed if missing |

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| "Two tickets touch the same file — spawn both anyway" | Path overlap → serial in one tree, or fail closed; never parallel |
| "Agent can merge its own PR to save a step" | `BATCH_WORK=1` blocks merge; human review is the gate |
| "RAM is fine, skip the check" | Thrash kills all agents; the check is cheap and fail-closed |
| "Dry-run is just a print" | Dry-run must exit before spawn — no worktree, no agent |
| "Failed ticket → abort everything" | Failure isolation: peers and later layers continue; only `blocked_by` chain stops |
| "Batch-work replaces start-work" | Batch spawns `start-work` per ticket; it is the orchestration layer, not the implementer |

## Verification

Before claiming a batch is done:

- [ ] DAG built from binder `blocked_by` + `parallel_group`; layers printed
- [ ] Independence gates pass within each layer (disjoint `paths`)
- [ ] `--dry-run` (if requested) printed DAG and exited before any spawn
- [ ] RAM check ran before each layer; below-threshold layer stopped the batch with a partial report
- [ ] One sibling worktree per ticket via `ensure-workspace --mode worktree --bind tkt`
- [ ] Spawned agents ran with `BATCH_WORK=1`; no agent called `finish-work`
- [ ] Layer barrier waited for all agents before next layer
- [ ] Failure isolation: a crashed agent recorded `failed`; peers + later layers continued
- [ ] Report table emitted (ticket, layer, worktree, status, PR URL, binder path) to stdout and `--report`
- [ ] Open PRs left for human review; handoff states "run `finish-work` per PR"
