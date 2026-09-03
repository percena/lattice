# tkt-437-review-code-auto-decided

> **TL;DR:** Add Auto-Decided line highlighting to review-code docs-sync axis
> **Kind:** feat · **Priority:** P2
> **Path:** spc-433 → tkt-437 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | feat, P2 |
| github | https://github.com/percena/lattice/issues/437 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-03T16:00:00Z |
| updated | 2026-09-03T16:00:00Z |
| adopted | false |
| summary | review-code Auto-Decided highlighting in docs-sync axis |
| spec | spc-433 — Vibe Coding 流程优化 (path: ../../specs/spc-433-vibe-coding-flow-optimization.md) |
| covers | A5 |
| blocked_by | #434 |
| merge_blocked_by | #434 |
| parallel_group | G1 |
| paths | skills/review-code/** |
| solo_merge | yes |
| autonomy | 3 |
| **primary_ticket** | tkt-437 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-437-review-code-auto-decided |
| worktree | sibling |
| prs | (none) |

## Acceptance (this slice)

- [x] **A5** review-code 在审阅时默认高亮 `Auto-Decided` 标记的代码行，列入重点审阅清单

## Approach

Add a sub-check to the docs-sync axis in review-code: scan the diff for `Auto-Decided:` comment markers (format: `// Auto-Decided: <reason>` per spec decision 3). Collect matched lines with file:line + reason. Emit them as a dedicated "Auto-Decided lines" subsection in the review output, flagged for priority human review. If no Auto-Decided lines found, report "none" (clean).

The check fits naturally in `references/docs-sync.md` as a new subsection, and in `references/finding-contract.md` §Dig deeper as a prompt for assessing uncited self-decisions. The `review-context.py` script could optionally collect Auto-Decided lines via a `--auto-decided` flag (grep the diff for the marker), but the minimal implementation is a model-driven scan in the docs-sync axis step.

Touch-set:
- `skills/review-code/SKILL.md` — docs-sync axis: add Auto-Decided sub-check
- `skills/review-code/references/docs-sync.md` — Auto-Decided scan + output format
- `skills/review-code/references/finding-contract.md` — Auto-Decided as dig-deeper prompt

## Anticipated decisions

- Auto-Decided marker format: `// Auto-Decided: <reason>` (spec decision 3) — disposition: pre-resolved(spec decision 3)
- output placement: dedicated subsection in review output, not inline in findings — disposition: pre-resolved(dry-run: review-code has axis subsections)
- whether to use review-context.py or model scan: — disposition: agent-decides (both are reversible; model scan is simpler for v1)
- severity: Auto-Decided lines are "priority review" not "material finding" by default — disposition: pre-resolved(decision-policy.md: self-decisions are journaled, not bugs)

## Decision journal

(append-only during execution)

## Pending decisions

- Should Auto-Decided highlighting also check the PR body `## Auto-Decided` section for completeness (code markers vs PR section cross-check)? Nice-to-have but not required for A5.

## Attempts

(none yet)

## Notes

This ticket is independent of tkt-435 and tkt-436 (no path overlap). It can proceed in parallel once tkt-434 (autonomy field) lands.

## References

- Spec: `spc-433`
- Blocked by: tkt-434 (needs autonomy field for context)
- decision-policy.md (defines self-decision chain — review-code consumes the contract)

## Lineage

- Parent spec: **spc-433**
- Parent issue: **#433**
- Primary ticket: **tkt-437**
- Covers: **A5**
- Blocked by: #434
- Merge blocked by: #434
- Parallel group: G1
- Worktree bind: tkt-437-review-code-auto-decided

## Assets

(none)

## Finish

- (none yet)
