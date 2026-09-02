---
# status: draft | locked | done | superseded
id: spc-416
slug: post-merge-ledger-stamping
title: Post-merge ledger stamping — belt-and-suspenders (simplified local stamp + GHA safety net)
kind: feat
status: done
mode: C
priority: P1
summary: "Replace the 732-line bash+Python hybrid finish-ledger.sh with a pure-Python finish-stamp.py (Layer 1, no CI dependency) backed by a GHA safety net (Layer 2). Eliminates the bash/Python boundary that caused 9+ recurring transition_ledger_snapshot_mismatch failures."
created: 2026-09-02
updated: 2026-09-02
tickets: [tkt-418, tkt-419]
prs: [pr-420, pr-421]
reviews: []
supersedes: [spc-398 A4]
superseded_by: null
---

# Spec: Post-merge ledger stamping — belt-and-suspenders

> **TL;DR:** finish-ledger.sh's bash/Python boundary (not commit_transaction) caused 9+ recurring ledger stamp failures across 4 distinct failure modes. Replace with ~150-line pure Python finish-stamp.py (primary, CI-independent) + GHA on `pull_request: closed` (safety net, Mode C repair). Dry run passed 22/22 assertions.
> **Kind:** feat · **Status:** locked · **Mode:** C · **Priority:** P1
> **Path:** ADR-013 → spc-416 → tkt-… → pr-…
> **Supersedes:** spc-398 A4 (finish-ledger backfill was a patch; this replaces the entire stamp path)

## Why

