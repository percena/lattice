# tkt-480-review-found-hardening

<!-- Binder is a thin recovery card (not a second issue tracker). -->

> **TL;DR:** Fix three dev-landed review-found defects — alignment-check `--home` clobber (A1), autonomy regex case mismatch (A2), artifacts.yml PR path filter (A3); one PR.
> **Kind:** bug · **Priority:** P1
> **Path:** spc-479 → tkt-480 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/480 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-05T16:00:00Z |
| updated | 2026-09-05T16:00:00Z |
| adopted | false |
| summary | Review-found hardening: alignment-check --home, autonomy re.I, artifacts.yml PR trigger |
| spec | spc-479 — Review-found hardening sweep (path: ../../specs/spc-479-review-found-hardening.md) |
| covers | A1, A2, A3 |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | (serial) |
| paths | skills/finish-work/scripts/alignment-check.sh; skills/batch-work/scripts/autonomy-filter.py; .github/workflows/artifacts.yml; +bats suites |
| solo_merge | yes |
| **primary_ticket** | tkt-480 |
| **related_tickets** | (none) |
| **worktree_bind** | `spc-479-review-found-hardening` |
| worktree | sibling `…/lattice.worktrees/spc-479-review-found-hardening/` |
| prs | (none) |
| found_by | human (full review of 80f3701..origin/dev) |
| escaped_from | pr-457 — tkt-447 refactor (A1 regression source) |

## Acceptance (this slice)

- [ ] **A1** `alignment-check.sh --pr N --home /some/worktree/.lattice` (with `LATTICE_HOME` unset) resolves HOME_DIR to the supplied path, not `$git_root/.lattice`; the merge gate scans binders at the supplied home. Mirrors `ci-gate-check.sh:84`. Regression test covers `LATTICE_HOME`-unset + `--home`-set.
- [ ] **A2** `autonomy-filter.py` matches `| Autonomy | 4 |` (capital A) the same as `| autonomy | 4 |`; a bats test asserts both forms resolve to score 4, and asserts the filter and `validate-lattice-artifacts.py` agree on the same row.
- [ ] **A3** A PR that touches only `skills/**` / `docs/**` / `tools/**` (no `.lattice/**`) triggers the `lattice-artifacts` workflow on `pull_request`; the check passes (validator exits 0, legacy baseline unchanged). Static test asserts `artifacts.yml` `pull_request` trigger has no path filter.

## Approach

- **A1:** wrap the `source_lattice_home_and_resolve` block at `alignment-check.sh:65-73` in `if [[ -z "$HOME_DIR" ]]; then … fi`, copying `ci-gate-check.sh:84` verbatim. Touch-set: `skills/finish-work/scripts/alignment-check.sh`; its bats suite (add `LATTICE_HOME`-unset + `--home`-set case — the gap that let the regression land).
- **A2:** change `autonomy-filter.py:30` `re.M` → `re.I | re.M`. Touch-set: `skills/batch-work/scripts/autonomy-filter.py`; `skills/batch-work/scripts/tests/autonomy-filter.bats` (add mixed-case row test + agreement assertion vs `validate-lattice-artifacts.py`).
- **A3:** in `artifacts.yml`, remove the `paths:` block under `pull_request:` (keep `push:` path filter intact). Touch-set: `.github/workflows/artifacts.yml`; `tools/tests/ci-local.bats` (static assertion `pull_request` has no path filter).

## Anticipated decisions

- A1 guard placement = call-site (not refactor shared resolver) — **pre-resolved** (Spec Decision 3)
- A3 = drop path filter (not maintain an allowlist) — **pre-resolved** (Spec Decision 2)
- push trigger path filter left intact — **pre-resolved** (Spec Agent-assumed)
- one ticket / one worktree / one PR — **pre-resolved** (Spec Decision 1)

## Decision journal

<!-- Append-only during execution. -->

## Notes

- A1 regression source: tkt-447 / PR #457 (`refactor(tkt-447): extract shared resolve_lattice_lib_scripts function`) — dropped both `if [[ -z "$HOME_DIR" ]]` guards; sibling `ci-gate-check.sh:84` retained them.
- A2 validator-side `AUTONOMY_TABLE_RE` (`tools/validate-lattice-artifacts.py:322`) already has `re.I | re.M`; the filter at `autonomy-filter.py:30` lacked `re.I`.
- A3 blocks PR #478 in practice (`mergeStateStatus: BLOCKED`, required `lattice-artifacts` check never fires for code/docs-only PRs).
