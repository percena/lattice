---
name: batch-work
description: "DAG-orchestrated unattended batch delivery: spawn multiple start-work agents in parallel on sibling worktrees with layer-barrier synchronization. Use when a Spec/ticket set has independence-gated parallel groups and the user wants one command to fan out work. Not for single-ticket start, fuzzy product align, PR merge, or manual ticket splitting."
allowed-tools: Bash Read Grep Glob Task AskUserQuestion
argument-hint: "[--ids ID1,ID2,... | --groups] [--spawn-mode {agent,process}] [--concurrency N] [--ram-threshold <GB>] [--base <ref>] [--report <path>] [--dry-run] [--with-review]"
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
| DAG build, layer barrier, spawn/collect, watchdog, fuse, stacked-base, `--with-review` recipes | `references/flow.md` |
| Decision protocol injected into every spawn brief | `../_lattice-lib/references/decision-policy.md` |
| Fallback protocol, caps, batch-fuse law injected into every spawn brief | `../_lattice-lib/references/fallback-policy.md` |
| `--with-review` chain review + morning digest | `../review-delivery/SKILL.md` |
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
| `--with-review`: night run ends in a ranked morning digest | Standalone chain review of already-open PRs → `review-delivery` |
| Human reviews PRs after batch, then `finish-work` per PR | Merge / cleanup → `finish-work` |
| | Open a single PR → `create-pr` |

## Invariants (must hold)

| INVARIANT | Detail |
| --- | --- |
| Independence gate | Every ticket in a parallel group must pass the `create-tickets` independence gates (disjoint `paths`, no shared API/type without Spec/ADR). Path-overlapping tickets are **serial** within one tree, not parallel |
| One worktree per tkt | Each spawned ticket gets its own sibling worktree via `ensure-workspace.sh --mode worktree --bind tkt --id N --slug <slug>`. Never share a tree across parallel tickets |
| Spawn mode is execution-primitive only | `--spawn-mode` selects the spawn primitive + status-detection backend, **nothing else**. Independence gate, worktree-per-tkt, batch marker, fuse + graceful drain, spawn-brief contract, stacked dependency bases, and binder SoT stamping hold **identically** in `agent` and `process` modes (ADR-008 INVARIANT) |
| Batch marker blocks merge | Before spawning the first agent, the orchestrator writes ONE `.lattice/.batch-work-active` marker at the repo MAIN clone `.lattice/` (single gate point — NOT per-worktree; retiring per-worktree copies is the spc-186 A1 decision). The merge hook (plugins/lattice/hooks/lib/batch-merge-gate.sh) blocks `gh pr merge` while the marker exists; finish-work removes it as a deliberate scripted step BEFORE merge (after human ack). Agents stop at `create-pr` (PR opened, human reviews, then human runs finish-work per PR). The marker carries a batch-id + timestamp line |
| RAM threshold before spawn | Before each layer spawn, check available RAM ≥ threshold (default 10 GB). Below threshold → fail closed for that layer (do not spawn); report and stop |
| Failure isolation | One agent crash does not block peers in the same layer or subsequent layers. Collect exit codes; a failed ticket is reported, not fatal |
| Accountable owner | One host owns DAG build, spawn, collect, and report. Delegated `start-work` agents own only their bounded ticket brief; host validates final PR list |
| Bound ids only | All `--ids` must resolve to real GitHub issue numbers (≥1) with a binder. `tkt-0` / fake ids remain forbidden (inherited from `ensure-workspace`) |
| No live-default PR | Agents never open PRs from the live default branch; worktrees branch off the resolved base |
| Spawn-brief contract | Every spawn brief carries the five items of the **Spawn-brief contract** section below: decision protocol, fallback protocol, evidence contract, per-agent scratch uniqueness, public-repo pre-authorization (when public). A brief missing any applicable item is malformed — do not spawn on it |
| Watchdog / timebox | Each spawn brief carries a per-ticket wall-clock timebox (DEFAULT per mode S/M/C; tunable `.lattice/config.yaml`). A ticket exceeding it is marked `failed` — the watchdog extends failure isolation from crashes to hangs. **At trip time, the host stamps the binder `status: stuck` + `wait_reason: unblock`** (FSM-2b, tkt-132) so the SoT reflects "needs human investigation," not "active work" — morning triage routes it through the existing stuck exits. The binder is left with whatever ledger exists; never deleted |
| Layer fuse + graceful drain | At each layer/wave barrier compute the layer's failed+stuck ratio; over threshold (DEFAULT 50%, tunable `.lattice/config.yaml`) → halt subsequent layers/waves, **graceful-drain** in-flight agents (finish current attempt, write ledgers — no mid-write kills), report partial results. The law is `fallback-policy.md` §Batch fuse; this skill is the wiring |
| Binder `status` is stamped | Spawned tickets flip binder `status` `queued → in-progress → pr-open` (agents stamp it per their brief; enum + validator per the ticket-binder template). Fuse-halted tickets stamp `deferred` + `wait_reason: fuse-halt` at trip time (ADR-004 amd tkt-136 Option B); blocked-by-failure dependents stamp `deferred` + `wait_reason: blocked-by-failure`; watchdog-timeout stamps `stuck` + `wait_reason: unblock` (FSM-2b, tkt-132). Never-spawned tickets have four mutually-exclusive reasons (see `references/flow.md` §Never-spawned reason mapping): `not-selected` and `workspace-failed` leave the binder `queued` (still schedulable); `fuse-halted` and `blocked-by-failure` stamp `deferred` (not schedulable until a human re-queues). No new enum values |
| `--with-review` is advice-only | Chains `review-delivery` after the last layer; material findings dispatch a bounded fix loop (≤2 cycles); the digest is the batch's final report artifact. Merge authority unchanged — marker + human `finish-work` |

