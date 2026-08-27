---
id: rev-20260827-023130Z
slug: round4-night-digest
title: Morning digest — round-4 night (tkt-80/81/82/84, PRs 86–89)
kind: digest
status: concluded
outcome: inform_only
summary: "4/4 delivered incl. a mid-night operator-feedback ticket; fourth zero-park/zero-stuck night; --from-heads and --check-all self-verified; shared 0.2.3 cut staged for the first live train-mode merge"
created: 2026-08-27
updated: 2026-08-27
related_specs: []
related_tickets: [tkt-80, tkt-81, tkt-82, tkt-84]
related_prs: [pr-86, pr-87, pr-88, pr-89]
---

# Morning digest — round-4 night

> **TL;DR:** Four tickets delivered (PRs #86–#89), including tkt-84 — filed FROM live operator feedback mid-night ("preference capture must be proactive") and shipped the same night as decision-policy law. Fourth consecutive zero-park/zero-stuck run. Two round-2/3 tools verified themselves in the field (`--from-heads` read this digest's own context from PR heads; `--check-all` stamped its author's binder). The two bundled PRs share a byte-identical 0.2.3 cut — merging them is the FIRST LIVE TEST of tkt-60's train mode. No merges performed; morning decisions are the operator's.
> **Kind:** digest · **Status:** concluded · **Outcome:** inform_only

## Triage

| PR | Ticket | Verdict | Notes |
| --- | --- | --- | --- |
| #89 | tkt-81 helper polish + 0.2.3 | **auto-pass** | All 5 scope items; full ci-local 18/18 at 0.2.3; parked `--check-all` default implemented as ratified-by-default (deferral → refuse); stamped its own binder with its own new flag |
| #88 | tkt-84 preference capture | **auto-pass** | Operator feedback → law in one night: decision-policy "Capture duty" INVARIANT + routing heuristic + 3-skill wiring; carries the shared 0.2.3 cut |
| #86 | tkt-80 prs-row cleanup | **auto-pass** | 13 rows canonicalized format-only (2 verified read-only via gh); repo-wide validator at ZERO warnings |
| #87 | tkt-82 zh README sync | **auto-pass** | 13-skill parity (zh doc was missing review-delivery entirely); terminology journaled (链路审查 etc.) |

## Attestation

- **A-fidelity:** every PR's diff reviewed against issue/binder acceptance; stamp-pr-open mirrored all issue boxes; tkt-81's parked decision resolved per its recorded default and journaled.
- **Cross-PR coherence:** sequential integration (dev + 4 heads, shared cut included) merged **clean**; full `ci-local` green on the combined tree; artifacts validator **zero warnings repo-wide** (first time ever).
- **Decision queue:** all journals chain-cited; 0 pending. One ratified-by-default worth operator eyes: `--check-all` refuses on deferral notes (safe direction; objection window open).
- **CI:** per-branch runs triggered by the night's pushes — verify rollups at merge time per the checks gate (the smart-retry preference now governs anomalies).

## The train-mode moment (morning)

Merge `#89` first (0.2.3 lands on dev), then `#88`: its version files are byte-identical blobs to the new base while bundled content changed — `validate-plugin-versions` should print the **"release-train cut shared with base — equal version 0.2.3 accepted"** path. Run it locally on #88's branch with `--base-ref dev` post-#89-merge and record the line — that closes the loop on round-1's biggest pain with machine evidence. Then `#86 → #87` (order free). Note for the merge step: the 0.2.3 CHANGELOG entry describes tkt-81's items; append one line for #88's capture law at merge or as a trailing chore (also update preferences.md's "being encoded via tkt-84" trailer to "encoded, pr-88").

## Findings (small, all non-blocking)

1. English README tier intro says "three tiers" over five rows (tkt-82 noticed; en-side) — one-line fix candidate.
2. build-review-context's ADR scan still reads local binders under `--from-heads` (author-noticed) — minor under-report; micro-item.
3. finish-work SKILL.md's pre-existing duplicate rule numbering (two 8s, two 12s) — cosmetic, noticed twice now; one-line renumber candidate.
4. preferences.md meta-entry trailer + 0.2.3 changelog line — the merge-time touch-ups above.

## Measurement

Fourth consecutive zero-park/zero-stuck night. New this round: an operator-feedback item entered the loop mid-night and shipped before morning — the capture→law latency was one wave. Tool self-verification count now 4 (stamp-pr-open, ci-local, --from-heads, --check-all).

## References

- Context: `build-review-context.sh --ids 80,81,82,84 --from-heads` (its own first field use)
- Prior digests: rev-20260826-145922Z · rev-20260826-160233Z · rev-20260826-172600Z
