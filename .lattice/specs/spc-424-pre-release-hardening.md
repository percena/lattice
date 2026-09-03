---
# status: draft | locked | done | superseded
id: spc-424
slug: pre-release-hardening
title: Pre-release state machine hardening — 6 verified fixes from dev branch review
kind: fix
status: locked
mode: C
priority: P2
summary: "Fix 6 verified correctness/hygiene gaps in the state machine stamp path found during pre-release dev branch review: finish-stamp closed→closed repair bug, _rollback_ledger silent swallow, cmd_record finally inconsistency, ensure-workspace status regex, ADR-013 status, GHA workflow_dispatch."
created: 2026-09-03
updated: 2026-09-03
tickets: [tkt-425]
prs: [pr-426]
reviews: []
supersedes: []
superseded_by: null
---

# Spec: Pre-release state machine hardening — 6 verified fixes from dev branch review

> **TL;DR:** Pre-release review of the dev branch confirmed 6 issues in the state machine stamp path. Four are code correctness gaps (Medium/Low-Med), two are documentation/CI hygiene (Low). All verified against the current tree. This Spec fixes all 6 in a single delivery ticket.
> **Kind:** fix · **Status:** locked · **Mode:** C · **Priority:** P2
> **Path:** dev branch review (2026-09-03) → spc-424 → tkt-… → pr-…

## Why

A critical pre-release review of the dev branch (before merge to main) examined the state machine core: `transition-api.py`, `transition_table.py`, `finish-stamp.py`, `finish-ledger.sh`, `ensure-workspace.sh`, the GHA safety net, L3 hooks, and the validator. The review confirmed the spc-337/spc-416 architecture is sound (0 `transition_ledger_snapshot_mismatch`, 0 illegal edges in replay, GHA safety net firing successfully), but found 6 latent correctness and hygiene gaps that should be fixed before the release. Each was re-verified against the codebase — no false positives.

## In scope

- **A1** `finish-stamp.py`: when binder is already `closed` and ledger is missing/empty, the repair path computes `record_from = ledger_last_to or prior_status` where both are `""` and `"closed"` respectively → attempts `closed→closed` which is illegal (not in LEGAL_EDGES). Fix: when `ledger_last_to` is empty (no ledger at all), use `open→closed` (the legal legacy edge) instead of `prior_status`.
- **A2** `transition-api.py`: `_rollback_ledger` (line ~557) swallows rollback failures with `except OSError: pass`. A failed rollback leaves a dangling ledger entry while `commit_transaction` reports "unchanged." Fix: log the rollback failure to stderr (still exit 3 — the caller already knows the transaction failed, but now the dangling entry is visible, not silent).
- **A3** `transition-api.py`: `cmd_record` finally block (lines ~646-647) has bare `fcntl.flock(lock_fd, LOCK_UN); os.close(lock_fd)` — not wrapped in try/except. If `LOCK_UN` raises, `os.close` is skipped → fd leak. Fix: wrap both in individual `try/except OSError: pass` (consistent with `_append_ledger_locked` lines 539-543).
- **A4** `ensure-workspace.sh`: status-row regex `^\| status \|` (line ~660) is too strict — won't match `|status| queued |` (no spaces) or `| **status** | queued |` (bold). Fix: use `^\| *status *\|` (matching the L3 hook's grammar) so differently-formatted binders aren't silently skipped.
- **A5** `docs/adr/013-finish-ledger-ledger-write-separation.md`: Status still `Proposed` despite implementation being done (spc-416 done, GHA firing). Fix: change to `Accepted`.
- **A6** `.github/workflows/finish-stamp.yml`: no `workflow_dispatch:` trigger — if all push paths lose the race, there's no manual re-trigger (PR already closed won't re-fire). Fix: add `workflow_dispatch:` with `inputs.pr` and `inputs.repo`.

## Out of scope

- The non-atomic two-write window in finish-stamp.py (binder write → ledger append) — this is a documented design trade-off (spc-416 D7), not a bug. The loud-failure + re-run recovery is the correct pattern.
- The post-ratchet coverage sensor showing 0/0 (`LM_CREATED_AFTER` not wired from config.yaml) — this is a #385 follow-up, not in this Spec.
- The 118 missing ledgers (all pre-cutoff legacy) — baselined by `closed_without_ledger_legacy` warning.
- The 18/27 never-walked edges — by design for rare paths; "pause M3 expansion" is still active.