## Defaults and escapes

| DEFAULT | Escape / HINT |
| --- | --- |
| `--concurrency 3` per layer | User opt-in `--concurrency N`; respect machine RAM + agent overhead |
| `--spawn-mode agent` (in-session Task subagent) | `--spawn-mode process`: spawn independent `claude --bg` detached processes per worktree + PID/`claude agents` polling (ADR-008). Execution isolation: host context freed from N completion reports; host-crash blast radius eliminated. Headless (visibility is not a goal) |
| RAM threshold 10 GB | `--ram-threshold <GB>`; set 0 to disable (not recommended) |
| **Required:** one of `--ids` or `--groups` | `--ids ID1,ID2,…` runs one layer (all parallel if gates pass); `--groups` reads `parallel_group` + `blocked_by` from **all** binders and builds DAG |
| Batch marker → agents create-pr only | To disable the gate, omit the marker file at MAIN `.lattice/` (discouraged; loses human review gate). Human-authorized merge escape: remove the marker, or set `.batch-merge-authorized` with a structured reason (ADR-007 §5b/§5c) |
| Report to stdout | `--report <path>` writes a durable Markdown report |
| Dry-run shows DAG + layers, no spawn | `--dry-run` always exits before any `ensure-workspace` / Agent call |
| Base = integration-branch resolved | `--base <ref>` override; passed through to `ensure-workspace`. Dependent (`blocked_by`) layers get a **stacked base** built by sequential merges of prior heads — see `references/flow.md` |
| Per-ticket timebox per mode: S 30 min / M 60 min / C 120 min | `.lattice/config.yaml` keys `batch_timebox_S/M/C` (minutes) |
| Fuse threshold 50% failed+stuck per layer | `.lattice/config.yaml` key `batch_fuse_threshold` (percent) |
| No chained review | `--with-review` chains `review-delivery` after the last layer (advice-only; see flow) |
| Operator states a durable work preference while directing the batch → the orchestrator writes it to `.lattice/preferences.md` at utterance time + one-line confirm (`../_lattice-lib/references/decision-policy.md` §Capture duty) | Feature-scoped / system-shape statements route per the capture-duty heuristic |
| Agent notices a defect outside its ticket's `paths` → binder `## Notes` line `- NOTICED: <path> — <one line> (out-of-paths, <date>)` at notice time, then move on (`../_lattice-lib/references/decision-policy.md` §Observation duty) | When `gh` is cheap + pre-authorized (brief item 5), optionally ALSO file an issue and reference it; the binder line stays mandatory |

## Spawn-brief contract (INVARIANT)

Every spawn brief carries all six items (full template: `references/flow.md` §SPAWN LAYER). Cite the policies — do not paste their bodies into the brief; the agent reads the referenced files.

