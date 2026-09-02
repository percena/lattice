# review-lineage — the three-layer method

The audit that found spc-337's defects (`rev-20260902-015425Z`) did three things the five reviews before it did not: it **computed** what the artifacts already said (L1), it **executed** what the docs promised (L2), and only then did it read history and judge (L3). This file is the exact procedure, with the commands. `SKILL.md` is the contract; this is the recipe.

Composition: the six elements of `../../create-review/references/audit-recipe.md` apply unchanged (fan-out, verify-then-report, enforcement-coverage, claim reconciliation, history archaeology, root-cause clustering). Below, each layer names the element it serves.

## L1 — running data (scripted; audit-recipe §3 enforcement-coverage input)

```bash
bash "$SKILL_ROOT/scripts/lineage-metrics.sh" --home "$PH" --since 30d --md > "$OUT/metrics.md"
bash "$SKILL_ROOT/scripts/lineage-metrics.sh" --home "$PH" --since 30d --json --no-snapshot > "$OUT/metrics.json"   # full lists (missing-ledger, never-walked, NOTICED)
```

`--md` writes `$PH/reviews/metrics/lineage-<UTC>.json` (`schema: 1`) and prints the delta against the newest previous snapshot; `--json --no-snapshot` gives you the untruncated lists without a second snapshot. Fields (`lineage_metrics.py`): `status_histogram`, `ledger_coverage{terminal,with_ledger,missing[],direct_jumps,pct}`, `edges{modelled,walked,never_walked[],unmodelled[]}`, `fix_cycles_histogram`, `side_states`, `wait_reasons`, `sections{attempts,pending_decisions,decision_journal}`, `noticed{count,lines[]}`, `escape_traces`, `git{commits_total,pr_merges,direct_commits,finish_stamps,direct_ratio}`, `specs{done_with_open_acceptance,prs_mismatch}`.

What L1 answers: *which modelled states/edges are exercised, how much of the terminal set has a ledger, how often the paved road was bypassed (direct jumps, direct commits), how much observation debt is queued, which Specs are done on paper only.* It never says why — that is L3.

Reuse rule (spc-369 D5): binder rows are read through `queue_health._parse_field_rows`, edges through `transition_table.LEGAL_EDGES`. If a number looks wrong, the finding is about the shared parser (and every consumer of it), not about this script.

## L2 — claims (scripted; audit-recipe §4 claim–implementation reconciliation)

```bash
bash "$SKILL_ROOT/scripts/claim-probes.sh" --home "$PH" --md   > "$OUT/probes.md"
bash "$SKILL_ROOT/scripts/claim-probes.sh" --home "$PH" --json > "$OUT/probes.json"     # keys: probes[], summary, degraded[]
bash "$SKILL_ROOT/scripts/claim-probes.sh" --only <id> --md                             # re-run one probe while reconciling
```

Registry: `references/probes.md` (`id | claim (where) | probe | expect | severity`); per-repo overlay `<home>/lineage-probes.tsv` merged by id. A `fail` row is a **candidate**. **Step 2 rule (INVARIANT): re-run the probe command from the registry before citing it — the evidence cell (`--md` and `--json` alike) is truncated to 200 chars and typically shows only the first drift instance; never cite a truncated cell, never write "single hit" from it.** Re-run the one-liner with cwd = repo root and `LATTICE_HOME`, `REGISTRY_DIR`, `PROBE_ID`, `REPO_ROOT` exported (or `claim-probes.sh --only <id>` for the verdict plus the registry command for the list), then open the promise (doc line, ADR §, Spec A*) and the implementation at the exact point. Worked: the baseline's `retired-paths-absent` cell showed one file; the full re-run showed three. Decide which side is wrong; both outcomes are findings. A `skip` row with a reason is not a pass — note it in Method as an unaudited surface.

Beyond the registry, **sample** claims by hand every run (the registry only covers classes someone already got burned by):

```bash
grep -n 'Verification' docs/adr/*.md | shuf -n 3            # run the named test / open the named script:line
grep -ln '^status: done' "$PH"/specs/*.md | shuf -n 2         # pick one checked A*, find the test or PR that proves it
```

## L3 — history + judgement (model; audit-recipe §5 archaeology, §6 clustering)

```bash
BASE=dev; W='30 days ago'
git --no-pager log "$BASE" --since="$W" --format=%s | grep -vE '\(#[0-9]+\)$' | grep -v '^finish(' \
  | sed -E 's/\(.*//; s/:.*//' | sort | uniq -c | sort -rn                  # direct-to-base commit classes beyond finish stamps
git --no-pager log "$BASE" --since="$W" --format='__%h %s' --name-only \
  | awk '/^__/{fix=($0 ~ /^__[0-9a-f]+ fix/); next} fix && NF{print}' \
  | sort | uniq -c | sort -rn | awk '$1>=2'                                  # recurrence: files touched by >= 2 fix( commits
git --no-pager log "$BASE" --since="$W" --format='%h %ad %s' --date=short \
  | grep -iE 'flip .*status|re-stamp|backfill'                               # a subject class repeating = same bug class fixed N times
grep -rhoE 'NOTICED:.*\(out-of-paths, [0-9-]+\)' "$PH"/tickets/*/README.md \
  | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort | uniq -c                   # NOTICED backlog age; which digest dispositioned any?
grep -ln 'NOTICED' "$PH"/reviews/*.md                                        # last sweep that drained the queue
```

