---
id: rev-20260902-080545Z
slug: lineage-audit-baseline
title: "Lineage audit — first baseline (30d window on dev, 2026-09-02)"
kind: audit
status: concluded
outcome: spawn_tickets
summary: "Baseline: ledger coverage 31.8% (all legacy), 19/26 edges never walked, 48.4% direct-to-base commits, 10 status-flip fixes in 7d, 3/7 probes fail; 6 ticket drafts + 1 decision."
created: 2026-09-02
updated: 2026-09-02
related_specs:
  - spc-369
  - spc-337
related_tickets:
  - tkt-372
  - tkt-370
  - tkt-371
related_prs: []
---

# Review: Lineage audit — first baseline (30d window on dev, 2026-09-02)

> **TL;DR:** The first scripted lineage snapshot of this repo says the conformance slice (spc-337) is working where it landed — every binder created since the ADR-012 ratchet date has a ledger and `queued → in-progress` went from 1 to 15 recorded entries — but the same terminal-stamp path has been fixed by hand ten times in seven days, the shared binder parser silently drops 15 closed binders from every count, two ledgers are keyed by a bare issue number, two SKILL-named scripts are not executable, and 35 `- NOTICED:` observations have never been dispositioned. Outcome `spawn_tickets`: six drafts (parser + guard, ledger key + guard, script modes + lint, one docs line, two sensor extensions, a NOTICED drain) and one `needs_decision` (what a checked Spec `A*` must cite).
> **Kind:** audit · **Status:** concluded · **Outcome:** spawn_tickets
> **Window:** `--since 30d` on `dev` @ `e3e0872` · **Snapshot:** `.lattice/reviews/metrics/lineage-20260902-080132Z.json` (first — no previous) · **Probes:** 4 pass / 3 fail / 0 skip

## Context

Dry run of `review-lineage` (spc-369 A3, tkt-372) on its own repo, following `skills/review-lineage/SKILL.md` Process 0–5. Sensors: `lineage-metrics.sh` (tkt-370) and `claim-probes.sh` (tkt-371) as merged on `dev` `e3e0872`. This is the first snapshot, so every Δ is `—`; the value of this run is the absolute baseline plus the findings that the numbers alone cannot show. The method origin is `rev-20260902-015425Z`; several of its numbers are re-measured here by script (ledger coverage, direct jumps, walked edges, direct-to-base ratio) so the hand counts and the sensor can be compared.

## Problem Audit

| Layer | Notes |
| --- | --- |
| Validity | The headline numbers are real drift, but two of them are partly about the sensors' shared parser (F2): the terminal denominator is 151 instead of 166 and coverage is computed on it. Reported as a finding, not corrected by hand. |
| Information | `.lattice` + `git log dev` sufficient for every finding below. Not available/used: `--gh` reconciliation (offline run), CI run history, GitHub issue states. |
| Hidden issues | Two root causes explain most symptoms: (C1) the terminal-stamp path (`finish-ledger.sh` / `stamp-pr-open.sh` / validator) is still where hand repairs concentrate; (C2) six scripts parse binder rows through one regex that cannot read a 3-column row, and one writer keyed ledgers by a bare id. |
| Existing solution | ADR-012 §1–§4 (landed via spc-337) already fixed the writer side; §5 (bot bookkeeping + single finish script), §6 (Spec DoD), §7 (binder front matter) are decided directions not yet implemented — this audit does not re-decide them, it measures the soak. |

## Metrics delta (L1 — `lineage-metrics.sh --since 30d --md`, 2026-09-02T08:01:32Z)

