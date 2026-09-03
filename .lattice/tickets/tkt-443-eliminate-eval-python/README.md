# tkt-443-eliminate-eval-python

> **TL;DR:** Replace all eval+python3 JSON parsing with read-based variable assignment
> **Kind:** bug · **Priority:** P1
> **Path:** spc-441 → tkt-443 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/443 |
| status | closed |
| fix_cycles | 0 |
| created | 2026-09-03T15:43:52Z |
| updated | 2026-09-03T16:52:01Z |
| adopted | false |
| summary | Eliminate fragile eval+python3 pattern — 8 sites across 4 files |
| spec | spc-441 — project-wide hardening sweep (path: ../../specs/spc-441-hardening-sweep.md) |
| covers | A2 |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | skills/_lattice-lib/scripts/finish-ledger.sh, skills/_lattice-lib/scripts/stamp-pr-open.sh, skills/finish-work/scripts/close-fixed-issues.sh, skills/finish-work/scripts/update-pr-base.sh |
| solo_merge | yes |
| autonomy | 3 |
| primary_ticket | tkt-443 |
| related_tickets | (none) |

## Acceptance (this slice)

- [x] **A2** No `eval "$(python3` or `eval "$(printf.*python3` remains in any `.sh` file; all existing bats tests pass

## Approach

Per site: keep inline python3 for JSON parsing (codebase convention), but print values as plain `key\nvalue\n` pairs. Read into shell vars with `read -r KEY` / `read -r VALUE`. No jq dependency added. Touch-set: finish-ledger.sh (2 sites), stamp-pr-open.sh (1), close-fixed-issues.sh (1), update-pr-base.sh (4).

## Anticipated decisions

- Replace eval with read: pre-resolved(spc-441 D2) — use read-based assignment
- Keep python3 -c inline: agent-decides (codebase convention: inline is standard)

## Decision journal

## Notes

## References

- Spec: spc-441

## Lineage

- Parent spec: **spc-441**
- Parent issue: **#441**
- Primary ticket: **tkt-443**
- Covers: **A2**
- Parallel group: G1

## Assets

## Finish


- pr-453 merged: 2026-09-03T16:49:18Z — https://github.com/percena/lattice/pull/453 (base merge)
- anomaly: direct jump — prior status `queued` before terminal merge; in-progress/pr-open stamps were skipped (ADR-012 §3; metric direct-jump)
- issue #443 closed: 2026-09-03T16:50:06Z (reason: completed) — https://github.com/percena/lattice/issues/443
