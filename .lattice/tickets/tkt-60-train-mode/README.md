# tkt-60-train-mode

> **TL;DR:** validate-plugin-versions gains release-train mode; create-tickets paths gate models implicit shared files (version manifests, changelog)
> **Kind:** feat · **Priority:** P2
> **Path:** (ticket-only) → tkt-60 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/60 |
| status | pr-open |
| adopted | false |
| summary | train mode for the version validator + shared-file modeling in the paths independence gate |
| spec | none — hygiene/enhancement from dogfood review |
| covers | rev-20260826-145922Z-18p Finding 1 |
| blocked_by | (none) |
| parallel_group | G1 (parallel) |
| paths | tools/validate-plugin-versions.py, tools/tests/plugin-versions.bats, skills/create-tickets/references/policy.md |
| solo_merge | yes |
| **primary_ticket** | tkt-60 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-60-train-mode |
| worktree | sibling …/lattice.worktrees/tkt-60-train-mode/ |
| prs | pr-68 — https://github.com/percena/lattice/pull/68 |

## Acceptance (this slice)

- [x] Train PR whose head shares the identical version-cut commit with its base passes; non-train bundled change without increment still fails; bats green
- [x] create-tickets policy documents implicit shared files in the paths gate

## Approach

Add a train detection path to `validate-plugin-versions.py`: when bundled content changed but the version-bearing files' blobs at head equal a commit reachable from BOTH head and base (the shared cut), or when `--release-tag` compare is requested, accept equal-version. Fixture-based bats in `plugin-versions.bats` (shared-cut pass, non-train fail). One paragraph + table row in create-tickets `policy.md` naming version manifests/changelog as implicit shared paths that route to the train convention (batch-work flow).

## Anticipated decisions

- Detection mechanism (shared-commit vs release-tag compare) — disposition: agent-decides (journal the choice + rationale; both satisfy acceptance)
- Whether train mode needs an explicit flag vs auto-detection — disposition: agent-decides (prefer auto with flag override)

## Decision journal

- **Detection mechanism: shared-cut blob comparison (not release-tag compare).** Chain source: 1 — binder `## Anticipated decisions` disposition "agent-decides; both satisfy acceptance" + `## Approach` lists shared-cut first; empirical fit: the train cut is byte-identical content but *distinct commits* per branch (`skills/batch-work/references/flow.md` §"orchestrator commits ONE identical version cut … byte-identical"), so blob-level identity (same blob OID at head and base, differing from the merge-base, with a SemVer increase since the fork) detects exactly the documented convention, while release-tag compare would add a tag-discipline dependency this repo does not yet have. Reversible, ticket-local.
- **Auto-detection with `--no-train` override flag (no opt-in flag).** Chain source: 1 — binder disposition "prefer auto with flag override". Auto keeps CI invocations unchanged; `--no-train` restores the unconditional strict law for callers that want it. Reversible, ticket-local.
- **Train acceptance requires clean version files in the worktree** (disk manifest/marketplace must match the head commit). Chain source: 5 — codebase convention (validator already folds worktree state into `changed_paths`; a dirty version file means the cut is not what ships). Reversible, ticket-local.

## Pending decisions

## Attempts

## Notes

- Do not weaken the strict per-landing law for non-train PRs (that guarantee is the feature)
- Empirical context: 6 PRs simultaneously red on 2026-08-26; the identical-cut workaround is documented in batch-work flow (#59)

## References

- Review: `rev-20260826-145922Z-18p` Finding 1 · Digest: `rev-20260826-145922Z`

## Lineage

- Parent spec: none (ticket-only)
- Primary ticket: **tkt-60** · Covers: Finding 1 · Parallel group: **G1** · Worktree bind: `tkt-60-train-mode`
- Child PRs: pr-68 — https://github.com/percena/lattice/pull/68

## Finish


- pr-68 merged: 2026-08-26T16:55:07Z — https://github.com/percena/lattice/pull/68 (base merge)
- issue #60 closed: 2026-08-26T16:55:12Z — https://github.com/percena/lattice/issues/60
