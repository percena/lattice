# Review-delivery axis procedures

Detail for the four axes. The SKILL.md invariants (artifact-only, never merges,
attestation, bounded) apply to every step here.

## Axis 1 — requirement fidelity (semantic A* → evidence)

Unit: the Spec `A*` ids the ticket set `covers` (union of binder `covers` rows;
whole Spec when input was `spc-N`).

1. For each covered `A*`, restate the criterion in one line (from the Spec, not
   the binder mirror — binders may paraphrase).
2. Find **evidence** in the PR diffs/bodies + test output recorded in PR bodies:
   file paths, test names, doc sections. Semantic match, not keyword match —
   “A6 says four axes” is satisfied by the axes existing, not by the word “four”.
3. Classify each `A*`:
   - `satisfied` — evidence path(s) cited
   - `partial` — some clauses lack evidence (name the missing clause)
   - `orphan` — covered but no evidence in any PR of the set
4. Sweep the reverse direction: diff hunks no `A*`/ticket explains =
   **ticket-less code**. List path + a one-line guess at intent. Ticket-less
   code is at least a `med` finding (scope discipline), higher if it touches
   contracts.
5. Checkbox state in binders/issues is a *claim*, not evidence. Divergence
   between checked boxes and missing evidence is itself a finding.

Attestation line for this axis names: which `A*` ids were mapped, how many
satisfied/partial/orphan, and the ticket-less-code result.

## Axis 2 — cross-PR coherence + throwaway integration build

**Static pass (pairwise):**

1. From each PR diff, list exported/changed interfaces: function signatures,
   CLI flags, config keys, file formats, shared reference docs.
2. Cross-check consumers *in the other PRs of the set* (the one-hop rule from
   review-code, applied across PRs): does PR B call what PR A renamed?
3. Flag duplicated solutions (two PRs solving the same sub-problem differently)
   and conflicting edits to the same doc section (merge-order sensitivity).

**Throwaway integration build (DAG order):**

```bash
BASE=$(git rev-parse --abbrev-ref HEAD)   # or the resolved integration branch
TMP="review-delivery/integration-$(date -u +%Y%m%d-%H%M%SZ)"
git fetch origin
git switch -c "$TMP" "$BASE"
# DAG order: topological order of blocked_by from the manifest — merge
# blockers before dependents, ONE AT A TIME (sequential). Do NOT octopus:
# release-train PRs share files (version/changelog cuts) and octopus refuses
# any non-trivial shared-file merge even when the edits are byte-identical.
for h in <pr-head-1> <pr-head-2> ...; do git merge --no-ff --no-edit "$h"; done
# Run what the repo runs (validators + tests actually present):
bash tools/validate-skills.sh                # example: this repo's validators
python3 tools/validate-lattice-artifacts.py
# …plus the project's test entry point when one exists
git switch "$BASE"
git branch -D "$TMP"                         # ALWAYS discard — even on failure
```

- Merge conflict during the sequential merge → finding (name the two
  PRs + path). Do **not** resolve it; discard and report. Exception: a conflict
  on a shared release-train file where one branch is a strict superset (e.g. a
  train version cut plus one branch's manifest additions) may be resolved by
  taking the superset side — note it in the attestation.
- Failures that appear only on the combined branch (each PR green alone) are
  the axis's highest-value findings — record the failing command + excerpt.
- Very slow suites: run a documented subset and say so in the attestation
  (silent subsetting is a red flag).

Attestation line names: pairs checked, merge result, validators/tests run,
combined-branch result, branch discarded.

## Axis 3 — decision-ratification queue (+ preference promotion, A3)

1. Collect from every binder in the set:
   - `## Pending decisions` entries → **ratification queue, blocking tier**
     (these parked a path or shaped the delivery on a default).
   - `## Decision journal` entries → **ratification queue, review tier**
     (self-decided under decision-policy; human confirms or reverses).
2. Rank: pending first (each with its recorded default-if-unanswered), then
   journal entries by blast radius (cross-contract > public surface > local).
   Each row cites binder path + the resolution source the entry claims.
3. Journal entries with **no cited resolution source** violate the journal
   contract (`decision-policy.md`) → per-PR finding, low/med.
4. **Promotion proposals (A3):** an entry is promotion-eligible when the same
   decision (same substance, not same wording) has been **ratified twice** —
   count = ratifications recorded in earlier digests' ratification ledgers plus
   `.lattice/preferences.md` history. Emit a proposal block: proposed
   preference text, suggested severity (INVARIANT/DEFAULT/HINT per
   `constraint-language.md`), the two ratification citations. The digest only
   *proposes* — a human ratifies the promotion; entries are superseded with a
   date, never deleted; Spec/ADR outrank preferences.

Attestation line names: binders scanned, pending/journal counts, promotion
proposals emitted (or none eligible).

## Axis 4 — per-PR findings (review-code contract, contained)

For each PR in the set, apply `review-code`'s material-finding bar to its diff
(the review-code SKILL.md “Material finding bar” + severity/confidence rules —
this file intentionally does not restate them; reuse, don't fork):

- Each finding: **severity (high/med/low) + failure scenario + evidence
  (path:line) + confidence (high/med/low) + recommended solution** (+
  alternatives when they genuinely exist).
- Stance: material correctness/regression in the changed paths; set-scoped
  extras (interface breakage *across* the set) belong to Axis 2 — do not
  double-report.
- No interactive fix loop here: this skill emits the digest and stops.
  review-code's hard-stop/AskUserQuestion machinery is not part of the digest
  pass; rework dispatch belongs to batch-work `--with-review` / the human.

Empty finding list for a PR is fine — the attestation still states what was
examined.

## Triage + merge order

- `auto-pass`: all four axes clean for that PR (Axis 3 clean = no pending
  decisions and no unratified journal entry *specific to that PR* — set-wide
  queue items belong to the queue, not to every PR's triage).
- `ratify-then-pass`: only Axis 3 items stand between the PR and auto-pass.
- `deep-review`: any material Axis 1/2/4 finding, or artifact insufficiency
  touching that PR.
- Merge order: topological (`blocked_by` DAG) first; within a layer, put
  `auto-pass` before `ratify-then-pass` before `deep-review`, and PRs that
  unblock others first. State the order as an explicit list.

## Escaped-defect count (trust calibration — spc-104 A4)

Fills the digest template's "Escaped defects" block. An **escape** = a bug
whose defective change merged via a PR a digest classed `auto-pass`;
`ratify-then-pass` escapes are counted separately. The rows are written at bug
filing by the verify-features tracing recipe
(`../../verify-features/references/triage.md` §Escape tracing) — cite it,
never re-derive or guess lineage here.

1. `grep -rn '| escaped_from |' .lattice/tickets/*/README.md` — every hit is a
   bug-class binder carrying traced lineage (`pr-N — digest rev-… (auto-pass)`).
2. Split hits by class in the row value: `auto-pass` vs `ratify-then-pass`.
3. **Since-last:** hits in bug binders created since the previous digest
   (binder/issue creation date vs the prior digest's `created:`).
   **Cumulative:** all hits.
4. Enter both counts per class in the digest block + one trend line vs the
   prior digest. Zero rows is a valid (good) result — state it, don't skip
   the block.
