# Batch-work flow recipes

Detailed step recipes for the `batch-work` skill. The `SKILL.md` is the protocol + invariants; this file holds the long scripts. Load on demand only when executing a specific phase.

## Arg parsing

```
--ids ID1,ID2,...      Comma-separated GitHub issue numbers (one layer; all parallel if gates pass)
--groups               Read parallel_group + blocked_by from each ticket binder; build DAG
--spawn-mode {agent,process}  Execution primitive (default: agent). process spawns
                       independent `claude --bg` detached processes per worktree + PID
                       polling (ADR-008); all orchestration invariants hold in both modes
--concurrency N        Max agents spawned per layer (default 3)
--report <path>        Write Markdown report to <path> (always also stdout)
--dry-run              Print DAG + layer assignment + spawn-mode; exit before any spawn
--ram-threshold <GB>   Skip spawn if available RAM below this (default 10; 0 disables)
--base <ref>           Base ref override passed to ensure-workspace.sh
--with-review          After the last layer's barrier, chain review-delivery on the batch
                       report (bounded fix loop for material findings; advice-only)
```

`--ids` and `--groups` are mutually exclusive. If neither is given, fail closed with usage.

Config tunables (`.lattice/config.yaml`, flat grep-able keys; all DEFAULT, absent = defaults below):

```yaml
batch_timebox_S: 30        # per-ticket wall-clock timebox, minutes, mode S
batch_timebox_M: 60        # mode M
batch_timebox_C: 120       # mode C
batch_fuse_threshold: 50   # layer failed+stuck percentage that trips the fuse
```

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
spawn-mode: <agent|process>
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
   - Prompt brief (bounded delegation — the **Spawn-brief contract**, SKILL.md; every numbered block below is mandatory when applicable):
     ```
     Worktree: <path> (branch <branch>). cd there before any work.
     Run: start-work tkt-<id>.
     Batch marker: .lattice/.batch-work-active is present at the repo MAIN clone
     .lattice/ (single gate point — NOT in this worktree). The merge hook blocks
     `gh pr merge` while it exists. Do not call finish-work; do not remove the marker.
     Never `git add -A`; stage named paths.
     Implement to the ticket's Acceptance criteria. Then open a PR via create-pr.
     Stop after create-pr. Report the PR URL.

     VERIFY-AFTER-MUTATE (Spawn-brief item 6): after gh pr create, run
     `bash skills/_lattice-lib/scripts/verify-main-chain.sh --stage pr --pr <N>
     --expected-oid <pushed HEAD> --repo <owner/name> --expected-base <base>
     --expected-head <branch>` (spc-254 A2/D5 — the one shared main-chain
     contract; push stage first: capture local HEAD before `git push`, then
     `--stage push --branch <branch> --expected-oid <local HEAD>`). Paste the
     `verified:`/`FAILED:` line into your report. Absent output or nonzero is
     HARD failure — do not treat it as "ambiguous, proceed"; stamp
     `stuck` + `wait_reason: unblock` and stop. The host re-probes every
     claimed PR in the report step; an unverified claim is flagged.

     TIMEBOX: <N> minutes wall-clock (mode <S|M|C>). Exceeding it marks this
     ticket failed; leave the binder ledger current at all times.

     BINDER STATUS: stamp the binder field-table status: in-progress when you
     start, pr-open after create-pr. (stuck/parked per the policies below.)

     DECISION PROTOCOL — read skills/_lattice-lib/references/decision-policy.md:
     resolve every mid-execution decision through its chain; reversible +
     ticket-local -> self-decide + "## Decision journal" entry citing the source;
     irreversible or cross-contract -> park & pivot ("## Pending decisions" +
     most-reversible seam). Never block waiting on a human.

     FALLBACK PROTOCOL — read skills/_lattice-lib/references/fallback-policy.md:
     articulated-difference before any retry; caps <=2 tries/path, <=3
     paths/ticket, the timebox above; early-stop on same-error-twice or scope
     escape; stop-with-ledger + one well-formed question is a deliverable.

     EVIDENCE CONTRACT: paste fresh `bash tools/ci-local.sh` output (summary
     table) in the PR body (engine repo; in a consumer repo, the repo's
     CI-parity command when one exists, else its test/validator runs). No
     stale or paraphrased runs; decision journal entries live in the binder;
     e2e evidence when UI is touched.

     SCRATCH: the scratchpad is shared across parallel agents — suffix every
     scratch file/dir with -tkt-<id> (or use subdir tkt-<id>/).

     [PUBLIC repo only] PRE-AUTHORIZATION: this brief pre-authorizes the
     create-pr public-repo step — do not wait for a human confirm. You MUST
     still run the sanitize self-check: no internal URLs, personal paths,
     team/customer identifiers in the PR title/body.

     [Stacked layer only] BASE + STACKING: your branch is based on <integration
     branch> (unmerged prior-layer work). Your PR still targets <true base>;
     add a "Stacking" note: "Stacked on <PR list>; diff cleans as those merge."
     Interface contracts you depend on: <exact file/section names from the
     prior layer's tickets>.
     ```
   - Before spawning the FIRST agent, write the batch marker at the repo MAIN clone (single gate point, spc-186 A1): `printf 'batch-id: %s\nstarted: %s\n' "$(date -u +%Y%m%d)-$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > <MAIN>/.lattice/.batch-work-active`. Do NOT write per-worktree copies. The marker stays untracked (MAIN `.lattice/.gitignore` or base-residue check tolerates it).
   - Record agent handle + ticket id + worktree path + **spawn timestamp** (watchdog input).

