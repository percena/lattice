---
# Morning digest — persisted by review-delivery under .lattice/reviews/.
# Id via: next-artifact-id.sh --kind rev --claim  (R1 token; file rev-<token>-<slug>.md)
# kind MUST be digest; outcome inform_only (triage is advice — merge stays human).
id: rev-YYYYMMDD-HHMMSSZ
slug: digest-<spc-N-or-set>
title: Morning digest — <set>
kind: digest
status: concluded
outcome: inform_only
summary: "≤120 chars — N PRs: a auto-pass · b ratify-then-pass · c deep-review"
created: YYYY-MM-DD
updated: YYYY-MM-DD
related_specs: [spc-N]
related_tickets: [tkt-…]
related_prs: [pr-…]
---

# Morning digest — <set>

> **TL;DR:** <one sentence: N PRs triaged, headline finding or “clean night”>
> **Input:** spc-N | ids … | batch report <path> · **Reviewed:** YYYY-MM-DDTHH:MMZ
> **Context:** artifact-only via build-review-context.sh (manifest below) — no transcripts read

## Triage (ranked)

| # | PR | Ticket | Covers | Triage | Why (one line) |
| --- | --- | --- | --- | --- | --- |
| 1 | pr-… url | tkt-… | A… | auto-pass | all axes attested clean |
| 2 | pr-… url | tkt-… | A… | ratify-then-pass | J2 awaits ratification |
| 3 | pr-… url | tkt-… | A… | deep-review | F1 (high) + artifact gap |

**Recommended merge order (DAG-respecting):** pr-… → pr-… → pr-…
<one line: which blocked_by edges force the order>

## Attestations (per axis — no bare LGTM)

### Axis 1 — requirement fidelity
- **Checked:** A-ids mapped (…), evidence paths per id; reverse sweep for ticket-less code
- **Result:** n satisfied / n partial / n orphan · ticket-less code: (none | list)
- **Verdict:** clean | findings F…

### Axis 2 — cross-PR coherence + integration build
- **Checked:** interface pairs (…); octopus/sequential merge of heads (…) on throwaway branch in DAG order; ran: (validators/tests)
- **Result:** merge (clean | conflict pr-X×pr-Y at path); combined run (green | failures + excerpt); branch discarded: yes
- **Verdict:** clean | findings F…

### Axis 3 — decision-ratification queue
- **Checked:** n binders; journal entries n, pending n; promotion eligibility vs preferences.md + prior digests
- **Result:** queue below; proposals: n
- **Verdict:** clean | items queued

### Axis 4 — per-PR findings (review-code contract)
- **Checked:** per-PR diffs (…files), material bar applied
- **Result:** findings table below (or “no material findings; examined: …”)
- **Verdict:** clean | findings F…

## Decision-ratification queue (ranked)

| # | Tier | Ticket | Entry | Source cited | Default / choice taken | Ratify? |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | pending | tkt-… | <question> | — | <default-if-unanswered> | ☐ |
| 2 | journal | tkt-… | <decision → choice> | preference DEFAULT | <choice> | ☐ |

### Preference-promotion proposals (entries ratified ×2)

- **Proposal:** <preference text> · **severity:** DEFAULT · **ratifications:** <digest-id/date>, <digest-id/date> · **action:** human ratifies → append to `.lattice/preferences.md` (supersede-with-date, never delete)
- (none eligible)

## Findings (material — review-code contract)

| Id | Sev | PR | Finding | Failure scenario | Evidence | Confidence | Recommended solution |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F1 | high | pr-… | … | inputs/state → bad outcome | path:line | high | … |

### NOTICED sweep (out-of-paths observations — §Observation duty)

| Binder | NOTICED line | Disposition |
| --- | --- | --- |
| tkt-… | `- NOTICED: <path> — <defect>` | ticket #… \| one-liner: <fix> \| wontfix: <why> |
| (none — sweep ran clean) | | |

### Artifact insufficiency

- <binder/section that could not explain the delivery — evidence: path> (or “none”)

## Escaped defects (trust calibration — spc-104 A4)

<!-- Recipe: axes.md §Escaped-defect count. Escape = bug binder `escaped_from`
     tracing to a digest-classed PR; sampling convention: SKILL.md §Trust calibration. -->

| Window | auto-pass | ratify-then-pass |
| --- | --- | --- |
| since last digest (rev-…) | n | n |
| cumulative | n | n |

**Trend:** <one line vs prior digest — steady/rising/falling; what it implies for `auto-pass` trust>

## References

- Context manifest: <inline or path> · Spec: spc-N · ADRs: …
- Batch report: <path | (none)>

---

**Verdict validity:** a materially changed rebase (conflict or non-trivial diff
change on base update) VOIDS this digest's verdict for that PR; clean rebases
carry it. This digest is advice — it gates nothing; merge authority stays with
finish-work + human (batch marker unchanged).
