# tkt-127-from-heads-local-source

<!-- Binder is a thin recovery card (not a second issue tracker). -->

> **TL;DR:** `build-review-context.sh --from-heads` emits `… is MERGED tkt-1-alpha-head — …` instead of `… is MERGED — …`; `IFS=$'\t' read` at line 373 leaks tab-only IFS into the `$(head_binder_for)` command substitution, breaking the internal `read -r state headref` (no space in IFS → whole python output lands in `state`).
> **Kind:** bug · **Priority:** P3
> **Path:** (no Spec) → tkt-127 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P3 |
| labels | bug, P3 |
| github | https://github.com/percena/lattice/issues/127 |
| status | closed |
| adopted | false |
| summary | build-review-context --from-heads mis-labels non-open PR state — IFS=$'\t' leak from line 373 read poisons head_binder_for's internal read |
| spec | (none — standalone process-hardening bug) |
| covers | (none) |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | skills/_lattice-lib/scripts/build-review-context.sh, skills/_lattice-lib/scripts/tests/build-review-context.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-127 (this issue) |
| **related_tickets** | tkt-122 (surfaces same bats suite; independent root cause) |
| **worktree_bind** | `tkt-127-from-heads-local-source` |
| worktree | sibling `…/lattice.worktrees/tkt-127-from-heads-local-source/` (default for shippable) |
| prs | pr-130 — https://github.com/percena/lattice/pull/130 |

## Acceptance (this slice)

- [x] **A1** `bats skills/_lattice-lib/scripts/tests/build-review-context.bats` — test 15 ("--from-heads marks a non-open PR as local source") passes; full 17-test suite green.
- [x] **A2** Root cause fixed: `head_binder_for` no longer inherits a tab-only IFS from its caller — the command substitution is decoupled from the `IFS=$'\t' read` at the call site (line 373).
- [x] **A3** No regression: tests 13/14 (`--from-heads` open-head + local fallback) still pass; the emitted label for a non-open PR is exactly `local (pr-N is MERGED — not an open head)` (state alone, no headref bleed).

## Reproduction Steps (bug-class)

1. **A1:** `bats …/build-review-context.bats` → `not ok 15 --from-heads marks a non-open PR as local source`; assertion `[[ "$output" == *"binder source: local (pr-11 is MERGED — not an open head)"* ]]` fails because actual output is `binder source: local (pr-11 is MERGED tkt-1-alpha-head — not an open head)`.
2. **Root cause (trace):** line 373 `IFS=$'\t' read -r _src _label <<<"$(head_binder_for …)"` — the `IFS=$'\t'` temporary assignment applies to the **entire** simple command, including the `$(head_binder_for)` command substitution. Inside `head_binder_for`, line 323 `read -r state headref < <(printf '%s' "$pr_json" | python3 …)` therefore runs with `IFS=$'\t'` (no space). The python output `MERGED tkt-1-alpha-head` has no tab → `read` cannot split it → `state="MERGED tkt-1-alpha-head"`, `headref=""`. The label printf at line 333 then substitutes `${state:-unknown}` → `MERGED tkt-1-alpha-head`.
3. **Confirmed via minimal repro:** `IFS=$'\t' read -r _src _label <<<"$(inner)"` (where inner does a default-IFS `read -r a b`) reproduces state-swallowing; decoupling `out="$(inner)"; IFS=$'\t' read … <<<"$out"` resolves it.

## Approach

- Fix the **root** at line 373: capture the command substitution into a variable first, then run the `IFS=$'\t' read` on the captured string — so the `$(head_binder_for)` subshell inherits the caller's default IFS, not the one-shot tab IFS:
  ```bash
  _hb_out="$(head_binder_for "${TICKET_IDS[$i]}" "${BINDERS[$i]}")"
  IFS=$'\t' read -r _src _label <<<"$_hb_out"
  ```
- Why not pin IFS inside `head_binder_for` line 323 instead: that band-aids the victim and leaves the leak footgun for any future `read` added under the same call pattern. Decoupling at the call site removes the leak class and keeps `head_binder_for` self-contained under default IFS.
- No version bump: per ADR-005, dev landings enforce only version non-decrease (this PR does not touch any plugin manifest version; dev-mode is lenient).

## Anticipated decisions

- Fix location (call site vs victim read) — disposition: pre-resolved (call-site decouple = root cause, removes leak class).

## Decision journal

<!-- append-only -->

## Pending decisions

<!-- (none) -->

## Attempts

<!-- (none) -->

## Notes

- Issue #127 was surfaced while verifying tkt-122's `ci-local.sh` full run on macOS bash 3.2; **not** a shell-portability defect (assertion is content-based, not BSD/GNU). tkt-122 fixed the sed-related failures in this same suite (tests 13/14/17); test 15 is a separate logic failure — same surface, independent root cause.
- Bundled with this PR: ADR-005 Status history touch-up (line 3 says `Accepted`; Status history only recorded `Proposed` — commit `c4cf429` set the header to Accepted but did not append the history entry). Unrelated to #127 but trivial doc consistency; batched to avoid a separate PR.

## References

- GitHub issue body: https://github.com/percena/lattice/issues/127
- ADR-005: docs/adr/005-version-bump-at-release-boundary.md
- No Spec (standalone process-hardening bug).

## Lineage

- Parent spec: (none)
- Parent issue: (none — ticket-only)
- Primary ticket: **tkt-127**
- Related / sub-tickets: tkt-122 (same bats suite, independent root cause)
- Covers: (none)
- Blocked by: (none)
- Parallel group: G1
- Worktree bind: `tkt-127-from-heads-local-source`

## Assets

Local files in `./assets/`.

## Finish

- pr-130 merged: 2026-08-27T08:09:41Z — https://github.com/percena/lattice/pull/130 (base merge)
- issue #127 closed: 2026-08-27T08:09:56Z — https://github.com/percena/lattice/issues/127