## WATCHDOG / TIMEBOX

Failure isolation covered crashes; the watchdog extends it to **hangs**.

- Each ticket's timebox comes from its spawn brief: DEFAULT per ticket mode — `batch_timebox_S/M/C` minutes from `.lattice/config.yaml` (30/60/120 when unset).
- While waiting at a barrier, check wall-clock elapsed per still-running ticket (`now − spawn timestamp`).
- Elapsed > timebox → mark the ticket `failed` (reason `timeout`), stop waiting on it, and move on. Do not let one hung agent hold the barrier past its timebox.
- **At trip time, stamp the binder `status: stuck` + `wait_reason: unblock`** (FSM-2b, tkt-132) so the SoT reflects "needs human investigation," not "active work." Morning triage routes it through the existing stuck exits (unblock / re-scope / cancel). The binder is never left at `in-progress` after a timeout — that would be an abandoned-ticket blind spot across runs (no durable failure signal; `--groups` re-spawns it with undefined behavior).
- Leave the worktree and binder **intact** — whatever `## Attempts` / `## Decision journal` ledger the agent wrote is the morning deliverable. Never delete or reset a timed-out worktree.
- A timed-out ticket counts toward the layer's fuse ratio (below) and marks its dependents `blocked-by-failure`.

## LAYER BARRIER

Wait for all agents spawned in the current **wave** to complete (background-completion channel), enforcing the WATCHDOG above. For each:

- Success with PR URL → `ok`, record PR URL. **Then probe it**: run `bash "$LIB/verify-mutation.sh" --pr <N>` (Spawn-brief item 6); the report's `verified` column is `ok` only if the probe confirms the PR exists OPEN at the claimed head. A claim whose probe `FAILED`s is recorded `unverified` (not `ok`) — the host does not merge on an unverified claim; morning triage investigates.
- Agent reported failure / no PR → `failed`, record reason.
- Timebox exceeded → `failed`, record `timeout` (watchdog).
- Agent stopped under fallback policy (binder `status: stuck`) → `stuck`, record the binder's question.

