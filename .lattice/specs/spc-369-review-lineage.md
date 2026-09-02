---
id: spc-369
slug: review-lineage
title: review-lineage — periodic lineage mining for insights (running data + claims + history)
kind: feat
status: locked
mode: C
priority: P1
summary: "A quality side-path skill that mines what the repo actually delivered — binders, ledgers, git history, Specs/ADRs/reviews — for overlooked defects and claim/implementation drift, with metric snapshots so trends are visible."
created: 2026-09-02
updated: 2026-09-02
tickets: [tkt-370, tkt-371, tkt-372, tkt-373]
prs: []
reviews: [rev-20260902-015425Z]
supersedes: []
superseded_by: null
---

# Spec: review-lineage

> **TL;DR:** Turn the method that found spc-337's defects — start from the running data, verify every claim against the tree, cluster by root cause, rank by impact — into a repeatable skill with scripted sensors and a metric baseline, so each audit starts from a delta instead of from zero and ends in a `rev-` with ticket drafts the operator can hand to `create-tickets`.
> **Kind:** feat · **Status:** locked · **Mode:** C · **Priority:** P1
> **Path:** rev-20260902-015425Z → spc-369 → tkt-370..373 → pr-…

## Why

Five FSM reviews in the week before 2026-09-02 compared the docs with the docs. The one that compared the docs with the *running data* (`rev-20260902-015425Z`) found what the others could not: 5 of 21 modelled edges ever walked, one `queued → in-progress` in 31 ledgers, 119/150 terminal binders without a ledger, hand-edited terminal states, a ledger path resolved from cwd, 97 bookkeeping commits pushed straight to the integration branch. The follow-up PR reviews then found four more drifts of the same kind — each one a documented promise the tree no longer met.

None of that needed new information; it needed someone to *compute* what the artifacts already said and to *execute* what the docs promised. That work is mechanical enough to script (metrics, probes) and judgement-heavy enough to keep an LLM in the loop (clustering, ranking, insight). Today it exists only as one review's method section. This Spec makes it a skill: `review-lineage`, in the `review-*` quality side-path family, run periodically over the whole repo, never merging, never filing issues, feeding M3 (insights → preferences / ADR / tickets).

## In scope

- **L1 running data** — `lineage-metrics.sh`: metric snapshot (JSON, schema-versioned, committed under `.lattice/reviews/metrics/`) + Markdown delta vs the previous snapshot.
- **L2 claims** — `claim-probes.sh`: a registry of executable probes (documented promise → command → expectation), seeded from the drift classes spc-337 found, extensible per repo.
- **L3 history + judgement** — `SKILL.md` + references: the three-layer method, verify-then-report, root-cause clustering, insight taxonomy, ranking rubric, `rev-` template with a Metrics-delta section and a Proposed-tickets table in `create-tickets`' batch shape.
- Registration surfaces, routing eval, cadence recipe (morning-triage / getting-started), M3 edge in `docs/workflow-fsm.md`.

## Out of scope

- Filing GitHub issues or editing binders/product code from the skill (attention contract; `create-tickets` stays the writer).
- Replacing `review-delivery` (one delivered set), `create-review` (decision support), `verify-features` (runtime bugs) — `review-lineage` cites and composes them.
- GitHub-live reconciliation by default (`reconcile-state.sh --gh` is an optional sensor).
- A metrics dashboard/UI; the snapshot JSON is the interface.

## Acceptance

- [ ] **A1** — **Metrics + snapshot + delta.** `skills/review-lineage/scripts/lineage-metrics.sh` computes, from `.lattice/` + `git` only: status histogram; ledger coverage + missing list; edge histogram vs `transition_table.LEGAL_EDGES` (walked / never-walked); direct jumps; `fix_cycles` distribution; side-state/`wait_reason` occurrences; Attempts / Pending / Decision-journal usage; `- NOTICED:` backlog; escape traces by `rule_id`; base-branch commits without a PR suffix vs PR merges over `--since`; Specs `done` with open A*; Specs whose `prs` ≠ child PR union. Writes `.lattice/reviews/metrics/lineage-<UTC>.json` (`schema: 1`) unless `--no-snapshot`; `--md` prints a delta table vs the newest previous snapshot. Bats on a fixture assert every metric; on this repo it runs < 10 s and matches the spc-337 hand counts for ledger coverage and direct jumps.
- [ ] **A2** — **Claim probes.** `skills/review-lineage/scripts/claim-probes.sh` runs a registry (`references/probes.md` table; optional `.lattice/lineage-probes.tsv` overlay merged by id) of `id | claim (where) | probe | expect | severity`; built-ins cover: SKILL-named scripts exist and are executable; `hooks.json` hook files exist; validator codes cited in docs exist; retired-path deny-list absent from docs; ADR `Verification:` script/test references resolve; `done` Specs cite a test per A* (else flagged); FSM doc M2 edges ⊆ schema. Output `--md` / `--json`, always exit 0. Each built-in probe has a planted-drift bats case and a clean-fixture pass.
- [ ] **A3** — **Skill.** `skills/review-lineage/SKILL.md` (≤ 300 lines, anatomy footers, `agents: claude-code,codex`) + `references/method.md`, `references/insight-taxonomy.md`, `references/templates/lineage-audit.md`. Invariants: artifact-only; verify-then-report (dropped-claim count in Method); never files issues, merges, or edits product code/binders; bounded (one pass, ≤ 7 findings + appendix). Process: sensors → history archaeology → claim reconciliation → clustering + ranking (impact × decidability) → `rev-` (kind `audit`, via `create-review` id/home conventions) → hand-off. A dry run on this repo yields a `rev-` that follows the template and whose Proposed-tickets table parses into `create-tickets`' section-2 batch without edits. `tools/validate-skills.sh` OK.
- [ ] **A4** — **Registration + cadence.** `review-lineage` present on every registration surface (`README.md`, `README.zh-CN.md`, `llms.txt`, `plugins/lattice/README.md`, `plugin.json` + `marketplace.json` keywords, `plugins/lattice/skills/` symlink, `docs/getting-started.md`); `evals/routing/review-lineage.json` (≥ 3 positive EN+ZH, negatives routing to review-delivery / create-review / verify-features) keeps `run-routing-evals.py --min-rank1 80` green; `docs/morning-triage.md` gains a weekly lineage-review step; `docs/workflow-fsm.md` M3 table gains the `review-lineage insight → preference / ADR / ticket proposal` edge. `ci-local.sh --fast` green.