## Acceptance

- [ ] **A1** `finish-stamp.py` ledger repair: when binder is already `closed` and `ledger_last_to` is empty (no ledger file), `record_from` uses `"open"` (not `"closed"`) → records `open→closed` (legal legacy edge). Fault test: already-closed binder with no ledger → finish-stamp exits 0 with a ledger entry, not exit 1 with "record CLI failed."
- [ ] **A2** `transition-api.py` `_rollback_ledger`: on rollback failure, prints a stderr warning naming the ticket and the dangling entry. The function still returns None (best-effort) but the failure is no longer silent.
- [ ] **A3** `transition-api.py` `cmd_record` finally: both `fcntl.flock(LOCK_UN)` and `os.close(lock_fd)` wrapped in individual `try/except OSError: pass` — consistent with `_append_ledger_locked`.
- [ ] **A4** `ensure-workspace.sh` status regex: `grep -m1 -E '^\| *status *\|'` (was `^\| status \|`). A binder with `|status| queued |` or `| **status** | queued |` now matches and stamps. Existing standard-format binders unchanged.
- [ ] **A5** ADR-013 Status: `Accepted` (was `Proposed`).
- [ ] **A6** `finish-stamp.yml` has `workflow_dispatch:` with `inputs.pr` (int, required) and `inputs.repo` (string, required) — operator can manually re-trigger the safety net for a PR that lost the race.

## Non-goals

- No change to the state machine model (transition_table.py LEGAL_EDGES).
- No change to the validator's replay or snapshot_mismatch logic.
- No change to the GHA's race-handling or retry logic (only adds a manual trigger).
- No new tests beyond fault tests for A1/A4.

## Decisions (principal, user-confirmed)

1. **Single ticket, single PR** — all 6 fixes are small (≤15 lines total code change), touch disjoint files, and share one review context. Splitting into 6 tickets would be pipeline overhead disproportionate to the fixes.
2. **Audited base-write for Spec** — user authorized `--allow-base-write` for the Spec/binder write on dev (strict profile escape), then code fixes happen in a sibling worktree via start-work.
3. **A1 fix uses `open→closed` legacy edge** — when the ledger is completely missing and the binder is already `closed`, we can't know the original prior status from the ledger. `open→closed` is the legal legacy edge (transition_table.py line 157) and produces a valid ledger entry. The validator's `closed_without_ledger` baseline check still catches the historical case; this fix only helps the auto-repair path.

## Agent-assumed (secondary)

- A2's stderr warning is advisory (not a return code change) — the rollback is still best-effort; the key improvement is visibility.
- A6's `workflow_dispatch` inputs mirror the existing `--pr` and `--repo` args of `finish-stamp-ci.py`; the `if:` guard on `merged == true` is skipped for manual runs.

## Risks / open questions

- A1: recording `open→closed` for a missing ledger is a best-effort repair — it produces a valid (if historically inaccurate) ledger. The alternative (skip repair, let `closed_without_ledger` detect) leaves no ledger at all. Recording is better than skipping because it makes the binder conformance-green.
- A4: loosening the regex to `^\| *status *\|` could match unintended lines (e.g., a prose mention of `| status |` in a code block). Mitigated by `grep -m1` (first match) and the `awk -F'|'` extraction which validates the pipe-delimited row structure.

## References

- Review: pre-release dev branch review (2026-09-03, this conversation) — 6 findings verified against tree
- ADR: `ADR-013` → `docs/adr/013-finish-ledger-ledger-write-separation.md`
- Prior Specs: `spc-416` (post-merge ledger stamping), `spc-337` (FSM conformance closure)
- Lineage: `rev-20260902-080545Z` (lineage audit baseline), `rev-20260902-015425Z` (FSM conformance audit)

## Links / bloodline (L0)

- Tickets: (to be created via create-tickets)
- PRs: (to be created)
- Reviews: pre-release dev branch review (2026-09-03)