Also read: the last three `rev-` files' Findings and Follow-ups (a finding marked fixed that reappears is a **reopened class**), and the `## Attempts` / `## Pending decisions` sections the metrics flagged as non-empty.

### Fan-out (audit-recipe §1; `../../_lattice-lib/references/orchestration-patterns.md`)

The three layers are already disjoint; if the repo is large, delegate **read-only** sweeps with disjoint briefs — e.g. (a) L2 reconciliation of failed probes, (b) L3 recurrence over `git log`, (c) NOTICED age + prior-rev reopened classes. One accountable owner (you) merges, and **every delegated claim is re-verified before it enters Findings** (`orchestration-patterns.md` Rules 1, 3; Red flag: "delegated output accepted without fresh verification"). Do not delegate the ranking or the rev.

### Verify-then-report accounting (audit-recipe §2 — INVARIANT)

Keep a scratch ledger while you work, one line per candidate:

```
C7 | source: probe skill-scripts-exist | claim: stamp-pr-open.sh not executable | re-run: git ls-files -s … → 100644 | VERIFIED → F3
C9 | source: tkt-370 NOTICED | claim: tkt-356/357 still count as missing ledger | re-run: metrics.json missing[] → absent | DROPPED
```

`## Method` reports: candidates considered, verified, **dropped** (the count and one line each — a dropped claim is information too: a NOTICED line that no longer reproduces should be dispositioned by the next digest), plus the exact commands executed for reconciliation and the sensors' timestamps / snapshot path.

## Ranking rubric (spc-369 Agent-assumed; ADR-007 §2–§3)

Score each **cluster** (not each symptom):

| Axis | Question | Low | Mid | High |
| --- | --- | --- | --- | --- |
| **Impact** = blast radius × frequency | Which artifacts/paths lie about state if this stays, and how often did it fire in the window? | one binder, once | one skill / one metric, a few times | every consumer of a shared parser/writer, or ≥ 3 fixes of the same class in the window |
| **Decidability** | Can a script, validator code, hook, or probe recognise the violation without ambiguity (ADR-007 §3)? | judgement call, convention still unsettled | decidable with a rule the team has not agreed on | one-liner check; a probe or validator code can carry it |

| Impact \ Decidability | High (script-enforceable) | Low (undecidable / convention) |
| --- | --- | --- |
| **High** | **Ticket draft** — repair + guard (validator code, probe row, bats fault-injection) in the same row; P1 | **`needs_decision` row** — state the options and the default; never a ticket that pretends to enforce (ADR-007 §3 "do not build checkers that invite gaming") |
| **Low** | Ticket draft, P3, or a one-liner disposition for the NOTICED queue | Insight only — name the taxonomy class, watch the delta |

Severity in Findings mirrors impact (`high` / `med` / `low`); order Findings by impact, then decidability. Every ticket row names the mechanism that prevents recurrence (audit-recipe §6) — "fix the regex" without "add the validator code" re-runs this audit next month.

## Reading the delta (▲ / ▼ are not good / bad)

| Metric | ▲ usually means | ▼ usually means | Look at |
| --- | --- | --- | --- |
| Ledger coverage % | path-point writers are stamping (ADR-012 §1) or legacy backfill landed | new terminal binders without ledger — a writer regressed or a bypass; check `direct_jumps` and the newest binders' `created` | `ledger_coverage.missing[]` restricted to binders created after the ratchet date |
| Direct jumps | merges from `queued`/`in-progress` — `create-pr` stamp skipped or hook not installed | healthy | the tickets' `prs` row vs ledger `pr-open` entry |
| Edges walked / never-walked | a rare path was exercised (good, verify it was intentional) — or an *unmodelled* edge appeared (`unmodelled[] > 0` = a writer outside the table) | nothing walked new paths; only a signal if a Spec claimed to deliver that edge | `edges.unmodelled[]` first |
| Direct commits (no PR suffix) | bookkeeping still pushed to base; compare with `finish(` stamps — if both rise together it is finish-work, if direct rises alone it is hand edits/escapes | ADR-012 §5 bookkeeping moved off the base | `git log` classes (L3 first command) |
| `finish(` stamps | more merges (throughput) | fewer merges or bot bookkeeping landed | PR merges in the same row |
| NOTICED backlog | agents are observing (good) **and** nobody is dispositioning (bad) — split by age | a digest drained it | dates in the lines; last digest with a NOTICED sweep |
| fix_cycles > 0 / Attempts / Pending | the M2 side machinery is actually used | idle — either no hard tickets or agents bypass the sections | compare with `rework` edges walked |
| Escape traces by rule | boundary misplaced (ADR-007 §8) — redraw or demote | healthy | the `rule_id` with the rise |
| Specs done with open A* / prs mismatch | `done` flipped by hand or bloodline not updated | finish-work Spec-close working | which Spec, which PR |
| Status histogram odd keys (`closed \|`) | a parser cannot read some binders — the *rest* of the table is undercounted | fixed | `queue_health._FIELD_ROW_RE`, `binder_rows.py` |

First snapshot: no delta; report absolute values and say so. Two snapshots less than a day apart mostly measure your own run; prefer weekly cadence (tkt-373 morning-triage step).
