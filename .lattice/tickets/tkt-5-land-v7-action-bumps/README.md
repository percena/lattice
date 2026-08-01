# tkt-5-land-v7-action-bumps

> **TL;DR:** Land the three Dependabot v7 major bumps (checkout/setup-node/setup-python) as one combined upgrade commit; dev CI must stay green.
> **Kind:** chore · **Status:** open · **Priority:** P2
> **Path:** spc-4 → tkt-5 → (pr-…)

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P2 |
| labels | chore, P2, spec |
| github | https://github.com/percena/lattice/issues/5 |
| status | open |
| adopted | false |
| summary | Land v7 bumps for checkout/setup-node/setup-python as one combined commit; dev CI green |
| spec | spc-4 — GitHub Actions v7 upgrade + Dependabot grouping policy (path: ../../specs/spc-4-gh-actions-v7-upgrade.md) |
| covers | A1, A2, A3, A4 |
| blocked_by | (none) |
| parallel_group | (serial) |
| paths | .github/workflows/*.yml |
| solo_merge | yes |
| **primary_ticket** | tkt-5 (this issue) — owns the one-PR ship; tkt-6/tkt-7 ride this PR |
| **related_tickets** | tkt-6, tkt-7 (same PR), tkt-8 (cleanup after merge) |
| **worktree_bind** | `spc-4-gh-actions-v7-upgrade` |
| worktree | sibling `…/lattice.worktrees/spc-4-gh-actions-v7-upgrade/` |
| prs | pr-9 (https://github.com/percena/lattice/pull/9, base dev, all CI green) |

## Acceptance (this slice)

- [x] **A1** all `actions/checkout@…` pins resolve to v7.0.1 SHA `3d3c42e5aac5ba805825da76410c181273ba90b1` + ` # v7.0.1` across lint.yml, lattice-scripts.yml, plugin-hooks.yml
- [x] **A2** `actions/setup-python@…` pins to v7.0.0 SHA `5fda3b95a4ea91299a34e894583c3862153e4b97` + ` # v7.0.0`
- [x] **A3** `actions/setup-node@…` pins to v7.0.0 SHA `820762786026740c76f36085b0efc47a31fe5020` + ` # v7.0.0`
- [x] **A4** CI (shellcheck, symlink-integrity, skill-quality, plugin-validate, bats) green on `dev`

## Notes

- Primary ship ticket. One-PR ship plan (path overlap on .github/workflows + .github/dependabot.yml + docs/adr).
- Supersedes Dependabot PRs #1, #2, #3 (closed by tkt-8 after merge).
