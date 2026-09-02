# tkt-339-path-point-writers

> **TL;DR:** ensure-workspace --bind stamps queued→in-progress; create-pr post-open script + PostToolUse hook stamp pr-open; morning-triage edges as transition-api commands.
> **Kind:** feat · **Priority:** P1
> **Path:** spc-337 → tkt-339 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | feat,P1 |
| github | https://github.com/percena/lattice/issues/339 |
| status | rework |
| fix_cycles | 1 |
| wait_reason | (none) |
| created | 2026-09-02T02:29:15Z |
| updated | 2026-09-02T03:31:49Z |
| adopted | false |
| summary | ensure-workspace --bind stamps queued→in-progress; create-pr post-open script + PostToolUse hook stamp pr-open; morning-triage edges as transition-api commands. |
| spec | spc-337 — FSM conformance closure (path: ../../specs/spc-337-fsm-conformance-closure.md) |
| covers | A3 |
| blocked_by | #338 |
| merge_blocked_by | #338 |
| parallel_group | G1 |
| paths | skills/_lattice-lib/scripts/ensure-workspace.sh, skills/_lattice-lib/scripts/tests/ensure-workspace*.bats, skills/create-pr/**, plugins/lattice/hooks/hooks.json, plugins/lattice/hooks/auto-stamp-pr-open.sh, plugins/lattice/scripts/tests/auto-stamp-pr-open.bats, docs/morning-triage.md |
| solo_merge | yes |
| **primary_ticket** | tkt-339 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-339-path-point-writers |
| worktree | sibling `…/lattice.worktrees/tkt-339-path-point-writers/` |
| prs | pr-348 — https://github.com/percena/lattice/pull/348 |

## Acceptance (this slice)

See GitHub issue #339 for the full slice text; Spec ids owned by this slice:

- [x] **A3** Bind a queued binder → one `queued → in-progress` entry; re-bind → none; pr-open untouched; `--no-stamp`; no binder → no-op. `after-pr-open.sh` chains verify + stamp and is what create-pr names. `auto-stamp-pr-open.sh` PostToolUse stamps after successful `gh pr create`, idempotent. morning-triage.md uses commands.

## Approach

1. `ensure-workspace.sh`: after the JSON success path for `--bind tkt`, call a new `stamp_in_progress()` — find `<worktree>/.lattice/tickets/tkt-<id>-*/README.md`; read status via `binder_rows.py`; if `queued` → `python3 transition-api.py commit tkt-<id> in-progress system spawn --binder <path>`; warn (not fail) on error; skip on `--no-stamp` or when no binder; include `stamped_in_progress: true|false` in the JSON.
2. `skills/create-pr/scripts/after-pr-open.sh --pr N --expected-oid OID [--repo]`: runs `verify-main-chain.sh --stage pr` then `stamp-pr-open.sh --pr N`; exit non-zero on FAILED proof (no stamp). SKILL.md rule 11 + short path step 6 + workflow.md §4.1 name it.
3. Plugin `hooks.json`: add `PostToolUse` matcher `Bash` → `auto-stamp-pr-open.sh`; the hook reads `tool_input.command` (must contain `gh pr create`) and `tool_response` (PR URL regex); resolves `_lattice-lib` via `${CLAUDE_PLUGIN_ROOT}/skills/_lattice-lib/scripts`; runs `stamp-pr-open.sh --pr N` from the command's cwd; always exit 0 (fail-open).
4. `docs/morning-triage.md` Step 3/4: replace 'Stamp `queued`' prose with `transition-api.py commit <tkt> queued human unblock|reschedule` commands; cancel stays `finish-ledger.sh --cancel`.
5. Bats: ensure-workspace stamp cases (queued / re-bind / pr-open / no-stamp / no binder); after-pr-open (proof fail → no stamp); auto-stamp hook (URL parse, non-gh command no-op, idempotent second run).

## Anticipated decisions

- Owner/reason for the bind stamp — disposition: pre-resolved(spc-337 Agent-assumed): `system` / `spawn`.
- Hook double-stamp with the script step — disposition: pre-resolved(spc-337 Risks): stamp-pr-open is idempotent; assert in bats.
- JSON field name for the stamp result — disposition: agent-decides.

## Decision journal

<!-- Append-only during execution. -->

- 2026-09-02 — **JSON field name** `stamped_in_progress` (bool; false on no-op/skip/failure). Source: binder Anticipated decisions (agent-decides); no other JSON field or exit code changed.
- 2026-09-02 — **Stamp home = the bind's resolved `lattice_home`** (worktree `.lattice` by default; an explicit `LATTICE_HOME` env is honoured, same as the JSON `lattice_home` field). Source: spc-337 A3 "binder under the worktree's Lattice home" + ensure-workspace's existing `LATTICE_HOME` contract; ticket-local, reversible.
- 2026-09-02 — **Stamp only on `--bind tkt`** (not on a pre-formed `--branch tkt-N-*`): the id is the spec-named input; pre-formed branches keep prior behaviour. Source: spc-337 A3 wording. Reversible follow-up if start-work resumes need it.
- 2026-09-02 — **`after-pr-open.sh --repo` defaults to origin** (`remote.origin.url` → owner/name, same parse as check-pr-context.sh) because `verify-main-chain --stage pr` requires `--repo`; `--expected-head`/`--expected-body-file`/`--binder`/`--check-all` pass through. Source: verify-main-chain usage + create-pr §4.1.
- 2026-09-02 — **PostToolUse hook also emits `hookSpecificOutput.additionalContext` on stdout** (stamped / failed) besides the stderr advisory, since stderr on exit 0 is not shown to the model (intercept-gh-pr-common.sh delivery contract). Exit is always 0. Source: spc-337 A3 "fail-open, advisory on error".
- 2026-09-02 — **Hook passes `--repo <owner/name>` parsed from the PR URL** to stamp-pr-open (the PR's own repo, not a guessed origin). Source: stamp-pr-open `--repo` contract.
- 2026-09-02T03:31:49Z — fix cycle 1: `pr-open` → rework (fix_cycles 1; cap ≤2; ADR-004 §5) — brief: review Hold (PR #348): M1 MEDIUM — auto-stamp-pr-open.sh resolves toplevel from payload cwd and stamp-pr-open picks the binder from the current branch, never checking the PR's headRefName: a 'cd ../tkt-11-x && gh pr create' from worktree tkt-10 stamps tkt-10's binder; from the main clone on dev the stamp is skipped yet additionalContext says 'stamped'. Fix: fetch headRefName, refuse when ≠ current branch (or parse --head), honest skip wording; one bats each. M2 (batch-work brief still says stamp in-progress by prose) → follow-up ticket, out of paths.

## Pending decisions

(none)

## Attempts

<!-- Fallback ledger (ADR-004 §5). -->

## Notes

- NOTICED: `skills/batch-work/references/flow.md:134` and `skills/batch-work/SKILL.md:96` still brief spawned agents to "stamp the binder status in-progress on start" by prose. With this slice the bind already commits `queued → in-progress`; a second `commit … in-progress` is refused (no `in-progress → in-progress` edge) and a hand edit is refused by the L3 hook. The brief text should say "the bind stamped it" (batch-work paths — not widened here).
- NOTICED: hook double-stamp idempotency is asserted through the recording shim (two calls, same PR); the real no-op-on-second-call behaviour is stamp-pr-open's own contract/suite (unchanged, spc-337 non-goal).
- NOTICED: `skills/create-pr/SKILL.md` Short path step 2 already resolves `$SKILL_ROOT`; after-pr-open.sh resolves `_lattice-lib` relative to its own install dir (`resolve-lattice-lib.sh`), so it also works when invoked by absolute path outside the skill flow.

## References

- Spec: `spc-337` → `.lattice/specs/spc-337-fsm-conformance-closure.md`
- ADR: `ADR-012` → `docs/adr/012-transitions-stamped-by-the-path.md`
- Review: `rev-20260902-015425Z`

## Lineage

- Parent spec: **spc-337**
- Parent issue (GH sub-issue of Spec primary): **#337**
- Primary ticket: **tkt-339**
- Covers: **A3**
- Blocked by: #338
- Merge blocked by: #338
- Parallel group: G1
- Worktree bind: tkt-339-path-point-writers

## Assets

(none)

## Finish

- (none yet)
