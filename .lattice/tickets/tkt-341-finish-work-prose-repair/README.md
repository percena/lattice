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
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T02:29:15Z |
| updated | 2026-09-02T02:29:15Z |
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
| prs | (none) |

## Acceptance (this slice)

See GitHub issue #341 for the full slice text; Spec ids owned by this slice:

- [ ] **A5** flow.md §7 uses `verify-main-chain.sh --stage merge`; SKILL.md names the state-home marker location; `ci-gate-check.sh` in short path + checklist; base-tip capture explicit; `docs-truth.bats` asserts all four.

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
