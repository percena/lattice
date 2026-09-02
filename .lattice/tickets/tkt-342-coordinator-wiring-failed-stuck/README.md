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
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T02:29:15Z |
| updated | 2026-09-02T02:29:15Z |
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
| prs | (none) |

## Acceptance (this slice)

See GitHub issue #342 for the full slice text; Spec ids owned by this slice:

- [ ] **A6** SKILL/flow pass `--batch-id`; `failed` → `stuck` via `_commit_stuck` before settle (fault test); comments reconciled; `batch-merge-gate.sh --create --batch-id` + `--touch`; wave touches marker at each barrier; ADR-011 amendment note.

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

## Pending decisions

(none)

## Attempts

<!-- Fallback ledger (ADR-004 §5). -->

## Notes

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
