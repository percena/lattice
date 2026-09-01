# Repo/system audit recipe (`kind: audit`) — portable

How to run a **findings-class repo/system audit** as a Lattice Review: sweep wide, then let **nothing** into Findings that the accountable auditor has not re-verified against the tree. Worked example throughout: `rev-20260827-033352Z` (post-round-4 verified audit → tkt-90…96 → PRs #97–#103).

**Composition (DEFAULT):** this recipe **composes with** the existing Problem Audit DEFAULT (validity / info sufficiency / hidden issues / **existing-solution-meets-goal** — `policy.md`); it never replaces it. Run the Problem Audit gate first, then the six elements below. Because `audit` is a decision-support kind that compares options, the review must also include the **multi-dimensional comparison matrix** (`policy.md`: rows = proposed option / status quo / alternatives; columns = cost, code-delta, risk, constraints, capability/feature tradeoffs) — the audit's recommendations are not credible without it.

**Delegation law is not restated here:** fan-out follows `../../_lattice-lib/references/orchestration-patterns.md` — one accountable owner, disjoint briefs, merged result validated by the host.

## The six elements

| # | Element | Severity |
| --- | --- | --- |
| 1 | Orthogonal fan-out | DEFAULT |
| 2 | Verify-then-report | **INVARIANT** (the core law) |
| 3 | Enforcement-coverage axis | DEFAULT |
| 4 | Claim–implementation reconciliation | DEFAULT |
| 5 | History archaeology | DEFAULT |
| 6 | Root-cause clustering + mechanism pairing | DEFAULT |

### 1. Orthogonal fan-out (DEFAULT)

Decompose the audit into **disjoint read-only sweeps** over orthogonal concerns and run them in parallel — e.g. process artifacts / packaging / code+tests / docs. Overlap between sweeps is tolerated (two sweeps finding the same defect is cheap); **gaps are not** (a concern no sweep owns is an unaudited surface). Delegation follows `orchestration-patterns.md` (fan-out + merge, one accountable owner).

> *Worked:* rev-20260827-033352Z Method — "Four parallel audit sweeps (process artifacts, packaging, tools/tests, docs)" covering the whole tree with no unowned concern.

### 2. Verify-then-report (INVARIANT — the core law)

A sweep's claim enters **Findings** only after the **accountable auditor re-verifies it against the tree**: exact `file:line`, command output, count re-checked. Claims that do not reproduce are **DROPPED**, and the dropped count is recorded in the Review's **Method** section. Delegated evidence is input, never conclusion (`orchestration-patterns.md`: never accept delegated output without fresh verification).

> *Worked:* rev-20260827-033352Z — "every finding hand-verified against the working tree at `f9568a3` — line numbers cited are real … Claims that did not reproduce were dropped" (e.g. F1's 19 stranded binders is a re-counted number, not a sweep's estimate).

### 3. Enforcement-coverage axis (DEFAULT)

For every law/claim the tree currently **meets**, ask: "**which validator / test / CI gate enforces this?**" An unenforced law is **itself a finding**, even when nothing violates it today. Motto: **"surfaces with a validator stay fresh; surfaces without one rot."**

> *Worked:* rev-20260827-033352Z F3 — the L0 artifact validator ran in no CI workflow and push CI ignored `dev`, so "ci-local green (19/19)" was true while every finding in the audit was invisible to the gates.

### 4. Claim–implementation reconciliation (DEFAULT)

Any doc sentence promising **tool behavior** is **EXECUTED against the tool** (or its code read at the exact promise), not merely checked for stale names/paths — the "validator rejects illegal transitions" class. **Doc–code disagreement is a finding regardless of which side is right** (the fix may land on either side).

> *Worked:* rev-20260827-033352Z F2 — three docs said the validator "rejects … illegal transitions"; running/reading `validate-lattice-artifacts.py` showed no transition checking of any kind.

### 5. History archaeology (DEFAULT)

The tree is not the only evidence. Mine **CI run history** (red runs never dispositioned), **digest/binder deferrals**, and **"noticed twice" items** (defects observed in earlier reviews/digests that recur). Every archaeology finding is marked **already-addressed-by-later-work** or **still-open** — checked against later commits/tickets, not assumed.

> *Worked:* rev-20260827-033352Z F3/F8 — 38 red runs in the last 200 with recurring causes never triaged, and rev-20260826-141124Z:116 debts "noticed, never filed"; each item carries an addressed-or-not verdict (e.g. tkt-65:34 "delivered by tkt-74, box still unchecked").

### 6. Root-cause clustering + mechanism pairing (DEFAULT)

Findings **cluster by root cause**, not by file (e.g. one checklist gap explaining all registration-surface drift). Every spawned ticket **pairs the repair with the mechanism preventing recurrence** — a fix without its guard re-runs the audit next quarter.

> *Worked:* rev-20260827-033352Z Process observation — F1/F2/F6 collapse into "enforcement asymmetry", and each spawned ticket ships repair **plus** mechanism (tkt-92: red-disposition duty + dev-branch CI, not just fixing the reds).

## Outcome discipline

Audit revs are findings-class: they usually conclude **`spawn_tickets`** with a **wave plan** (ordering + parallel groups for the spawned tickets, per element 6's mechanism pairing). `inform_only` is legitimate only when every finding is already addressed or explicitly accepted.

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| "The sweep agent cited a line number, that's evidence" | Verify-then-report is the core law: the accountable auditor re-verifies against the tree; non-reproducing claims are dropped **and counted** in Method |
| "Nothing violates this rule, so no finding" | Enforcement-coverage: an unenforced law is itself a finding — surfaces without a validator rot |
| "The doc just needs a wording refresh" | If the sentence promises tool behavior, execute it against the tool; disagreement is a finding whichever side is right |
| "CI is green now, old reds are history" | Red runs never dispositioned are exactly the archaeology signal; mine them and mark addressed-or-not |
| "File the fix ticket, prevention can come later" | Mechanism pairing: every spawned ticket pairs repair with the guard preventing recurrence |
| "Skip the Problem Audit — this is an audit already" | The recipe composes with the Problem Audit DEFAULT (validity/sufficiency/existing-solution first) + the comparison matrix; it does not replace them |
| "One big sweep is simpler than fan-out" | Disjoint parallel sweeps make gaps visible; a monolithic sweep hides what it never looked at |

## Verification

- [ ] Sweeps were disjoint and read-only; every audited concern had an owning sweep (gaps none, overlap OK)
- [ ] Every Finding carries re-verified `file:line` / command evidence; Method records the dropped-claim count
- [ ] Enforcement-coverage asked per law met; unenforced laws surfaced as findings
- [ ] Doc sentences promising tool behavior were executed/read against the implementation
- [ ] CI red history + deferral/"noticed twice" mining done; each item marked addressed-or-not against later work
- [ ] Findings clustered by root cause; each spawned ticket pairs repair with prevention mechanism
- [ ] Problem Audit gate ran (or explicit one-line skip) including the existing-solution-meets-goal row; comparison matrix present (audit is decision-support); outcome set (usually `spawn_tickets` + wave plan)
