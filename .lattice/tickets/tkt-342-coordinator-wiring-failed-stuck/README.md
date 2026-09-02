# tkt-342-coordinator-wiring-failed-stuck

> **TL;DR:** batch-work coordinator wired by default (--batch-id), failed fail-closes to stuck, marker --create + barrier heartbeat, ADR-011 amended.
> **Kind:** bug · **Priority:** P1
> **Path:** spc-337 → tkt-342 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug,P1 |
| github | https://github.com/percena/lattice/issues/342 |
| status | in-progress |
| fix_cycles | 1 |
| wait_reason | (none) |
| created | 2026-09-02T02:29:15Z |
| updated | 2026-09-02T02:53:48Z |
| adopted | false |
| summary | batch-work coordinator wired by default (--batch-id), failed fail-closes to stuck, marker --create + barrier heartbeat, ADR-011 amended. |
| spec | spc-337 — FSM conformance closure (path: ../../specs/spc-337-fsm-conformance-closure.md) |
| covers | A6 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | G1 |
| paths | skills/batch-work/SKILL.md, skills/batch-work/references/flow.md, skills/batch-work/scripts/run-process-wave.sh, skills/batch-work/scripts/lib/coordinator.py, skills/batch-work/scripts/tests/**, skills/finish-work/scripts/batch-merge-gate.sh, skills/finish-work/scripts/tests/batch-merge-gate*.bats, docs/adr/011-consumer-repo-footprint-hygiene.md |
| solo_merge | yes |
| **primary_ticket** | tkt-342 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-342-coordinator-wiring-failed-stuck |
| worktree | sibling `…/lattice.worktrees/tkt-342-coordinator-wiring-failed-stuck/` |
| prs | pr-347 — https://github.com/percena/lattice/pull/347 |

## Acceptance (this slice)

See GitHub issue #342 for the full slice text; Spec ids owned by this slice:

- [x] **A6** SKILL/flow pass `--batch-id`; `failed` → `stuck` via `_commit_stuck` before settle (fault test); comments reconciled; `batch-merge-gate.sh --create --batch-id` + `--touch`; wave touches marker at each barrier; ADR-011 amendment note.

## Approach

1. `batch-merge-gate.sh`: add `--create --batch-id <id>` (writes `batch-id:`/`started:` lines at `lattice-state-home`; idempotent, refuses to overwrite a different batch-id without `--force`) and `--touch` (mtime refresh). Keep `--remove --reason` unchanged.
2. `coordinator.py cmd_record_node`: extend the `if status in ("unknown","timeout")` branch to include `"failed"`; comment at :417 updated; bats: failed node → binder `stuck` + `wait_reason: unblock`, and transition failure → not settled.
3. `run-process-wave.sh`: reconcile the :356 vs :366 comments (coordinator activates with `--batch-id`; `--coordinator` only overrides the path); in `barrier_poll` end-of-wave, when `WAVE_BATCH_ID` set, `batch-merge-gate.sh --touch` (resolve via `$LIB/../../finish-work/scripts` or a `--gate-script` arg); non-coordinator `record_stuck` path also covers `failed`.
4. SKILL.md step 7 + flow.md §SPAWN LAYER: marker via `batch-merge-gate.sh --create --batch-id "$BATCH_ID"`; `run-process-wave.sh … --batch-id "$BATCH_ID"` in the canonical invocation; Verification checklist rows updated.
5. ADR-011: append 'Amendment (2026-09-02, spc-337/tkt-342): heartbeat implemented — wave touches the marker at each barrier'.

## Anticipated decisions

- Should `failed` also fail-close in agent mode (host prose) — disposition: pre-resolved(spc-337 A6 scope): process mode scripts only; agent-mode prose says 'stamp stuck via transition-api' (no new prose duty beyond naming the command).
- `--touch` location (finish-work/scripts vs _lattice-lib) — disposition: agent-decides; keep with the gate script.

## Decision journal

<!-- Append-only during execution. -->

- 2026-09-02 — `--touch`/`--create` live in `skills/finish-work/scripts/batch-merge-gate.sh` (not `_lattice-lib`): one helper owns the marker's whole lifecycle (create → heartbeat → remove). Source: binder Anticipated decisions #2 (agent-decides); reversible — the wave takes `--gate-script <path>` so relocation is a one-line default change.
- 2026-09-02 — `failed` joins `unknown|timeout` in a single `STUCK_STATUSES` set in `coordinator.py`, mirrored by the wave's non-coordinator branch. Source: spc-337 A6 ("same as `unknown|timeout`"). Ticket-local; reversible.
- 2026-09-02 — The non-coordinator `timeout` branch in `barrier_poll` now also calls `record_stuck` (previously only the coordinator path stamped stuck on timeout; the legacy path silently left the binder `in-progress`). Source: spc-337 A6 + SKILL Verification row "`failed|timeout|unknown` all fail-close"; the header comment already claimed it. Ticket-local; reversible; self-test T5 and existing bats stay green (no-binder → ledger-only fallback, rc 0).
- 2026-09-02 — `--create` treats a legacy marker with NO `batch-id:` line as a DIFFERENT batch (refused without `--force`). Fail-closed by design: a raw-touched marker means a batch of unknown provenance may be live. Source: spc-337 A6 "refuses to overwrite a DIFFERENT batch-id" + ADR-007 §5 (human-adjudicated escape). Reversible.
- 2026-09-02 — `--status` JSON gains an additive `batch_id` field (`""` when absent) so `--create` can "print JSON like `--status`" with the id visible; existing consumers (`jq .marker_present/.allowed`) are unaffected. Source: spc-337 A6.
- 2026-09-02 — `coordinator.bats` "resume cursor correctness" test now creates in-progress binders for its two `failed` nodes (the behaviour change makes a binder mandatory for settle, exactly as the tkt-298 pattern does for `unknown`). Source: spc-337 A6 fault-test parity.
- 2026-09-02 — `coordinator.py --self-test` T3 updated to the new contract (in-progress binder + real sibling transition-api; asserts the binder flipped to stuck) and a T3b added for the refused-transition path. While doing so, found the self-test was NOT hermetic: coordinator state lives at the out-of-repo state home (ADR-011), so `st-batch` persisted across runs and the monotonic settle guard (A3.3) refused T3's re-spawn. Pinned `LATTICE_STATE_HOME` to the self-test temp dir (same pin the bats suites use). Ticket-local test hygiene; reversible.
- 2026-09-02 — Pre-existing reds left as-is (out of A6 scope, environmental): coordinator.bats #8 ends with `run command -v claude; [ "$status" -ne 0 ]` and spawn-ticket-process.bats "missing claude binary" — both fail on any host where `claude` is on PATH (it is here); red at baseline before this change.
- 2026-09-02 — Agent-mode (Task) prose unchanged beyond naming the command — pre-resolved in binder Anticipated decisions #1 (spc-337 A6 scope: process-mode scripts only).
- 2026-09-02T02:53:41Z — fix cycle 1: `pr-open` → rework (fix_cycles 1; cap ≤2; ADR-004 §5) — brief: mini-review Hold: batch-merge-gate.bats uses bare '! grep' assertions (exempt from set -e; CI guard check-bats-assertions fails) — rewrite as 'if grep …; then false; fi'

## Pending decisions

(none)

## Attempts

<!-- Fallback ledger (ADR-004 §5). -->

## Notes

- NOTICED: `skills/finish-work/SKILL.md` / `references/flow.md` (owned by tkt-341) describe `batch-merge-gate.sh` only for `--remove --reason`; a one-line mention that `--status` now reports `batch_id` and that the marker is created by `--create` (so an unexpected marker at finish time names its owning batch) would help operator triage. No functional dependency — the gate's `--check`/`--remove` behaviour is unchanged.
- NOTICED: `skills/finish-work/SKILL.md` lines ~64/89/113 still say the marker lives at "the repo MAIN clone `.lattice/`"; since ADR-011 / spc-282 A1 it lives at the out-of-repo state home (`$XDG_STATE_HOME/lattice/<repo-fingerprint>/`). Prose-only drift for tkt-341's owner; not touched here.

## References

- Spec: `spc-337` → `.lattice/specs/spc-337-fsm-conformance-closure.md`
- ADR: `ADR-012` → `docs/adr/012-transitions-stamped-by-the-path.md`
- Review: `rev-20260902-015425Z`

## Lineage

- Parent spec: **spc-337**
- Parent issue (GH sub-issue of Spec primary): **#337**
- Primary ticket: **tkt-342**
- Covers: **A6**
- Blocked by: (none)
- Merge blocked by: (none)
- Parallel group: G1
- Worktree bind: tkt-342-coordinator-wiring-failed-stuck

## Assets

(none)

## Finish

- (none yet)
