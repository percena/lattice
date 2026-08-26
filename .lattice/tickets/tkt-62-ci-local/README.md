# tkt-62-ci-local

> **TL;DR:** One-command local CI-parity runner (`tools/ci-local.sh`) wired into the batch-work evidence contract
> **Kind:** feat · **Priority:** P2
> **Path:** (ticket-only) → tkt-62 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/62 |
| status | in-progress |
| adopted | false |
| summary | ci-local.sh runs everything CI runs; batch briefs cite it as the required evidence command |
| spec | none — enhancement from dogfood review |
| covers | rev-20260826-145922Z-18p Finding 3 |
| blocked_by | (none) |
| parallel_group | G1 (parallel) |
| paths | tools/ci-local.sh, tools/README.md, skills/batch-work/references/flow.md |
| solo_merge | yes |
| **primary_ticket** | tkt-62 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | tkt-62-ci-local |
| worktree | sibling …/lattice.worktrees/tkt-62-ci-local/ |
| prs | (none) |

## Acceptance (this slice)

- [ ] `bash tools/ci-local.sh` reproduces every CI verdict locally on a clean tree (validate-skills, artifacts, plugin-versions with default base ref, shellcheck, all bats with the BATS_TEST_TMPDIR shim); summary table; nonzero exit on any failure; itself shellcheck-clean
- [ ] batch-work evidence contract names it

## Approach

Read `.github/workflows/*.yml` to enumerate exactly what CI runs; wrap each as a step function with pass/fail capture; default `--base-ref` = `origin/dev` fork-point (overridable); print a final table and exit max(status). Update the flow.md EVIDENCE CONTRACT block to require `ci-local` output instead of the two-validator subset. tools/README row.

## Anticipated decisions

- Whether ci-local skips plugin-versions when no bundled paths changed — disposition: agent-decides (mirror CI path filters)

## Decision journal

- Coverage: ci-local runs the full CI verdict set — the brief's five mandated steps plus symlink-integrity, routing evals, behavioral validate + fake-provider smoke, and `claude plugin validate` (auto-skip with note when CLI absent). Source: 1 — ticket AC "reproduces every CI verdict locally on a clean tree" + Approach "enumerate exactly what CI runs; wrap each as a step function". Reversible, ticket-local (all steps are one-command wrappers; each <1s except smoke ~10s).
- plugin-versions auto-skip gate = lint-heavy.yml `on.paths` filter (skills/, tools/, evals/, plugins/, .claude-plugin/, the workflow file), with untracked files counted as changed (they enter CI's diff once committed). Source: 1 — binder Anticipated decisions disposition "mirror CI path filters". Reversible, ticket-local.
- Default `--base-ref` = `git merge-base origin/dev HEAD` (fork point); when origin/dev is unavailable the script falls back to validate-plugin-versions.py's own base-ref resolution rather than guessing. Source: 1 — brief/Approach. Reversible, ticket-local.
- `--fast` skips only bats (not the ~10s behavioral smoke), matching the brief's literal flag contract and the binder note "bats is the slow step". Source: 1. Reversible, ticket-local.
- One-line fix OUTSIDE the paths row: `skills/finish-work/scripts/tests/close-fixed-issues.bats` `make_fake_gh` now always self-manages its tmpdir. The per-suite BATS_TEST_TMPDIR shim (required by unguarded uses in `plugins/lattice/scripts/tests/strip-quoted-and-heredocs.bats`) shared one dir across tests, so gh.log accumulated and the dry-run log assertion false-failed — ci-local showed a red CI would not show. Source: 5 — codebase convention (`plugins/lattice/scripts/tests/track-skill-activation.bats` "Self-managed per-test tmp dir: a shared BATS_TEST_TMPDIR (pre-1.4 bats)"). Reversible one-liner; suite verified green with and without the shim; CI behavior unchanged. Flagged in the PR body for ratification.

## Pending decisions

## Attempts

## Notes

- Root cause context: agents ran 2/5 validators; the train red was discovered only on GitHub
- Keep runtime reasonable — bats is the slow step; a `--fast` flag skipping bats is acceptable if default stays full

## References

- Review: `rev-20260826-145922Z-18p` Finding 3

## Lineage

- Parent spec: none (ticket-only)
- Primary ticket: **tkt-62** · Covers: Finding 3 · Parallel group: **G1** · Worktree bind: `tkt-62-ci-local`
- Child PRs: (none yet)

## Finish

- (none yet)