Then run the FUSE CHECK (below). If the fuse holds and more waves remain in this layer, re-run the RAM CHECK and spawn the next wave. A `failed` ticket does not block peers in the same wave. Once all waves of the layer finish, proceed to the next layer.

## FUSE CHECK + GRACEFUL DRAIN

Law: `../_lattice-lib/references/fallback-policy.md` §Batch fuse — over-threshold layer failure is systemic (broken base or environment), not per-ticket bad luck. This section is the wiring.

At every wave/layer barrier:

1. Compute the layer's cumulative ratio: `(failed + stuck) / completed-so-far in this layer` (timeouts count as failed).
2. Ratio > `batch_fuse_threshold` (DEFAULT 50%) → **trip**:
   - **Halt** all subsequent waves and layers — nothing new spawns into a broken base.
   - **Graceful-drain** in-flight agents: let each finish its current attempt and write its ledgers; **no mid-write kills**. Apply the watchdog timebox as the outer bound on the drain.
   - Record every never-spawned ticket as `fuse-halted` in the report. **Stamp its binder `status: deferred` + `wait_reason: fuse-halt`** (ADR-004 amd tkt-136 Option B) so the SoT reflects "not schedulable"; `deferred → queued` remains a human transition (re-schedule into a later batch). No new enum values — `deferred` already exists.
   - Emit the partial REPORT (all completed results + the trip: layer, ratio, threshold) and stop the batch.
3. Ratio ≤ threshold → continue normally.

## PROCESS-MODE SPAWN (`--spawn-mode process`)

When `--spawn-mode process`, SPAWN LAYER delegates to a helper script so the host LLM session never holds N child PIDs in-band and its context is not flooded by completion reports (ADR-008's core win).

Per wave, after every ticket in the wave has been `ensure-workspace`'d and its brief written to a per-ticket file (the brief must carry all six Spawn-brief contract items — ADR-008 D4):

1. Build the wave manifest (TSV; `#`/blank lines ignored). One row per ticket:
   ```
   ticket<TAB>worktree<TAB>brief_file<TAB>timebox_min
   tkt-219<TAB>/…/lattice.worktrees/tkt-219-foo<TAB>/tmp/brief-219<TAB>60
   ```
2. Call:
   ```bash
   bash skills/batch-work/scripts/run-process-wave.sh \
     --manifest <wave-manifest> \
     --concurrency <N> --ram-threshold <GB> \
     --state-file <batch-state> [--report <path>]
   ```
   The script spawns `claude --bg -p "$(cat brief_file)" --permission-mode acceptEdits` detached per worktree (via `spawn-ticket-process.sh`, which fixes the reference tool's shared-`cwd` defect by binding `cwd` to each ticket's sibling worktree — ADR-006 preserved), records pid+worktree+started-iso to the batch state file, and runs the barrier (below).
3. The batch marker (`.lattice/.batch-work-active` at repo MAIN) is written before the first wave in **both** modes — process mode is not exempt.
4. Concurrency cap + RAM gate are enforced inside the script (per-wave RAM re-check; below-threshold stops further spawns, in-flight continues). The host's `--concurrency` / `--ram-threshold` pass straight through.

The host records the wave's report rows (compact: ticket/pid/status/timebox/duration) — NOT the per-agent transcript. The spawn-brief still carries the verify-after-mutate mandate (item 6); the host re-probes each `completed` ticket's PR via `verify-mutation.sh --pr <N>` in the report step.

## PROCESS-MODE STATUS DETECTION (`--spawn-mode process`)

In `process` mode the in-session background-completion channel is unavailable (agents are independent OS processes, not Task children). Status detection switches to OS-level polling, driven by `run-process-wave.sh`:

- **Ground truth:** `kill -0 <pid>` liveness (portable across macOS/Linux). `claude agents --json` is enrichment, never the sole signal (schema-drift-tolerant; `spawn-ticket-process.sh --probe <pid>` wraps this).
- **Watchdog:** each ticket's `spawn timestamp` (recorded in the batch state file) is compared to wall-clock at each poll; `elapsed > timebox` → kill the pid, mark `timeout`, stamp the binder `status: stuck` + `wait_reason: unblock` (FSM-2b, tkt-132). Same FSM as `agent` mode — the mode flag only selects the liveness source.
- **Classification from PID alone:** `completed` (process exited within timebox) or `timeout` (killed past timebox). A `completed` ticket is **not** automatically `ok` — the host runs `verify-mutation.sh --pr <N>` to confirm the PR exists OPEN at the claimed head; an unverified claim is `unverified` (morning triage), exactly as in `agent` mode.
- **Failure isolation:** one pid's death is invisible to peers (true process isolation — ADR-008's other core win). A host-process crash no longer kills the batch; the detached `claude --bg` processes survive.
- **Fuse:** the wave script's `completed`/`timeout` counts feed the layer's failed+stuck ratio; a trip halts subsequent waves/layers with graceful drain (in-flight pids finish their attempt; no mid-write kills).


