---
id: rev-20260826-145922Z-18p
slug: batch-dogfood-findings
title: Dogfood findings — first full spc-42 batch-work night run
kind: dogfood
status: concluded
outcome: spawn_tickets
summary: "27 findings from running the attention-loop batch on the engine itself: release-train version law, 5-place skill registration, marker noise, plus validated positives"
created: 2026-08-26
updated: 2026-08-26
related_specs: [spc-42]
related_tickets: [tkt-43, tkt-44, tkt-45, tkt-46, tkt-47, tkt-48, tkt-49, tkt-50]
related_prs: [pr-52, pr-53, pr-54, pr-55, pr-56, pr-57, pr-58, pr-59]
---

# Dogfood findings — first full batch-work night run (spc-42)

> **TL;DR:** The spc-42 train (8 tickets, 3 layers, 8 agents, 8 PRs, zero unattended merges) was executed with batch-work orchestration and host chain-review. 27 observations were logged; the systemic ones are: the per-PR plugin-version law conflicts with parallel delivery (solved in-run by a release-train convention — needs first-class support), "register a new skill" spans 5 uncoordinated places (2 of 5 were missed and caught late), and local verification lacked CI parity. Several spc-42 mechanisms were validated live (integration build, park-free night, stop conditions never needed, marker gate held). Outcome: spawn_tickets for the fixes below.
> **Kind:** dogfood · **Status:** concluded · **Outcome:** spawn_tickets

## Context

First end-to-end execution of the spc-42 attention-loop design *on the repo that defines it*: layers G1 (tkt-43/44/45) → G2 (46/47/48/49, concurrency 4) → G3 (50), one sibling worktree + batch marker per ticket, spawn briefs carrying the decision/fallback/evidence contracts, host review per layer, stacked integration bases between layers, and a closing chain review. Full raw log: 27 numbered observations (session scratchpad); distilled here.

## Problem Audit

Skipped — this review *is* the observation log of a live run; each finding carries its own evidence.

## Findings

