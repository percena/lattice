# tkt-341-finish-work-prose-repair

> **TL;DR:** finish-work prose repaired: multi-PR merge verifier, marker location, ci-gate-check in short path, explicit base-tip capture; docs-truth bats.
> **Kind:** docs · **Priority:** P2
> **Path:** spc-337 → tkt-341 → (pr-…)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P2 |
| labels | docs,P2 |
| github | https://github.com/percena/lattice/issues/341 |
| status | pr-open |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T02:29:15Z |
| updated | 2026-09-02T02:42:04Z |
| adopted | false |
| summary | finish-work prose repaired: multi-PR merge verifier, marker location, ci-gate-check in short path, explicit base-tip capture; docs-truth bats. |
| spec | spc-337 — FSM conformance closure (path: ../../specs/spc-337-fsm-conformance-closure.md) |
| covers | A5 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | G1 |
| paths | skills/finish-work/SKILL.md, skills/finish-work/references/flow.md, skills/finish-work/tests/docs-truth.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-341 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-341-finish-work-prose-repair |
| worktree | sibling `…/lattice.worktrees/tkt-341-finish-work-prose-repair/` |
| prs | pr-345 — https://github.com/percena/lattice/pull/345 |

## Acceptance (this slice)

See GitHub issue #341 for the full slice text; Spec ids owned by this slice:

- [x] **A5** flow.md §7 uses `verify-main-chain.sh --stage merge`; SKILL.md names the state-home marker location; `ci-gate-check.sh` in short path + checklist; base-tip capture explicit; `docs-truth.bats` asserts all four.

## Approach

1. flow.md §7 LAYER LOOP step 6: before `gh pr merge`, `BASE_TIP=$(git ls-remote origin refs/heads/<base> | cut -f1)`; after merge `verify-main-chain.sh --stage merge --pr <N> --expected-oid $BASE_TIP --repo <owner/name>`; drop `verify-mutation.sh --pr`.
2. SKILL.md: three occurrences of 'repo MAIN clone `.lattice/`' → 'out-of-repo state home (`lattice-state-home.sh`; ADR-011)'.
3. SKILL.md Finish cycle: add a `ci-gate-check.sh` checklist row after base update; short path step 3 names it (`scripts/ci-gate-check.sh --pr N`) — read the script's usage first.
4. SKILL.md short path: insert the base-tip capture line before step 7 (single PR).
5. `tests/docs-truth.bats`: four grep assertions (negative + positive) mirroring tkt-118 A7 style.

## Anticipated decisions

- Where the base-tip capture lives (short path vs flow.md only) — disposition: pre-resolved(spc-337 A5): both; short path carries the one-liner.
- Whether to touch Common Rationalizations rows — disposition: agent-decides (only if they repeat the stale marker location).

## Decision journal

<!-- Append-only during execution. -->

- 2026-09-02 — Short path renumbered 7→12: the base-tip capture is its own numbered step 7 (`BASE_TIP=$(git ls-remote origin "refs/heads/<BASE>" | cut -f1)`), merge+proof is step 8; internal refs updated (`step 9`→`step 10` in the Finish-ledger step; flow.md §7 `steps 3–11`→`3–12`). Source: spc-337 A5 "one explicit command in the short path"; reversible, ticket-local.
- 2026-09-02 — `docs-truth.bats` lives at `skills/finish-work/tests/` (binder `paths` / issue #341 verbatim) although sibling script suites sit under `scripts/tests/`; the file is prose-only (no script under test), so the top-level `tests/` split is defensible. Source: binder `paths` row (pre-resolved by create-tickets).
- 2026-09-02 — flow.md §7 step 6 under `--close`: `verify-main-chain.sh --stage merge` proves MERGED + base-tip advance, which a close never produces, so the `--close` branch confirms `gh pr view <N> --json state` = `CLOSED` instead. Source: `verify-main-chain.sh --help` (stage merge contract); reversible, ticket-local.
- 2026-09-02 — Common Rationalizations rows left untouched: none repeats the stale marker location (anticipated-decision disposition "only if they repeat it"). `ci-gate-check.sh` was also added to the SKILL `**Scripts:**` roster so the short-path reference resolves to a listed script.

## Pending decisions

(none)

## Attempts

<!-- Fallback ledger (ADR-004 §5). -->

## Notes

- NOTICED: skills/finish-work/scripts/ci-gate-check.sh — on gh 2.92 it fails "cannot load gh pr checks" because it requests `--json name,state,conclusion,link` and `conclusion` is not a `gh pr checks` JSON field; the script fix is a separate ticket (out-of-paths, 2026-09-02)

## References

- Spec: `spc-337` → `.lattice/specs/spc-337-fsm-conformance-closure.md`
- ADR: `ADR-012` → `docs/adr/012-transitions-stamped-by-the-path.md`
- Review: `rev-20260902-015425Z`

## Lineage

- Parent spec: **spc-337**
- Parent issue (GH sub-issue of Spec primary): **#337**
- Primary ticket: **tkt-341**
- Covers: **A5**
- Blocked by: (none)
- Merge blocked by: (none)
- Parallel group: G1
- Worktree bind: tkt-341-finish-work-prose-repair

## Assets

(none)

## Finish

- (none yet)