| # | Item | Content |
| --- | --- | --- |
| 1 | Decision protocol | Cite `_lattice-lib/references/decision-policy.md`: resolve every mid-execution decision through the chain; reversible + ticket-local → self-decide + binder `## Decision journal` entry citing the source; anything else → park & pivot (`## Pending decisions` + reversible seam). Never block waiting on a human |
| 2 | Fallback protocol | Cite `_lattice-lib/references/fallback-policy.md`: articulated-difference rule before any retry, caps (≤2 tries/path, ≤3 paths/ticket, the brief's timebox), early-stop signals (same error twice, scope escape), stuck-with-ledger = deliverable |
| 3 | Evidence contract | Fresh test/validator output pasted in the PR body (no stale or paraphrased runs); decision journal entries in the binder; e2e evidence when UI is touched |
| 4 | Scratch uniqueness | Parallel agents share one scratchpad — real collisions observed. Every scratch file/dir gets a per-ticket unique suffix or subdir (e.g. `…-tkt-<id>` or `tkt-<id>/`) |
| 5 | Public-repo pre-authorization | A night agent cannot "explicitly confirm" `create-pr`'s public-repo step — no human is present. When the repo is PUBLIC, the orchestrator pre-authorizes PR creation **in the brief** and mandates the sanitize self-check (no internal URLs, personal paths, team/customer identifiers in title/body) before `gh pr create` |
| 6 | Verify-after-mutate | A `gh pr create` / `gh pr merge` / `git push` that reported success but left no durable artifact is the highest-cost silent failure (rev-20260829-140444Z F5). After every such mutation, run `skills/_lattice-lib/scripts/verify-mutation.sh --pr <N>` (or `--commit`/`--branch`) and include the `verified:`/`FAILED:` line in your report. On `FAILED`, **do not proceed on assumed success** — stamp `stuck` + `wait_reason: unblock` and stop. The host also probes each agent-claimed PR in the report step |

The brief also carries the per-ticket timebox, the binder `status` stamping instruction (`in-progress` on start, `pr-open` after `create-pr`), and — for stacked layers — the base ref, the Stacking note for the PR body, and the interface contracts (exact file/section names) the ticket depends on.

## Step 0 (every run)

> **Note:** `--dry-run` does **not** skip Step 0. `ensure-lattice.sh` is an idempotent writer (creates/refreshes `.lattice/` scaffolding only); it always runs, even in dry-run, so the DAG build has the binders it expects. Dry-run exits before any `ensure-workspace` / `Agent` call, not before lattice setup.

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")
bash "$LIB/ensure-lattice.sh"
```

## Flow

1. **INTAKE** — parse args: `--ids`, `--groups`, `--spawn-mode` (default `agent`; ∈ {agent,process}, else fail closed), `--concurrency`, `--report`, `--dry-run`, `--ram-threshold`, `--base`, `--with-review`. Read timebox + fuse tunables from `.lattice/config.yaml` (defaults above).
2. **RESOLVE TICKETS** — for each id, locate binder `.lattice/tickets/tkt-<id>-<slug>/README.md`; extract `parallel_group`, `blocked_by`, `paths`, `worktree_bind`, `slug`. Fail closed if a binder is missing.
3. **BUILD DAG** — nodes = tickets; edges = `blocked_by`. Topologically sort into layers: layer 0 = no blockers, layer k = all `blocked_by` satisfied by layers < k. Tickets with the same `parallel_group` and no cross-dependency share a layer.
4. **VALIDATE INDEPENDENCE** — within each layer, confirm `paths` are disjoint (no path glob overlap across tickets in the same layer). Overlap → demote to serial (next layer) or fail closed with a report.
5. **DRY-RUN EXIT** — if `--dry-run`, print DAG (layers + ticket ids + worktree paths + concurrency) and exit 0 before any spawn.
6. **RAM CHECK** — before each layer: read available RAM (macOS `vm_stat` + `sysctl -n hw.pagesize`; Linux `/proc/meminfo`). Below threshold → fail closed for this layer; stop batch; report partial results.
7. **SPAWN LAYER (waves)** — if the layer has more tickets than `--concurrency`, spawn in **waves** of `--concurrency` tickets each, with a barrier between waves (see step 8). Within a wave:
   - Resolve worktree binding: honor the binder's `worktree_bind` field if present (pass through to `ensure-workspace`), else fall back to the standard `--bind tkt --id <N> --slug <slug>` pattern.
   - `bash "$LIB/ensure-workspace.sh" --mode worktree --bind tkt --id <N> --slug <slug> [--base <ref>]` (or the binder's `worktree_bind` override).
   - Capture `path` + `cd_hint` from JSON.
   - Launch the ticket per `--spawn-mode` (ADR-008). Before spawning the FIRST ticket in the batch, write the batch marker at the MAIN clone (single gate point): `printf 'batch-id: %s\nstarted: %s\n' "$(date -u +%Y%m%d)-$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > <MAIN>/.lattice/.batch-work-active` (do NOT write per-worktree copies). Brief: full **Spawn-brief contract** template (`references/flow.md` §SPAWN LAYER) — core instruction stays "run `start-work tkt-<id>` in worktree <path>; implement to acceptance; open PR via `create-pr`; do NOT call `finish-work`", plus the six contract items, the timebox, and the binder-status stamping instruction.
     - `agent` (default): Launch a `Task` (`subagent_type: general-purpose` or the configured start-work agent) with `run_in_background: true`. Status arrives via the background-completion channel.
     - `process`: Write the brief to a file, then per wave call `bash skills/batch-work/scripts/run-process-wave.sh --manifest <wave-manifest> --concurrency <N> --ram-threshold <GB> --state-file <batch-state> [--report <path>]` (`references/flow.md` §PROCESS-MODE SPAWN + §PROCESS-MODE STATUS DETECTION). The wave manifest is TSV `ticket<TAB>worktree<TAB>brief_file<TAB>timebox_min`; worktrees are ensure-workspace'd first. The script spawns `claude --bg` detached per worktree (via `spawn-ticket-process.sh`), polls `kill -0` + per-ticket timebox, and prints a compact report — the host's context is not flooded by N completion reports. PID-from-exit is `completed`/`timeout`; the host still probes each completed ticket's PR via `verify-mutation.sh` (spawn-brief item 6).
   - Bound delegation: the agent owns only its ticket brief + worktree; host owns DAG + report.
   - Record spawn timestamp per ticket (watchdog input).
8. **LAYER/WAVE BARRIER + WATCHDOG** — wait for all tickets in the current wave to settle (success or fail). A ticket exceeding its timebox is marked `failed` (`timeout`) and no longer waited on; its binder keeps whatever ledger exists. Collect exit status + PR URL per ticket. In `process` mode the wave script's `completed`/`timeout` rows ARE this barrier's result; in `agent` mode the in-session background-completion channel is the result. **FUSE CHECK:** compute the layer's cumulative failed+stuck ratio; over threshold → halt all subsequent waves/layers, graceful-drain in-flight agents (finish current attempt, write ledgers), jump to REPORT with partial results. Otherwise, if more waves remain in this layer, run RAM check again and spawn the next wave. A failed ticket is recorded; peers and subsequent waves/layers proceed (failure isolation).
9. **NEXT LAYER** — repeat RAM check + spawn for the next layer. A ticket whose `blocked_by` includes a failed dependency is skipped (recorded as blocked-by-failure). If the layer depends on earlier layers' unmerged output, build the **stacked base** (sequential merges of prior heads — `references/flow.md` §STACKED DEPENDENCY BASES) and pass it via `--base`.
10. **WITH-REVIEW (opt-in)** — if `--with-review`: after the last layer's barrier, chain `review-delivery` on the batch report; material findings dispatch a bounded fix loop (re-brief the ticket's agent in its worktree, ≤2 cycles) before the digest is finalized (`references/flow.md` §WITH-REVIEW). Advice-only; no merge.
11. **REPORT** — emit a Markdown table: ticket, layer, worktree path, agent status (ok/failed/blocked/fuse-halted), PR URL, binder path. Write to `--report <path>` if given; always also print to stdout. Under `--with-review`, the digest is the batch's final report artifact (the table is referenced from it).
12. **HANDOFF** — summary: N spawned, M ok, K failed, L blocked (+ fuse trip if any). Human reviews open PRs (digest-first when `--with-review`), then runs `finish-work` per PR. The repo-MAIN `.lattice/.batch-work-active` marker ensured no agent merged.

