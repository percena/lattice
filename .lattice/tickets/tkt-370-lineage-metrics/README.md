# tkt-370-lineage-metrics

> **TL;DR:** lineage-metrics.sh + lib/lineage_metrics.py: L1 running-data metrics with schema-versioned JSON snapshot and delta vs previous.
> **Kind:** feat · **Priority:** P1

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | feat,P1 |
| github | https://github.com/percena/lattice/issues/370 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T07:21:07Z |
| updated | 2026-09-02T07:47:00Z |
| adopted | false |
| summary | lineage-metrics.sh + lib/lineage_metrics.py: L1 running-data metrics with schema-versioned JSON snapshot and delta vs previous. |
| spec | spc-369 — review-lineage (path: ../../specs/spc-369-review-lineage.md) |
| covers | A1 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | G0 |
| paths | skills/review-lineage/scripts/lineage-metrics.sh, skills/review-lineage/scripts/lib/lineage_metrics.py, skills/review-lineage/scripts/tests/lineage-metrics.bats, skills/review-lineage/scripts/tests/fixtures/metrics/** |
| solo_merge | yes |
| **primary_ticket** | tkt-370 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-370-lineage-metrics |
| worktree | sibling `…/lattice.worktrees/tkt-370-lineage-metrics/` |
| prs | pr-375 — https://github.com/percena/lattice/pull/375 |

## Acceptance (this slice)

- [x] **A1** — see GitHub issue #370 and Spec spc-369 A1.

## Approach

1. `lib/lineage_metrics.py`: import `queue_health` (scan_binders for coverage/direct jumps), `transition_table` (LEGAL_EDGES), `binder_rows` (field parsing) via the `_lattice-lib/scripts/lib` sys.path pattern used by queue-health.sh; functions `collect(home, repo_root, since) -> dict`, `load_previous(snapshot_dir)`, `delta(cur, prev)`, `render_md(cur, delta)`.
2. Metrics: status histogram; ledger coverage; edge histogram from all ledgers vs LEGAL_EDGES → walked/never-walked lists; direct jumps; fix_cycles histogram; side-state + wait_reason counts; sections non-empty counts (Attempts / Pending decisions / Decision journal) via regex; NOTICED lines (count + list of `path — text`); escape traces (`rule_id=…` grep) by rule; git: `git log --format=%s <base> --since` → commits without `(#N)$` vs with; Specs done with open `- [ ]` A*; Spec prs vs child binder prs union.
3. `lineage-metrics.sh`: Step-0 resolver (LATTICE_SKILL_ROOT → resolve-lattice-lib.sh), args `--home --since --snapshot-dir --json --md --no-snapshot`; python3 missing → degrade message (ensure-python3 pattern); writes snapshot then prints.
4. Bats: fixture home under `tests/fixtures/metrics/` with 6 binders (mixed statuses, one with ledger, one NOTICED, one fix_cycles 2), 2 ledgers, 1 done Spec with an open A*; planted previous snapshot to assert delta arrows; `--no-snapshot` leaves the dir untouched; git metrics tested on a tmp repo with two commits (one with `(#1)`).

## Anticipated decisions

- Snapshot dir committed vs ignored — pre-resolved(spc-369 Agent-assumed): committed under .lattice/reviews/metrics/.
- Delta rendering when no previous snapshot — agent-decides (print 'first snapshot').

## Decision journal

- 2026-09-02 — Status histogram reads through `queue_health._parse_field_rows` unchanged (no normalisation, no second parser); the 15 binders with a 3-column field table therefore surface as their own malformed keys (`closed |`) rather than being silently folded into `closed` — the sensor shows the shared parser's defect instead of hiding it. Source: 2 — Spec D5 "no second status parser" + Risks "read through binder_rows.py only". reversible, ticket-local.
- 2026-09-02 — Escape traces count `rule_id=<x>` only on bullet lines (`- …`); a prose mention (tkt-194 Approach, this binder's Approach) is not a trace. Source: 1 — binder Approach "escape traces (`rule_id=…` grep) by rule" + ADR-007 §8 (traces are journal entries). reversible, ticket-local.
- 2026-09-02 — Spec `prs` mismatch is evaluated for `done` Specs only (an in-flight Spec is expected to lag), and split into `missing_in_spec` (child PR the Spec never cites — real drift) vs `extra_in_spec` (Spec-only PRs — on this repo all three are the Spec-creation/planning PR). The A1 "≠" count is kept as `prs_mismatch_count`; `prs_missing_in_spec_count` is the strict signal. Source: 5 — heuristic (verified on repo data: pr-343 = `create(spc-337)`, pr-109 = `docs(spc-104) planning PR`). reversible, ticket-local.
- 2026-09-02 — No previous snapshot → the report prints "First snapshot — no previous `lineage-*.json`" and every Δ cell is `—`; `delta()` returns `{"previous": null, "changes": {}}`. Source: 1 — binder Anticipated decisions (agent-decides: print 'first snapshot'). reversible, ticket-local.
- 2026-09-02 — python3 missing → exit 1 with `ensure-python3.sh`'s install hint + one `lineage-metrics: unavailable` line (not exit 0 like the digest-embedded queue-health sensor): a standalone metrics run that produced nothing must not look successful. Source: 5 — codebase convention (`ensure-python3.sh` header: `bash "$ENSURE_PY" || exit 1`). reversible, ticket-local.
- 2026-09-02 — `--since` accepts `Nd` (→ `--since "N days ago"`), an ISO date (→ `--since`), else a ref (→ `<ref>..<base>`); default `30d`. Base: `--base` > `resolve-integration-branch.sh` `recommended_base` (empty on this repo: two long-lived branches → `ask`) > first of dev/develop/main/master that exists (local, then `origin/`). Source: 1 — binder Approach + brief. reversible, ticket-local.
- 2026-09-02 — `tools/validate-skills.sh` registration-integrity loop fails on any `skills/<dir>` not in USER_FACING/EXEMPT **and** lacking a `plugins/lattice/skills/<dir>` symlink — a placeholder SKILL.md would not fix either. Kept the lint green with the smallest reversible seam: one EXEMPT line (commented "tkt-372/373 move it to USER_FACING") + the symlink tkt-373 would create anyway. Both files are outside this ticket's `paths` → recorded under Pending decisions for ratification. Source: 5 — most reversible option; brief pre-authorised "minimal … only if unavoidable, say so in the PR". reversible, cross-contract (tkt-373 surface).

## Pending decisions

- Cross-contract touch for ratification: `tools/validate-skills.sh` gained `review-lineage` in `EXEMPT` and `plugins/lattice/skills/review-lineage` symlink was created (tkt-373's registration surface) so the W0 scripts can land without SKILL.md. tkt-371 (parallel, same dir) needs the same two lines; whichever merges second resolves a one-line conflict. tkt-373 should delete the EXEMPT line when it moves `review-lineage` into USER_FACING. Alternative if rejected: revert both and accept a red `validate-skills` until tkt-372/373 land.

## Attempts

(none — first path green: 22/22 bats, all CI guards on the first run)

## Notes

- NOTICED: skills/_lattice-lib/scripts/lib/queue_health.py — `_FIELD_ROW_RE` value group is `.*?` up to the LAST `|`, so a 3-column field table row `| status | closed | |` parses as status `closed |`; 15 closed binders (tkt-121, tkt-191, tkt-192, tkt-194, …) are thereby NOT counted as terminal by `scan_binders` (coverage denominator 149, not 164). One-line fix: capture `([^|]*?)` (out-of-paths, 2026-09-02)
- NOTICED: .lattice/.transition-ledger/356.jsonl + 357.jsonl — bind/spawn stamp (`queued → in-progress`, reason `spawn`) wrote ledgers keyed by the bare issue number (`"ticket":"356"`) instead of `tkt-356`; `scan_binders` cannot associate them with the binders, so the same tickets still count as "missing ledger" (out-of-paths, 2026-09-02)
- NOTICED: .lattice/specs/spc-104, spc-270, spc-337 — front-matter `prs` cite Spec-creation/planning PRs (pr-109/112, pr-312, pr-343) no child binder carries; harmless, but `prs` semantics ("delivery PRs" vs "all PRs touching the Spec") are undocumented in ADR-011 L0 (out-of-paths, 2026-09-02)

## References

- Spec: `spc-369` → `.lattice/specs/spc-369-review-lineage.md`
- Review: `rev-20260902-015425Z` (method origin)

## Lineage

- Parent spec: **spc-369**
- Parent issue (GH sub-issue of Spec primary): **#369**
- Primary ticket: **tkt-370**
- Covers: **A1**
- Blocked by: (none)
- Parallel group: G0
- Worktree bind: tkt-370-lineage-metrics

## Finish


- pr-375 merged: 2026-09-02T07:46:43Z — https://github.com/percena/lattice/pull/375 (base merge)
- issue #370 closed: 2026-09-02T07:46:52Z (reason: completed) — https://github.com/percena/lattice/issues/370
