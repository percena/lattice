# tkt-371-claim-probes

> **TL;DR:** claim-probes.sh + references/probes.md registry: executable claim–implementation probes seeded from the spc-337 drift classes, per-repo overlay, planted-drift tests.
> **Kind:** feat · **Priority:** P1

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | feat,P1 |
| github | https://github.com/percena/lattice/issues/371 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T07:21:07Z |
| updated | 2026-09-02T07:21:07Z |
| adopted | false |
| summary | claim-probes.sh + references/probes.md registry: executable claim–implementation probes seeded from the spc-337 drift classes, per-repo overlay, planted-drift tests. |
| spec | spc-369 — review-lineage (path: ../../specs/spc-369-review-lineage.md) |
| covers | A2 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | G0 |
| paths | skills/review-lineage/scripts/claim-probes.sh, skills/review-lineage/references/probes.md, skills/review-lineage/scripts/tests/claim-probes.bats, skills/review-lineage/scripts/tests/fixtures/probes/** |
| solo_merge | yes |
| **primary_ticket** | tkt-371 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-371-claim-probes |
| worktree | sibling `…/lattice.worktrees/tkt-371-claim-probes/` |
| prs | (none) |

## Acceptance (this slice)

- [ ] **A2** — see GitHub issue #371 and Spec spc-369 A2.

## Approach

1. Registry: Markdown table in `references/probes.md` (`id | claim (where) | probe | expect | severity`); parser in a python3 heredoc inside `claim-probes.sh` (dependency-free); optional overlay `.lattice/lineage-probes.tsv` merged by id (overlay wins).
2. Built-in probes (each a shell one-liner run with `REPO_ROOT`, `LATTICE_HOME` exported): skill-scripts-exist (grep `scripts/[a-z0-9-]+\.sh` in each SKILL.md → test -x); hooks-json-files-exist; validator-codes-cited-exist (grep backticked snake_case codes in docs/*.md ∩ validator source); retired-paths-absent (deny-list file in references); adr-verification-refs-resolve; spec-done-cites-tests (each `- [x] **A` line in a done Spec mentions `.bats`/`test`/`bats` or the Spec is flagged); fsm-doc-edges-subset-of-schema (reuse the awk from transition-parity.bats).
3. Expectations: `exit0` or `regex:<pattern>` on stdout; status pass|fail|skip (skip when a prerequisite path is absent); `--md`/`--json`; always exit 0.
4. Bats: fixtures/probes/clean/ passes all; one planted fixture per probe (e.g. SKILL naming a missing script; docs with 'MAIN clone .lattice/'; a done Spec with an A* citing no test) fails exactly that probe; overlay override test.

## Anticipated decisions

- Registry format Markdown table vs TSV — pre-resolved(spc-369 Agent-assumed): Markdown table.
- Probe timeout per probe — agent-decides (default 20 s via `timeout` when available).

## Decision journal

## Pending decisions

(none)

## Attempts

## Notes

## References

- Spec: `spc-369` → `.lattice/specs/spc-369-review-lineage.md`
- Review: `rev-20260902-015425Z` (method origin)

## Lineage

- Parent spec: **spc-369**
- Parent issue (GH sub-issue of Spec primary): **#369**
- Primary ticket: **tkt-371**
- Covers: **A2**
- Blocked by: (none)
- Parallel group: G0
- Worktree bind: tkt-371-claim-probes

## Finish

- (none yet)
