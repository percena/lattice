# tkt-61-skill-registration

> **TL;DR:** New-skill registration integrity — CONTRIBUTING checklist, validator check (skills/ ⊆ registration surfaces), backfill 5 skills missing from the plugin bundle
> **Kind:** chore · **Priority:** P2
> **Path:** (ticket-only) → tkt-61 → (pr-…)

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P2 |
| labels | chore, P2 |
| github | https://github.com/percena/lattice/issues/61 |
| status | queued |
| adopted | false |
| summary | registration-integrity validator + bundle symlink backfill (batch-work, run-e2e, generate-wiki, review-code, review-production) + USER_FACING adds |
| spec | none — hygiene from dogfood review |
| covers | rev-20260826-145922Z-18p Finding 2 |
| blocked_by | (none) |
| parallel_group | G1 (parallel) |
| paths | plugins/lattice/skills/, plugins/lattice/.claude-plugin/plugin.json, tools/validate-skills.sh, tools/tests/validate-skills.bats, CONTRIBUTING.md |
| solo_merge | yes |
| **primary_ticket** | tkt-61 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-61-skill-registration |
| worktree | sibling …/lattice.worktrees/tkt-61-skill-registration/ |
| prs | (none) |

## Acceptance (this slice)

- [ ] All shipped skills present in bundle symlinks + USER_FACING (or documented exemption); registration-integrity check fails on an unregistered skills/ dir; bats green
- [ ] CONTRIBUTING new-skill checklist (5 surfaces) added

## Approach

Backfill `plugins/lattice/skills/` symlinks (3-level relative, mirroring existing) for the 5 missing skills; add batch-work + run-e2e to `USER_FACING` and to the bats green-fixture list; new check in `validate-skills.sh`: iterate `skills/*/` dirs, assert membership in USER_FACING ∪ EXEMPT (document `_lattice-lib` as exempt) and presence in `plugins/lattice/skills/`; CONTRIBUTING gains the 5-surface checklist. **Bundled change → version bump required at land (train rule if landed with siblings).**

## Anticipated decisions

- Exempt-list mechanism (inline array vs marker file) — disposition: agent-decides
- Whether generate-wiki/review-* need plugin.json keyword entries too — disposition: agent-decides (match existing precedent)

## Decision journal

## Pending decisions

## Attempts

## Notes

- Historic evidence: these 5 skills shipped for weeks without reaching plugin installs; tkt-47 missed 2 of 5 surfaces in-flight
- symlink-integrity CI job must stay green — verify link depth against existing entries

## References

- Review: `rev-20260826-145922Z-18p` Finding 2

## Lineage

- Parent spec: none (ticket-only)
- Primary ticket: **tkt-61** · Covers: Finding 2 · Parallel group: **G1** · Worktree bind: `tkt-61-skill-registration`
- Child PRs: (none yet)

## Finish

- (none yet)
