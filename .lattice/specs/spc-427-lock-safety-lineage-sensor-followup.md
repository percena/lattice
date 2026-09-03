---
# status: draft | locked | done | superseded
id: spc-427
slug: lock-safety-lineage-sensor-followup
title: Transition-api lock safety + lineage sensor wiring follow-up
kind: fix
status: locked
mode: C
priority: P3
summary: "Fix 3 pre-existing issues from spc-424 review: _rollback_ledger unlocked RMW race, lock teardown 3x duplication, lineage-metrics post-ratchet coverage 0/0."
created: 2026-09-03
updated: 2026-09-03
tickets: [tkt-428]
prs: []
reviews: []
supersedes: []
superseded_by: null
---

# Spec: Transition-api lock safety + lineage sensor wiring follow-up

> **TL;DR:** Three pre-existing issues identified during spc-424 pre-release review but deferred as non-blocking. All confirmed on current dev. Small surgical fixes: add flock to _rollback_ledger, extract _release_lock_fd helper, wire ratchet cutoff from config.
> **Kind:** fix · **Status:** locked · **Mode:** C · **Priority:** P3
> **Path:** spc-424 review (2026-09-03) → spc-427 → tkt-… → pr-…

## Why

The spc-424 pre-release review found 3 pre-existing issues in the state machine stamp path that were not introduced by spc-424's fixes and were deferred as non-blocking. Now that v0.4.0 is released to main, these should be cleaned up to harden the lock safety and sensor coverage before the next feature work.

## In scope

- **A1** `transition-api.py` `_rollback_ledger` — does an unlocked read-modify-write of the ledger file. `write_text` clobbers the file with a stale in-memory snapshot; a concurrent `cmd_record` that appends between the read and write has its entry silently dropped. Fix: re-acquire the ledger flock (via `lock_path`) before the read-modify-write, release after. This also addresses the dangling terminal entry issue (the rollback is now atomic with the lock, so no concurrent writer can interleave).
- **A2** `transition-api.py` lock teardown — the `fcntl.flock(LOCK_UN) + os.close(lock_fd)` pattern is duplicated 3x (`cmd_commit:368`, `_append_ledger_locked:538`, `cmd_record:650`). A3 (spc-424) fixed cmd_record's finally with individual try/except, but cmd_commit and _append_ledger_locked still have bare `os.close`. Fix: extract a `_release_lock_fd(fd)` helper that wraps both in individual try/except, and call it from all 3 sites.
- **A3** `lineage-metrics.sh` / `.lattice/config.yaml` — the post-ratchet coverage metric always shows 0/0 because `LM_CREATED_AFTER` is never set (the SKILL.md Process 0 doesn't pass `--created-after`, and config.yaml has no cutoff). Fix: add a `lineage.ratchet_cutoff` key to config.yaml (default `2026-09-02`) and have `lineage-metrics.sh` read it when `--created-after` is not explicitly passed.

## Out of scope

- No change to the state machine model (transition_table.py).
- No change to the validator's replay logic.
- No backfill of legacy missing ledgers (pre-cutoff, baselined).
- No migration of binder machine fields to front matter (ADR-012 §7 follow-up).

## Acceptance

- [ ] **A1** `_rollback_ledger` acquires the ledger flock before reading, holds it through the write, and releases it after. A concurrent `cmd_record` that appends between the read and write is now serialized (no dropped entry). Fault test: two concurrent recorders + a rollback — the concurrent entry survives.
- [ ] **A2** A `_release_lock_fd(fd)` helper exists and is called from all 3 finally blocks (`cmd_commit`, `_append_ledger_locked`, `cmd_record`). No bare `os.close(lock_fd)` remains in any lock teardown. Existing transition-api.bats tests pass.
- [ ] **A3** `lineage-metrics.sh` reads `lineage.ratchet_cutoff` from config.yaml (or `--created-after` override) and passes it to `LM_CREATED_AFTER`. Post-ratchet coverage shows real numbers (not 0/0) when binders created after the cutoff exist.

## Decisions (principal, user-confirmed)

1. **Single ticket, single PR** — all 3 fixes are small, touch 2 files, and share one review context.
2. **A1 uses the same `lock_path` mechanism** — not a new lock; the existing per-ticket ledger lock is re-acquired. No deadlock risk (the outer lock in `commit_transaction` is already released before `_rollback_ledger` is called).
3. **A3 default cutoff = 2026-09-02** — the ADR-012 ratchet date. Configurable via config.yaml `lineage.ratchet_cutoff`.

## References

- Review: spc-424 pre-release review (2026-09-03)
- ADR: `ADR-012` §4 (ledger coverage as CI metric)
- Prior Spec: `spc-424` (pre-release hardening)

## Links / bloodline (L0)

- Tickets: (to be created)
- PRs: (to be created)
- Reviews: spc-424 review
