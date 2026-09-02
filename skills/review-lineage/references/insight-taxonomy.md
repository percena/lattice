# Insight taxonomy (review-lineage)

Named classes for the pattern-level `## Insights` of a lineage audit. A Finding is one verified defect; an insight is the class it belongs to, stated with its base rate so the next run can watch the delta. Cite the id (`T1`…`T9`) in the Finding's `cluster` cell and in Insights. Every class carries a **detection hint** (which sensor field or command surfaces it) and a **real example** from this repo's history (`rev-20260902-015425Z` F-ids; spc-337 follow-up binders tkt-338..342, tkt-356/357, tkt-370/371 NOTICED lines).

| Id | Class | One-line definition |
| --- | --- | --- |
| T1 | modelled-but-unwalked | The design has a state/edge/mechanism that production data never exercises |
| T2 | claim-without-enforcement | A doc promises behaviour that no validator, hook, test, or probe checks |
| T3 | done-without-evidence | A `done` / `[x]` / `closed` mark whose proof cannot be found in the tree |
| T4 | silent-bypass | State changed outside the writer that owns it (hand edit, direct-to-base commit) and nothing recorded it |
| T5 | recurrence | The same bug class is fixed ≥ 2× in the window |
| T6 | invisible-queue | Observations are captured but no consumer drains them |
| T7 | prose-vs-script ratio | A path is described in words where a script could execute it; drift follows |
| T8 | artifact-truth | The artifact's checked box, status row, or count is not what the tree shows |
| T9 | environment-dependence | Green in one environment, red in another; the docs assume one of them |

## T1 — modelled-but-unwalked

- **Detect:** `edges.never_walked[]` and `side_states` in the metrics; `sections.attempts/pending_decisions` ≈ 0 while the policies that fill them are thousands of words; grep the mechanism name in `*.sh|*.py` — zero hits outside tests.
- **Read with care:** rare paths (`stuck`, `deferred`, cancel) are *meant* to be rare. The insight is the ratio and its trend, not "delete the edge". Deletion is `needs_decision`.
- **Example:** rev-20260902-015425Z F1 — 21 modelled edges, 5 walked; `queued → in-progress` recorded once in 31 ledgers while being the most common transition. Baseline 2026-09-02 (`rev-20260902-080545Z`): 26 modelled, 7 walked, 19 never walked, side-state binders 0 of 168.

## T2 — claim-without-enforcement

- **Detect:** `claim-probes.sh` rows (`skill-scripts-exist`, `validator-codes-cited-exist`, `retired-paths-absent`, `adr-verification-refs-resolve`); for any law the tree currently meets ask "which validator / test / CI gate enforces this?" (audit-recipe §3) — no answer is the finding.
- **Example:** rev-20260827-033352Z F2/F3 — three docs said "the validator rejects illegal transitions"; the validator ran no transition check and ran in no CI workflow. rev-20260902-015425Z F4 — `finish-work/references/flow.md:468` still called `verify-mutation.sh --pr` after a merge (it rejects MERGED); `ci-gate-check.sh` was a hard rule that `SKILL.md` never named. Baseline 2026-09-02: `finish-work/references/flow.md:45` still promises a `gh pr checks --json` field list containing `conclusion` after tkt-349 stopped requesting it.

## T3 — done-without-evidence

- **Detect:** `specs.done_with_open_acceptance`, `specs.prs_mismatch`; probe `spec-done-acceptance-cites-evidence`; a Spec whose `created` == `done` date; a later `rev-` re-opening A* of a `done` Spec.
- **Example:** rev-20260902-015425Z F6 — spc-254 and spc-270 flipped `done` on their creation day with every A* checked; the next review found A1–A5/A7/A8 partial and A3 wiring absent. Baseline 2026-09-02: 14 of 16 `done` Specs have checked A* boxes citing no test / PR / ticket (evidence lives in binders and PR bodies, so this is a convention gap, severity low — ADR-012 §6 direction).

## T4 — silent-bypass

- **Detect:** `ledger_coverage.direct_jumps` + the `direct-jump tickets` list; `git.direct_commits` vs `git.finish_stamps` (direct minus finish = hand commits); binders whose `status` changed in a commit with no `.transition-ledger/` change (`git log -p -- <binder> | grep '^[-+]| status'`); escape traces with `rule_id`.
- **Example:** rev-20260902-015425Z F1 — tkt-325/326/327 closed by editing the `| status |` row in `45d18c8`/`d17e1ca` (no API, no ledger); F3 — 150 non-PR pushes to `dev` in 9 days, 97 of them `finish(` stamps. Baseline 2026-09-02: 164/339 base commits without a PR suffix (48.4 %), 111 `finish(`; 10 direct jumps.

