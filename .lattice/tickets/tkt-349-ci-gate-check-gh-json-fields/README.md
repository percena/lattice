# tkt-349-ci-gate-check-gh-json-fields

> **TL;DR:** ci-gate-check.sh asks gh pr checks for a 'conclusion' JSON field that gh 2.9x lacks; the hard CI gate exits 2 on every run.
> **Kind:** bug · **Priority:** P1

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug,P1 |
| github | https://github.com/percena/lattice/issues/349 |
| status | pr-open |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T03:33:16Z |
| updated | 2026-09-02T03:55:08Z |
| adopted | false |
| summary | ci-gate-check.sh asks gh pr checks for a 'conclusion' JSON field that gh 2.9x lacks; the hard CI gate exits 2 on every run. |
| spec | none |
| paths | skills/finish-work/scripts/ci-gate-check.sh, skills/finish-work/scripts/tests/ci-gate-check*.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-349 (this issue) |
| worktree_bind | tkt-349-ci-gate-check-gh-json-fields |
| prs | pr-354 — https://github.com/percena/lattice/pull/354 |

## Acceptance

- [x] **A1** rollup fetched with `name,state,bucket,link`; `normalize_check` derives the legacy state/conclusion pair from `state`+`bucket`; gh-2.92-shaped bats: all-green pass, real red block, TIMED_OUT infra waiver, pending block.
- [x] **A2** `Unknown JSON field` from gh surfaces as a distinct 'field mismatch' error (exit 2, still fail-closed).

## Approach

1. Replace the field list with `name,state,bucket,link,workflow`; classify pass/fail/pending from `bucket` (pass|fail|pending|skipping|cancel) with `state` as fallback. 2. Detect 'Unknown JSON field' in gh stderr and surface it as its own actionable error (still exit 2). 3. Add a recorded gh 2.92 payload fixture; bats: all-green passes, real red blocks, unknown-field error message.

## Anticipated decisions

(none — S-class)

## Decision journal

- 2026-09-02 normalization keeps `conclusion` when a payload already carries it (older gh / existing fixtures) and derives it otherwise; pending detected via `bucket == pending` OR a pending-ish `state`, so both gh generations classify identically (source: agent-judgment, ticket-local).
- 2026-09-02 verified live on gh 2.92.0 against PR #351: `ok=True checks_total=1` (was exit 2 on every run before).

## Notes

- Surfaced during the spc-337 delivery (finish-work runs on PRs #343–#348; reviewer finding on PR #348). Follow-up per preferences.md "Review-findings → tickets".

## Lineage

- Parent issue: #349 (ticket-only, no Spec)
- Primary ticket: tkt-349
- Refs: spc-337, ADR-012

## Finish

- (none yet)
