# tkt-82-zh-readme-sync

> **TL;DR:** Port tkt-75's English README updates (13-skill tables, corrected packaging claims) into README.zh-CN.md
> **Kind:** docs · **Priority:** P3
> **Path:** (ticket-only) → tkt-82 → (pr-…)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P3 |
| labels | documentation, P3 |
| github | https://github.com/percena/lattice/issues/82 |
| status | in-progress |
| adopted | false |
| summary | zh README catches up with the English README's current skill reality |
| spec | none — digest finding (rev-20260826-172600Z F7), noticed-by tkt-75 |
| covers | digest F7 |
| blocked_by | #75 (port its merged English wording, not a moving target) |
| parallel_group | G1 (parallel) |
| paths | README.zh-CN.md |
| solo_merge | yes |
| **primary_ticket** | tkt-82 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-82-zh-readme-sync |
| worktree | sibling …/lattice.worktrees/tkt-82-zh-readme-sync/ |
| prs | (none) |

## Acceptance (this slice)

- [ ] README.zh-CN tables/claims enumerate the same skills as the English README with equivalent wording intent; existing zh voice/structure preserved

## Approach

Diff README.md (post-#77) against README.zh-CN.md section by section; port the skill-table rows, tier notes, and corrected packaging claims; translate faithfully rather than restructure. Verify by listing both files' table rows side by side in the PR body.

## Anticipated decisions

- Terminology for new concepts (e.g. 链路审查 for chain review) — disposition: agent-decides (follow the zh doc's existing glossary habits; journal choices)

## Decision journal

- "chain review" → **链路审查** — 1 (binder Approach anticipated this term; zh doc already renders "chain" as 链路 in 理念 section: "链路不跳步", "链路可续作") — reversible, ticket-local
- "unattended" → **无人值守** (batch-work row); "attended" → **有人值守** (day-phase doc row) — 5, codebase convention (standard zh ops term pair; no prior zh rendering in doc) — reversible, ticket-local
- **attestation / mini-review / artifact kept in English** (逐轴 attestation, mini-review 扫描, 仅产出 artifact) — 5, codebase convention (zh doc's glossary habit retains English jargon: fail-loud, outcome, story, runner, sibling, base) — reversible, ticket-local
- "ranked morning digest" → **按优先级排序的晨间摘要** — 5, most natural zh rendering consistent with digest artifacts' own zh-free naming; digest itself stays untranslated concept-wise — reversible, ticket-local
- Tier-table intro count: **分五类** (count-accurate to the 5 rows after adding review-delivery), NOT a literal port of EN's "three tiers" — 5, codebase convention (zh doc's existing habit was count-accurate: said 四类 for its 4 rows). EN's "three tiers" looks stale vs its own 5 rows → noticed-but-not-touched (README.md out of scope) — reversible, ticket-local
- Added missing **workflow-fsm / day-phase rows to the zh docs table** — same-file catch-up beyond the skill tables; 1 (binder summary: "zh README catches up with the English README") + reversible, ticket-local (paths: README.zh-CN.md only)
- Packaging claim "六个技能": **no such claim exists in README.zh-CN.md** (verified `grep 六` — empty); the six-skills claim lived in getting-started, fixed by #77, out of this ticket's paths — nothing owed here

## Pending decisions

## Attempts

## Notes

- Docs-only: no version bump; CI path-filtered

## References

- Digest: `rev-20260826-172600Z` Finding 7 · tkt-75 audit table (PR #77 body)

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: **tkt-82** · Parallel group: **G1** · Worktree bind: `tkt-82-zh-readme-sync`

## Finish

- (none yet)
