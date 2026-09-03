---
# status: draft | locked | done | superseded
id: spc-430
slug: test-coverage-427-followup
title: spc-427 test coverage follow-up — rollback race fault test + config shell parse test
kind: test
status: locked
mode: S
priority: P3
summary: "Two test-coverage gaps surfaced by the v0.5.0 release review: spc-427 A1 _rollback_ledger concurrency race has no fault test (spec acceptance promised one), and spc-427 A3 lineage-metrics.sh config.yaml ratchet_cutoff shell-level parse is untested. Both fixes are already shipped and verified by code reading; this Spec guards them with automated tests."
created: 2026-09-03
updated: 2026-09-03
tickets: []
prs: []
reviews: []
supersedes: []
superseded_by: null
---

# Spec: spc-427 test coverage follow-up — rollback race fault test + config shell parse test

> **TL;DR:** spc-427 shipped three lock-safety + sensor fixes; the v0.5.0 release review found two of them lack automated test coverage despite spec acceptance checkboxes claiming it. This Spec adds the missing bats tests — no product code change, only tests.
> **Kind:** test · **Status:** locked · **Mode:** S · **Priority:** P3
> **Path:** v0.5.0 release review (2026-09-03) → spc-430 → tkt-… → pr-…
> **Parent:** spc-427

## Why

spc-427's Acceptance checkboxes say A1 and A3 are verified, but the release review (this session) found:

- **A1** — the acceptance criterion literally reads *"Fault test: two concurrent recorders + a rollback — the concurrent entry survives."* No such test exists in `transition-api.bats`. The existing fault test (line 223) covers the ledger-**write** failure path (`IsADirectoryError` → abort before rename), which never reaches `_rollback_ledger` (invoked only on **rename** failure). The most important fix — the unlocked RMW race — is the least tested.
- **A3** — `lineage-metrics.bats` test 24 exercises the Python `lm.collect(created_after=...)` API, not the new shell-level grep+sed parse of `config.yaml` `lineage.ratchet_cutoff` (lines 113-117). A YAML-parse regression could silently leave `LM_CREATED_AFTER` empty (0/0, the old broken behavior) with no test catching it.

Both fixes are correct (verified by code reading + 35/24 bats green); the risk is **future regression goes uncaught** because the guard tests are absent.

## In scope

- **A1** `skills/_lattice-lib/scripts/tests/transition-api.bats` — add a fault test that injects a **rename** failure (so `_rollback_ledger` runs) while a concurrent `cmd_record` appends to the same ledger, then asserts the concurrent entry **survives** the rollback (not silently dropped by `write_text` clobbering). This directly closes the spc-427 A1 acceptance gap.
- **A2** `skills/review-lineage/scripts/tests/lineage-metrics.bats` — add a shell test that plants a `config.yaml` with `lineage.ratchet_cutoff: "2026-09-02"` (no `--created-after` passed) and asserts `LM_CREATED_AFTER` flows into the snapshot's `coverage_post_ratchet.created_after` field. Also a negative case (no config key → empty → 0/0, old behavior preserved).

## Out of scope

- No change to `transition-api.py` or `lineage-metrics.sh` product code (fixes already shipped in spc-427).
- No new fault-injection harness beyond what the existing bats fixture style uses.
- No concurrent test for `_release_lock_fd` (A2 spc-427) — the helper is a pure refactor already covered by the 35 existing tests; a concurrency test there adds no signal.

## Acceptance

- [ ] **A1** A new `transition-api.bats` test injects a rename failure during `commit` (e.g., make the binder path unwritable / replace binder with a dir so `os.replace` raises) while a concurrent `cmd_record` has appended an entry to the same ledger. After the failed commit, the concurrent recorder's entry is still present in the ledger file (rollback did not clobber it). The test passes on current code and **fails** if the spc-427 A1 lock is removed (regression guard).
- [ ] **A2** A new `lineage-metrics.bats` shell test plants `config.yaml` with `lineage.ratchet_cutoff: "2021-01-01"`, runs `lineage-metrics.sh --md --no-snapshot` without `--created-after`, and asserts the output/snapshot reflects `created_after=2021-01-01`. A second case with no `ratchet_cutoff` key asserts `created_after` is empty (backward-compatible degrade). Both pass on current code.
- [ ] **A3** `bats skills/_lattice-lib/scripts/tests/transition-api.bats` and `bats skills/review-lineage/scripts/tests/lineage-metrics.bats` both fully green (no regressions to the 35 + 24 existing tests).

## Decisions (principal, user-confirmed)

1. **Test-only Spec, no product change** — the fixes are already shipped and correct; this Spec exclusively adds regression guards.
2. **A1 fault via rename failure, not ledger-write failure** — the existing test already covers the write-fail path; the gap is the rename→rollback path where `_rollback_ledger` actually runs.
3. **A1 concurrency model: one background `cmd_record` append + one foreground `commit` that fails at rename** — simple enough to be deterministic in bats; a full parallel-stress test is out of scope for S-mode.
4. **Parent spc-427 stays `done`** — this is a coverage follow-up, not a re-open of the fix spec. spc-430 cites spc-427 as parent.

## References

- Parent Spec: `spc-427` (lock safety + lineage sensor wiring)
- Review: v0.5.0 release review (this session, 2026-09-03)
- ADR: `ADR-012` §4 (ratchet cutoff date)

## Links / bloodline (L0)

- Tickets: (to be created)
- PRs: (to be created)
- Reviews: (none)