## T5 — recurrence

- **Detect:** L3 command "files touched by ≥ 2 `fix(` commits"; a commit-subject class repeating (`flip … status`, `re-stamp`, `backfill`); a `rev-` finding whose Follow-up is checked but whose symptom is back (**reopened class**); `fix_cycles` ≥ 2 on one binder.
- **Example:** Baseline 2026-09-02 — 10 "flip binder status → closed / re-stamp / backfill" commits between 2026-08-27 and 2026-09-02 (`2c5e3bf`, `47379e3`, `60e066a`, `64a6abd`, `c896957`, `052de11`, `abf8e0f`, `d17e1ca`, `45d18c8`, `dd144ba`); `finish-ledger.sh` in 15 `fix(` commits in 30 days, `validate-lattice-artifacts.py` in 13, `stamp-pr-open.sh` in 8. rev-20260902-015425Z F5 called the coordinator wiring gap "the same shape as rev-20260831's artifact-truth problem, one round later".

## T6 — invisible-queue

- **Detect:** `noticed.count` and the dates inside the lines vs the date of the last `rev-` that contains a NOTICED sweep (`grep -ln NOTICED <home>/reviews/*.md`); `needs-decision.md` rows without a resolution date; `## Pending decisions` entries older than the ticket's PR.
- **Example:** Baseline 2026-09-02 — 35 `- NOTICED:` lines in 15 binders, oldest 2026-08-27 (tkt-93/94); the only digest with a NOTICED sweep predates them (rev-20260827-023130Z), so nothing has been dispositioned. rev-20260827-033352Z F8 — rev-20260826-141124Z:116 listed debts "noticed, never filed".

## T7 — prose-vs-script ratio

- **Detect:** words in `SKILL.md` + `references/` vs script calls on the main path (`wc -w` vs `grep -c '\.sh\|\.py'`); a step that says "stamp / remember to / cd to the main clone and…"; hooks that intercept a command but the SKILL still tells the agent to run the follow-up by hand.
- **Example:** rev-20260902-015425Z F4 — finish-work 11.9k words, ~2.5 : 1 manual : scripted steps, and all four verified drifts were in the prose half. ADR-012 §1 is the mechanism answer ("stamps live at path points, never in prose"). Watch: after tkt-339 the `queued → in-progress` edge went from 1 to 15 ledger entries.

## T8 — artifact-truth

- **Detect:** `status_histogram` keys that are not schema words (`closed \|`); binder ↔ ledger last-state disagreement; `git ls-files -s` mode vs "executable" claims; a checked A* whose test file does not exist; validator warnings in the baseline file that never ratchet down.
- **Example:** rev-20260902-015425Z F1 — tkt-257 binder `closed`, ledger last entry `pr-open`. Baseline 2026-09-02: 15 binders whose 3-column `| status | closed | |` row parses as `closed |` (`queue_health.py:59`), so the terminal denominator is 151 instead of 166; `stamp-pr-open.sh` and `review-context.py` tracked as `100644` while their SKILLs name them as scripts.

## T9 — environment-dependence

- **Detect:** a probe/test that passes in CI and fails locally (or the reverse); tool version strings in NOTICED lines (`gh 2.92`, `bats 1.2.1`, BSD/bash-3.2); "plugin installed" assumed by docs (`~/.claude/plugins/installed_plugins.json`).
- **Example:** rev-20260902-015425Z F0 — the dogfood machine had no lattice plugin installed, so "machine-enforced" in `CLAUDE.md` was false locally, which is how hand edits reached `dev`. tkt-341 NOTICED — `ci-gate-check.sh` failed on gh 2.92 because `conclusion` is not a `gh pr checks --json` field (fixed by tkt-349; the doc line survived — T2). tkt-356 — BSD/bash-3.2 portability of the partial-line simulation.

## Using the taxonomy

- One Finding, one primary class; add a secondary in parentheses when the mechanism spans two (a T8 miscount caused by a T5 recurrence of parser bugs).
- Insights section: one bullet per class observed, with the base rate from the snapshot and the direction to watch next run.
- A class with **no** instance this run is worth one line ("T4 silent-bypass: 0 hand-edited status rows since the L3 hook — watch") — absence after a mechanism landed is the evidence the mechanism works.