| Metric | Value | Δ |
| --- | --- | --- |
| Binders | 168 | — |
| Ledger coverage (terminal with ledger) | 48/151 (31.8%) | — |
| Missing ledger | 103 | — |
| Direct jumps (merge from queued/in-progress) | 10 | — |
| Ledger entries / files | 123 / 51 | — |
| Edges walked / modelled | 7 / 26 | — |
| Edges never walked | 19 | — |
| Edges unmodelled (walked but not in LEGAL_EDGES) | 0 | — |
| Side-state binders (parked/stuck/rework/deferred) | 0 | — |
| Binders with fix_cycles > 0 | 7 | — |
| Binders with `## Attempts` entries | 5 | — |
| Binders with `## Pending decisions` entries | 4 | — |
| Binders with `## Decision journal` entries | 72 | — |
| `- NOTICED:` backlog | 35 | — |
| Escape traces (`rule_id=`) | 2 (`batch-merge-gate`) | — |
| Base commits (`dev`, since 30d) | 339 | — |
|   PR merges (`(#N)` suffix) | 175 | — |
|   Direct commits (no PR suffix) | 164 (48.4%) | — |
|   `finish(` stamps | 111 | — |
| Specs done with open A* | 0 | — |
| Specs with `prs` ≠ child binder PR union | 3 (spc-104, spc-270, spc-337 — Spec-only planning PRs; no child PR missing) | — |

Status histogram: `closed` 151 · `closed \|` 14 · `closed \| working: queued \\| in-progre…` 1 · `in-progress` 1 · `queued` 1.

Edges walked: `pr-open->closed` 37 · `in-progress->pr-open` 28 · `queued->pr-open` 17 · `queued->in-progress` 15 · `queued->closed` 10 · `pr-open->rework` 8 · `rework->in-progress` 8. Never walked (19): `deferred->closed`, `deferred->deferred`, `deferred->pr-open`, `deferred->queued`, `in-progress->closed`, `in-progress->deferred`, `in-progress->parked`, `in-progress->stuck`, `open->closed`, `parked->closed`, `parked->pr-open`, `parked->queued`, `pr-open->pr-open`, `queued->deferred`, `rework->closed`, `rework->pr-open`, `stuck->closed`, `stuck->pr-open`, `stuck->queued`. Direct-jump tickets: tkt-272, 274, 275, 276, 323, 324, 325, 326, 327, 335.

_Snapshot written: `.lattice/reviews/metrics/lineage-20260902-080132Z.json` (schema 1)._

## Probe results (L2 — `claim-probes.sh --md`, 2026-09-02T08:01Z, registry `skills/review-lineage/references/probes.md`, overlay none)

| probe | status | severity | evidence |
| --- | --- | --- | --- |
| skill-scripts-exist | fail | high | skills/create-pr/SKILL.md names _lattice-lib/scripts/stamp-pr-open.sh -> skills/_lattice-lib/scripts/stamp-pr-open.sh (missing or not executable) ⏎ skills/review-code/SKILL.md names SKILL_ROOT/scripts… |
| hooks-json-files-exist | pass | high |  |
| validator-codes-cited-exist | pass | med |  |
| retired-paths-absent | fail | med | skills/finish-work/references/flow.md:45:- **CI merge gate (machine-enforced, spc-186 A6/A8, ADR-007 §5a).** Run `ci-gate-check.sh --pr <N> --evidence "<local test output>" [--binder <path>]`. It fetc… |
| adr-verification-refs-resolve | pass | med |  |
| spec-done-acceptance-cites-evidence | fail | low | spc-104-runtime-verification.md: A2 A3 A4 — no test/PR/ticket evidence cited ⏎ spc-116-retire-release-train.md: A1 A2 A3 A5 A7 A8 A9 A10 — no test/PR/ticket evidence cited ⏎ spc-12-skill-gap-bridge.md… |
| fsm-doc-edges-subset-of-schema | pass | high |  |

claim-probes: 4 pass, 3 fail, 0 skip. `validate-lattice-artifacts.py`: 219 warnings (baseline classes `missing_binder_timestamp`, `prs_row_format`), 0 errors, exit 0.

## Comparison matrix — how to act on C2 (one parser, one ledger key)

