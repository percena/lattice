# tkt-107-escaped-defect-metric

> **TL;DR:** The trust-calibration metric spc-42 parked on, as pure artifact mechanics — bug binders carry found_by/escaped_from lineage, every digest counts escapes per triage class, and spc-42's revisit trigger is armed by a dated amendment
> **Kind:** feat · **Priority:** P2
> **Path:** spc-104 → tkt-107 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/107 |
| status | pr-open |
| adopted | false |
| summary | binder template found_by/escaped_from + tracing recipe + digest escape-count block + spc-42 amendment |
| spec | spc-104 — runtime verification loop |
| covers | A4, A5 |
| blocked_by | tkt-105 (train order; content-independent except the cut) |
| parallel_group | G1 (wave 2; path-disjoint with tkt-106/tkt-108) |
| paths | skills/create-tickets/references/templates/ticket-binder.md, skills/review-delivery/SKILL.md, skills/review-delivery/references/axes.md, skills/review-delivery/references/templates/digest.md, .lattice/specs/spc-42-attention-loop.md |
| solo_merge | yes (after tkt-105) |
| **primary_ticket** | tkt-107 (this issue) |
| **related_tickets** | tkt-105 (bug producer), tkt-47 (review-delivery origin; its SKILL.md already hooks the metric as "a later ticket") |
| **worktree_bind** | tkt-107-escaped-defect-metric |
| worktree | sibling …/lattice.worktrees/tkt-107-escaped-defect-metric/ |
| prs | pr-111 — https://github.com/percena/lattice/pull/111 |

## Acceptance (this slice)

- [x] **A1** ticket-binder template: optional `found_by` (`verify-features rev-… | human | review`) and `escaped_from` (`pr-N — digest rev-… (auto-pass)`) rows with a usage note (bug-class binders only)
- [x] **A2** tracing recipe in review-delivery references (blame/`git log -S` defective lines → PR → grep digests for its triage class); digest template gains an escape-count block beside the sampling convention (since-last-digest + cumulative per class); SKILL.md §Trust calibration updated from "metric tooling is a later ticket" to the shipped mechanics
- [x] **A3** dated amendment in spc-42 Risks: metric mechanics landed via spc-104; the "revisit risk-tiered auto-merge once the metric exists" trigger is now armed (auto-merge itself stays out of scope)
- [x] **A4** ci-local green; carries the shared 0.3.0 cut byte-identically

## Approach

All doc/template edits — no scripts. The digest count is a grep discipline documented in axes.md (`grep -rn '| escaped_from |' .lattice/tickets/` filtered to bug binders newer than the previous digest), not a new tool; if a helper is ever wanted it is a follow-up. spc-42 edit is a dated append (never rewrite locked text — same law as ADR amendments).

## Anticipated decisions

- Field placement — pre-resolved: optional rows in the binder field table (commented in the template), keeping first_table_block parsing untouched
- Escape definition — agent-decides: a bug whose defective change merged via a PR a digest classed `auto-pass` (ratify-then-pass escapes counted separately); journal the exact wording

## Decision journal

- Escape definition → "An **escape** = a bug whose defective change merged via a PR a digest classed `auto-pass`; `ratify-then-pass` escapes are counted separately" — wording now in axes.md §Escaped-defect count; `deep-review`/pre-digest history = no escape (source: agent-judgment per Anticipated decisions, aligned with spc-104 Decision 6 + verify-features triage.md §Escape tracing)

## Pending decisions

## Attempts

## Notes

- The digest template was just touched by #102 (NOTICED sweep) — this branch bases on the round-5 integration state, so edit the post-#102 template

## References

- spc-104 A4 / Decision 6 · spc-42 Risks · review-delivery SKILL.md §Trust calibration

## Lineage

- Parent spec: **spc-104** (#104) · Primary ticket: **tkt-107** · Parallel group: **G1 (wave 2)** · Worktree bind: `tkt-107-escaped-defect-metric`

## Finish
