---
id: rev-20260827-033352Z
slug: post-round4-verified-audit
title: Post-round-4 verified audit — binder lifecycle contract breach, CI enforcement gaps, surface drift
kind: findings
status: concluded
outcome: spawn_tickets
summary: "Full-repo audit after rounds 1-4, every finding hand-verified: finish-ledger never closes pr-open binders (19 stranded), the artifacts validator is not in CI and push CI ignores dev, prs-row grammar split across 4 implementations, check-duplicate-work fails open, registration surfaces drift where no validator looks"
created: 2026-08-27
updated: 2026-08-27
related_specs: []
related_tickets: [tkt-90, tkt-91, tkt-92, tkt-93, tkt-94, tkt-95, tkt-96]
related_prs: [pr-97, pr-98, pr-99, pr-100, pr-101, pr-102, pr-103]
---

# Review: Post-round-4 verified audit

> **TL;DR:** Operator-requested audit of the last 24h of delivery (rounds 1–4, PRs #52–#89). Every finding below was hand-verified against the working tree at `f9568a3` — line numbers cited are real. One systemic contract breach (F1), one systemic enforcement gap (F3), and a family of surface drifts that share a single root cause: **surfaces with a validator stay fresh; surfaces without one rot.** Outcome: seven tickets.
> **Kind:** findings · **Status:** concluded · **Outcome:** spawn_tickets
> **Next:** tkt-90…tkt-96 — delivered same day as PRs #97–#103 (order: #100→#103, #101→#102; #97/#98/#99 free); merges are the operator's

## Method

Four parallel audit sweeps (process artifacts, packaging, tools/tests, docs) followed by manual re-verification of every claim — regex/branch inspection, run-log pulls, and count checks. Claims that did not reproduce were dropped. `ci-local.sh` is green (19/19) at `f9568a3`; every finding below is invisible to the current gates.

## Findings (verified)

### F1 — finish-ledger never closes FSM-era binders; 19 stranded at `pr-open` [SEV: high]

`skills/_lattice-lib/scripts/finish-ledger.sh:392` flips only the legacy literal:
`re.sub(r'(\| status \|)\s*open\s*(\|)', r'\1 closed \2', s)` — while `stamp-pr-open.sh` (tkt-63) stamps `pr-open`, the normal path for every PR ticket. Verified: **19 binders** carry a merged `## Finish` ledger and `status: pr-open` (tkt-44, 46–50, 60–65, 73–75, 80–82, 84). Violates spc-42:76 ("binder field-table status is the single source of truth"). `skills/finish-work/SKILL.md:111` documents the flip that does not happen. tkt-44 (FSM) and tkt-63 (stamp) broke each other; the fixture in finish-ledger's bats only ever uses `open`.

### F2 — the validator cannot see F1, and three docs claim it can [SEV: high]

`tools/validate-lattice-artifacts.py` has `closed_without_finish` (line 357) but no inverse (merged Finish ⇒ terminal status) and **no transition checking of any kind** — yet `docs/workflow-fsm.md:142`, ADR-004 §6, and `CHANGELOG.md` (0.2.0 entry) all say it "rejects … illegal transitions". The round-4 "zero warnings repo-wide" milestone is a coverage artifact. Also verified: no duplicate-binder-id check (`tkt-35-*` exists twice since round 0, flagged in rev-20260826-141124Z:116, never filed).

### F3 — CI enforcement gaps: the L0 validator runs nowhere in CI, and push CI ignores `dev` [SEV: high]

`grep -r validate-lattice-artifacts .github/` → no hits; the artifact contract is enforced only when an agent voluntarily runs `ci-local`. All four workflows trigger `push: branches: [main]` while the integration branch is `dev` — **no post-merge run has ever validated the combined tree of dev**. Run history (last 200): 38 failure + 2 startup_failure + 22 cancelled. Recurring red causes, none ever dispositioned: (a) `validate-plugin-versions` "bundled content changed without a version increment" races during trains (hit again on tkt-84 at 02:19Z *after* tkt-60's train fix); (b) bats reds mid-flight fixed by later pushes; (c) platform event outages (startup_failure, empty jobs — the round-3 Finding 2 outage). Reds are cured by later green pushes and never triaged — the operator has noticed this repeatedly.

### F4 — prs-row grammar: one canon, four implementations, two writers off-canon [SEV: medium]

Validator canon (`PRS_ROW_CANON_RE`, tools/validate-lattice-artifacts.py:58): comma-joined `pr-N — URL`. But `stamp-pr-open.sh:325` and `finish-ledger.sh:408` append with ` · ` (the joiner tkt-74 explicitly rejected), and `finish-ledger.sh:398` emits bare `pr-N` when the URL lookup fails — so the **second PR on any ticket deterministically re-creates the warning class tkt-80 just cleaned to zero**. `build-review-context.sh:409` matches only literal `(none)`/`(none yet)`, so decorated placeholders read as filled and the gh fallback never fires.

### F5 — check-duplicate-work fails open [SEV: medium]

`skills/_lattice-lib/scripts/check-duplicate-work.sh` (303 lines, default-on in two skills, zero tests): no `jq` preflight and every `gh|jq` failure collapses to empty → prints "OK no possible overlap found", contradicting its own line-27 principle; `set -eu` without `pipefail` (only lib script missing it); documented CJK OR-branch ("shared CJK run ≥3 chars") is not implemented — all three match sites are bare `[[ $SHARED -ge 2 ]]`, so CJK titles (1 run = 1 token) can never match; `--title` with no value hits `$2: unbound variable` instead of the advertised advisory exit 0.

### F6 — registration surfaces drift exactly where no validator looks [SEV: medium]

Verified matrix: `marketplace.json` keywords lack `review-delivery`, `review-production`, `generate-wiki`; `plugin.json` keywords lack `review-production`, `generate-wiki`; the two manifests disagree with each other. `plugins/lattice/README.md` documents 8 of 14 shipped units and heads its hooks section "0.1.x". `llms.txt` predates six releases: 10 of 13 skills, two dead README anchors. `skills/_lattice-lib/SKILL.md` says "six user-facing skills" and its script table lists 11 of 18 (omitting 0.2.3 headliners `stamp-pr-open.sh`, `build-review-context.sh`). `tools/run-routing-evals.py:27` hardcodes a 10-skill catalog (missing `batch-work`, `run-e2e`, `review-delivery` — exactly the three skills with no tests/evals of any kind). Root cause: CONTRIBUTING's new-skill checklist omits these surfaces; `docs/getting-started.md` — which *is* on the checklist — is fully current.

### F7 — doc claims contradicting shipped reality [SEV: low, wide]

ADR-002 §3 still specifies the `BATCH_WORK=1` env gate replaced by the `.lattice/.batch-work-active` marker in 0.2.0 (no amendment; ADR-004 cites ADR-002, ADR-002 says "Related: none"). `README.md:83` "three tiers" over a five-row table (zh side is correct). `finish-work/SKILL.md` rule numbering duplicates 8 and 12 (noticed in two digests). `docs/getting-started.md` omits the `preferences.md` scaffold from both "what ensure-lattice does" and "what gets committed". `docs/day-phase.md:38` says tkt-48's mechanism is "landing separately" (landed). `CHANGELOG.md:11` calls 0.2.3 "single-PR bump" (it was a two-PR shared train cut). `workflow-fsm.md` M3 lacks the pr-88 direct-capture edge; `rework → pr-open` (start-work:88) is in no table/diagram. `.lattice/config.yaml` documents none of the batch tunables batch-work reads.

### F8 — artifact hygiene left open by rounds 1–4 [SEV: low]

`spc-12` still `status: locked`, A1–A4 unchecked, `prs: []`, though all four tickets closed (the dev→main ledger-bypass debt named in rev-20260826-141124Z:116, never filed). `tkt-65:34` unchecked though delivered by tkt-74 — and now un-stampable: `--check-all` refuses on its "deferred" note. Round-4 digest's train-mode evidence line ("release-train cut shared with base") was never recorded. `strip-quoted-and-heredocs.bats:178,197` use bare `${BATS_TEST_TMPDIR}` — under local bats 1.2.1 the two "must not execute" security assertions are vacuously true (tkt-62 journal named these lines; fix never applied). `build-review-context.sh` ADR scan reads local binders under `--from-heads`.

## Process observation (the operator's actual question)

The loop's fast paths demonstrably work (4 zero-park nights, utterance→law in one wave, 4 self-verified tools). The failures cluster in three structural holes, and each spawned ticket pairs a repair with the *mechanism* that prevents recurrence:

1. **Enforcement asymmetry** — laws exist as prose; only symlinks/frontmatter have validators, so only those stay true (F1/F2/F6). Mechanism: every law lands with its check (tkt-90/91/94).
2. **Red-run leak** — CI reds are cured by later greens, never dispositioned; nothing owns "why was that red?" (F3). Mechanism: red-disposition duty + dev-branch CI (tkt-92).
3. **Out-of-paths observation leak** — noticed defects have no capture channel unless a human reads the digest; same items recur across rounds (F7/F8 items were all *noticed* before). Mechanism: capture duty for agent observations, mirroring tkt-84's operator-preference duty (tkt-96).

## References

- Prior: rev-20260827-023130Z (round-4 digest) · rev-20260826-141124Z (design rev; :116 named F2/F8 debts)
- Verification base: `f9568a3` · run-log evidence: gh runs 33032948048, 32988009357, 32987857891, 32985801055
