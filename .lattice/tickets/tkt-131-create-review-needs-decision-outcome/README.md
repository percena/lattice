# tkt-131-create-review-needs-decision-outcome

> **TL;DR:** Add needs_decision outcome to create-review so design-level undecided reviews get a forcing function instead of stalling at inform_only
> **Kind:** feat · **Priority:** P2
> **Path:** rev-20260827-102420Z → tkt-131 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/131 |
| status | pr-open |
| adopted | false |
| summary | Add needs_decision outcome to create-review for design-level undecided reviews |
| spec | none — ticket-only from rev-20260827-102420Z F1 |
| covers | rev F1 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | skills/create-review/SKILL.md, skills/create-review/references/policy.md, skills/create-review/references/templates/review.md |
| solo_merge | yes |
| **primary_ticket** | tkt-131 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-131-create-review-needs-decision-outcome |
| prs | pr-141 — https://github.com/percena/lattice/pull/141 |

## Acceptance (this slice)

- [x] **A1** create-review accepts needs_decision as a valid outcome (front-matter + skill flow)
- [x] **A2** needs_decision next-step: review enters a triage-queue mechanism (not terminal stop like inform_only)
- [x] **A3** rev-20260827-064527Z can be re-outcomed to needs_decision and surfaces for triage
- [x] **A4** bats/validator: concluded review with needs_decision passes; inform_only unchanged

## Approach

Add needs_decision to the outcome enum in create-review SKILL.md:42 and the next-step table (:103-109). The outcome means "review is NOT terminal — it needs a human design-policy decision before it can become actionable." Add a triage-queue mechanism: a .lattice/reviews/needs-decision.md checklist (or a section in morning-triage.md if tkt-134 lands first) that lists all needs_decision reviews. Update policy.md outcome table + review.md template front matter. Validator: accept needs_decision as valid outcome.

## Anticipated decisions

- Triage-queue mechanism shape (file vs. morning-triage section) — disposition: agent-decides (reversible, ticket-local; prefer file if tkt-134 not landed)
- Whether to retroactively re-outcode rev-20260827-064527Z — disposition: pre-resolved (A3 acceptance says yes, that one review)

## References

- GitHub issue body is SoT for long prose
- Review: rev-20260827-102420Z (Finding 1)
- Prior: rev-20260827-064527Z (fsm-design-gaps — the live inform_only example)

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: tkt-131 · Parallel group: G1 · Worktree bind: tkt-131-create-review-needs-decision-outcome

## Finish

- (none yet)
