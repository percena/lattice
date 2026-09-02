# ADR 013: Finish-ledger ledger write separation — `commit_transaction` is architecturally unreliable for ledger append

- **Status:** Proposed
- **Date:** 2026-09-02
- **Deciders:** operator, Claude
- **Related:** `spc-398` A4, `#416` (bug ticket), `tkt-402` (PR #404, #405 — failed patches)
- **Related ADRs:** amends `ADR-012` §4 (ledger coverage — the finish-ledger gap is the mirror problem ADR-012 identified but did not solve), extends `ADR-007` §5a (CI gate — the `transition_ledger_snapshot_mismatch` is the gate firing on the gap)

## Context

ADR-012 §4 established the transition ledger as the conformance sensor — every terminal binder must carry a `tkt-N.jsonl` whose final `to` equals the binder's `status`. The validator replays this ledger and rejects `transition_ledger_snapshot_mismatch` (ledger final `to` ≠ binder `status`).

`finish-ledger.sh` is the script that stamps a merged ticket to `closed`. It uses `commit_transaction()` (an embedded Python function in `transition-api.py`) to **atomically** write the binder (temp file → `os.replace`) AND append the ledger entry (`fcntl.flock` + file append). This atomicity was designed in spc-297 (single-write atomicity) to prevent a half-stamped binder without a ledger entry.

**In practice, the ledger append silently fails in a significant fraction of executions.** This has caused `transition_ledger_snapshot_mismatch` CI failures on every merged ticket since 2026-09-02 — 9+ instances across tkt-381, 382, 383, 384, 385, 386, 400, 401, 402.

### Recurrence log

| Ticket | Date | What happened | Fix applied |
|--------|------|---------------|-------------|
| tkt-381 | 09-02 | `commit_transaction` returned 0 but ledger entry missing | Manual `transition-api.py record` backfill |
| tkt-382 | 09-02 | Same | Manual backfill |
| tkt-383 | 09-02 | Same | Manual backfill |
| tkt-384 | 09-02 | Same | Manual backfill |
| tkt-402 (PR #404) | 09-02 | **Patch 1:** Python verify inside heredoc | Didn't fire (import scope / `_ta._append_ledger_locked` path resolution) |
| tkt-402 (PR #405) | 09-02 | **Patch 2:** Bash fallback using CLI `record`, gated on `FLIP_HAPPENED` | Worked for tkt-402 but `FLIP_HAPPENED` didn't propagate in subagent fork (tkt-385) |
| tkt-385 | 09-02 | `FLIP_HAPPENED` not propagated → fallback skipped | Manual backfill |
| tkt-386 | 09-02 | Duplicate entry from double-append → discontinuity | Manual dedup |
| tkt-400/401 | 09-02 | Missing `in-progress→pr-open` (squash merge didn't bring stamp entry) | Manual insert |
| dev fix | 09-02 | **Patch 3:** Remove `FLIP_HAPPENED` gate | Untested in production |

### Why patches fail

Each patch adds a detection layer on top of the existing `commit_transaction` architecture. But each detection layer has its own failure mode:

| Patch | Detection mechanism | Failure mode |
|-------|---------------------|--------------|
| Python verify (PR #404) | `_ta._append_ledger_locked` call inside heredoc | Import scope, path resolution, `_ta` module visibility unreliable in heredoc context |
| Bash fallback (PR #405) | `tail -1 \| python3 -c` + CLI `record` | Gated on `FLIP_HAPPENED` which is extracted from Python stdout via `sed` — doesn't propagate in subagent forks |
| Remove gate (dev) | Always run | Untested — may still fail if the bash variable resolution or file path is wrong in some context |

The pattern is **recursive patching**: each patch's detector introduces a new failure surface, requiring the next patch to detect the detector's failure. This is a structural problem, not a bug.

## Decision Drivers

- **9+ recurrences in one day** — the failure rate is not marginal; it affects every merged ticket.
- **3 failed patch attempts** — each patch addressed a symptom (Python import scope, variable propagation, gate removal) but the root cause (unreliable atomic write across two files) persists.
- **The CLI `transition-api.py record` is empirically reliable** — every manual backfill used it and it never failed. The failure is specific to `commit_transaction`'s embedded `_append_ledger_locked`.
- **CI is red on dev** — `transition_ledger_snapshot_mismatch` fires on every push that touches `.lattice/`, blocking the CI gate (ADR-007 §5a).
- **Branch protection (tkt-399) now enforces CI** — the gate is no longer soft. A persistent CI red means future PRs cannot merge.
- **Complexity compounds** — `finish-ledger.sh` is 700+ lines of bash+Python hybrid. Each patch adds 20+ lines. The detection logic is now more complex than the write logic it's trying to detect failures of.

## Considered Options

### Option A: CLI separation (recommended)

**What:** `finish-ledger.sh` writes the binder only (simple file write — temp → rename). Then calls `transition-api.py record tkt-N pr-open closed human "merge"` CLI as a separate, explicit step to append the ledger entry. `commit_transaction` is removed from the finish-ledger flow entirely.

**Good:**
- The CLI `record` command is independently tested (35 bats tests) and empirically reliable (9+ manual backfills never failed).
- Separation of concerns: binder write and ledger append are two explicit, independent steps — each can fail without corrupting the other.
- The detection problem disappears: if `record` fails, it prints a clear error to stderr and exits non-zero — the caller sees it immediately.
- Simpler code: no `commit_transaction`, no `_append_ledger_locked`, no `FLIP_HAPPENED`, no Python verify, no bash fallback — just a CLI call.

**Bad:**
- Loses the single-write atomicity guarantee (spc-297): the binder could be stamped to `closed` while the ledger entry fails to append. But this is ALREADY happening — `commit_transaction` doesn't deliver the atomicity it promises. The atomicity is theoretical, not real.
- Two `git add` steps instead of one (binder + ledger). Minor — the staging step already handles both files.

**Migration:** The `commit_transaction` function stays in `transition-api.py` for other callers (e.g., `stamp-pr-open.sh`, `bump-fix-cycle.sh`). Only `finish-ledger.sh` stops using it. The change is localized to the finish-ledger flow.

### Option B: Finish-work layer separation

**What:** `finish-ledger.sh` writes the binder only. The `finish-work` skill's bash flow (not finish-ledger.sh) calls `transition-api.py record` AFTER finish-ledger.sh completes. The ledger append is in the finish-work orchestrator, not in the stamp script.

**Good:**
- Even simpler for `finish-ledger.sh` — it only does the binder + ## Finish body.
- The finish-work flow is bash-only (no Python heredoc) — more reliable.

**Bad:**
- Couples ledger append to the finish-work skill, not to finish-ledger.sh. If someone calls `finish-ledger.sh` directly (outside finish-work), the ledger won't be appended.
- Splits the atomicity guarantee across two scripts — harder to reason about.

### Option C: Validator auto-heal

**What:** The validator detects `transition_ledger_snapshot_mismatch` and auto-appends the missing `pr-open→closed` entry using `transition-api.py record`.

**Good:**
- Zero code changes to `finish-ledger.sh`.
- Self-healing — no manual intervention needed.

**Bad:**
- The validator is a read-only contract checker (by design — `validate-lattice-artifacts.py` is `permissions: read` in CI). Making it write files violates its architecture.
- Masks the root cause — the failure becomes invisible, and other issues with the ledger may also be silently "healed."
- The validator runs in CI, not locally — the ledger would be fixed in CI but not on the local checkout, creating divergence.

### Option D: CI post-merge action

**What:** A GitHub Action runs after a PR merges to dev. It checks each merged ticket's ledger and appends missing entries.

**Good:**
- Runs in a controlled CI environment — no subagent fork or local working directory issues.
- Decoupled from finish-ledger.sh and finish-work.

**Bad:**
- Adds CI complexity (new workflow, new script).
- The ledger is still broken between merge and the action run — any push in that window triggers `transition_ledger_snapshot_mismatch`.
- Doesn't fix the local development experience — agents still see the mismatch.

## Decision

**We will adopt Option A (CLI separation):** `finish-ledger.sh` writes the binder only, then calls `transition-api.py record` CLI to append the ledger entry. `commit_transaction` is removed from the finish-ledger call chain.

The single-write atomicity guarantee (spc-297) was designed to prevent exactly this failure, but `commit_transaction` does not deliver it in practice. The atomicity is **theoretical, not real** — the ledger append silently fails in a significant fraction of executions. Separating the two writes makes each step independently verifiable and individually reliable. The CLI `record` command has been proven reliable through 9+ manual backfills.

## Consequences

- **Positive:**
  - No more `transition_ledger_snapshot_mismatch` CI failures from finish-ledger gaps.
  - Simpler `finish-ledger.sh` — no `commit_transaction`, no `_append_ledger_locked`, no `FLIP_HAPPENED`, no Python verify, no bash fallback. Net code reduction.
  - The CLI `record` command is the single ledger writer — one code path, one test surface, one failure mode.
  - The `commit_transaction` function stays available for other callers that need it (stamp-pr-open.sh, bump-fix-cycle.sh) — no breakage.

- **Negative / trade-offs:**
  - Loses the theoretical single-write atomicity (spc-297). The binder and ledger are written in two steps. If the ledger append fails, the binder is already stamped to `closed` but the ledger is missing. This is the SAME state we're already in — `commit_transaction` already produces this state silently. The difference is that a CLI `record` failure is LOUD (prints to stderr, exits non-zero) while `commit_transaction`'s failure is SILENT (returns 0, ledger entry absent). The trade-off is: loud failure > silent failure.
  - The `do_flip` logic in finish-ledger.sh's Python heredoc still uses `prepare_commit_text` to compute the entry dict. This is fine — `prepare_commit_text` is pure (no disk I/O). The change is: instead of calling `commit_transaction(binder, nt, entry)`, call a simple file write for the binder + CLI `record` for the ledger.

- **Follow-ups:**
  - Bug ticket `#416` — the recurring finish-ledger ledger gap
  - `spc-398` A4 — the original spec acceptance (will need amendment to reflect the architectural change)
  - A new ticket should be created to implement Option A after this ADR is accepted
  - spc-297 (single-write atomicity) should be amended to note that the atomicity guarantee is no longer delivered by `commit_transaction` for the finish-ledger flow

- **Verification:**
  - After implementation, the validator (`validate-lattice-artifacts.py`) should report zero `transition_ledger_snapshot_mismatch` findings on newly merged tickets.
  - The `finish-ledger.bats` test suite should verify the ledger entry is appended after a finish-ledger run.
  - The CI `artifacts` workflow should stay green on `.lattice/` pushes.

## Status history

- 2026-09-02: Proposed (9+ recurrences, 3 failed patches, architectural redesign needed)

## Notes

- ADR-012 §4 identified this as the "mirror problem" — "the Finish ledger requires the operator to commit directly to the integration branch... which is non-atomic (issues close before the ledger is pushed)." This ADR addresses the non-atomicity within finish-ledger.sh itself, which ADR-012 noted but did not solve.
- The `transition-api.py record` CLI has been the de facto reliable ledger writer throughout this session — every manual backfill used it. Option A simply makes it the primary path, not the fallback.
- The `commit_transaction` function is not removed from `transition-api.py` — it stays for other callers. Only the finish-ledger flow changes.

---

_Not a Lattice bloodline/graph node. Cite from Spec/PR/Review with `ADR-013` or this path._