Detailed recipes (DAG build, RAM probe, spawn/collect, report shape): **`references/flow.md`**.

## Safety

- **Batch marker merge block.** Before spawning the first agent, the orchestrator writes ONE `.lattice/.batch-work-active` marker at the repo MAIN clone `.lattice/` (single gate point — not per-worktree; spc-186 A1 retires per-worktree copies). The merge hook (plugins/lattice/hooks/lib/batch-merge-gate.sh) blocks `gh pr merge` while the marker is present, keeping a human review gate over the batch. Agents are instructed not to call `finish-work`. **The marker is removed by finish-work as a deliberate scripted step BEFORE merge** (after human ack, via `batch-merge-gate.sh --remove --reason "..."`), not after the merge — the merge hook enforces this fail-closed.
- **RAM threshold.** Default 10 GB available before spawn. Spawn is skipped (fail closed) when RAM is below threshold; the batch stops with a partial report rather than thrashing the machine. Override via `--ram-threshold <GB>`; `0` disables (not recommended).
- **Failure isolation.** Agent crashes are per-ticket. The host collects each agent's result via the background-completion channel; a crash is recorded as `failed` for that ticket and does not block peers in the same layer or tickets in later layers (except tickets `blocked_by` the failed one, which are marked `blocked-by-failure`).
- **Watchdog / timebox.** Failure isolation covers hangs, not just crashes: each brief carries a per-ticket wall-clock timebox (DEFAULT per mode S/M/C; `.lattice/config.yaml`); a ticket that exceeds it is marked `failed` (`timeout`) and the batch moves on. **At trip time, the host stamps the binder `status: stuck` + `wait_reason: unblock`** (FSM-2b, tkt-132) so the binder SoT reflects "needs human investigation" — morning triage routes it through the existing stuck exits (unblock / re-scope / cancel). The worktree and binder are left intact — whatever `## Attempts` / journal ledger exists is the deliverable.
- **Layer fuse + graceful drain.** At each barrier the host computes the layer's failed+stuck ratio; over threshold (DEFAULT 50%, `.lattice/config.yaml`) the failure is systemic — halt subsequent layers/waves, let in-flight agents finish their current attempt and write their ledgers (no mid-write kills), and report partial results. Law: `fallback-policy.md` §Batch fuse.
- **`--with-review` never merges.** The chained `review-delivery` digest and its fix loop are advice; merge authority is unchanged (marker + human `finish-work`).
- **No live-default PR.** All work happens in sibling worktrees branched off the resolved base. The main checkout stays on base for orchestration.
- **No unbound ids.** `--ids` must be real GitHub issue numbers with binders. `ensure-workspace` still rejects `tkt-0` / fake ids.

