---
# Lineage audit — persisted by review-lineage under <home>/reviews/.
# Id via: next-artifact-id.sh --kind rev --claim  (R1 token; file rev-<token>-lineage-audit-<slug>.md)
# kind MUST be audit; status concluded; exactly one outcome: spawn_tickets | needs_decision | inform_only.
id: rev-YYYYMMDD-HHMMSSZ
slug: lineage-audit-<slug>
title: "Lineage audit — <window / trigger>"
kind: audit
status: concluded
outcome: spawn_tickets
summary: "≤120 chars — headline number + headline cluster + outcome"
created: YYYY-MM-DD
updated: YYYY-MM-DD
related_specs: [spc-…]
related_tickets: [tkt-…]
related_prs: []
---

# Review: Lineage audit — <window / trigger>

> **TL;DR:** <one sentence a cold reader can act on: the delta headline, the top cluster, what the operator decides next>
> **Kind:** audit · **Status:** concluded · **Outcome:** spawn_tickets | needs_decision | inform_only
> **Window:** `--since <…>` on `<base>` · **Snapshot:** `<home>/reviews/metrics/lineage-<UTC>.json` (prev: `lineage-<UTC>.json` | first) · **Probes:** n pass / n fail / n skip

## Context

Why this run (cadence / post-soak / operator ask), the home + window mined, and what changed since the previous lineage audit (or "first baseline").

## Problem Audit

| Layer | Notes |
| --- | --- |
| Validity | Are the sensor numbers about real drift, or about the sensors (parser, window)? |
| Information | `.lattice` + git sufficient? What was not available (no `--gh`, no CI history)? |
| Hidden issues | The root cause the symptoms share |
| Existing solution | Which ADR/Spec already decided the direction; what is merely unimplemented |

## Metrics delta (L1 — pasted from `lineage-metrics.sh --md`)

<!-- Paste the Headline table verbatim, then only the sub-tables a Finding cites (edges, NOTICED, Specs). Keep the "Snapshot written:" line. -->

## Probe results (L2 — pasted from `claim-probes.sh --md`)

<!-- Paste the table + summary line verbatim. Every `fail` row must appear below as a Finding, an Appendix item, or a dropped claim in Method. -->

## Comparison matrix

<!-- Required for kind audit (create-review rule 1b). Compare how to act on the top cluster: proposed / status quo / alternative. -->

| Option | Cost | Code-delta | Risk | Constraints | Capability |
| --- | --- | --- | --- | --- | --- |
| Proposed: <repair + guard> | | | | | |
| Keep status quo | | | | | |
| Alternative: <…> | | | | | |

## Findings (ranked; ≤ 7)

### F1 — <title> (<high|med|low> · cluster C1 · T<n> <class>)

- **Failure scenario:** <inputs/state → wrong outcome, who is misled>
- **Evidence (re-verified):** `path:line` — <what it says>; `<command>` → <output/count>
- **Since last run:** new | persisting (seen in rev-…) | regressed
- **Mechanism (repair + guard):** <what to change> + <validator code / probe row / test that keeps it fixed>

### F2 — …

## Insights (pattern level — cite `insight-taxonomy.md` ids)

- **T<n> <class>:** <base rate from this snapshot> — <direction to watch next run>
- …

## Proposed tickets (create-tickets §2 batch shape, extended with kind · priority · why)

<!-- Columns 1–7 are exactly `create-tickets/references/flow.md` §2 "Proposed tickets"; kind/priority/why are appended so the operator can file without re-deriving. `covers` = the Finding id(s) this row repairs. Every row pairs repair with its guard (audit-recipe §6). -->

| # | title | covers | paths (approx) | blocked_by | parallel_group | solo-merge | kind | priority | why |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | … | F1 | … | none | G1 | yes | fix | P1 | <one line: symptom → guard> |

**Ship plan:** one-PR | multi-PR — <why>. **Needs-decision rows** (undecidable clusters — not tickets): <F-id: options + default> | (none).

## Outcome

`spawn_tickets` | `needs_decision` | `inform_only` — <one line why>. The operator confirms the table above → `create-tickets`; this review filed nothing.

### Follow-ups

- [ ] Operator: go / edit rows on the Proposed-tickets table
- [ ] Next lineage audit after <cadence>; compare against `lineage-<UTC>.json`

## Method

- **Sensors:** `lineage-metrics.sh --since <…> --md` @ <UTC> (snapshot `<path>`), `claim-probes.sh --md` @ <UTC> (registry `<path>`, overlay <path|none>), `validate-lattice-artifacts.py` (<n> warnings / <n> errors), `reconcile-state.sh` (<binders|not run>)
- **Sweeps (L3):** <commands run — commit mix, recurrence, NOTICED age, prior-rev reopened classes>; fan-out: <none | briefs>
- **Claim reconciliation:** <probe ids re-run by hand>; sampled: <ADR Verification bullets executed>, <done-Spec A* checked against tests/PRs>
- **Verify-then-report:** candidates <n> · verified <n> · **dropped <n>** — <one line per dropped claim: source → why it did not reproduce>
- **Bounds:** one pass, timebox <n> min, Findings <n>/7, Appendix <n>
- **Not done / unaudited surfaces:** <skip rows, no --gh, …>

## Appendix (overflow candidates, verified but below the fold)

- <A1 …>

## References

- Sensors: `skills/review-lineage/scripts/lineage-metrics.sh`, `scripts/claim-probes.sh`, `references/probes.md`
- Prior lineage audits / method origin: `rev-…`, `rev-20260902-015425Z`
- Laws cited: ADR-004 §1, ADR-007 §3/§8, ADR-012 §1/§4/§5
