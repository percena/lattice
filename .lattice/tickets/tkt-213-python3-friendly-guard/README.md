# tkt-213-python3-friendly-guard

<!-- Binder is a thin recovery card (not a second issue tracker). -->

> **TL;DR:** Build ensure-python3.sh guard, add guards to unguarded skill scripts, add plugin hook fail-open advisory, document the python3 prerequisite.
> **Kind:** chore · **Status:** open · **Priority:** P1
> **Path:** spc-212 → tkt-213 → (pr-…)

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P1 |
| labels | chore, P1 |
| github | https://github.com/percena/lattice/issues/213 |
| status | open |
| adopted | false |
| summary | ensure-python3.sh guard + script guards + hook advisory + docs prereq |
| spec | spc-212 — make python3 dependency explicit and user-friendly (path: ../../specs/spc-212-python3-friendly-guard.md) |
| covers | A1, A2, A3, A4, A5 |
| blocked_by | (none) |
| parallel_group | (serial) |
| paths | skills/_lattice-lib/scripts/**, skills/*/scripts/**, plugins/lattice/hooks/**, README |
| solo_merge | yes |
| **primary_ticket** | tkt-213 (this issue) — owner of the ship (one PR) |
| **related_tickets** | (none) |
| **worktree_bind** | `spc-212-python3-friendly-guard` (open-time spc bind; reused for this single-ticket ship) |
| worktree | sibling `/Users/mxue/GitRepos/MVP/lattice.worktrees/spc-212-python3-friendly-guard/` |
| prs | pr-214 — https://github.com/percena/lattice/pull/214 |

## Acceptance (this slice)

- [x] **A1** `ensure-python3.sh` exists under `_lattice-lib/scripts/`; `command -v python3` present → exit 0 silently; absent → platform-specific install command (macOS / Arch / Alpine / Debian·Ubuntu·Fedora) to stderr + nonzero exit.
- [x] **A2** No previously-unguarded python3-using skill script emits a bare "command not found"; each guards (fail-closed) or degrades gracefully.
- [x] **A3** Plugin PreToolUse hooks emit a one-time fail-open advisory when python3 absent ("Lattice guardrails degraded: strict-profile protections inactive. Install: …"); tool call still allowed.
- [x] **A4** README + install docs state "Requires bash + python3 (stdlib only, no pip)."
- [x] **A5** No regression: already-graceful (`check-duplicate-work.sh`) and already-hard-guarding (`ensure-workspace.sh`, `alignment-check.sh`, `ci-gate-check.sh`) scripts unchanged; hook fail-open semantics preserved.

## Notes

- Per-script guard decision: `queue-health.sh` (advisory) → degrade; `finish-ledger.sh`, `stamp-pr-open.sh`, `ratify.sh`, `spec-supersede.sh`, `reconcile-state.sh`, `bump-fix-cycle.sh`, `upload-github-asset.sh`, `build-review-context.sh`, `ensure-lattice.sh`, `close-fixed-issues.sh`, `update-pr-base.sh`, `cleanup-workspace.sh` → fail-closed (real work needs python3).
- Hook advisory must fire **once** per hook invocation, not once per python3 subprocess.
- Decisions D1 (keep Python), D2 (no jq), D3 (split fail-closed/fail-open), D4 (standalone helper) are locked in spc-212 — do not re-litigate.

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-212` (path above)
- ADR: none
- Worktree policy: one tree ↔ one PR; this ship reuses the spc-212 worktree

## Lineage

- Parent spec: **spc-212**
- Parent issue (GH sub-issue of Spec primary): **#212**
- Primary ticket: **tkt-213**
- Related / sub-tickets: (none)
- Covers: **A1, A2, A3, A4, A5**
- Blocked by: (none)
- Parallel group: (serial)
- Worktree bind: `spc-212-python3-friendly-guard`
- Child PRs: (none yet)

## Assets

(none)

## Finish

- (none yet)
