# tkt-362-spc337-docs-residue

> **TL;DR:** Prose residue from spc-337 reviews: hooks table, L3 row, header, naming, gate flags
> **Kind:** docs · **Priority:** P3
> **Path:** none → tkt-362 → (pr-…)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P3 |
| labels | docs, P3 |
| github | https://github.com/percena/lattice/issues/362 |
| status | pr-open |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T00:00:00Z |
| updated | 2026-09-02T09:18:08Z |
| adopted | true |
| summary | Fix 5 docs residue items from spc-337 reviews |
| spec | none (post-spc-337 leftover audit) |
| covers | A1, A2, A3, A4, A5 |
| paths | plugins/lattice/README.md, skills/start-work/references/policy.md, skills/_lattice-lib/scripts/verify-main-chain.sh, skills/finish-work/references/flow.md, skills/finish-work/SKILL.md |
| **primary_ticket** | tkt-361 (batch primary) |
| **related_tickets** | tkt-361, tkt-363 (same batch PR) |
| **worktree_bind** | tkt-361-spc337-leftover-audit |
| worktree | sibling lattice.worktrees/tkt-361-spc337-leftover-audit/ |
| prs | pr-380 — https://github.com/percena/lattice/pull/380 |

## Acceptance (this slice)

- [x] **A1** plugins/lattice/README.md hooks table lists intercept-git-branch-create (L1), intercept-shippable-write (L3, incl. the status-row rule) and auto-stamp-pr-open (PostToolUse).
- [x] **A2** start-work policy.md L3 row cites the status-row rule and the transition-api escape.
- [x] **A3** verify-main-chain.sh header matches stage_merge semantics (tip advanced past expected OID, ancestry proven).
- [x] **A4** One variable name (BASE_TIP) across finish-work flow §3.1, §7 and the SKILL short path.
- [x] **A5** finish-work SKILL names batch-merge-gate.sh --create (batch-work) and --status (batch_id) alongside --remove.

## Approach

Direct prose edits: added L1/L3/PostToolUse rows + Event column to hooks table; appended status-row rule + transition-api escape to L3 row; fixed "base OID stable" → "base tip advanced"; unified PRE_MERGE_BASE → BASE_TIP; added --create/--status to Scripts line.

## Notes

- Batch PR with tkt-361 (spawn zombie) and tkt-363 (slug-named ledger replay).

## References

- GitHub issue body is SoT for long prose
- Worktree policy: one tree ↔ one PR; spc|tkt open binds
