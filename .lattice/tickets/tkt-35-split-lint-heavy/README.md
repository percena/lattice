# tkt-35-split-lint-heavy

> **TL;DR:** Split lint.yml heavy jobs (skill-quality, plugin-validate) into a new path-filtered lint-heavy.yml; keep light jobs (shellcheck, symlink-integrity) in lint.yml with its own path filter
> **Kind:** chore · **Status:** open · **Priority:** P3

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P3 |
| labels | chore, P3 |
| github | https://github.com/percena/lattice/issues/35 |
| status | open |
| adopted | true |
| summary | split lint.yml heavy jobs into path-filtered workflow |
| spec | (none — ci-chore) |
| covers | A1, A2, A3, A4 |
| blocked_by | tkt-31 (soft — only blocks green symlink-integrity verification, not the split itself) |
| parallel_group | (none) |
| paths | .github/workflows/lint.yml, .github/workflows/lint-heavy.yml |
| solo_merge | yes (one PR) |
| **primary_ticket** | tkt-35 |
| **related_tickets** | tkt-31 |
| **worktree_bind** | tkt-35-split-lint-heavy |
| prs | #37 |

## Acceptance (this slice)

- [ ] **A1** `lint.yml` retains only `shellcheck` + `symlink-integrity` jobs, with workflow-level `paths:` filter `skills/**`, `plugins/**`, `tools/**`, `.github/workflows/lint.yml` (push main + PR trigger unchanged) — ✅ verified local
- [ ] **A2** New `.github/workflows/lint-heavy.yml` moves `skill-quality` + `plugin-validate` jobs verbatim (steps/env preserved), with `paths:` filter `skills/**`, `tools/**`, `evals/**`, `plugins/**`, `.claude-plugin/**`, `.github/workflows/lint-heavy.yml` (push main + PR trigger) — ✅ verified local
- [ ] **A3** docs/README-only change on a PR branch triggers **neither** workflow (verified by test push + observed skip) — ⏳ pending live probe (optional; symmetric inverse of A4, standard GitHub path-filter semantics)
- [ ] **A4** skills/plugins/tools change still triggers **both** workflows (coverage unchanged — verified by test push) — ✅ verified live on PR #37: this PR's workflow-file changes triggered two separate workflow runs (32832995707=lint, 32832995320=lint-heavy)

## Notes

- Path-dependency matrix verified from script source (validate-skills.sh, run-routing-evals.py, run-behavioral-evals.py, validate-plugin-versions.py). Plugin skills are symlinks into `skills/`, so `plugin-validate` transitively depends on `skills/**`.
- `concurrency.group` uses `github.workflow` → split workflows get independent groups, run in parallel (no contention).
- `fetch-depth: 0` only needed by `skill-quality` (validate-plugin-versions.py git diff); keep per-job, do not pollute plugin-validate.
- **Known blocker for A1 green verification:** `plugins/lattice/skills/run-e2e` symlink is broken (points `../../../../skills/run-e2e`, one `../` too many) — tracked in **tkt-31** / #31 (OPEN). symlink-integrity job is red on any PR until tkt-31 lands. Verify A1/A3/A4 against the other jobs; treat symlink-integrity red as the known tkt-31 condition, not a regression of this ticket.

## References

- GitHub issue #35 body is SoT for long prose
- Predecessor commit `0e6ecc7` already dropped `dev` from push triggers across all three workflows
