---
id: spc-387
slug: weak-spot-topology
title: "review-lineage L4: weak-spot topology + optimization recommendations"
kind: feat
status: locked
mode: C
priority: P2
summary: "A fourth analytical layer for review-lineage: clusters fixed files into path-level hotspots, tracks cross-audit recurrence, and produces root-cause hypotheses + curve-bending recommendations so the team knows which structural change would eliminate the most rework."
created: 2026-09-02
updated: 2026-09-02
tickets: [tkt-388, tkt-389]
prs: []
reviews: [rev-20260902-080545Z]
supersedes: []
superseded_by: null
---

# Spec: review-lineage L4 — weak-spot topology + optimization recommendations

> **TL;DR:** Add an L4 synthesis layer to the `review-lineage` skill (spc-369): a `hotspot-metrics.sh` sensor that clusters files fixed repeatedly into path-level weak spots, a method extension for root-cause + curve-bending analysis, and template sections for the topology table + optimization recommendations — so each audit answers "which path in our workflow keeps breaking and what single structural change would fix the most of it."
> **Kind:** feat · **Status:** locked · **Mode:** C · **Priority:** P2
> **Path:** rev-20260902-080545Z → spc-387 → tkt-… → pr-…

## Why

The first lineage-audit baseline (`rev-20260902-080545Z`) found that the `review-lineage` skill (spc-369, L1–L3 delivered via tkt-370..373) detects recurrence at the individual-finding level — T5 recurrence insight, manual git log sweeps, `fix_recurrence` metric (tkt-385) — but cannot **synthesize** cross-cutting recurrence into structural weak-spot analysis.

**The evidence:** the terminal-stamp path (finish-ledger.sh, stamp-pr-open.sh, validate-lattice-artifacts.py, 2× bats) accounts for **46 of 85 `fix()` commits** in 30 days (**54%**). The same finding class has been flagged in **5+ reviews** with explicit "persisting" language (`rev-20260828-082751Z` → `rev-20260902-015425Z` → `rev-20260902-080545Z`, mention counts growing 2→10→13). ADR-012 §5 (bot-owned single finish script) is the decided structural fix but not yet implemented.

The current skill can detect this as individual findings (F1: "terminal-stamp path still repaired by hand, ten times in seven days") but cannot:

1. **Cluster** the 5 files into one hotspot — it sees 5 independent data points, not one structural weak spot.
2. **Attribute** the cluster to a workflow stage (finish-work terminal-stamp path).
3. **Track** the finding across audits — it says "persisting" manually in prose, not via scripted finding-signature matching.
4. **Diagnose** root cause — it doesn't connect "3 independent writers disagree on state transitions" to "ADR-012 §5 is the decided fix."
5. **Recommend** curve-bending fixes — it produces per-finding ticket drafts ("fix this regex") but not "landing ADR-012 §5 would eliminate ~54% of terminal-stamp recurrence."

The user's insight: *which paths/aspects are repeatedly creating tickets for fixes or enhancements = weak spots in the system/workflow.* This Spec makes that insight a scripted, repeatable part of the audit.

## In scope

- **L4 sensor** — `hotspot-metrics.sh`: computes hotspot clusters, fix-class histogram, ticket genealogy, cross-audit recurrence, and NOTICED feedback data. See A1 for the metric contract.
- **L4 method** — `references/method.md` extension: root-cause hypothesis generation, curve-bending analysis (ranking formula), structural-vs-tactical diagnosis. See A2.
- **Template extension** — `references/templates/lineage-audit.md`: `## Weak-spot topology` + `## Optimization recommendations` sections. See A3.
- **Bats** — planted-drift tests for each metric; dry run on this repo identifies the terminal-stamp cluster as #1 hotspot. See A4.

## Out of scope