## NEXT-LAYER DEPENDENCY CHECK

Before spawning a ticket whose `blocked_by` includes a failed ticket: mark it `blocked-by-failure` and skip. Do not spawn. **Stamp its binder `status: deferred` + `wait_reason: blocked-by-failure`** (ADR-004 amd tkt-136 Option B) so the SoT reflects "not schedulable"; `deferred → queued` remains a human transition.

## STACKED DEPENDENCY BASES (blocked_by layers)

The gap this closes: a `blocked_by` layer needs the earlier layers' output, but the batch marker (at repo MAIN .lattice/) forbids merging anything mid-night. The dependency is satisfied by **stacking**, not merging:

1. At each layer boundary with unmerged dependencies, the **orchestrator** builds a local integration branch: start from the true base, then **sequentially merge** each prior layer head (`git merge <head>` one at a time, in layer order). **NOT octopus** (`git merge h1 h2 h3`) — octopus fails on shared-file edit conflicts (observed: parallel branches touching the same manifest files abort an octopus).
2. Pass the integration branch to the next layer via `ensure-workspace.sh … --base <integration-branch>`.
3. **Version/changelog handling:** version bump is deferred to the dev→main release boundary (ADR-005); parallel agents do NOT bump versions or edit the changelog. Branch-specific manifest edits (e.g. registering a new skill) ride only their own branch; the morning merge takes the superset on conflict.
4. **PRs still target the true base** (e.g. `dev`) — never the integration branch, which is local and disposable. Until earlier PRs merge, a stacked PR's diff shows the prior layers' work too; its body carries the **Stacking note** ("Stacked on <PR list>; diff cleans as those merge") so the morning human reads it in merge order.
5. **Interface contracts ride the briefs**: the exact file/section names the earlier layers delivered (what the stacked ticket may call/extend) are written into the spawn brief — the agent must not rediscover them by diffing the stack.
6. Merge order in the morning follows the DAG: earlier layers first; each merge cleans the next stacked PR's diff.

## WITH-REVIEW CHAIN (`--with-review`)

After the last layer's barrier (or after a fuse trip's drain, over whatever PRs were delivered):

1. Run `review-delivery` with the batch report path as input (`../review-delivery/SKILL.md`) — artifact-only chain review: fidelity, cross-PR coherence + throwaway integration build, decision-ratification queue, per-PR findings.
2. **Material findings** (review-code material bar) dispatch a bounded fix loop: re-brief the ticket's implementer agent **in its existing worktree** with the findings as the new brief (address-review shape; binder `pr-open → rework → in-progress → pr-open` per `_lattice-lib/references/workflow-fsm-reference.md` or monorepo `docs/workflow-fsm.md`). **≤ 2 cycles per ticket** — the fallback-policy / review-fix bound; still-material findings after cycle 2 stay in the digest as `deep-review`.
3. Finalize the digest only after the fix loop settles; the digest (persisted under `.lattice/reviews/`, `kind: digest`) is the **batch's final report artifact** — the REPORT table is referenced from it.
4. Advice only: no `gh pr merge`, no marker removal. Merge authority is unchanged — batch marker + human `finish-work` (which removes the marker BEFORE merge, after human ack).

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
| tkt-4 | L1 | — | fuse-halted | — | … |

