# tkt-349-ci-gate-check-gh-json-fields

> **TL;DR:** ci-gate-check.sh asks gh pr checks for a 'conclusion' JSON field that gh 2.9x lacks; the hard CI gate exits 2 on every run.
> **Kind:** bug · **Priority:** P1

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug,P1 |
| github | https://github.com/percena/lattice/issues/349 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T03:33:16Z |
| updated | 2026-09-02T03:33:16Z |
| adopted | false |
| summary | ci-gate-check.sh asks gh pr checks for a 'conclusion' JSON field that gh 2.9x lacks; the hard CI gate exits 2 on every run. |
| spec | none |
| paths | skills/finish-work/scripts/ci-gate-check.sh, skills/finish-work/scripts/tests/ci-gate-check*.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-349 (this issue) |
| worktree_bind | tkt-349-ci-gate-check-gh-json-fields |
| prs | (none) |

## Acceptance

See GitHub issue #349 body (A1, A2).

## Approach

1. Replace the field list with `name,state,bucket,link,workflow`; classify pass/fail/pending from `bucket` (pass|fail|pending|skipping|cancel) with `state` as fallback. 2. Detect 'Unknown JSON field' in gh stderr and surface it as its own actionable error (still exit 2). 3. Add a recorded gh 2.92 payload fixture; bats: all-green passes, real red blocks, unknown-field error message.

## Anticipated decisions

(none — S-class)

## Decision journal

## Notes

- Surfaced during the spc-337 delivery (finish-work runs on PRs #343–#348; reviewer finding on PR #348). Follow-up per preferences.md "Review-findings → tickets".

## Lineage

- Parent issue: #349 (ticket-only, no Spec)
- Primary ticket: tkt-349
- Refs: spc-337, ADR-012

## Finish

- (none yet)