- Implementing ADR-012 §5/§6/§7 (the structural fixes the analysis recommends — separate Specs/ADRs).
- A dashboard/UI (JSON + Markdown topology table is the interface).
- Fully automating "stale NOTICED" detection (stays L3 judgment — the sensor provides the data, the agent judges).
- Fully automating "ADR decided but not implemented" status (sensor greps ADR references; implementation-status check stays L3).
- Changing spc-369's A1–A4 (already delivered; this Spec adds a layer on top, not a refinement of L1–L3).
- LLM inside the scripts (sensors are deterministic and CI-runnable, same posture as spc-369 D3).

## Acceptance

- [ ] **A1** — **Hotspot sensor.** `skills/review-lineage/scripts/hotspot-metrics.sh` computes, from `.lattice/` + `git` only, the following metrics and writes them into the snapshot JSON (schema-versioned) + `--md` delta:

  | metric | what it computes |
  | --- | --- |
  | `hotspot_clusters` | Files fixed in ≥N commits (default ≥2) in the window, grouped into clusters by path-derived attribution. Each cluster reports: `files[]`, `fix_commit_count` (unique commits touching any file, deduped by hash), `total_modifications` (file×commit pairs), `fix_share_pct` (cluster fix commits / total fix commits), `stage` (workflow stage), `skill` (owning skill or "shared"/"cross-cutting"). |
  | `fix_class_histogram` | Fix commits classified by subject-regex: `status-flip` (`flip\|status.*closed\|backfill`), `regex-drift` (`regex\|parse\|field`), `bash-guard` (`bash.*3\.2\|unbound\|empty.*array\|set -u`), `field-mismatch` (`field\|gh.*json\|conclusion`), `atomicity` (`atomic\|race\|lock\|transaction`), `other` (catch-all). Reports `{class: count}`. |
  | `ticket_genealogy` | For each review with a Proposed-tickets table: `{rev_id, tickets_spawned, tickets_with_fix_cycles_gt0, total_fix_cycles}`. For each Spec: `{spec_id, ticket_count, tickets_with_fix_cycles_gt0, total_fix_cycles}`. |
  | `cross_audit_recurrence` | For each finding-class (terminal-stamp, regex-drift, silent-bypass, invisible-queue, done-without-evidence): `{class, revs[]}` (list of rev-ids where a finding of that class appears in a `### F` heading), `trend` (▲/▼/— based on mention-or-severity growth across revs). Tracked by finding-class signature (extracted from F-heading keywords), not grep mention counts. |
  | `noticed_feedback` | `{total_noticed, became_ticket, wontfix, stale_unresolved}`. `became_ticket`: NOTICED lines in a binder that has a corresponding ticket in a rev's Proposed-tickets table. `stale_unresolved`: NOTICED lines older than 7 days with no disposition marker in any rev. (Stale detection is advisory — the agent confirms in L3.) |

  **File→skill auto-derivation** (no manual config table): `skills/<skill>/` → that skill; `skills/_lattice-lib/` → `shared` (referenced by ≥2 SKILL.md files); `tools/` → `cross-cutting`. **Skill→stage** from `validate-skills.sh` arrays (`USER_FACING` → delivery path; `QUALITY_SIDE_PATHS` → review path; `_lattice-lib` → shared). **Reuse** (D5): composes `lineage_metrics.git_metrics()` (no second git log runner), `queue_health._parse_field_rows()` (no second binder parser), `validate-skills.sh` arrays (no second skill registry). `--since`, `--home`, `--base`, `--snapshot-dir`, `--json`/`--md`, `--no-snapshot` flags parallel `lineage-metrics.sh`. Exit 0 always. Bats on a fixture asserts every metric; on this repo it runs < 5 s and identifies the terminal-stamp cluster with 54% fix share.

