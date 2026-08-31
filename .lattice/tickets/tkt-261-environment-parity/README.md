# tkt-261-environment-parity

> **TL;DR:** Both CIs pin same Bats; ci-local degraded/fail on mismatch; drift check runs in dev mode only
> **Kind:** feat · **Status:** queued · **Priority:** P2
> **Path:** spc-254 → tkt-261 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | feat,P2 |
| github | https://github.com/percena/lattice/issues/261 |
| status | queued |
| adopted | false |
| summary | Both CIs pin same Bats; ci-local degraded/fail on mismatch; drift check runs in dev mode only |
| spec | spc-254 — Executable workflow contracts (path: ../../specs/spc-254-executable-workflow-contracts.md) |
| covers | A9 |
| blocked_by | (none) |
| parallel_group | l1-independent |
| paths | .github/workflows/*.yml, tools/ci-local.sh, check-installed-skill-drift.sh |
| solo_merge | yes |
| primary_ticket | tkt-261 |
| related_tickets | (none) |
| worktree_bind | tkt-261-environment-parity |
| prs | (none) |
| created | 2026-08-31T00:00:00Z |
| updated | 2026-08-31T00:00:00Z |

## Acceptance (this slice)

- [ ] **A9**
- mirror spc-254 A* criteria for this slice; see Spec for full text.

## Notes

- Foundation/parallel per ship plan: layer 0=(tkt-255) serial; layer 1=tkt-256/260/261; layer 2=tkt-257(after 256)/tkt-259(after 255); layer 3=tkt-258(after 255+257).
- One sibling worktree per concurrent ship slot.

## References

- GitHub issue body is SoT for long prose: https://github.com/percena/lattice/issues/261
- Spec: `spc-254` (path above)
- Review: `rev-20260830-141357Z`

## Lineage

- Parent spec: **spc-254**
- Parent issue: **#254** (sub-issue of Spec primary)
- Primary ticket: **tkt-261**
- Covers: **A9**
- Blocked by: (none)
- Parallel group: l1-independent
- Worktree bind: tkt-261-environment-parity
- Child PRs: (none yet)

## Assets

Local files in `./assets/`.

## Finish

- (none yet)