## Relationship

| Skill | Role in batch-work |
| --- | --- |
| `start-work` | Spawned per ticket in its worktree; implements to acceptance |
| `create-tickets` | Source of `parallel_group` + `blocked_by` + `paths` in binders |
| `finish-work` | **Not** called by spawned agents (`.batch-work-active` marker + prompt instruction); human runs per PR after review |
| `create-pr` | Called by spawned agents to open the PR (stop point) |
| `create-review` | Optional: host may write one `rev` summarizing the batch outcome |
| `review-delivery` | Chained by `--with-review` after the last layer; consumes the batch report; material findings dispatch a bounded (≤2 cycles) fix loop before the digest — the batch's final report artifact — is finalized |

## Anti-patterns

| Don’t | Why |
| --- | --- |
| Spawn agents without independence gates / path overlap check | Shared paths → merge conflicts + violated disjoint-write rule |
| Allow spawned agents to call `finish-work` (merge) | Loses the human review gate; the `.batch-work-active` marker blocks this |
| Skip RAM check before a layer | Machine thrash → all agents fail; worse than a stopped batch |
| Reuse one worktree for multiple parallel tickets | Violates one-tree-per-PR + disjoint-write invariants |
| Treat batch as unattended merge | Batch fans out to PRs; merge is a separate human-owned step |
| Re-create Spec / re-grill product scope inside batch | Scope must be locked before batch; fuzzy → `create-spec` first |
| One agent crash blocks the whole batch | Failure isolation: collect, report, continue |
| Dry-run that spawns | `--dry-run` exits before any `ensure-workspace` / Agent call |
| Fan out on `--ids` that lack binders | Binder is recovery SoT; fail closed if missing |
| Spawn a brief without the five contract items | Policy-blind agents block, spin, or leak — the brief is the night's law |
| Kill in-flight agents when the fuse trips | Graceful drain: finish the attempt, write the ledger; mid-write kills destroy the morning's map |
| Octopus-merge prior heads for a dependency base | Octopus fails on shared-file edits; build the integration branch by sequential merges |

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| "Two tickets touch the same file — spawn both anyway" | Path overlap → serial in one tree, or fail closed; never parallel |
| "Agent can merge its own PR to save a step" | The `.batch-work-active` marker blocks merge; human review is the gate |
| "RAM is fine, skip the check" | Thrash kills all agents; the check is cheap and fail-closed |
| "Dry-run is just a print" | Dry-run must exit before spawn — no worktree, no agent |
| "Failed ticket → abort everything" | Failure isolation: peers and later layers continue; only `blocked_by` chain stops |
| "Batch-work replaces start-work" | Batch spawns `start-work` per ticket; it is the orchestration layer, not the implementer |
| "Octopus-merge the layer heads for the next layer's base" | Octopus fails on shared-file edits (observed in practice). Sequential merges of prior heads, in layer order |
| "The agent can confirm the public-repo step itself" | A night agent has no human to satisfy `create-pr`'s explicit-confirm gate; the orchestrator pre-authorizes in the brief and mandates the sanitize self-check |
| "The hung agent will finish eventually — keep waiting" | The timebox *is* the wait. Watchdog marks `failed`, keeps the ledger, moves on |
| "Fuse tripped but the next layer's tickets look independent" | Over-threshold means systemic (broken base/env), not per-ticket bad luck — halt, drain, report |
| "Each parallel branch can bump the version its own way" | Divergent version bumps conflict on sequential merges; version bump is deferred to the dev→main release boundary (ADR-005), not per-PR on the integration branch |
| "Two agents, one scratchpad — names won't collide" | They did (observed). Per-ticket suffix/subdir is part of the brief |
| "Digest says auto-pass, so merge it" | `--with-review` is advice-only; marker + human `finish-work` remain the merge authority |