- [ ] **A2** — **Method extension.** `skills/review-lineage/references/method.md` gains an `## L4 synthesis` section covering:

  - **Root-cause hypothesis**: for each hotspot cluster, generate a hypothesis from the cluster's properties — multi-writer disagreement (≥3 files in the cluster are independent writers of the same state); decided-but-unimplemented ADR (fix subjects reference `ADR-NNN §N` that is `Accepted` but has no implementing ticket/PR); format-drift escape (cluster includes a parser + its input format); environment-dependence (fix subjects reference `bash 3.2` / `gh` version / `root`).
  - **Curve-bending analysis**: rank hotspots by `impact = fix_commit_count × fix_class_diversity × cross_audit_recurrence_count × structural_depth` where `fix_class_diversity` = distinct fix classes in the cluster, `structural_depth` = 2 if the cluster references a decided-but-unimplemented ADR, 1 otherwise. For each hotspot, state the hypothesized curve-bending effect ("landing ADR-012 §5 → cluster fix_commit_count should fall from 46 to < 15") and the verification metric (what number the next snapshot's Δ should show). This is a **ranking formula computed by the agent in L3/L4**, not a sensor metric — the sensor provides the inputs, the method section defines how to combine them.
  - **Structural-vs-tactical diagnosis**: `structural` = the hotspot references a decided-but-unimplemented ADR/Spec direction (the fix is to land the ADR, not to patch); `tactical` = patchable (file a ticket). Structural hotspots produce an optimization recommendation, not a ticket draft.

- [ ] **A3** — **Template extension.** `skills/review-lineage/references/templates/lineage-audit.md` gains two sections after `## Findings`:

  ```markdown
  ## Weak-spot topology

  | hotspot | files | fix_count | ticket_count | stage | fix_classes | cross_audit | root_cause | structural? |
  | --- | --- | --- | --- | --- | --- | --- | --- | --- |
  | … | … | … | … | … | … | … | … | yes (ADR-NNN §N) / no |

  ## Optimization recommendations

  | rank | hotspot | action | impact | curve_bending_% | verification_metric |
  | --- | --- | --- | --- | --- | --- |
  | 1 | … | land ADR-NNN §N | … | … | next Δ: fix_commit_count …→<… |
  ```

  The topology table is populated from `hotspot-metrics.sh --md` output. The recommendations are authored in L4 (agent judgment, not scripted). Bounded: ≤5 hotspots + ≤3 recommendations (same bounded posture as Findings ≤7).

- [ ] **A4** — **Bats + dry run.** `skills/review-lineage/scripts/tests/hotspot-metrics.bats` with planted-drift tests: (1) a fixture repo with 3 `fix(` commits touching 2 files in the same skill dir asserts a hotspot cluster with `fix_commit_count=3`; (2) a fixture with a `flip` subject asserts `fix_class_histogram.status-flip=1`; (3) a fixture with a NOTICED line + a rev Proposed-tickets entry asserts `noticed_feedback.became_ticket=1`. A dry run on this repo: `hotspot-metrics.sh --md` identifies the terminal-stamp cluster as #1 with 54% fix share, `cross_audit_recurrence.terminal-stamp.revs` contains ≥3 rev-ids, and `fix_class_histogram.status-flip` > 0. `ci-local.sh --fast` green.

## Non-goals

- No automatic implementation of ADR-012 §5/§6/§7 (the analysis recommends; separate Specs deliver).
- No LLM inside the scripts (deterministic, CI-runnable).
- No rewrite of L1–L3 (spc-369 A1–A4 are delivered; this adds L4 on top).
- No dashboard/UI (JSON + Markdown is the interface).
- No global BOARD index (bloodline is L0 + GitHub).

## Decisions (principal, user-confirmed)

1. **D1 — Separate Spec, not spc-369 A5.** L4 is a different capability (synthesis + root-cause + curve-bending) from L1–L3 (measurement + claims + history). spc-369 can `done` independently after its soak cycle; this Spec builds on the delivered L1–L3 without extending spc-369's Acceptance.
2. **D2 — Sensor name: `hotspot-metrics.sh`.** Parallel to `lineage-metrics.sh` (L1) and `claim-probes.sh` (L2); the three sensors compose, each writing into the same snapshot JSON or a sibling.
3. **D3 — file→skill mapping auto-derived, no manual config table.** `skills/<skill>/` → that skill; `skills/_lattice-lib/` → `shared`; `tools/` → `cross-cutting`. Skill→stage from `validate-skills.sh` arrays. This is verifiable by the existing `skill-scripts-exist` probe and does not require maintenance.
4. **D4 — curve_bending_impact is a method formula (L4), not a sensor metric (L1).** The sensor provides `fix_commit_count`, `fix_class_diversity`, `cross_audit_recurrence_count`, `structural_depth`; the agent computes the ranking and authors the recommendation in L4. Over-automating the ranking would invite formula gaming (ADR-007 §3).
5. **D5 — Reuse over rebuild (spc-369 D5 posture).** `hotspot-metrics.sh` composes `lineage_metrics.git_metrics()` (no second git log runner), `queue_health._parse_field_rows()` (no second binder parser), `validate-skills.sh` arrays (no second skill registry). The hotspot sensor reads the same `.lattice/` + `git` data sources as L1.

## Agent-assumed (secondary)

- Snapshot location: the hotspot metrics write into the same snapshot JSON as `lineage-metrics.sh` (schema 2 — a new `hotspot` top-level key, schema-versioned). Alternatively, a sibling snapshot `hotspot-<UTC>.json` if the two sensors run independently. Default: same snapshot, appended after L1 metrics.
- Fix-class classification regexes are seeded from the baseline audit's evidence (status-flip, backfill, regex, bash-guard, field-mismatch, atomicity) and are extensible per repo via the same overlay mechanism as `claim-probes.sh`.
- Finding-class signatures are extracted from `### F<N> — <text>` headings by keyword matching (terminal-stamp, regex-drift, silent-bypass, invisible-queue, done-without-evidence, environment-dependence), mapping to the insight taxonomy T1–T9.
- `structural_depth` is 2 when fix subjects in the cluster reference an ADR section that is `Accepted` with no implementing ticket; 1 otherwise. Implementation-status check is advisory (the agent confirms in L3).

## Risks / open questions

- **Snapshot schema bump:** adding `hotspot` to the existing snapshot changes schema 1 → 2. `lineage_metrics.load_previous()` must handle both schemas (graceful degrade for `hotspot` key absent in old snapshots — the Δ is `—` for hotspot metrics on the first run with an old baseline).
- **Cluster boundary ambiguity:** `_lattice-lib/scripts/` files are shared by multiple skills (finish-ledger.sh referenced by 3 SKILL.md files). The `shared` attribution is correct but may hide which skill's workflow is the primary consumer. Mitigation: the topology table shows `skill: shared (finish-work, create-pr, finish-work)` so the agent can see the consumers.
- **Fix-class regex false positives:** `fix(` subjects are free-form; the regexes may misclassify. Mitigation: every class has a planted-drift test; `other` is the catch-all; the agent can override in L4.
- **Cross-audit finding-signature matching:** keyword extraction from F-headings may miss synonyms or paraphrased findings. Mitigation: the signature set is seeded from the insight taxonomy (T1–T9) and is extensible; the agent can add a manual override in L4.

## References

- Review: `rev-20260902-080545Z` (lineage-audit baseline — the dry run that demonstrated the gap)
- Prior Spec: `spc-369` (review-lineage — L1–L3 delivered; this Spec adds L4)
- ADR: `ADR-012` §4 (conformance sensor), §5 (bot bookkeeping — the #1 structural fix the analysis would recommend), §7 (binder front matter — the #2 structural fix)
- ADR: `ADR-007` §3 (decidability — curve_bending stays method, not sensor)
- Skill anatomy: `skills/review-lineage/SKILL.md`, `references/method.md`, `references/insight-taxonomy.md`, `references/templates/lineage-audit.md`
- Sensor reuse: `skills/review-lineage/scripts/lib/lineage_metrics.py` (`git_metrics`), `skills/_lattice-lib/scripts/lib/queue_health.py` (`_parse_field_rows`), `tools/validate-skills.sh` (USER_FACING / QUALITY_SIDE_PATHS arrays)
- GitHub primary: https://github.com/percena/lattice/issues/387

## Links / bloodline (L0)

- Tickets: (none yet — `create-tickets` after this Spec is locked)
- PRs: (none yet)
- Reviews: `rev-20260902-080545Z` (lineage-audit baseline, produced by the skill's own dry run — the origin of this Spec)
