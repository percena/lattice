# tkt-14-bug-repro-loop

> **TL;DR:** Pre-fix reproduction / post-fix verification loop for bug-class tickets in start-work CLASSIFY step
> **Kind:** feat · **Status:** open · **Priority:** P2
> **Path:** spc-12 → tkt-14 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/14 |
| status | open |
| adopted | false |
| summary | pre-fix reproduction / post-fix verification loop in start-work for bug-class tickets |
| spec | spc-12 — Lattice skill-gap bridge (path: ../../specs/spc-12-skill-gap-bridge.md) |
| covers | A3 |
| blocked_by | (none — same PR as tkt-13, not a dependency) |
| parallel_group | G2 (serial) |
| paths | skills/start-work/SKILL.md |
| solo_merge | no (rides on tkt-13's PR) |
| **primary_ticket** | tkt-13 (duplicate-work precheck is primary of this PR) |
| **related_tickets** | tkt-13 (same PR) |
| **worktree_bind** | tkt-13-duplicate-work-precheck (shared with primary) |
| worktree | sibling …/lattice.worktrees/tkt-13-duplicate-work-precheck/ |
| prs | (none) |

## Acceptance (this slice)

- [x] **A3** start-work CLASSIFY step identifies bug-class tickets and runs Phase 0c (reproduce from ticket Reproduction Steps, capture evidence in binder `reproduction-evidence.md`; if no longer reproduces, consider wont-fix) → Phase 1 (fix) → Phase 1b (re-verify, cross-comparison table, max 2 cycles)

## Notes

- Shares start-work/SKILL.md path with tkt-13 → one-PR, one worktree
- tkt-13 is the primary ticket; this rides as related_ticket
- ERP reference: implement Step 0c (Pre-Fix Reproduction, HARNESS-970) + Step 1b (Post-Fix Verification)
- Existing DEFAULT "no forced TDD" preserved for non-bug tickets

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-12` (path above)
- ADR: `ADR-002` → `docs/adr/002-lattice-skill-gap-bridge-adaptations.md`
- Review: `rev-20260825-072540Z` Finding 3
- ERP reference: `FlowDance ERP skill: implement/references/step-0c-pre-fix-reproduction.md`, `step-1b-post-fix-verification.md`

## Lineage

- Parent spec: **spc-12**
- Parent issue (GH sub-issue): **#12**
- Primary ticket: **tkt-13** (not this issue)
- Related / sub-tickets: **tkt-13** (same PR)
- Covers: **A3**
- Blocked by: (none)
- Parallel group: **G2 (serial)**
- Worktree bind: `tkt-13-duplicate-work-precheck` (shared)
- Child PRs: (none yet)

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
