# tkt-33-batch-work-marker-fix

> **TL;DR:** Replace unreliable BATCH_WORK=1 env-var gate with a marker-file mechanism that survives across Bash sessions
> **Kind:** fix · **Priority:** P2

| Field | Value |
| --- | --- |
| kind | fix |
| priority | P2 |
| labels | bug, P2 |
| github | https://github.com/percena/lattice/issues/33 |
| status | closed |
| adopted | false |
| summary | fix BATCH_WORK=1 enforcement — env var → marker file |
| spec | (none — review-fix) |
| covers | A1 |
| blocked_by | (none) |
| parallel_group | (none) |
| paths | skills/batch-work/SKILL.md, skills/batch-work/references/flow.md, skills/finish-work/SKILL.md |
| solo_merge | no (rides with tkt-31) |
| **primary_ticket** | tkt-31 |
| **related_tickets** | tkt-31, tkt-32, tkt-34 |
| **worktree_bind** | tkt-31-run-e2e-symlink-fix (shared) |
| prs | pr-36 — https://github.com/percena/lattice/pull/36 |

## Acceptance (this slice)

- [x] **A1** finish-work gate detects batch-work mode via a marker file (e.g. `<worktree>/.lattice/.batch-work-active`) that survives across Bash sessions, not via env var alone; batch-work orchestrator writes the marker before spawning agents; finish-work prints clear guidance and the marker lifecycle is handled (removed after human runs finish-work)

## Notes

- Source: review-code pass on dev→main change set (2026-08-25)
- Root cause: Claude Code Bash sessions are ephemeral — env vars don't persist across calls
- Agent tool has no env-var parameter; prompt-text `BATCH_WORK=1` is not in the shell environment

## References

- GitHub issue body is SoT for long prose

## Finish

- pr-36 merged: 2026-08-25T09:45:49Z — https://github.com/percena/lattice/pull/36 (base merge)
- issue #33 closed: 2026-08-25T09:46:40Z — https://github.com/percena/lattice/issues/33
