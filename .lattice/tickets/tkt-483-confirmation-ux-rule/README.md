# tkt-483-confirmation-ux-rule

> **TL;DR:** Add a shared rule that every skill confirmation marks one `(Recommended)` option and lists it first (dynamic for severity-conditional sites); yes/no states a lean + why. Fix all 9 enumerated-option sites.
> **Kind:** feat · **Priority:** P2
> **Path:** spc-482 → tkt-483 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/483 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-05T00:00:00Z |
| updated | 2026-09-05T00:00:00Z |
| adopted | false |
| summary | Confirmation-UX rule: mark recommended option + list first across all skills |
| spec | spc-482 — confirmation-UX rule (path: ../../specs/spc-482-confirmation-ux-rule.md) |
| covers | A1, A2, A3, A4 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | (serial) |
| paths | skills/_lattice-lib/references/**, skills/create-spec/**, skills/review-code/**, skills/finish-work/**, skills/create-pr/**, skills/create-tickets/** |
| solo_merge | yes |
| **primary_ticket** | tkt-483 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-483-confirmation-ux-rule` |
| worktree | sibling `…/lattice.worktrees/spc-482-confirmation-ux-rule/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A1** `_lattice-lib/references/confirmation-ux.md` exists with the DEFAULT rule (mark one `(Recommended)` + list first; yes/no states lean + why); linked from `skill-anatomy.md`.
- [ ] **A2** Every enumerated-option confirmation site in `create-spec`, `review-code`, `finish-work`, `create-pr`, `create-tickets` tags one recommended option and lists it first; conditional `finish-work` mini-review uses dynamic ordering (severity-default tagged `(Recommended)` and first).
- [ ] **A3** Rule covers yes/no soft-confirms; `create-pr` / `start-work` / `run-e2e` reference it and exemplify the lean.
- [ ] **A4** Each touched skill's verification checklist has an entry asserting the confirmation-UX rule.

## Approach

One cohesive skill-docs edit, one PR. Read-only dry-run done — touch-set confirmed. Add the shared rule file first (foundation), link it from `skill-anatomy.md`, then walk each enumerated-option site and (a) tag exactly one option `(Recommended)` and (b) reorder so it is first; for `finish-work` mini-review use dynamic ordering at presentation time. Append a verification checklist line to each touched skill. yes/no sites get a one-line lean where they currently ask bare.

Touch-set:
- `skills/_lattice-lib/references/confirmation-ux.md` (new)
- `skills/_lattice-lib/references/skill-anatomy.md`
- `skills/create-spec/SKILL.md`
- `skills/review-code/SKILL.md`
- `skills/finish-work/SKILL.md`
- `skills/finish-work/references/flow.md`
- `skills/create-pr/references/workflow.md`
- `skills/create-tickets/references/flow.md`

## Anticipated decisions

- `(Recommended)` label wording — disposition: pre-resolved (Spec D1 / host AskUserQuestion convention: "(Recommended)" suffix, first option).
- Conditional-site ordering — disposition: pre-resolved (Spec D2: dynamic ordering at presentation time).
- create-pr unexpected-diff default — disposition: pre-resolved (Spec D3: `exclude`).
- yes/no coverage — disposition: pre-resolved (Spec D4: lean + one-line why).
- Whether to rewrite per-site yes/no prose vs. rely on the shared rule — disposition: agent-decides (reversible, ticket-local; prefer one exemplar per skill + rule reference over mass rewrite).

## Decision journal

<!-- Append-only during execution. -->

## Pending decisions

(none — all principals pre-resolved in Spec D1–D4)

## Attempts

(none yet)

## Notes

- Path-overlap across skills → one-PR / one-worktree (rule 9).
- Worktree currently bound to spc-482; start-work rebinds to tkt-483.

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-482` (`.lattice/specs/spc-482-confirmation-ux-rule.md`)
- Worktree policy: one tree ↔ one PR; spc|tkt open binds

## Lineage

- Parent spec: **spc-482**
- Parent issue (GH sub-issue of Spec primary): **#482**
- Primary ticket: **tkt-483**
- Related / sub-tickets: (none)
- Covers: **A1, A2, A3, A4**
- Blocked by: (none)
- Merge blocked by: (none)
- Parallel group: (serial)
- Worktree bind: `spc-482-confirmation-ux-rule` → `tkt-483-confirmation-ux-rule`
- Child PRs: (none yet)

## Assets

(none)

## Finish

- (none yet)