## Non-goals

- No automatic ticket creation, no auto-fix, no merge authority — the skill's output is advice and drafts.
- No LLM inside the scripts; sensors are deterministic and CI-runnable.
- No rewrite of historical artifacts; snapshots are append-only files.

## Decisions (principal, user-confirmed)

1. **D1 — Name and family: `review-lineage`, quality side-path (`review-*`).** Periodic, whole-repo; distinct from `review-delivery` (one delivered set) and `create-review` (human decision support).
2. **D2 — Autonomy boundary: rev + ticket drafts only.** The skill never runs `gh issue create`; its outcome is `needs_decision` or `spawn_tickets` with a draft table the operator confirms (ADR-004 attention contract; preferences.md "review-findings → tickets").
3. **D3 — Three data layers with a committed metric baseline.** L1 running data (scripted), L2 claims (scripted probes), L3 history + judgement (LLM); every run emits a snapshot and a delta so findings are trends, not one-offs.
4. **D4 — Delivery: Spec + four tickets, all delivered now** (T1 ∥ T2 → T3 → T4).
5. **D5 — Reuse over rebuild.** Sensors compose `queue_health.py`, `transition_table.py`, `validate-lattice-artifacts.py`, `reconcile-state.sh` and the parity logic; no second status parser, no second edge table.

## Agent-assumed (secondary)

- Snapshot location `.lattice/reviews/metrics/` (project knowledge, committed — ADR-011 §1); file name `lineage-<YYYYMMDD-HHMMSSZ>.json`.
- Probe registry lives in `references/probes.md` as a Markdown table (grep-able, reviewable), not YAML.
- Ranking rubric: impact (blast radius × frequency) × decidability (can a script enforce it — ADR-007 §3); undecidable-but-important items become `needs_decision` rows.

## Risks / open questions

- Metric drift when binder formats migrate (ADR-012 §7 front matter): `lineage_metrics.py` must read through `binder_rows.py` only.
- Probe false positives teach agents to ignore the report (ADR-007 §9): every built-in probe ships with a planted-drift test and a clean pass; noisy probes are demoted to `skip` with a reason, never deleted silently.
- Routing overlap with `review-delivery`/`create-review`: the eval's negatives guard it; the SKILL "When NOT" table is explicit.

## Delivery plan

| Wave | Ticket | Covers | Blocked by | Parallel group | Path boundary |
| --- | --- | --- | --- | --- | --- |
| W0 | tkt-370 | A1 | none | G0 | `skills/review-lineage/scripts/lineage-metrics.sh`, `scripts/lib/lineage_metrics.py`, `scripts/tests/lineage-metrics.bats`, `scripts/tests/fixtures/metrics/**` |
| W0 | tkt-371 | A2 | none | G0 | `skills/review-lineage/scripts/claim-probes.sh`, `references/probes.md`, `scripts/tests/claim-probes.bats`, `scripts/tests/fixtures/probes/**` |
| W1 | tkt-372 | A3 | tkt-370, tkt-371 | (serial) | `skills/review-lineage/SKILL.md`, `references/method.md`, `references/insight-taxonomy.md`, `references/templates/lineage-audit.md` |
| W2 | tkt-373 | A4 | tkt-372 | (serial) | root READMEs, `llms.txt`, plugin/marketplace json, `plugins/lattice/README.md` + skills symlink, `docs/getting-started.md`, `docs/morning-triage.md`, `docs/workflow-fsm.md`, `evals/routing/review-lineage.json` |

Independence gate (G0): tkt-370 and tkt-371 share only the fixtures root, split into disjoint subdirectories.

## References

- Review: `rev-20260902-015425Z` (method section + re-verification pass)
- ADR: `ADR-012` §4 (ledger coverage as conformance sensor), `ADR-007` §3/§8 (decidability, escape metrics), `ADR-004` §1 (attention contract)
- Skills composed: `create-review` (audit-recipe, ids/home), `review-delivery` (digest conventions), `_lattice-lib` sensors
- GitHub primary: https://github.com/percena/lattice/issues/369

## Links / bloodline (L0)

- Tickets: `tkt-370`, `tkt-371`, `tkt-372`, `tkt-373` (GitHub children #370–#373, native sub-issues of #369)
- PRs: (none yet)
- Reviews: `rev-20260902-015425Z`
