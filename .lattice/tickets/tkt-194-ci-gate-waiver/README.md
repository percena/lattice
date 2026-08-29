# tkt-194 — CI merge gate with compiled infra-class waiver + stamped trace

> **Status:** queued · kind feat · priority P1 · covers spc-186 A6, A8

## Field table

| Field | Value | Notes |
| --- | --- | --- |
| kind | feat | |
| priority | P1 | |
| labels | feat, P1 | |
| github | https://github.com/percena/lattice/issues/194 | |
| status | queued | |
| adopted | false | |
| summary | CI merge gate is prose-only (alignment-check never runs `gh pr checks`); "never merge blind on mergeable" has no teeth. Compile infra-class failure detection + waiver stamp; real failures block. | |
| spec | spc-186 | |
| covers | A6, A8 | |
| blocked_by | tkt-188 | shares finish-work flow.md §3.4 hot file |
| parallel_group | g3 | layer 3 |
| paths | skills/finish-work/scripts/finish-preflight.sh, skills/finish-work/references/flow.md, docs/ | |
| solo_merge | true | one PR |
| primary_ticket | tkt-194 | |
| related_tickets | tkt-188 | blocker (shared flow.md) |
| worktree_bind | (pending start-work) | |
| worktree | (pending start-work) | |
| prs | (none) | |

## Acceptance (this slice)

- [ ] finish-work preflight runs a `gh pr checks` rollup (not just mergeable)
- [ ] Failure classification: infra-class (billing/quota/rate-limit/timeout/empty-step flake) vs real — via log patterns + job-run metadata
- [ ] Infra-only red + local verification evidence present → pass with auto-stamped waiver (trace: rule_id ci-gate, reason, authorizer=human at merge time, in binder journal + PR comment)
- [ ] Real failures → block (HARD)
- [ ] The waiver is a compiled corner case per ADR-007 §5a (NOT an escape — no human adjudication needed, the rule defines the legitimate path)
- [ ] tests for the classifier

## Approach

finish-preflight.sh (or a new ci-gate helper) calls `gh pr checks <N> --json name,state,exitCode` and classifies each non-green check: pattern-match failure logs (billing/quota/rate-limit/timeout/empty-step ≤~5s + same failure on unrelated main) into infra-class vs real. Infra-only + local evidence (cited in binder) → pass + waiver stamp. Real → exit 1. The waiver trace carries `rule_id=ci-gate` for the morning-digest escape/metric sensor. This operationalizes the project's current degraded-CI reality (billing block) as a legitimate compiled path rather than an untracked exception.

## Anticipated decisions

- **Infra-class pattern list** — must-ask: operator confirms initial list (billing, quota, rate-limit, timeout, empty-step flake). Recommend a config-tunable pattern set under .lattice/config.yaml.
- **Waiver evidence requirement** — pre-resolved: local test evidence (bats/ci-local output) must be cited in the binder journal for the waiver to stamp.
- **Classifier placement** — agent-decides: recommend a new lib helper skills/finish-work/scripts/lib/ci_failure_classify.py.

## Decision journal

- 2026-08-29: created from spc-186 POST_SPLIT (P1-7). Layer 3 behind tkt-188 (shared finish-work flow.md §3.4).

## Pending decisions

(none — infra-class list pending operator confirm at start-work)

## Notes

- This is ADR-007 §5a compiled-corner-case design: the infra-class waiver is part of the rule, not an exception requiring human adjudication. The real-failure block IS the red line.
- Blocked by tkt-188 (shared skills/finish-work/references/flow.md §3.4 hot file).

## References

- Spec: spc-186
- Law: ADR-007 (§5a compiled corner cases)
- Review: rev-20260829-160834Z
- GH issue: #194

## Lineage

- Parent spec: spc-186
- Primary ticket: tkt-194
- Related: tkt-188 (blocker)
- Covers: A6, A8
- Blocked by: tkt-188
- Parallel group: g3