1. **Release-train version law (was F21, HIGH — partially fixed in-run).** `validate-plugin-versions` demands a version increment per bundled-content PR vs its merge-base → every parallel PR must edit the same version/changelog files, which the create-tickets `paths` independence gate never modeled. All 6 skill PRs went red simultaneously. In-run solution, now documented in batch-work flow (#59): one byte-identical 0.2.0 cut committed to every train branch; branch-specific manifest edits ride their own branch; morning merges take the superset on conflict and prefer `--no-update-branch` when clean. **Remaining work:** validator "train mode" (compare against last release tag, or accept equal-version when the cut commit is shared) so the transient post-base-update red disappears; create-tickets paths gate should name implicit shared files.
2. **"Register a new skill" spans 5 uncoordinated places (F14+F23+F27, MED).** skills/dir · validate-skills `USER_FACING` · validate-skills.bats fixture list · plugin bundle symlink + manifest · README/getting-started tables. tkt-47 missed 2 of 5 (bundle symlink → host review; fixture → CI). Historic evidence: **batch-work, run-e2e, generate-wiki, review-code, review-production were never added to the plugin bundle symlinks**, and batch-work/run-e2e are absent from `USER_FACING` — silent gaps shipped for weeks. Fix: a new-skill checklist in CONTRIBUTING or a scaffold script + a validator that asserts skills/ dirs ⊆ registration surfaces.
3. **Local verification ≠ CI parity (F22, MED).** Spawn briefs ran 2 of the repo's 5 CI validators; the host review also skipped the CI axis it prescribes. Fix: a `ci-local` entry point (validate-skills + artifacts + plugin-versions + shellcheck + bats) wired into batch-work's evidence contract and the review checklist.
4. **Batch ergonomics debt (F6/F7/F13/F16, MED, partially fixed in-run).** Shared scratchpad collision between parallel agents (observed overwrite); untracked marker file spooks every `check-pr-context` run; public-repo "explicit confirm" is un-executable unattended; PR-URL-then-binder-stamp forces a two-commit dance. The first three are now brief-contract law in #59; remaining fixes: check-pr-context marker whitelist, a pr-open stamp helper (or create-pr owning the binder stamp).
5. **Integration mechanics (F1/F25, fixed in-run → #59 + #58).** Layer dependencies vs marker-blocked merges resolved by stacked integration bases (sequential merges only — octopus empirically fails on shared-file trains; superset rule for train-file conflicts). Now documented in batch-work flow and review-delivery axes.
6. **Small template/validator debts (F8/F9/F12/F17/F19/F20, LOW).** Binder `prs` row: no canonical filled format + duplicated by Lineage "Child PRs" + header `**Status:**` duplicates the table row (validator checks only the table); no validator cross-check of prs row vs GitHub; `update-pr-base.sh` lacks a machine-readable `diff_changed` signal for the A8 rebase-verdict rule; ensure-lattice vs lattice-init symlink-resolution asymmetry; label taxonomy drift (`documentation` vs docs-kind canon); finish-work mini-review text duplicated across SKILL.md/flow.md invites drift; workflow-fsm fuse-edge wording (`queued` vs `deferred`) needs one clarifying sentence.
7. **Validated positives (F15/F24/F26 + run facts).** The night contract held end-to-end: 8/8 agents stopped at create-pr (marker never violated); 0 parked decisions and 0 fallback stops were needed, and every agent journaled its decisions with chain citations — the front-loading (Approach + policies in briefs) plausibly caused this; the pre-merge integration build caught nothing structural because slices were genuinely disjoint, and went green including version law; CI's only red was one systemic cause, not scattered defects; host review + CI + a peer agent each caught a distinct defect class (bundle, fixture, doc-recipe) — three independent nets, all needed.

## Recommendations

1. File follow-up tickets (priority order): validator train mode + paths-gate shared-file modeling (Finding 1) · new-skill checklist/scaffold + registration validator + backfill missing bundle symlinks/`USER_FACING` entries (Finding 2) · `ci-local` parity runner (Finding 3) · check-pr-context marker whitelist + pr-open stamp helper (Finding 4) · the LOW batch in Finding 6.
2. Keep the release-train convention as the documented default for any multi-PR batch on this engine repo.
3. Re-run this dogfood on the *next* batch to measure whether Finding 7's zero-park/zero-stuck holds without the orchestrator improvising.

## Outcome (required to conclude)

**Outcome:** `spawn_tickets` — scope is clear per Recommendation 1; no new Spec needed (fits as hygiene/enhancement tickets, several citing spc-42).

### Follow-ups

- [x] Ticket: validate-plugin-versions train mode + create-tickets shared-file paths modeling → **tkt-60** (#60)
- [x] Ticket: new-skill registration checklist/scaffold + validator; backfill batch-work/run-e2e/generate-wiki/review-code/review-production into bundle + USER_FACING → **tkt-61** (#61)
- [x] Ticket: `ci-local` parity runner wired into batch-work evidence contract → **tkt-62** (#62)
- [x] Ticket: check-pr-context marker whitelist + pr-open binder stamp helper (+ issue-body acceptance sync, A1) → **tkt-63** (#63)
- [x] Ticket: merge-train hardening in finish-work + update-pr-base diff signal (F20 + A3) → **tkt-64** (#64)
- [x] Ticket (LOW, batchable): template/validator debts of Finding 6 → **tkt-65** (#65)

## Addendum — merge-train phase (post-digest)

Three more findings from executing the morning merge train itself:

- **A1 (gate catch, positive + gap):** `alignment-check` HARD-blocked the first merge because agents check binder acceptance but never sync the GitHub issue body's checkboxes — the gate worked; the gap is that no step owns issue-body sync (candidate: create-pr or the pr-open stamp helper does it).
- **A2 (guard catch):** `cleanup-workspace` refused a "dirty" worktree whose only dirt was the batch marker — the ad-hoc conflict path had skipped finish-work's marker-removal step. Guard correct; marker lifecycle must be in any train script.
- **A3 (orchestrator incident, severity high, repaired):** the train's conflict-resolution script ran `git add -A` before its unresolved-conflict check, committing conflict markers into `axes.md` on dev via PR #59's merge; caught by immediate post-merge inspection, repaired same-hour on dev (`fix: repair axes.md conflict markers…`). Lesson for the rework/merge tooling ticket: conflict resolution must be file-explicit (`checkout --ours/--theirs <path>` per named path), never `add -A`; and a post-merge marker sweep (`grep -r '<<<<<<<'`) belongs in the finish-work verification list.

## References

- Digest for this batch: `rev-20260826-145922Z`
- Spec: `spc-42` · ADR: `ADR-004` · PRs #52–#59
- Raw 27-item log: session scratchpad `dogfood-log.md` (distilled fully above)
