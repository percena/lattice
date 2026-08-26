# tkt-47-review-delivery

> **TL;DR:** New review-delivery skill — artifact-only chain review (A* fidelity, cross-PR coherence, decision queue, per-PR findings) + build-review-context.sh + ranked morning digest with attestation
> **Kind:** feat · **Status:** open · **Priority:** P2
> **Path:** spc-42 → tkt-47 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/47 |
| status | open |
| adopted | false |
| summary | review-delivery skill + context bundle script + morning digest (auto-pass / ratify / deep-review triage, promotion proposals) |
| spec | spc-42 — Attention loop (path: ../../specs/spc-42-attention-loop.md) |
| covers | A6, A3 |
| blocked_by | #44 |
| parallel_group | G2 (parallel) |
| paths | skills/review-delivery/ (new), skills/_lattice-lib/scripts/build-review-context.sh (new), skills/_lattice-lib/scripts/tests/, README.md, docs/getting-started.md |
| solo_merge | yes |
| **primary_ticket** | tkt-47 (this issue) |
| **related_tickets** | tkt-46 (preferences lifecycle this digest renders proposals for) |
| **worktree_bind** | tkt-47-review-delivery |
| worktree | sibling …/lattice.worktrees/tkt-47-review-delivery/ |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A6** review-delivery skill exists: input `spc-N | --ids tkt list | batch report`; context assembled exclusively from durable artifacts via `build-review-context.sh` (Spec, ADRs, binders incl. journals/attempts, PR bodies+diffs, batch report, test evidence — never implementer transcripts; artifact insufficiency is itself a finding); four axes (semantic A*→evidence fidelity incl. orphan criteria and ticket-less code; cross-PR coherence incl. throwaway pre-merge integration build in DAG order; decision-ratification queue; per-PR findings reusing the review-code contract); morning digest triages every PR `auto-pass | ratify-then-pass | deep-review` with recommended merge order; per-axis attestation mandatory (no bare LGTM); never merges
- [ ] **A3** (completion) digest renders preference-promotion proposals for decision-journal entries ratified ×2

## Notes

- Reuses the review-code finding contract for the per-PR axis — do not fork a parallel contract (containment, like finish-work's mini-review)
- Digest persists under `.lattice/reviews/` (kind: digest) + stdout; never a merge gate — merge authority stays with finish-work + human
- Trust calibration hooks (sampling convention, escaped-defect metric) documented in the skill; metric tooling itself is out of spc-42 scope

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-42` (path above)
- ADR: `ADR-004` §4
- Review: `rev-20260826-141124Z` Finding 6

## Lineage

- Parent spec: **spc-42**
- Parent issue (GH sub-issue): **#42**
- Primary ticket: **tkt-47**
- Related / sub-tickets: tkt-46
- Covers: **A6, A3 (completion)**
- Blocked by: **#44**
- Parallel group: **G2 (parallel)**
- Worktree bind: `tkt-47-review-delivery`
- Child PRs: (none yet)

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
