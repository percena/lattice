# tkt-219-spawn-ticket-process-helper

<!-- Binder is a thin recovery card (not a second issue tracker). -->

> **TL;DR:** New `spawn-ticket-process.sh` helper that spawns an independent `claude --bg` detached process in a given worktree `cwd`, records PID + worktree + spawn timestamp to a per-batch state file; plus `--self-test` exercising PID tracking + liveness probe against a dummy.
> **Kind:** feat · **Priority:** P1
> **Path:** spc-213 → tkt-219 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | enhancement, P1 |
| github | https://github.com/percena/lattice/issues/219 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-08-30T00:00:00Z |
| updated | 2026-08-30T16:50:00Z |
| adopted | false |
| summary | spawn-ticket-process.sh helper: claude --bg detached per-worktree + PID state + self-test |
| spec | spc-213 — batch-work process-isolation spawn mode (path: ../../specs/spc-213-batch-work-process-spawn.md) |
| covers | A2, A6 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | skills/batch-work/scripts/** |
| solo_merge | yes |
| **primary_ticket** | tkt-219 |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-219-spawn-ticket-process-helper |
| worktree | sibling `…/lattice.worktrees/tkt-219-spawn-ticket-process-helper/` |
| prs | pr-225 — https://github.com/percena/lattice/pull/225 |

## Acceptance (this slice)

- [x] **A2** — `skills/batch-work/scripts/spawn-ticket-process.sh` exists; `--cwd <worktree> --brief-file <path> [--state-file <path>] [--base <ref>] [--permission-mode acceptEdits]` spawns `claude --bg` detached with `BATCH_*` env, records `pid`, `worktree`, `started` (UTC ISO) to the state file, exits 0 on spawn. Missing `--cwd` or `--brief-file` → fail closed (nonzero, usage to stderr).
- [x] **A6** — `--self-test` exercises PID tracking + liveness probe against a dummy (e.g. `claude --bg -p "echo ready"` or a `sleep` surrogate) without launching real implementation; asserts PID recorded + liveness detected + liveness-false after kill. Prints PASS/FAIL lines (reference: a cross-repo batch tool's self-test pattern).

## Approach

- bash helper (consistent with `_lattice-lib/scripts/`), not `.mjs`.
- Spawn: `claude --bg -p "$(cat "$BRIEF_FILE")" --permission-mode "${PM:-acceptEdits}"` with `cwd="$CWD"`, detached (`setsid`/`&` + disown), `BATCH_TICKET=1` + `BATCH_PORT`-equivalent env passthrough.
- State record: append a TSV/JSON line `{pid, worktree, started_iso}` to `--state-file <path>` (the orchestrator passes a per-batch state file).
- Liveness probe function: `kill -0 <pid>` (ground truth) + optional `claude agents --json` enrichment (tolerate schema drift by falling back to `kill -0`).
- Self-test: spawn a `sleep 5` surrogate via the same spawn path, assert PID recorded + alive, `kill`, assert not-alive; print PASS/FAIL counts; exit nonzero on any FAIL.

## Anticipated decisions

- brief delivery via `-p` prompt string vs brief-file the agent reads — disposition: agent-decides (prompt-length limit may force brief-file; the helper reads the file either way so the caller chooses).
- `claude agents --json` schema stability — disposition: pre-resolved (PID liveness is ground truth; `agents --json` is enrichment, tolerate drift).

## Decision journal

<!-- Append-only during execution. -->

## Pending decisions

<!-- none yet -->

## Attempts

<!-- Fallback ledger, one entry per attempt. -->

## Notes

- This is the foundational disjoint-paths ticket; tkt-221 wires it into SPAWN LAYER + status detection.
- ERP's shared-`cwd` defect is explicitly fixed: `--cwd` is required and binds to the ticket's worktree.

## References

- GitHub issue body is SoT for long prose: #219
- Spec: `spc-213` (path above)
- ADR: `ADR-008` → `docs/adr/008-batch-work-process-isolation-spawn.md`
- Worktree policy: one tree ↔ one PR

## Lineage

- Parent spec: **spc-213**
- Parent issue (GH sub-issue of Spec primary): **#218**
- Primary ticket: **tkt-219**

## Finish

- pr-225 merged: 2026-08-29T16:34:17Z — https://github.com/percena/lattice/pull/225 (base merge)
- issue #219 closed: 2026-08-29T16:34:41Z — https://github.com/percena/lattice/issues/219
