# ADR 013: Post-merge ledger stamping — belt-and-suspenders (simplified local stamp + GHA safety net)

- **Status:** Proposed
- **Date:** 2026-09-02
- **Deciders:** operator, Claude
- **Related:** `spc-398` A4, `#416` (bug ticket), tkt-402 (PR #404, #405 — failed patches)
- **Related ADRs:** implements `ADR-012` §5 (Post-merge bookkeeping is event-driven, with a scripted fallback), extends `ADR-007` §5a (CI gate — `transition_ledger_snapshot_mismatch` is the gate firing on the gap), amends `spc-297` (single-write atomicity scope narrowed — see Consequences)

## Context

ADR-012 §4 established the transition ledger as the conformance sensor — every terminal binder must carry a `tkt-N.jsonl` whose final `to` equals the binder's `status`. The validator replays this ledger and rejects `transition_ledger_snapshot_mismatch` (ledger final `to` ≠ binder `status`). ADR-012 §5 recorded the direction: "Post-merge bookkeeping is event-driven, with a scripted fallback. The Finish ledger is written by a GitHub Action on `pull_request: closed` (merged) committing as a bot; consumers without Actions use a single idempotent, resumable `finish-work` script. Human clones stop pushing bookkeeping commits to the integration branch." This was deferred as a follow-up Spec. That follow-up never landed; `finish-ledger.sh` remained the sole stamp path, and the failure it produced is the subject of this ADR.

### The failure

`finish-ledger.sh` is a 732-line bash+Python hybrid that stamps a merged ticket to `closed`. The critical write path crosses the bash/Python boundary three times: (1) a Python heredoc calls `commit_transaction()` to atomically write the binder + append the ledger; (2) bash stages both files via `git add ... || true`; (3) bash extracts `FLIP_HAPPENED` from Python stdout via `sed` to gate a staging assertion. Three patch attempts (PR #404 Python verify, PR #405 bash fallback, dev `FLIP_HAPPENED` removal) each added a new detection layer with its own failure surface. **All three patches failed.** The result: `transition_ledger_snapshot_mismatch` CI failures on every merged ticket from 2026-09-02 — 9+ instances across tkt-381, 382, 383, 384, 385, 386, 400, 401, 402.

### Recurrence log with failure-mode classification

Git forensics (commit-by-commit ledger/binder state tracing) reveals **four distinct failure modes**, not the single "commit_transaction unreliable" narrative the initial diagnosis assumed:

| Ticket | Date | Failure mode | What happened | Fix applied |
|--------|------|-------------|---------------|-------------|
| tkt-381 | 09-02 | **A: staging/commit** | Binder stamped to `closed`; ledger NOT committed. `commit_transaction` wrote both to disk (proven by reproduction — see §Root Cause), but `git add \|\| true` silently dropped the ledger staging, and the commit excluded it. | Manual backfill via `cf63571` (folded into tkt-382 fix PR) |
| tkt-382 | 09-02 | **A: staging/commit** | Same as tkt-381 | Manual backfill |
| tkt-383 | 09-02 | **A: staging/commit** | Same — binder stamped, ledger not committed | Manual backfill (`27beae2`) |
| tkt-384 | 09-02 | **A: staging/commit** (partial) | Binder stamped; ledger committed but with "+ backfill" in the commit message — the agent manually intervened | Manual backfill (`c5f1343`) |
| tkt-385 | 09-02 | **C: squash-merge data loss** | Squash merge of PR #414 brought only `queued→in-progress` in the ledger (the `in-progress→pr-open` stamp was lost). Binder status was `in-progress` (not `pr-open`) on dev. finish-ledger recorded a direct-jump, but the manual backfill used `pr-open→closed` — creating a discontinuity. | Manual backfill (`9c9a0d9`, `0a28558`) + discontinuity fix (`c5e9343`) |
| tkt-386 | 09-02 | **B: fallback without binder stamp** | `commit_transaction` did not stamp the binder (binder stayed `pr-open`), but the bash fallback appended the ledger `pr-open→closed` entry independently — creating binder/ledger inconsistency (ledger says `closed`, binder says `pr-open`). A second finish run then stamped the binder AND appended a duplicate ledger entry. | Manual dedup + binder stamp (`7070d3f`) |
| tkt-400 | 09-02 | **C: squash-merge data loss** | Squash merge lost `in-progress→pr-open` entry. Ledger had only `queued→in-progress` + `pr-open→closed` (discontinuous). | Manual insert of missing entry (`7070d3f`) |
| tkt-401 | 09-02 | **C: squash-merge data loss** | Same as tkt-400 | Manual insert (`7070d3f`) |
| tkt-402 (PR #404) | 09-02 | **D: patch detector failure** | Python verify inside heredoc — didn't fire (`_ta._append_ledger_locked` import scope / path resolution in heredoc context) | Superseded by PR #405 |
| tkt-402 (PR #405) | 09-02 | **D: patch detector failure** | Bash fallback gated on `FLIP_HAPPENED` — variable not propagated in subagent fork, fallback skipped | Manual backfill + dev fix (`3a6a73d`) |
| tkt-386 (post-patch) | 09-02 | **D: double-append** | Bash fallback + `commit_transaction` both appended `pr-open→closed` — duplicate entry | Manual dedup (`7070d3f`) |

### Failure mode detail

**Mode A — staging/commit flow failure (tkt-381, 382, 383, 384):** `commit_transaction` writes both the binder and the ledger to disk (confirmed by isolated reproduction — see §Root Cause). The bash staging step (`git add -- "$LEDGER_FILE" 2>/dev/null || true`) silently swallows any staging failure. The tkt-360 A1 staging assertion (`FLIP_HAPPENED == "1"`) should catch this, but `FLIP_HAPPENED` is extracted from Python stdout via `sed` across the bash/Python boundary — unreliable in subagent fork contexts. The result: the binder is committed, the ledger is not, and `transition_ledger_snapshot_mismatch` fires in CI.

**Mode B — fallback without binder stamp (tkt-386):** When `commit_transaction` fails or the Python heredoc exits non-zero, `set -e` should halt the script. But the bash fallback (added in PR #405, lines 709-730) runs AFTER the staging assertion — if the agent re-invokes finish-ledger or runs the fallback's `record` CLI separately, the ledger entry is appended without the binder stamp. This creates the inverse inconsistency: ledger says `closed`, binder says `pr-open`.

**Mode C — squash-merge data loss (tkt-385, 400, 401):** The worktree stamps `in-progress→pr-open` (via `stamp-pr-open.sh` or the create-pr PostToolUse hook) and commits it in the PR branch. But if the stamp wasn't committed before the PR was squash-merged, or the squash merge resolved the ledger file differently, dev receives a ledger missing the intermediate entry. finish-ledger then appends `pr-open→closed` to a ledger whose prior entry's `to` is `in-progress` — a discontinuity. The bash fallback's hardcoded `pr-open→closed` edge makes this worse: it doesn't read the actual prior status.

**Mode D — patch detector failure (tkt-402, tkt-386 post-patch):** Each patch adds a detection layer with its own failure surface. The Python verify (PR #404) failed on import scope. The bash fallback (PR #405) failed on `FLIP_HAPPENED` propagation. The `FLIP_HAPPENED` removal (dev) is untested. The double-append (tkt-386) happened because both `commit_transaction` and the bash fallback appended the same entry.

### Root cause: the bash/Python boundary, not `commit_transaction`

**The initial diagnosis — "`commit_transaction` is architecturally unreliable for ledger append" — is incorrect.** Isolated reproduction (test repo, standard binder path, offline overrides) proves `commit_transaction` writes BOTH the binder and the ledger entry to the correct paths, and the staging step stages both. The function either succeeds atomically (returns 0, both files modified) or fails loudly (returns 3, `SystemExit` raised, script halts). There is no code path where `commit_transaction` returns 0 without writing the ledger entry.

The failures occur **downstream of `commit_transaction`**, at the bash/Python boundary:

| Step | Language | Error handling | Failure mode |
|------|----------|----------------|--------------|
| Path resolution | Python | Correct | — |
| Binder write + ledger append | Python (`commit_transaction`) | Correct (atomic, fail-closed) | — |
| Ledger staging | **Bash** (`git add ... \|\| true`) | **Silent swallow** | Mode A |
| Staging assertion gate | **Bash** (`FLIP_HAPPENED` from `sed`) | **Variable propagation unreliable** | Mode A |
| Bash fallback | **Bash** (`record` CLI, hardcoded edge) | **Wrong edge, `\|\| true`** | Mode B, D |
| Python verify fallback | **Python** (`_ta._append_ledger_locked`) | **`except OSError: pass`** | Mode D |
| Squash merge | **Git** (squash collapses commits) | **No ledger continuity check** | Mode C |

Each patch added a detection layer on top of the existing architecture, and each detection layer had its own failure surface — a pattern of **recursive patching** where the detector's failure mode requires the next patch to detect. The root cause is NOT the write step (`commit_transaction`); it is the **bash/Python boundary** and the **local-commit post-merge stamping model** itself.

## Decision Drivers

- **9+ recurrences in one day** across four distinct failure modes — the failure rate is not marginal; it affects every merged ticket.
- **3 failed patch attempts** — each patch addressed a symptom (Python import scope, variable propagation, gate removal) but the root cause (bash/Python boundary + local stamping model) persists.
- **ADR-012 §5 already recorded the direction** — "Post-merge bookkeeping is event-driven, with a scripted fallback." This was deferred and never implemented. The deferral is the proximate cause of this crisis.
- **Branch protection (tkt-399) now enforces CI** — the gate is no longer soft. A persistent CI red means future PRs cannot merge.
- **Complexity compounds** — `finish-ledger.sh` is 732 lines of bash+Python hybrid with 4 fallback layers. The detection logic is now more complex than the write logic it guards.
- **Squash-merge data loss is unfixable in the local stamp model** — no amount of finish-ledger.sh patching can recover ledger entries lost during squash merge (Mode C). The stamp must happen on the merged branch, not on a local clone.
- **The operator's intent is to bypass the current approach entirely** — 10+ PRs have been created attempting to patch this; a systemic solution is required.

## Considered Options

### Option A: CLI separation (the original ADR-013 proposal — rejected)

**What:** `finish-ledger.sh` writes the binder only (temp → rename), then calls `transition-api.py record tkt-N pr-open closed human "merge"` CLI as a separate step.

**Why rejected:**
- **Does not fix Mode A**: the staging step (`git add ... || true`) stays in bash — the same silent staging failure that caused tkt-381/382/383 recurs.
- **Does not fix Mode C**: squash-merge data loss is unaffected — the GHA/local split is not changed.
- **Introduces a hardcoded-edge bug**: `record tkt-N pr-open closed` always records `pr-open→closed`, but for direct jumps (prior status `in-progress` or `queued`), the correct edge is `in-progress→closed` or `queued→closed`. This creates discontinuities — the exact Mode C symptom.
- **Does not fix Mode B/D**: the bash fallback layers remain; the double-append and fallback-without-binder-stamp classes persist.
- **The atomicity trade-off is unnecessary**: the ADR argued `commit_transaction`'s atomicity is "theoretical, not real." Reproduction proves it IS real — the failure is downstream, not in the atomic write.

### Option B: All-Python finish-ledger (considered)

**What:** Replace the 732-line bash+Python hybrid with a single Python script that does: path resolution → binder write → ledger append → `git add` (via subprocess, no `|| true`) → staging verification → summary. The bash wrapper becomes ~20 lines of argument parsing + `python3 finish_ledger.py "$@"`.

**Good:**
- Eliminates the bash/Python boundary for Modes A, B, D — all I/O, staging, and verification in one process with proper error handling.
- No `|| true`, no `FLIP_HAPPENED` propagation, no multiple fallback layers.
- Surgical: keeps `commit_transaction` (proven correct), fixes the downstream staging/commit flow.

**Bad:**
- Does not fix Mode C (squash-merge data loss) — the stamp still happens on a local clone, and squash-merge-lost entries are still unrecoverable.
- Still requires the agent to run the script locally and commit — the "human clone pushes bookkeeping commits to the integration branch" pattern that ADR-012 §5 explicitly sought to eliminate.
- The agent (Claude Code) must still be trusted to invoke the correct commit flow — process deviation is what caused some Mode A failures (manual `git commit` with pathspec excluding `.transition-ledger/`).

### Option C: Validator auto-heal (rejected)

**What:** The validator detects `transition_ledger_snapshot_mismatch` and auto-appends the missing `pr-open→closed` entry.

**Why rejected:**
- The validator is a read-only contract checker (by design — `validate-lattice-artifacts.py` is `permissions: read` in CI). Making it write files violates its architecture.
- Masks the root cause — other ledger issues would be silently "healed."
- CI-only — the ledger would be fixed in CI but not on the local checkout, creating divergence.

### Option D: CI post-merge action (considered, subsumed by Option E)

**What:** A GitHub Action runs after a PR merges to dev, checks each merged ticket's ledger, and appends missing entries.

**Why subsumed:** This is a subset of Option E — it handles only the ledger gap, not the binder stamp. Option E does both atomically.

### Option E: GitHub Action post-merge stamping (original proposal — superseded by E+)

**What:** A GHA triggered on `pull_request: closed` replaces `finish-ledger.sh` as the sole stamp path.

**Why superseded:** This design has a **critical single point of failure**: the GHA. If CI billing is exhausted (this org has experienced GitHub Actions billing blocks before — documented in `lattice-ci-billing-block` memory), or Actions are disabled, or the GHA script fails, the binder/ledger are not stamped and there is no automatic fallback. The "simplified `finish-ledger.sh` fallback" mentioned in the original proposal is under-specified — there is no trigger, no detection, and no guarantee the operator knows the GHA failed until CI goes red on the next push.

The failure matrix:

| Scenario | GHA | Local stamp | Validator (CI) | Result |
|----------|-----|-------------|----------------|--------|
| Normal | ✅ | (not required) | ✅ | ✅ stamped |
| CI billing exhausted | ❌ | (not defined) | ❌ | 🔴 binder stays `pr-open`, ledger missing `→closed`, **no one knows** |
| GHA script error | ❌ | (not defined) | ✅ | 🔴 CI red, stamp incomplete, manual intervention needed |
| GHA push conflict | ⚠️ rejected | (not defined) | ✅ | 🔴 GHA retries or abandons, stamp lost |

### Option E+: Belt-and-suspenders — simplified local stamp (primary) + GHA verification/repair (safety net) (recommended)

**What:** A **simplified local stamp** (single Python script, ~80 lines, no bash/Python boundary) replaces the 732-line `finish-ledger.sh` as the PRIMARY stamp path. It runs inside the `finish-work` flow immediately after merge — no CI dependency. A **GHA on `pull_request: closed`** runs as a SAFETY NET: it verifies the local stamp landed, repairs ledger continuity (Mode C), and catches local stamp failures. An optional **scheduled sweep GHA** (daily) catches anything both missed.

**Design:**

**Layer 1 — Simplified local stamp (primary, no CI dependency):**

A new `finish-stamp.py` (single Python script) replaces `finish-ledger.sh`'s 732-line bash+Python hybrid. Called by `finish-work` flow immediately after `gh pr merge` + worktree cleanup. The script:

1. Reads the binder's current `status` and the ledger's last entry's `to`.
2. **Idempotent**: if status is already `closed` and the ledger's last `to` is `closed` → exit 0 (no-op — GHA or a previous run already stamped).
3. Resolves the CORRECT edge from the actual prior status (reads binder, no hardcoding): `pr-open→closed` for normal merges, `in-progress→closed` / `queued→closed` for direct jumps (ADR-012 §3).
4. Writes the binder (status→closed, `## Finish` body, `prs` row, `updated` stamp) via temp→rename (same atomic pattern as the `elif s != orig` branch in the current script — no `commit_transaction`).
5. Appends the ledger entry via `transition-api.py record` CLI subprocess (proven reliable — 9+ manual backfills never failed). The `record` CLI resolves the correct edge, not a hardcoded one.
6. Stages both files via `subprocess.run(["git", "add", ...])` — **NO `|| true`**, fail loud on non-zero exit.
7. Verifies staging via `git diff --cached --name-only` — **fail loud (exit 1)** if the ledger is not staged. This is the tkt-360 A1 assertion, but in Python (no `FLIP_HAPPENED` variable propagation).
8. Does NOT commit or push — the `finish-work` flow's `finish-commit.sh` handles that (unchanged).

**What this eliminates (vs. current `finish-ledger.sh`):**
- No `commit_transaction` (the function that was wrongly blamed — it stays in `transition-api.py` for other callers, but is no longer in the finish path).
- No `_append_ledger_locked` Python verify inside heredoc (import scope issues).
- No `FLIP_HAPPENED` bash↔Python variable propagation (the staging assertion is in Python, same process).
- No bash fallback with hardcoded `pr-open→closed` edge (the `record` CLI resolves the edge from the binder's actual prior status).
- No `|| true` on `git add` (staging is in Python subprocess, exit non-zero propagates).
- No 732-line bash+Python hybrid — ~80 lines of pure Python.

**Layer 2 — GHA post-merge verification/repair (safety net, CI-dependent):**

A GitHub Action on `pull_request: closed` (merged) runs on the dev branch after merge. It:

1. For each closing issue, finds the binder and checks if `status == closed` AND ledger last `to == closed`.
2. If already stamped (local stamp ran) → exit 0 (no-op, verify only).
3. If NOT stamped (local stamp failed, CI billing was unavailable, or the agent deviated from flow) → stamps binder + ledger (same logic as Layer 1, same `finish-stamp.py` script invoked in CI).
4. **Mode C repair**: verifies ledger continuity — if the ledger's last `to` ≠ the binder's prior `status` before the flip, inserts the missing intermediate edge(s). This is the squash-merge data loss fix — only the GHA can do this reliably because it runs on the merged dev branch and can see the full ledger history.
5. Commits + pushes as `github-actions[bot]`.

**Layer 3 — Scheduled sweep GHA (optional catch-up, CI-dependent):**

A daily cron GHA that scans for tickets in `.lattice/tickets/` whose binder `status` is `pr-open` (or any non-terminal working state) but whose PR has been merged for > N hours. Stamps them. This catches cases where both Layer 1 and Layer 2 failed (agent didn't run finish-work properly AND the event-triggered GHA failed). Only runs if CI is available — if billing is exhausted, Layer 1 is the sole path.

**Race condition between Layer 1 and Layer 2:**

Layer 1 (local stamp) and Layer 2 (GHA) run concurrently — the `pull_request: closed` event fires when `gh pr merge` completes, before the local stamp runs. The race is **benign** because both are idempotent:
- If Layer 1 finishes first: the GHA sees `status == closed` → no-op.
- If Layer 2 finishes first: the local stamp sees `status == closed` → no-op (exit 0). The `finish-work` flow's `git push` may be rejected (GHA already pushed); `finish-commit.sh` handles this by pulling first or detecting "nothing to commit" (its existing no-op path).
- If both finish simultaneously: the second committer's `git push` is rejected (non-fast-forward) → rebase → see the other's commit → no-op. Both converge to the same end state.

**Failure matrix (revised):**

| Scenario | Layer 1 (local) | Layer 2 (GHA) | Layer 3 (sweep) | Result |
|----------|----------------|---------------|-----------------|--------|
| Normal | ✅ stamps | ✅ no-op (verify) | — | ✅ |
| CI billing exhausted | ✅ stamps | ❌ (no CI) | ❌ (no CI) | ✅ — **local stamp is primary, no CI dependency** |
| Local stamp fails (bash/Python boundary — but this is now pure Python, much less likely) | ❌ | ✅ stamps (CI catches it) | — | ✅ (if CI available) |
| Local stamp fails + CI exhausted | ❌ | ❌ | ❌ | 🔴 — operator must manually run `finish-stamp.py` (simple, single command) |
| Squash-merge data loss (Mode C) | ✅ stamps (but may create discontinuity if ledger has gap) | ✅ repairs continuity | — | ✅ — GHA verifies + repairs |
| Agent deviates from finish-work flow (doesn't run local stamp) | ❌ (not run) | ✅ stamps | ✅ catches if > N hours | ✅ (if CI available) |
| Everything fails | ❌ | ❌ | ❌ | 🔴 — but `transition_ledger_snapshot_mismatch` fires on next CI-enabled push, and the recovery command (`finish-stamp.py --pr N --binder ...`) is a single command |

**Good:**
- **No single point of failure**: CI billing exhaustion does NOT break the primary path. The local stamp runs without CI.
- **Fixes Mode A**: staging is in Python (no `|| true`, no `FLIP_HAPPENED` propagation). One process, one language.
- **Fixes Mode B**: no bash fallback — the local stamp either stamps both or fails loud (exit non-zero, `finish-commit.sh` halts).
- **Fixes Mode C**: the GHA verifies ledger continuity on the merged branch and repairs missing intermediate edges. The local stamp also reads the actual prior status (no hardcoded edge), so even without the GHA, direct-jump discontinuities are avoided (the edge is correct; only the missing intermediate entry might need GHA repair).
- **Fixes Mode D**: no multiple fallback layers — one Python script, one code path, one test surface.
- **No grace window**: the local stamp runs immediately after merge (inside `finish-work` flow), before `git push`. There is no window where the binder is un-stamped on the local clone. The GHA may add its own commit later, but the local clone is already consistent.
- **Aligns with ADR-012 §5**: GHA on `pull_request: closed` (safety net) + simplified local `finish-work` script (primary). "Consumers without Actions use a single idempotent, resumable `finish-work` script" — the local stamp IS that script.
- **The bypass the operator wanted**: the 732-line bash+Python hybrid is replaced by ~80 lines of pure Python. `commit_transaction`, `FLIP_HAPPENED`, bash fallback, Python verify — all gone. The GHA is a bonus safety net, not a dependency.

**Bad:**
- The local stamp still runs in the agent's environment (subagent fork, worktree). But it's pure Python (no bash/Python boundary), ~80 lines, no `|| true`, no variable propagation — the failure surface is drastically smaller. If it DOES fail, the GHA catches it (when CI is available).
- Adds GHA complexity (new workflow, `contents: write` permissions, bot commit). But the GHA is a safety net, not the primary path — if it fails, the local stamp already handled the stamp.
- GHA push conflicts with local stamp pushes — handled by idempotency + rebase (benign race).
- The agent must still be trusted to run `finish-stamp.py` as part of the `finish-work` flow. But the flow is simpler (one Python script, not a 732-line hybrid) and the GHA backstops it.
- Consumer repos without Actions: Layer 1 (local stamp) is the sole path. It's simpler and more reliable than the current `finish-ledger.sh`, but it doesn't have the GHA safety net. Mode C (squash-merge data loss) is partially mitigated (correct edge resolution from actual prior status) but not fully (missing intermediate entries are not inserted without the GHA's continuity check).

## Decision

**We will adopt Option E+ (belt-and-suspenders)**: a simplified local stamp (`finish-stamp.py`, ~80 lines pure Python) is the PRIMARY stamp path (no CI dependency), backed by a GHA on `pull_request: closed` as a SAFETY NET (verification + Mode C repair), and an optional daily sweep GHA as catch-up.

The original Option E (GHA-only) was superseded because it has a **single point of failure**: if CI billing is exhausted (this org has experienced GitHub Actions billing blocks before), the entire stamping fails with no automatic fallback. Option E+ flips the dependency — the local stamp is primary and CI-independent; the GHA is a bonus safety net that catches local stamp failures and repairs ledger continuity, but is NOT required for the primary path to function.

The initial ADR-013 proposal (Option A: CLI separation) is **rejected** — it does not fix the staging/commit flow (Mode A), does not fix squash-merge data loss (Mode C), and introduces a hardcoded-edge bug. The initial diagnosis ("`commit_transaction` is architecturally unreliable") is **corrected** — `commit_transaction` is provably correct in isolation; the root cause is the bash/Python boundary in `finish-ledger.sh` and the squash-merge data loss model.

## Consequences

- **Positive:**
  - All four failure modes (A: staging/commit, B: fallback without stamp, C: squash-merge loss, D: patch detector) are addressed at the architectural level, not via patching.
  - **No single point of failure**: CI billing exhaustion does NOT break the primary stamp path. The local stamp (`finish-stamp.py`) runs without CI.
  - The bash/Python boundary is eliminated for the primary stamp path — pure Python, no `|| true`, no `FLIP_HAPPENED`, no Python verify, no bash fallback.
  - Ledger continuity is verified by the GHA safety net — missing intermediate edges are detected and repaired (Mode C fix).
  - The correct transition edge is resolved from the binder's actual prior status — no hardcoded `pr-open→closed` (fixes the discontinuity bug in the bash fallback).
  - **No grace window**: the local stamp runs immediately after merge, before `git push`. The binder is consistent on the local clone before any CI runs.
  - ADR-012 §5's deferred direction is implemented — GHA on `pull_request: closed` (safety net) + simplified local `finish-work` script (primary).
  - `finish-ledger.sh` is replaced by `finish-stamp.py` (~80 lines Python). The 732-line bash+Python hybrid is retired.

- **Negative / trade-offs:**
  - **spc-297 (single-write atomicity) scope narrows**: `commit_transaction`'s atomicity guarantee was designed for the local stamp flow. Under Option E+, `finish-stamp.py` writes the binder (temp→rename) and appends the ledger (via `record` CLI) as two separate steps — not atomic. But this is the SAME state `commit_transaction` already produced in practice (the atomicity was theoretical for the finish path — it was never the real problem). `commit_transaction` stays in `transition-api.py` for other callers (`stamp-pr-open.sh`, `bump-fix-cycle.sh`); the finish path no longer uses it.
  - **GHA permissions**: the safety-net workflow needs `contents: write` to push the bookkeeping commit. This is a bot commit (`github-actions[bot]` or a dedicated GHA app token). If the org restricts token permissions, a PAT or GitHub App may be needed.
  - **Race condition**: Layer 1 (local stamp) and Layer 2 (GHA) run concurrently. Both are idempotent, so the race is benign — but the `finish-work` flow must handle a rejected `git push` (GHA already pushed) by pulling and detecting the no-op. `finish-commit.sh`'s existing "nothing to commit" path handles this.
  - **Consumer repos without Actions**: Layer 1 (local stamp) is the sole path. Mode C (squash-merge data loss) is partially mitigated (correct edge resolution from actual prior status) but the missing intermediate entry is not inserted without the GHA's continuity check. This is acceptable — consumer repos without Actions don't have the squash-merge frequency of the main repo.
  - **The agent must still run `finish-stamp.py`** as part of the finish-work flow. But the script is ~80 lines of pure Python (no bash/Python boundary), and the GHA backstops it. Process deviation is caught by the GHA (if CI available) or the scheduled sweep.

- **Follow-ups:**
  - Bug ticket `#416` — the recurring finish-ledger ledger gap (scope updated: implement `finish-stamp.py` + GHA safety net, not CLI separation).
  - A new Spec to implement: (1) `finish-stamp.py` (simplified local stamp), (2) the GHA workflow (`pull_request: closed` verification + Mode C repair), (3) optional daily sweep GHA.
  - `spc-398` A4 — the original CI/CD structural fixes spec (amend to reference Option E+).
  - `finish-work` SKILL.md step 11 — update: run `finish-stamp.py` (replaces `finish-ledger.sh`). The step is still required (primary path), but simpler. For repos with the GHA, the GHA backstops this step.
  - `spc-297` — amend: single-write atomicity guarantee applies to `commit_transaction` for non-finish callers; the finish path uses separate binder write + `record` CLI (non-atomic but loud-failure).
  - `finish-ledger.bats` tests — rewrite for `finish-stamp.py` (pure Python, no bash/Python boundary tests needed — the boundary no longer exists).
  - The `finish-ledger.sh` script is deprecated, not deleted — it may stay as a legacy entrypoint that delegates to `finish-stamp.py` for backward compatibility with existing skill references.

- **Verification:**
  - The GHA workflow stamps binder + ledger for every merged PR within the grace window.
  - The validator reports zero `transition_ledger_snapshot_mismatch` findings on newly merged tickets (after the GHA runs).
  - Ledger continuity is verified: no missing intermediate edges after GHA stamping.
  - The `finish-ledger.bats` test suite verifies the fallback path (simplified, no `commit_transaction`, no bash fallback layers).
  - CI stays green on `.lattice/` pushes after the GHA completes.

## Status history

- 2026-09-02: Proposed (initial: CLI separation — Option A; rejected after git forensics proved `commit_transaction` correct, root cause is bash/Python boundary + squash-merge data loss)
- 2026-09-02: Revised → Option E (GHA post-merge stamping — GHA primary, local fallback)
- 2026-09-02: Revised → Option E+ (belt-and-suspenders — simplified local stamp primary + GHA safety net) — after CI billing exhaustion risk analysis showed Option E has a single point of failure

## Notes

- The initial ADR-013 diagnosis ("`commit_transaction` is architecturally unreliable for ledger append") was based on the observation that `commit_transaction` returned 0 but the ledger was missing in the commit. Git forensics (commit-by-commit ledger/binder state tracing) and isolated reproduction proved that `commit_transaction` writes both files correctly — the failure is in the bash staging/commit flow (`git add || true`, `FLIP_HAPPENED` propagation) and in squash-merge data loss, not in `commit_transaction`.
- ADR-012 §5 identified this direction in its original accepted form: "Post-merge bookkeeping is event-driven, with a scripted fallback. The Finish ledger is written by a GitHub Action on `pull_request: closed` (merged) committing as a bot; consumers without Actions use a single idempotent, resumable `finish-work` script." This ADR implements that deferred direction.
- The `transition-api.py record` CLI has been the de facto reliable ledger writer throughout this session — every manual backfill used it. Option E makes it the primary path inside the GHA, not a fallback bolted onto a broken flow.
- The `.jsonl.lock` sidecar files observed in-repo (`tkt-385.jsonl.lock`, `tkt-400.jsonl.lock`, `tkt-401.jsonl.lock`) indicate `resolve_state_home()` returned empty for some runs, causing the co-located lock fallback (ADR-011 violation). This is a symptom of the local-execution-context unreliability that Option E eliminates.
- 10+ PRs were created attempting to patch this bug (tkt-317, 323, 335, 338, 360, 382 normalise, 385 discontinuity, 386 dedup, 400/401 insert, 402 verify, 402 fallback, 402 gate removal). Each patch addressed one failure mode while introducing another. This ADR replaces the patch approach with an architectural bypass.

---

_Not a Lattice bloodline/graph node. Cite from Spec/PR/Review with `ADR-013` or this path._
