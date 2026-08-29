# tkt-211 — Batch-work verify-after-mutate discipline

> **Status:** in-progress · kind feat · priority P1 · ticket-only (no Spec parent)

## Field table

| Field | Value | Notes |
| --- | --- | --- |
| kind | feat | |
| priority | P1 | process gap that caused a real incident (rev-20260829-140444Z) |
| labels | feat, P1 | |
| github | https://github.com/percena/lattice/issues/211 | |
| status | closed | |
| adopted | false | |
| summary | Mechanize the rev-20260829-140444Z F5 lesson: every gh/git mutation confirmed via a follow-up probe; absence/nonzero = HARD failure, never "ambiguous, proceed." Defends batch-work against false-success from harness output-swallowing. | |
| spec | (none — ticket-only) | spc-186 is done/closed; this is a standalone process-hardening ticket |
| covers | (none — ticket-only) | |
| blocked_by | (none) | |
| parallel_group | (none) | standalone |
| paths | skills/_lattice-lib/scripts/verify-mutation.sh, skills/_lattice-lib/scripts/tests/verify-mutation.bats, skills/batch-work/SKILL.md, skills/batch-work/references/flow.md | |
| solo_merge | true | one PR |
| primary_ticket | true | |
| related_tickets | (none) | |
| worktree_bind | tkt-211 | |
| worktree | /Users/mxue/GitRepos/MVP/lattice.worktrees/tkt-211-verify-after-mutate | |
| prs | pr-215 — https://github.com/percena/lattice/pull/215 | |
| created | 2026-08-29T14:08:00Z | |
| updated | 2026-08-29T14:53:18Z | |

## Acceptance (this slice)

- [ ] `verify-mutation.sh` confirms: PR exists+state+head-OID (--pr N [--expected-oid]); commit object exists (--commit OID); remote ref exists+matches (--branch name [--expected-oid]). Exit 0 on verified presence; 1 on absence/mismatch; 2 on usage. Never silent.
- [ ] batch-work spawn-brief contract (SKILL.md + flow.md) adds mandatory verify-after-mutate item
- [ ] batch-work orchestrator report step probes each agent-claimed PR; unverified claims flagged `unverified`
- [ ] bats tests + check-bats-assertions clean
- [ ] ci-local all-green; validator 0 errors

## Approach

A read-only `verify-mutation.sh` helper (skills/_lattice-lib/scripts/) — the incident root cause was believing a `gh pr create`/`merge`/`git push` succeeded without confirming the durable result. The helper closes that gap:
- `--pr N [--expected-oid OID] [--repo owner/name]` → `gh pr view N --json state,headRefOid`; exit 0 only if PR exists, is OPEN (or MERGED if --allow-merged), and head OID matches --expected-oid when given.
- `--commit OID` → `git cat-file -e OID`; exit 0 only if the object exists.
- `--branch name [--expected-oid OID]` → `git ls-remote origin <name>`; exit 0 only if the remote ref exists and matches --expected-oid when given.
- repo-identity binding: refuse to verify a PR from a foreign repo (consistent with stamp-pr-open/finish-ledger posture).
- Output: one-line `verified: <kind> <id> <detail>` (stdout) on success; `FAILED: <reason>` (stderr) + exit 1 on absence/mismatch. Exit 2 on usage. **Never silent** — the whole point is loud failure.

batch-work wiring (ADR-007 §5a compiled check — part of the rule, not an escape):
- SKILL.md spawn-brief contract: add item 6 "after every `gh pr create`/`gh pr merge`/`git push`, run `verify-mutation.sh` on the claimed id; include its `verified:`/`FAILED:` line in your report; on FAILED, do NOT proceed on assumed success — stamp `stuck` + wait_reason: unblock."
- flow.md report step: the host probes each agent-claimed PR via `verify-mutation.sh`; the report table gains a `verified` column (ok/unverified).

## Anticipated decisions

- **--allow-merged flag** — pre-resolved: add it (verifying a PR that was just merged is legitimate; default still requires OPEN since the common case is post-create verification).
- **Multi-mutation in one call** — pre-resolved: one mutation per invocation (composable); a `--all` batch mode is out of scope.
- **Where the helper lives** — agent-decides: recommend skills/_lattice-lib/scripts/ (consumed by batch-work + available standalone to finish-work/start-work).

## Decision journal

- 2026-08-29: created as ticket-only follow-up to rev-20260829-140444Z (F5 lesson). Standalone (spc-186 closed). ADR-007 §5a framing: verify-after-mutate is a compiled check, part of the "transitions fire only on durable artifacts" rule — not an escape.

## Pending decisions

(none)

## Notes

- This is the mechanization of a lesson, not a bug fix — the harness output-swallowing is out of Lattice scope; this ticket hardens Lattice against its consequences (silent false-success).
- Reference: rev-20260829-140444Z (F5); ADR-007 §5a/§8; bug #196 (the incident, closed — this ticket prevents recurrence at the process layer).

## References

- Review: rev-20260829-140444Z (retrospective + F5 lesson)
- Law: ADR-007 (§5a compiled checks; §8 sensors)
- Related bug: #196 (closed)
- GH issue: #211

## Lineage

- Primary ticket: tkt-211
- Ticket-only (no Spec parent)
- GH issue: #211

## Finish

- pr-215 merged: 2026-08-29T14:53:01Z — https://github.com/percena/lattice/pull/215 (base merge)
- issue #211 closed: 2026-08-29T14:53:12Z — https://github.com/percena/lattice/issues/211
