# tkt-34-docs-sync-new-skills

> **TL;DR:** Sync README, README.zh-CN, getting-started, CHANGELOG, plugin.json for new skills (batch-work, run-e2e) and feature additions
> **Kind:** docs · **Status:** open · **Priority:** P2

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P2 |
| labels | documentation, chore |
| github | https://github.com/percena/lattice/issues/34 |
| status | closed |
| adopted | false |
| summary | sync README/docs/CHANGELOG for new skills (batch-work, run-e2e) |
| spec | (none — review-fix) |
| covers | A1, A2, A3 |
| blocked_by | (none) |
| parallel_group | (none) |
| paths | README.md, README.zh-CN.md, docs/getting-started.md, CHANGELOG.md, plugins/lattice/.claude-plugin/plugin.json |
| solo_merge | no (rides with tkt-31) |
| **primary_ticket** | tkt-31 |
| **related_tickets** | tkt-31, tkt-32, tkt-33 |
| **worktree_bind** | tkt-31-run-e2e-symlink-fix (shared) |
| prs | (none) · pr-36 — https://github.com/percena/lattice/pull/36 |

## Acceptance (this slice)

- [x] **A1** README.md + README.zh-CN.md Skills tables include `batch-work` and `run-e2e`; loop diagram shows batch-work as optional parallel path
- [x] **A2** docs/getting-started.md lists `batch-work` and `run-e2e` in the skill listing
- [x] **A3** CHANGELOG.md [Unreleased] has entries for: batch-work skill, run-e2e skill, start-work bug repro loop, finish-work Privacy/Secrets axis + BATCH_WORK gate, check-duplicate-work.sh script

## Notes

- Source: review-code pass on dev→main change set (2026-08-25)
- No closed-source project names, local paths, or credentials in updated docs (per global privacy rule)

## References

- GitHub issue body is SoT for long prose

## Finish

- pr-36 merged: 2026-08-25T09:45:49Z — https://github.com/percena/lattice/pull/36 (base merge)
- issue #34 closed: 2026-08-25T09:46:43Z — https://github.com/percena/lattice/issues/34
