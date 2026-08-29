# tkt-194 — CI merge gate with compiled infra-class waiver + stamped trace

> **Status:** queued · kind feat · priority P1 · covers spc-186 A6, A8

## Field table

| Field | Value | Notes |
| --- | --- | --- |
| kind | feat | |
| priority | P1 | |
| labels | feat, P1 | |
| github | https://github.com/percena/lattice/issues/194 | |
| status | closed | |
| adopted | false | |
| summary | CI merge gate is prose-only (alignment-check never runs `gh pr checks`); "never merge blind on mergeable" has no teeth. Compile infra-class failure detection + waiver stamp; real failures block. | |
| spec | spc-186 | |
| covers | A6, A8 | |
| blocked_by | tkt-188 | shares finish-work flow.md §3.4 hot file |
| parallel_group | g3 | layer 3 |
| paths | skills/finish-work/scripts/ci-gate-check.sh, skills/finish-work/scripts/lib/ci_failure_classify.py, skills/finish-work/scripts/tests/ci-gate-check.bats, skills/finish-work/references/flow.md, .lattice/config.yaml | |
| solo_merge | true | one PR |
| primary_ticket | tkt-194 | |
| related_tickets | tkt-188 | blocker (shared flow.md) |
| worktree_bind | (pending start-work) | |
| worktree | (pending start-work) | |
| prs | pr-207 — https://github.com/percena/lattice/pull/207 | |

## Acceptance (this slice)

- [x] finish-work preflight runs a `gh pr checks` rollup (not just mergeable)
- [x] Failure classification: infra-class (billing/quota/rate-limit/timeout/empty-step flake) vs real — via log patterns + job-run metadata
- [x] Infra-only red + local verification evidence present → pass with auto-stamped waiver (trace: rule_id ci-gate, reason, authorizer=human at merge time, in binder journal + PR comment)
- [x] Real failures → block (HARD)
- [x] The waiver is a compiled corner case per ADR-007 §5a (NOT an escape — no human adjudication needed, the rule defines the legitimate path)
- [x] tests for the classifier

## Approach

finish-preflight.sh (or a new ci-gate helper) calls `gh pr checks <N> --json name,state,exitCode` and classifies each non-green check: pattern-match failure logs (billing/quota/rate-limit/timeout/empty-step ≤~5s + same failure on unrelated main) into infra-class vs real. Infra-only + local evidence (cited in binder) → pass + waiver stamp. Real → exit 1. The waiver trace carries `rule_id=ci-gate` for the morning-digest escape/metric sensor. This operationalizes the project's current degraded-CI reality (billing block) as a legitimate compiled path rather than an untracked exception.

## Anticipated decisions

- **Infra-class pattern list** — must-ask: operator confirms initial list (billing, quota, rate-limit, timeout, empty-step flake). Recommend a config-tunable pattern set under .lattice/config.yaml.
- **Waiver evidence requirement** — pre-resolved: local test evidence (bats/ci-local output) must be cited in the binder journal for the waiver to stamp.
- **Classifier placement** — agent-decides: recommend a new lib helper skills/finish-work/scripts/lib/ci_failure_classify.py.

## Decision journal

- 2026-08-29: created from spc-186 POST_SPLIT (P1-7). Layer 3 behind tkt-188 (shared finish-work flow.md §3.4).
- 2026-08-29: implemented ci-gate-check.sh as a standalone finish-work script (not embedded in finish-preflight.sh) — same pattern as batch-merge-gate.sh. The script runs `gh pr checks <N> --json`, fetches log excerpts via `gh run view --log-failed`, and classifies via lib/ci_failure_classify.py.
- 2026-08-29: classifier ordering decision — TIMED_OUT and STARTUP_FAILURE/ACTION_REQUIRED are checked BEFORE empty-step flake. A TIMED_OUT conclusion with no log is timeout (the conclusion IS the signal), not an empty-step flake. STARTUP_FAILURE with no log is runner_infra. This prevents the empty-step heuristic from masking specific infra conclusions.
- 2026-08-29: unknown failures (CANCELLED without infra pattern) treated as real (fail-closed). The gate never passes on unclassified red — ADR-007 §5a: only machine-decidable infra-class compiles into the rule; ambiguous → red line.
- 2026-08-29: config-tunable patterns ship as commented defaults in .lattice/config.yaml (ci_gate: section). The script reads from config.yaml but falls back to built-in DEFAULT_PATTERNS when absent — no dependency on PyYAML (minimal flat-key parser). Pattern set proposed for operator confirm: billing, rate_limit, timeout, runner_infra (categories); empty_step detected via metadata (no log output).
- 2026-08-29: evidence requirement pre-resolved — --evidence flag carries local test output (bats/ci-local). Without it, infra-only red is a HARD block (fail-closed). The local evidence IS the human authorization (authorizer=human-at-merge-time).
- 2026-08-29T12:48:26Z — direct jump: queued → pr-open (in-progress stamp skipped; PR #207) [WARN — signal logged, not silently lost]

## Pending decisions

(none — infra-class pattern list surfaced for operator confirm: billing, rate_limit, timeout, runner_infra, empty_step; config-tunable via .lattice/config.yaml)

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

## Finish

- pr-207 merged: 2026-08-29T13:02:54Z — https://github.com/percena/lattice/pull/207 (base merge)
- issue #194 closed: 2026-08-29T13:03:08Z — https://github.com/percena/lattice/issues/194