| Option | Cost | Code-delta | Risk | Constraints | Capability |
| --- | --- | --- | --- | --- | --- |
| **A — patch `_FIELD_ROW_RE` + normalise ledger key, and add a validator code for each so the class cannot return (proposed)** | low | 2 regex/normalisation lines + 2 validator codes + bats fixtures | validator warning noise on 15 legacy binders until they are re-rowed — goes into the warning baseline | must keep `binder_rows.py`/`queue_health` as the only parsers (spc-369 D5, ADR-012 §7) | every consumer (queue-health, lineage-metrics, finish-ledger) counts correctly at once; ratchet visible next snapshot |
| Keep status quo | 0 | 0 | every count that feeds ADR-012 §4's "first-class metric" is off by 15 binders; the next format drift is silent again | — | — |
| C — migrate binder machine fields to YAML front matter now (ADR-012 §7) | high | new parser + lazy migration + all writers | large blast radius during the spc-337 soak | ADR-012 says "a later Spec" | removes the table-row parser class entirely |

Recommendation: **A now, C as the already-planned later Spec** — A is a day of work with a guard, C is the structural fix and should not be rushed into the soak window.

## Findings (ranked; 7)

### F1 — The terminal-stamp path is still repaired by hand, ten times in seven days (high · C1 · T5 recurrence, T4 silent-bypass)

- **Failure scenario:** each time `finish-ledger.sh` / `stamp-pr-open.sh` / the validator disagree, an operator commits a "flip status" or "backfill" fix straight to `dev`; until then a binder lies about its state and CI on `dev` is red (`dd144ba`: "artifacts CI red on dev"). The repair is local each time; the class returns.
- **Evidence (re-verified):** `git --no-pager log dev --since='30 days ago' --format='%h %ad %s' --date=short | grep -iE 'flip (binder )?status|closed-open → closed|backfill pr-open'` → 10 commits: `2c5e3bf` 08-27, `47379e3` 08-27, `60e066a` 08-28, `64a6abd` 08-28, `c896957` 08-28, `052de11` 08-31, `abf8e0f` 08-31, `d17e1ca` 09-02, `45d18c8` 09-02, `dd144ba` 09-02. Files in ≥ 2 `fix(` commits in 30 days: `skills/_lattice-lib/scripts/finish-ledger.sh` 15, `tools/validate-lattice-artifacts.py` 13, `finish-ledger.bats` 13, `stamp-pr-open.sh` 8, `skills/finish-work/SKILL.md` 8 (88 `fix(` commits total in the window).
- **Since last run:** persisting — `rev-20260902-015425Z` F3 counted the cost (tkt-317/323, pr-333/334); three more fixes landed after it (`a878acb`, `dd144ba`, `f264caf`).
- **Mechanism:** the structural answer is decided (ADR-012 §5: bot-owned post-merge bookkeeping + one idempotent `finish-work` script; follow-up Spec after the soak — `rev-20260902-015425Z` Follow-ups). What is missing *now* is a number the soak can be judged by: a `fix_recurrence` metric in `lineage-metrics.sh` (files in ≥ N `fix(` commits per window + repeated subject classes), so the next snapshot shows whether §1–§4 bent the curve before §5 is built (ticket 5).

### F2 — One regex drops 15 closed binders from every count; two ledgers are keyed by a bare id (med · C2 · T8 artifact-truth)