## Summary
- spawned: 2
- ok: 1
- failed: 1 (of which timeout: 1)
- stuck: 0
- blocked-by-failure: 1
- fuse-halted: 1 (fuse tripped at L0: 50% > threshold 50%)

## Handoff
Human reviews open PRs, then runs finish-work per PR.
The repo-MAIN .lattice/.batch-work-active marker ensured no agent merged.
```

Report-status vocabulary (`ok | failed | stuck | blocked-by-failure | workspace-failed | fuse-halted`) is **report-level**, not the binder enum. Binder `status` (SoT) is stamped by the agents: `queued → in-progress → pr-open` (or `stuck`/`parked` per policy); **fuse-halted tickets stamp `deferred`+reason `fuse-halt`** (ADR-004 amd tkt-136 Option B), **blocked-by-failure dependents stamp `deferred`+reason `blocked-by-failure`**, **watchdog-timeout stamps `stuck`+`wait_reason: unblock`** (FSM-2b, tkt-132); never-spawned tickets stay `queued` — the report note is their record. Include the fuse-trip line only when it tripped. Under `--with-review`, the digest is the final artifact and references this table.

**Never-spawned reason mapping (tkt-151 A6 — one unambiguous mapping per reason):**

| Report status | Binder status | Binder wait_reason | When it applies |
| --- | --- | --- | --- |
| `not-selected` | `queued` (unchanged) | `(none)` | Ticket was not in the `--ids` set, or `--groups` never reached it (e.g. an earlier-layer fuse halted before its layer). No agent spawned, no worktree created. |
| `workspace-failed` | `queued` (unchanged) | `(none)` | `ensure-workspace.sh` failed for this ticket; no agent spawned. Worktree may be partially created — orchestrator does not retry. |
| `fuse-halted` | `deferred` | `fuse-halt` | Fuse tripped at a layer barrier **before** this ticket's wave/layer spawned. Distinct from `blocked-by-failure` (a dependency *failed*): here the *system* halted. |
| `blocked-by-failure` | `deferred` | `blocked-by-failure` | A ticket in this ticket's `blocked_by` set failed; the dependency is unsatisfied. Distinct from `fuse-halted`: a specific prior ticket failed, not a system-wide halt. |

`not-selected` and `workspace-failed` leave the binder at `queued` (the ticket is still schedulable into a later batch with no repair); `fuse-halted` and `blocked-by-failure` stamp `deferred` (the ticket is *not* schedulable until a human re-queues it — `deferred → queued` is a manual transition). These four are mutually exclusive and exhaustive over the never-spawned space; a ticket that spawned and crashed is `failed`/`stuck`, never a never-spawned reason.

## Failure-isolation contract

- The host owns DAG + spawn + collect + report. Agents own only their ticket brief + worktree.
- Agent crash → recorded `failed`; no abort of the batch.
- Agent hang → watchdog: timebox exceeded → recorded `failed` (`timeout`); worktree + binder ledger left intact.
- Workspace-creation failure → recorded `workspace-failed`; no agent spawned for that ticket.
- Dependency failure → dependent ticket `blocked-by-failure`; skipped, not spawned.
- Systemic failure → fuse: layer failed+stuck ratio over threshold → halt later layers/waves, graceful-drain in-flight agents (ledgers written, no mid-write kills), partial report.
- The host never silently re-runs a failed ticket; the report lists it for human triage. (The only sanctioned re-entry is the `--with-review` fix loop, bounded at ≤2 cycles per ticket.)
