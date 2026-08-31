# tkt-274 — Versioned runtime evidence validation

> **TL;DR:** Require a versioned, fresh, identity-bound runtime proof payload instead of accepting a handwritten status=pass.
> **Kind:** bug · **Priority:** P1
> **Path:** spc-270 → tkt-274 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/274 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-08-31T10:07:37Z |
| updated | 2026-08-31T10:07:37Z |
| adopted | false |
| summary | Validate versioned story/result identity, freshness, assertions, screenshots, round-trip and leftovers for pass evidence. |
| spec | spc-270 — workflow proof closure follow-up (path: ../../specs/spc-270-workflow-proof-closure-followup.md) |
| covers | A5 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | proof-wave-1 |
| paths | skills/run-e2e/**, skills/_lattice-lib/references/templates/feature-map.md, tools/validate-lattice-artifacts.py (evidence parser only), tools/tests/lattice-artifacts.bats (evidence fixtures only) |
| solo_merge | yes |
| **primary_ticket** | tkt-274 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-274-versioned-runtime-evidence` |
| worktree | sibling `…/lattice.worktrees/tkt-274-versioned-runtime-evidence/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A5.1** Story and result use a versioned schema with stable feature/story/run identity.
- [ ] **A5.2** A pass proves oracle/mutations parity, valid last-verified/run freshness, non-empty all-passing assertions, and existing screenshots.
- [ ] **A5.3** Mutation stories prove reload/re-navigation round-trip and disclose leftovers; destructive runs include authorization trace.
- [ ] **A5.4** Shallow handwritten pass, stale run, mismatched identity, missing assertion/screenshot, failed assertion, and undeclared leftovers all fail validator fixtures.
- [ ] **A5.5** Existing artifacts have an explicit compatibility and migration path.

## Approach

Define a dependency-free versioned evidence object shared by run-e2e templates and the artifact validator. Parse story headers and result JSON as one identity-bound proof, validate timestamps against feature-map `last-verified`, and require assertion/screenshot artifacts to exist. Encode mutation round-trip and leftovers explicitly rather than infer them from prose. Add fault fixtures before tightening compatibility so existing consumers receive actionable errors.

## Anticipated decisions

- Evidence schema version is explicit in both story and result — disposition: pre-resolved(spc-270 A5).
- Freshness compares run timestamp with last-verified using UTC ISO-8601 — disposition: pre-resolved(existing artifact timestamp law).
- Exact schema field names may follow current run-e2e result shape — disposition: agent-decides.
- Destructive authorization remains operator-provided and durable — disposition: pre-resolved(run-e2e contract).

## Decision journal

- 2026-08-31 — scheduled before warning-ratchet ticket to avoid concurrent edits to validator fixtures (source: path-overlap gate).

## Pending decisions

(none)

## Attempts

(none)

## Notes

This ticket owns evidence parsing only. Warning identity/baseline behavior belongs to tkt-276.

## References

- Review: `rev-20260831-073033Z`
- Spec: `spc-270`
- Prior delivery: `tkt-259`

## Lineage

- Parent spec: **spc-270**
- Parent issue: **#270**
- Primary ticket: **tkt-274**
- Related / sub-tickets: none
- Covers: **A5**
- Blocked by: none
- Merge blocked by: none
- Parallel group: proof-wave-1
- Worktree bind: `tkt-274-versioned-runtime-evidence`
- Child PRs: none

## Finish

- (none yet)
