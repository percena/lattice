# tkt-409-config-yaml-e2e-env-docs

> **TL;DR:** Add `e2e_env` allowlist + verify-features wave/crawl bounds doc rows to the `.lattice/config.yaml` template (lattice-init.sh heredoc), which already documents batch/ci_gate/queue_health tunables but omits the knobs verify-features reads.
> **Kind:** docs · **Priority:** P3
> **Path:** tkt-409 → (pr-…)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P3 |
| labels | documentation, P3 |
| github | https://github.com/percena/lattice/issues/409 |
| status | in-progress |
| adopted | true |
| summary | document e2e_env allowlist + verify-features wave/crawl/flaky bounds in the config.yaml template |
| spec | none |
| covers | A1 |
| blocked_by | none |
| parallel_group | (serial — batch with tkt-410/411/412) |
| paths | skills/_lattice-lib/scripts/lattice-init.sh |
| solo_merge | no (batch PR) |
| **primary_ticket** | tkt-409 (batch primary) |
| **related_tickets** | tkt-410, tkt-411, tkt-412 (NOTICED-drain batch) |
| **worktree_bind** | tkt-409-noticed-drain-fixes |
| worktree | sibling …/lattice.worktrees/tkt-409-noticed-drain-fixes/ |
| prs | pending |

## Acceptance (this slice)

- [x] **A1** `.lattice/config.yaml` template (lattice-init.sh heredoc) documents the `e2e_env` allowlist and the verify-features wave/crawl/flaky bounds (`wave_max`, `stories_per_wave`, `crawl_pages_max`, `flaky_retry_max` or the names the skill actually reads) as commented defaults, consistent with the existing batch_tunables/ci_gate/queue_health doc style.

## Approach

The verify-features SKILL.md (INVARIANT 4 + Preflight step 0) reads `.lattice/config.yaml` for `e2e_env` + bounds (≤20 crawl pages, ≤12 stories/wave, ≤2 waves, flaky retry ≤1). The config.yaml template currently documents batch_timebox/fuse, ci_gate, and queue_health but not these. Add commented doc rows in the same heredoc, matching the existing "# key: value # explanation" style. Confirm the exact key names the skill reads before writing (the SKILL.md names them conceptually; the template should match the code that reads them, or document the conceptual names if none are read yet — the skill may currently hard-code the bounds).

## Decision journal

## Pending decisions

## Attempts

## Notes

- NOTICED in tkt-105 (binder line): "config.yaml template documents batch tunables but not e2e_env or verify-features wave/crawl bounds." Filed by tkt-386 NOTICED backlog drain.
- If verify-features currently hard-codes the bounds (no config read yet), the template rows are forward-looking doc seeds with a note, not live-tunable keys.

## References

- verify-features SKILL.md INVARIANT 4 · lattice-init.sh config.yaml heredoc · tkt-105 binder NOTICED line

## Lineage

- Parent spec: none · Primary ticket: tkt-409 · Parallel group: (serial NOTICED-drain batch) · Worktree bind: `tkt-409-noticed-drain-fixes`

## Finish