- **Failure scenario:** `queue-health.sh`, `lineage-metrics.sh`, and every other consumer of `queue_health._parse_field_rows` see status `closed |` for a binder whose row has an empty third cell, so the binder is neither terminal nor counted for ledger coverage; ADR-012 §4's "first-class conformance metric" is computed on 151 binders instead of 166. Separately, the `queued → in-progress` entries for tkt-356/357 live in files the ticket's replay never opens.
- **Evidence (re-verified):** `skills/_lattice-lib/scripts/lib/queue_health.py:59` `_FIELD_ROW_RE = r"^\|\s*(?P<field>[A-Za-z_]+)\s*\|\s*(?P<value>.*?)\s*\|\s*$"` — non-greedy up to the *last* pipe. `grep -l '^| status | closed | ' .lattice/tickets/*/README.md` → 15: tkt-121, 191, 192, 194, 201, 211, 236, 237, 238, 239, 240, 241, 242, 243, 246 (`tkt-121-validator-hardening/README.md:15` also carries the template legend `working: queued \| in-progress …` inside the value). Status histogram keys `closed \|` 14 + `closed \| working…` 1. Ledgers: `.lattice/.transition-ledger/356.jsonl` and `357.jsonl` contain `"ticket":"356"` / `"357"` (`queued→in-progress`, reason `spawn`, 05:20Z/05:31Z), added by `5fc6b63` (pr-358); `tkt-356.jsonl` / `tkt-357.jsonl` start at `in-progress→pr-open`. The current bind path passes `tkt-$id` (`ensure-workspace.sh:669`; this ticket's `tkt-372.jsonl` is keyed correctly) — the writer of the bare-id files could not be identified from the tree.
- **Since last run:** new (tkt-370 NOTICED the regex on 2026-09-02; numbers there were 149/164 — the mechanism reproduces, the counts moved).
- **Mechanism:** capture `([^|]*?)` in `_FIELD_ROW_RE` + validator warning `binder_row_extra_columns` with a planted 3-column fixture (ticket 1); normalise the ledger key to `tkt-N` in `transition-api.py` + validator error `ledger_key_not_ticket_id` + merge the two stray files into their `tkt-` ledgers (ticket 2).

### F3 — Two SKILL-named scripts are tracked as `100644` (med · C3 · T2 claim-without-enforcement)

- **Failure scenario:** `create-pr/SKILL.md` and `review-code/SKILL.md` name `stamp-pr-open.sh` / `review-context.py` as scripts (skill-anatomy rule 1: skill-owned executables); both work today only because every caller prefixes `bash` / `python3`. A consumer or a hook that invokes the path directly gets `Permission denied`, and nothing in CI notices.
- **Evidence (re-verified):** `git ls-files -s skills/_lattice-lib/scripts/stamp-pr-open.sh skills/review-code/scripts/review-context.py` → `100644` both; probe `skill-scripts-exist` re-run in full → exactly these two (3 lines: review-code names the file twice). Every other SKILL-named script is `100755`.
- **Since last run:** new (tkt-371 NOTICED both on 2026-09-02, still open).
- **Mechanism:** `chmod +x` both + a mode lint in `tools/validate-skills.sh` (`git ls-files -s 'skills/*/scripts/*.sh' 'skills/*/scripts/*.py'` must be `100755`) so the probe's `high` row never fires for this class again (ticket 3).

### F4 — `finish-work/references/flow.md:45` promises a `gh pr checks` field the script no longer requests (med · C4 · T2, T9 environment-dependence)

- **Failure scenario:** an agent following flow.md re-adds `conclusion` to the `--json` list (it is not a field on gh ≥ 2.6x; gh 2.92.0 here) or reports the CI gate as broken; the line is the one tkt-341 NOTICED and tkt-349 fixed in the script only.
- **Evidence (re-verified):** `skills/finish-work/references/flow.md:45` — "It fetches `gh pr checks <N> --json name,state,conclusion,link`"; `skills/finish-work/scripts/ci-gate-check.sh:138-146` — docstring "`conclusion` is NOT a field … derive the legacy pair when absent". Probe `retired-paths-absent` (phrase `name,state,conclusion,link`) → this single hit.
- **Since last run:** new; the guard already exists (the probe row) — only the repair is missing.
- **Mechanism:** one-line docs fix (ticket 4, one-liner); the probe keeps it fixed.

### F5 — 35 `- NOTICED:` observations, none dispositioned (med · C5 · T6 invisible-queue)

- **Failure scenario:** the Observation-duty queue (`decision-policy.md`) drains only through `review-delivery`'s NOTICED sweep; no digest has run since `rev-20260827-023130Z`, which predates every line. Agents keep writing (16 lines on 2026-09-02 alone), nobody reads; two lines already describe states later work changed (see Method, dropped claims).
- **Evidence (re-verified):** `grep -l '^- NOTICED:' .lattice/tickets/*/README.md | wc -l` → 15 binders; dates in the lines: 08-27 ×4 (tkt-93/94), 08-31 ×2, 09-01 ×7, 09-02 ×16 (6 lines carry no date); `grep -ln NOTICED .lattice/reviews/*.md` → only `rev-20260826-141124Z` (design note, not a sweep).
- **Since last run:** persisting (`rev-20260827-033352Z` F8 "noticed, never filed" was the same class one round earlier).
- **Mechanism:** one drain pass with the review-delivery disposition table (`ticket | one-liner | wontfix`) recorded in a rev (ticket 6), and this skill's weekly cadence (tkt-373 morning-triage step) reading NOTICED age from the snapshot so the pile cannot go invisible again.

### F6 — 14 of 16 `done` Specs have checked `A*` boxes that cite no test, PR, or ticket (low · C6 · T3 done-without-evidence)

- **Failure scenario:** a checked box is a self-report; the proof lives in binders and PR bodies, so a cold reader (or the `spec_done_open_acceptance` validator) cannot tell a proven A* from an optimistic one — the pattern `rev-20260902-015425Z` F6 documented for spc-254/270.
- **Evidence (re-verified):** probe `spec-done-acceptance-cites-evidence` re-run in full → 14 Specs (spc-104, 116, 12, 145, 212, 213, 220, 226, 254, 270, 277, 282, 4, 42). Sampled the other way: spc-337 A1 → `transition-api.py:64-70` resolves the ledger home from the binder path; A4 → `plugins/lattice/hooks/intercept-shippable-write.sh:140-149` refuses status-row edits — both boxes are **true**, the proof is just off-artifact.
- **Since last run:** persisting (ADR-012 §6 records the direction: acceptance boxes cite the test or fault-injection case).
- **Mechanism:** undecidable today — which citation form counts (`bats` name, `pr-N`, `tkt-N`, a fixture id) is a convention the team has not fixed, and a lint before the convention invites `see tests` boilerplate (ADR-007 §3). → **needs_decision row**, folded into the ADR-012 §6 follow-up Spec; the probe stays `low`.

### F7 — Coverage is 31.8 % and entirely legacy; 19 of 26 edges have never been walked (low · C7 · T1 modelled-but-unwalked)

- **Failure scenario:** none today — this is the baseline that the ratchet must move. The risk is misreading: a flat 31.8 % next month would look like failure while every new binder is covered.
- **Evidence (re-verified):** all 103 missing-ledger binders were created before 2026-09-01 (93 have no `created` row, 10 dated 08-29..08-31); 0 binders created after the ADR-012 §4 cutoff lack a ledger. Direct jumps (10) are all pre-spc-337 tickets (tkt-272..335). `queued → in-progress` entries: 15 now vs 1 in `rev-20260902-015425Z` (tkt-339's bind stamp). Side-state binders 0/168; `open->closed` is a legacy lazy-migration edge (`transition_table.py:157`).
- **Since last run:** improved on the writer side (F1 of the origin rev), unchanged on the legacy side.
- **Mechanism:** give the sensor a `--created-after <date>` (or read the ADR-012 cutoff from config) so the headline reports post-ratchet coverage next to the legacy total (ticket 5, same sensor ticket as the recurrence metric). Never-walked edges are rare-path by design — insight, not a deletion order.

## Insights (pattern level — `references/insight-taxonomy.md`)

- **T5 recurrence:** the terminal-stamp path is the hot spot — `finish-ledger.sh` 15 fixes/30d, 10 status-flip commits/7d. Watch: fixes per file should fall after ADR-012 §5 lands; if they fall before, §1–§4 sufficed.
- **T4 silent-bypass:** 164/339 base commits without a PR (48.4 %); 111 are `finish(` stamps, ~53 are docs/tickets/fix commits pushed by hand (17 `docs`, 13 `fix`, 4 `stamp`, 3 `tickets`). Watch: the non-finish direct count is the hand-edit signal; it should trend to 0 under the strict profile.
- **T7 prose-vs-script:** `queued → in-progress` 1 → 15 entries once the bind stamped it (ADR-012 §1). The same move remains to be made for cancel/triage edges (0 walked).
- **T8 artifact-truth:** one shared regex mis-reads 15 of 168 binders; the fix is one capture group, the lesson is spc-369 D5 — one parser, guarded by a fixture.
- **T1 modelled-but-unwalked:** 19/26 edges, 0 side-state binders, `## Attempts` 5 / `## Pending decisions` 4 / `## Decision journal` 72 — the M2 side machinery is rarely used; `rev-20260902-015425Z` P2 #13 ("pause M3 expansion until exercised") still holds.
- **T6 invisible-queue:** 35 NOTICED lines, 0 dispositions, oldest 6 days.
- **T9 environment-dependence:** gh 2.92.0 field set (F4); bats 1.2.1 vs CI pin; the origin rev's F0 (plugin not installed locally) is not re-checked here — out of the artifact universe.
- **T3 done-without-evidence:** 14/16 done Specs — convention gap, decision pending (F6).

## Proposed tickets (create-tickets §2 batch shape, extended with kind · priority · why)

| # | title | covers | paths (approx) | blocked_by | parallel_group | solo-merge | kind | priority | why |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | queue_health field-row regex reads 3-column rows + validator `binder_row_extra_columns` | F2 | skills/_lattice-lib/scripts/lib/queue_health.py, tools/validate-lattice-artifacts.py, tools/tests/lattice-artifacts.bats, skills/_lattice-lib/scripts/tests/ | none | G1 | yes | fix | P2 | 15 closed binders parse as `closed \|` and vanish from every count; fixture-guarded so the next format drift is a warning, not silence |
| 2 | transition-api normalises ledger key to `tkt-N` + validator `ledger_key_not_ticket_id`; fold `356.jsonl`/`357.jsonl` into their ledgers | F2 | skills/_lattice-lib/scripts/transition-api.py, tools/validate-lattice-artifacts.py, .lattice/.transition-ledger/ | #1 | G1 | yes | fix | P2 | bind entries stranded outside the ticket's replay; both rows edit the validator, hence serial |
| 3 | chmod +x stamp-pr-open.sh / review-context.py + script-mode lint in validate-skills.sh | F3 | skills/_lattice-lib/scripts/stamp-pr-open.sh, skills/review-code/scripts/review-context.py, tools/validate-skills.sh, tools/tests/ | none | G2 | yes | chore | P2 | SKILL-named scripts must be executable (skill-anatomy rule 1); lint keeps the `high` probe quiet for this class |
| 4 | finish-work flow.md:45 — drop `conclusion` from the documented `gh pr checks --json` field list | F4 | skills/finish-work/references/flow.md | none | G2 | yes | docs | P3 | one-liner; `retired-paths-absent` probe already guards it |
| 5 | lineage-metrics: `fix_recurrence` metric (files ≥ N fix commits, repeated subject classes) + post-ratchet coverage (`--created-after`) | F1, F7 | skills/review-lineage/scripts/lineage-metrics.sh, scripts/lib/lineage_metrics.py, scripts/tests/lineage-metrics.bats, scripts/tests/fixtures/metrics/ | none | G3 | yes | feat | P2 | the ADR-012 soak needs a number for "same class fixed again" and for coverage that can actually move |
| 6 | drain the NOTICED backlog: disposition all 35 lines (`ticket \| one-liner \| wontfix`) in a rev; file the `ticket` rows | F5 | .lattice/reviews/, .lattice/tickets/*/README.md (Notes only) | none | G3 | yes | chore | P2 | 15 binders, oldest 08-27, zero dispositions; two lines are already stale |

**Ship plan:** multi-PR — G1 serial (1 → 2, shared validator), G2 ∥ G3 independent paths. **Needs-decision rows:** F6 — what a checked Spec `A*` must cite (`bats` name | `pr-N`/`tkt-N` | fixture id | nothing, evidence stays in binders); default: fold into the ADR-012 §6 follow-up Spec, keep the probe at `low`.

## Outcome

`spawn_tickets` — six decidable, guard-paired drafts above; F6 is carried as a needs-decision row inside this outcome rather than a second outcome. The operator confirms (go / edit rows) → `create-tickets`; this review filed nothing, merged nothing, edited no product code or binder.

### Follow-ups

- [ ] Operator: go / edit rows on the Proposed-tickets table; F6 decision (or defer to the ADR-012 §6 Spec)
- [ ] Next lineage audit after one week of soak (tkt-373 morning-triage cadence); diff against `lineage-20260902-080132Z.json` — expect coverage ▲ only via ticket 5's post-ratchet view, direct commits ▼ once ADR-012 §5 lands, fix-recurrence ▼

## Method

- **Sensors:** `bash skills/review-lineage/scripts/lineage-metrics.sh --md` @ 2026-09-02T08:01:32Z (0.9 s; snapshot `.lattice/reviews/metrics/lineage-20260902-080132Z.json`, first — committed with this rev); `bash skills/review-lineage/scripts/claim-probes.sh --md` and `--json` @ 08:01Z (registry `skills/review-lineage/references/probes.md`, overlay none, 0.7 s); `python3 tools/validate-lattice-artifacts.py` → 219 warnings / 0 errors / exit 0; `reconcile-state.sh` not run (offline, no `--gh`).
- **Sweeps (L3, no fan-out — single owner):** `git log dev --since='30 days ago'` commit-class split (non-PR, non-finish subjects), files in ≥ 2 `fix(` commits, status-flip subject class, NOTICED dates + last review containing a sweep, prior revs' Follow-ups (`rev-20260902-015425Z`, `rev-20260827-033352Z`).
- **Claim reconciliation:** probes `skill-scripts-exist`, `retired-paths-absent`, `spec-done-acceptance-cites-evidence` re-run by hand for full lists; sampled ADR `Verification:` bullets — ADR-006 (hooks.json + `assert-shippable-cwd.bats` resolve), ADR-012 (`closed_without_ledger` present in the validator, 4 hits), ADR-011 ("fresh-clone simulation test lands in the test suite" — not located by name; see Appendix A1); sampled done-Spec boxes — spc-337 A1 (`transition-api.py:64-70`), spc-337 A4 (`intercept-shippable-write.sh:140-149`), spc-186 A6 (`ci-gate-check.sh` exists) — all three hold.
- **Verify-then-report:** candidates 14 · verified 12 · **dropped 2** — (1) tkt-370 NOTICED "tkt-356/357 still count as missing ledger": `ledger_coverage.missing[]` does not contain them (`tkt-356.jsonl`/`tkt-357.jsonl` exist; only the bind entries are stranded — F2 rewritten accordingly); (2) tkt-341 NOTICED / brief "`ci-gate-check.sh` fails on gh 2.92 (`conclusion`)": the script derives the field since tkt-349 (`ci-gate-check.sh:138-146`) — addressed-by-later-work; only the doc line remains (F4).
- **Bounds:** one pass, timebox 90 min (tkt-372 night shift), Findings 7/7, Appendix 2.
- **Not done / unaudited:** GitHub-live state (`--gh`), CI run history, the origin rev's F0 (local plugin install), `skip`-class probes (none this run).

## Appendix

- **A1 — ADR-011 Verification bullet "a fresh-clone simulation test lands in the test suite":** no bats file names it; `assert-shippable-cwd.bats` mentions a fresh clone but is the L2 gate suite. Unverified either way → candidate for the next run (T2 if absent).
- **A2 — Spec `prs` semantics:** spc-104/270/337 list Spec-creation PRs (pr-109/112, pr-312, pr-343) no child binder carries; the sensor reports it as a mismatch with 0 missing child PRs. Harmless; ADR-011 L0 does not define whether `prs` means delivery PRs or all PRs (tkt-370 NOTICED). Docs one-liner when convenient.

## References

- Sensors: `skills/review-lineage/scripts/lineage-metrics.sh`, `skills/review-lineage/scripts/claim-probes.sh`, `skills/review-lineage/references/probes.md`, `skills/review-lineage/references/retired-paths.txt`
- Method: `skills/review-lineage/SKILL.md`, `references/method.md`, `references/insight-taxonomy.md`; origin `rev-20260902-015425Z`; audit law `skills/create-review/references/audit-recipe.md`
- Parsers/writers cited: `skills/_lattice-lib/scripts/lib/queue_health.py`, `skills/_lattice-lib/scripts/transition-api.py`, `skills/_lattice-lib/scripts/ensure-workspace.sh`, `skills/finish-work/scripts/ci-gate-check.sh`, `plugins/lattice/hooks/intercept-shippable-write.sh`
- Laws: ADR-004 §1, ADR-007 §3/§8, ADR-011, ADR-012 §1/§4/§5/§6/§7; Specs spc-337, spc-369