## Red Flags

- Two tickets in the same layer whose binder `paths` rows overlap — the independence gate was skipped
- A spawned worktree without the repo-MAIN `.lattice/.batch-work-active` marker (single gate point), or any agent invoking merge/`finish-work` during the batch window
- Spawn briefs missing contract items (decision policy, evidence contract, timebox) — "the agent will figure it out" is how nights are lost

## Verification

Before claiming a batch is done:

- [ ] DAG built from binder `blocked_by` + `parallel_group`; layers printed
- [ ] Independence gates pass within each layer (disjoint `paths`)
- [ ] `--dry-run` (if requested) printed DAG and exited before any spawn
- [ ] RAM check ran before each layer; below-threshold layer stopped the batch with a partial report
- [ ] One sibling worktree per ticket via `ensure-workspace --mode worktree --bind tkt`
- [ ] `--spawn-mode` selection honored at SPAWN LAYER (`agent`→Task in-session; `process`→`run-process-wave.sh` + `spawn-ticket-process.sh` detached per worktree); `--dry-run` prints the selected mode; all orchestration invariants hold in both modes (ADR-008)
- [ ] Orchestrator wrote ONE `.lattice/.batch-work-active` marker at the repo MAIN clone `.lattice/` (batch-id + timestamp); no per-worktree copies; no agent called `finish-work`
- [ ] Layer barrier waited for all agents before next layer
- [ ] Failure isolation: a crashed agent recorded `failed`; peers + later layers continued
- [ ] Report table emitted (ticket, layer, worktree, status, PR URL, binder path) to stdout and `--report`
- [ ] Open PRs left for human review; handoff states "run `finish-work` per PR"
- [ ] Every spawn brief carried all applicable Spawn-brief contract items: decision-policy cite, fallback-policy cite, evidence contract, scratch uniqueness, public-repo pre-auth (when public)
- [ ] Per-ticket timebox rode each brief; watchdog marked over-timebox tickets `failed` (`timeout`), stamped binder `stuck` + `wait_reason: unblock` at trip time, and left the binder ledger intact
- [ ] Fuse ratio computed at every barrier; a trip halted subsequent layers/waves, drained in-flight agents gracefully, and produced a partial report
- [ ] Dependent layers spawned off a sequential-merge stacked base via `--base`; PRs targeted the true base and carried a Stacking note; interface contracts rode the briefs
- [ ] `--with-review` (if requested): `review-delivery` ran on the batch report after the last barrier; material findings dispatched a bounded (≤2 cycles) fix loop; digest finalized as the batch's final report artifact; no merge performed
- [ ] Binder `status` stamped `queued → in-progress → pr-open` per spawned ticket; fuse-halted/blocked-by-failure stamped `deferred`+`wait_reason`; watchdog-timeout stamped `stuck`+`wait_reason`; the four never-spawned reasons (`not-selected`/`workspace-failed`→`queued`, `fuse-halted`/`blocked-by-failure`→`deferred`) each map to exactly one binder state (no invented enum values)