`finish-ledger.sh` is a 732-line bash+Python hybrid that stamps a merged ticket to `closed`. The critical write path crosses the bash/Python boundary three times: (1) a Python heredoc calls `commit_transaction()`; (2) bash stages both files via `git add ... || true`; (3) bash extracts `FLIP_HAPPENED` from Python stdout via `sed` to gate a staging assertion. Three patch attempts (PR #404, #405, dev gate removal) each added a new detection layer with its own failure surface. All three failed — the result: `transition_ledger_snapshot_mismatch` CI failures on every merged ticket from 2026-09-02 (tkt-381, 382, 383, 384, 385, 386, 400, 401, 402).

ADR-013's git forensics (commit-by-commit ledger/binder state tracing) and isolated reproduction proved the initial diagnosis wrong: `commit_transaction` is NOT unreliable — it writes both binder and ledger correctly in isolation. The actual root cause is the **bash/Python boundary** downstream of `commit_transaction`:

- **Mode A** (tkt-381/382/383): `git add || true` silently drops ledger staging; `FLIP_HAPPENED` variable propagation unreliable across bash/Python boundary
- **Mode B** (tkt-386): bash fallback appends ledger without binder stamp → binder/ledger inconsistency
- **Mode C** (tkt-385/400/401): squash merge loses `in-progress→pr-open` ledger entry from worktree
- **Mode D** (tkt-402/386 post-patch): each patch's detector has its own failure surface (import scope, FLIP_HAPPENED, double-append)

This org has experienced GitHub Actions billing blocks before (documented in `lattice-ci-billing-block` memory). A GHA-only solution (Option E) has a single point of failure: if billing is exhausted, stamping stops. Option E+ flips the dependency — the local stamp is primary (CI-independent), the GHA is a safety net.

ADR-012 §5 already recorded the direction: "Post-merge bookkeeping is event-driven, with a scripted fallback. The Finish ledger is written by a GitHub Action on `pull_request: closed`... consumers without Actions use a single idempotent, resumable `finish-work` script." This was deferred and never implemented. This spec implements that direction.

## In scope

- **Layer 1 — `finish-stamp.py`** (~150 lines pure Python, replaces 732-line `finish-ledger.sh` as primary stamp path):
  - Reads binder status; idempotent no-op if already `closed`
  - Resolves correct transition edge from actual prior status (no hardcoded `pr-open→closed`)
  - Writes binder (temp→rename): status→closed, `## Finish` body, `prs` row, `updated` stamp
  - Appends ledger via `transition-api.py record` CLI subprocess (proven reliable)
  - Stages both files via Python `subprocess.run` with `check=True` (no `|| true`)
  - Verifies staging in-process (no `FLIP_HAPPENED` variable propagation)
  - Mode C repair: checks ledger continuity before stamping; inserts missing intermediate edge(s) if detected
- **Layer 2 — GHA `pull_request: closed`** (safety net, CI-dependent):
  - Verifies the local stamp landed (no-op if binder already `closed`)
  - Repairs ledger continuity (Mode C — inserts missing intermediate edges on the merged branch)
  - Catches local stamp failures and agent process deviations
  - Commits as `github-actions[bot]`
- **`finish-work` SKILL.md** step 11 — updated to use `finish-stamp.py` instead of `finish-ledger.sh`
- **`finish-ledger.sh`** — deprecated; becomes a legacy entrypoint that delegates to `finish-stamp.py` (backward-compatible for existing skill references)
- **`finish-stamp.bats`** test suite — covers all 5 dry-run scenarios

## Out of scope

- **Layer 3 — daily sweep GHA** (optional catch-up) — deferred to a follow-up ticket if Layers 1+2 prove insufficient after one dogfood cycle
- Rewriting `stamp-pr-open.sh` or `bump-fix-cycle.sh` — they still use `commit_transaction` and are not in the finish path
- Removing `commit_transaction` from `transition-api.py` — it stays for other callers (stamp-pr-open, bump-fix-cycle)
- Rewriting the validator (`validate-lattice-artifacts.py`) — the validator stays read-only; the grace window is eliminated because the local stamp runs immediately

## Acceptance

- [x] **A1** `finish-stamp.py` stamps binder + ledger in a single Python process — no bash/Python boundary, no `commit_transaction`, no `FLIP_HAPPENED`, no bash fallback, no `|| true`
- [x] **A2** `finish-stamp.py` resolves the correct transition edge from the binder's actual prior status (`pr-open→closed` for normal merges, `in-progress→closed` for direct jumps, `queued→closed` for skipped lifecycle) — no hardcoded edge
- [x] **A3** `finish-stamp.py` is idempotent — no-op (exit 0, no duplicate ledger entry, nothing staged) when binder is already `closed` and ledger is consistent
- [x] **A4** `finish-stamp.py` detects and repairs ledger discontinuity (Mode C) — when the ledger's last `to` ≠ binder's prior `status`, inserts the missing intermediate edge before stamping `→closed`, producing a continuous ledger
- [x] **A5** `finish-stamp.py` staging fails LOUD — exit non-zero when the ledger cannot be staged (gitignored, held index lock, foreign cwd) — no `|| true` swallowing
- [x] **A6** GHA on `pull_request: closed` (merged) verifies the local stamp landed and repairs missing ledger entries (Mode C safety net) — runs on the merged dev branch, commits as `github-actions[bot]`
- [x] **A7** `finish-work` SKILL.md step 11 updated to run `finish-stamp.py` (replaces `finish-ledger.sh` invocation)
- [x] **A8** `finish-ledger.sh` delegates to `finish-stamp.py` (legacy entrypoint, backward-compatible — existing skill references still work)
- [ ] **A9** `finish-stamp.bats` test suite covers all 5 dry-run scenarios: normal (pr-open→closed), direct jump (in-progress→closed), idempotent (already closed → no-op), Mode C repair (missing edge → insert + stamp), staging failure (gitignored → exit non-zero)
- [ ] **A10** No more `transition_ledger_snapshot_mismatch` on newly merged tickets after implementation — CI stays green on `.lattice/` pushes

## Non-goals

- Making `commit_transaction` the finish-path writer again — it's proven correct but the bash/Python boundary around it is the problem; the finish path uses `record` CLI instead
- Eliminating all local bookkeeping commits to the integration branch — the local stamp is primary; the GHA is a safety net. ADR-012 §5's "human clones stop pushing bookkeeping commits" is aspirational for a future where the GHA-only model has soaked long enough
- Supporting cancel path in `finish-stamp.py` v1 — cancel path is a separate concern (no PR, different evidence requirements); `finish-ledger.sh --cancel` is retained for now

## Decisions (principal, user-confirmed)

1. **Local stamp is primary (CI-independent); GHA is safety net** — CI billing exhaustion does NOT break the primary path. This is the critical departure from the rejected Option E (GHA-only) which had a single point of failure.
2. **`finish-stamp.py` is pure Python** (~150 lines) — eliminates the bash/Python boundary that caused all four failure modes. No `commit_transaction`, no `FLIP_HAPPENED`, no bash fallback, no `|| true`.
3. **`commit_transaction` is NOT used in the finish path** — it stays in `transition-api.py` for other callers (`stamp-pr-open.sh`, `bump-fix-cycle.sh`). The finish path uses `record` CLI for ledger append + temp→rename for binder write.
4. **Ledger append via `transition-api.py record` CLI** — proven reliable by 9+ manual backfills that never failed. The `record` CLI resolves the correct edge from the `from`/`to` arguments (not hardcoded).
5. **`finish-ledger.sh` is deprecated, not deleted** — becomes a legacy entrypoint that delegates to `finish-stamp.py` for backward compatibility with existing skill references. Avoids breaking consumer repos that call `finish-ledger.sh` directly.
6. **Mode C repair in Layer 1** — the local stamp checks ledger continuity before stamping and inserts missing intermediate edges. This is a bonus beyond the original ADR-013 design (which put Mode C repair only in the GHA Layer 2). Having it in Layer 1 means CI-unavailable repos also get Mode C protection.
7. **spc-297 (single-write atomicity) scope narrows** — the finish path no longer uses `commit_transaction`'s atomic binder+ledger write. The binder is written (temp→rename) and the ledger is appended (via `record` CLI) as two separate steps. The atomicity trade-off is acceptable: a `record` CLI failure is LOUD (exit non-zero), while `commit_transaction`'s failure was SILENT (returned 0). spc-297's acceptance should be amended to note the finish path is non-atomic but loud-failure.
8. **spc-398 A4 is superseded** — the original "finish-ledger stamps the pr-open→closed transition ledger entry" was a patch on the broken stamp path. This spec replaces the entire stamp path.

## Agent-assumed (secondary)

- `finish-stamp.py` reuses existing library functions from `skills/_lattice-lib/scripts/lib/` (`binder_rows`, `status_vocab`, `transition_table`) — no new library code needed.
- `finish-stamp.py` imports `transition-api.py` via `importlib.util` (same pattern as the current `finish-ledger.sh` heredoc) for `ledger_path`, `home_for_binder`, and `edge_for` resolution.
- The GHA workflow uses `GITHUB_TOKEN` with `contents: write` permission (default for `pull_request` events in public repos; may need explicit `permissions:` block).
- The GHA invokes `finish-stamp.py` in CI (same script, same code path) — idempotent, so if the local stamp already ran, the GHA is a verify-only no-op.
- The race between local stamp and GHA is benign (both idempotent; the second committer rebases and sees the other's commit → no-op).

## References

- ADR: `docs/adr/013-finish-ledger-ledger-write-separation.md` (Option E+ — belt-and-suspenders)
- Related ADRs: `ADR-012` §5 (Post-merge bookkeeping is event-driven — deferred direction), `ADR-007` §5a (CI gate — `transition_ledger_snapshot_mismatch`)
- Bug ticket: `#416` (finish-ledger ledger gap — recurring `transition_ledger_snapshot_mismatch`)
- Superseded: `spc-398` A4 (finish-ledger backfill — was a patch on the broken stamp path)
- Dry run: 22/22 assertions passed across 5 scenarios (normal, direct jump, idempotent, Mode C repair, staging failure)
- Prototype: `skills/_lattice-lib/scripts/finish-stamp.py` (dry-run version, needs production hardening)
- CI billing risk: `lattice-ci-billing-block` memory (org has experienced GitHub Actions billing blocks)
- Recurrence log: tkt-381, 382, 383, 384, 385, 386, 400, 401, 402 (9+ instances, 4 failure modes)
