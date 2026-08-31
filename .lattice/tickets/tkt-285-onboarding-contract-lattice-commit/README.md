# tkt-285-onboarding-contract-lattice-commit

> **TL;DR:** Tell the operator .lattice/ is meant to be committed; stop mis-flagging scaffolded bootstrap files as leak residue.
> **Kind:** chore · **Status:** open · **Priority:** P2
> **Path:** spc-282 → tkt-285 → (pr-…)

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P2 |
| labels | chore,P2 |
| github | https://github.com/percena/lattice/issues/285 |
| status | open |
| adopted | false |
| summary | One-time guidance on .lattice/ scaffold; check-base-residue treats bootstrap files as expected-dirt-once (advisory) |
| spec | spc-282 — Consumer-repo footprint hygiene (path: ../../specs/spc-282-consumer-repo-footprint-hygiene.md) |
| covers | A5 |
| blocked_by | (none) |
| parallel_group | wave-1 (with 283, 284) |
| paths | skills/_lattice-lib/scripts/ensure-lattice.sh, skills/_lattice-lib/scripts/lattice-init.sh, plugins/lattice/scripts/check-base-residue.sh |
| solo_merge | yes |
| primary_ticket | tkt-285 |
| related_tickets | (none) |
| worktree_bind | spc-282-consumer-repo-footprint-hygiene |
| prs | (none yet) |
| created | 2026-08-31T00:00:00Z |
| updated | 2026-08-31T00:00:00Z |

## Why

`ensure-lattice.sh` scaffolds `.lattice/{preferences.md,config.yaml,README.md}` onto MAIN as tracked-by-design decision-chain artifacts with no auto-commit and no guidance — the "Preferences file appearing in main branch" symptom. `check-base-residue.sh` mis-flags the legitimate first-scaffold as leak residue, confusing the operator about what to commit vs. what is temp.

## Scope

- `ensure-lattice.sh` / `lattice-init.sh`: emit a one-time guidance line when scaffolding tracked bootstrap files (`.lattice/preferences.md`, `config.yaml`, `README.md`): "`.lattice/` is meant to be committed; run `git add .lattice/` once to track Lattice's project-knowledge footprint."
- `check-base-residue.sh`: treat scaffolded-once files (`preferences.md`, `config.yaml`, `README.md`) as expected-dirt-once (advisory message, not a hard residue fail) so the legitimate first-scaffold is not mis-flagged as leak residue. If the file is already committed, no advisory.
- Tests: `ensure-lattice.bats` gains a "fresh repo scaffold emits guidance" assertion; `check-base-residue` advisory-not-fail for the 3 bootstrap files.

## Approach

1. `ensure-lattice.sh`: after the scaffold block (line ~233 for preferences, ~110/130 for config/README in `lattice-init.sh`), print a one-time guidance line to stderr (and include in JSON output as `guidance` field).
2. `check-base-residue.sh`: add an advisory whitelist for `.lattice/preferences.md`, `.lattice/config.yaml`, `.lattice/README.md` — emit a guidance message ("scaffolded, not yet committed; commit `.lattice/`") rather than fail.
3. bats: fresh-repo `ensure-lattice` → guidance emitted; `check-base-residue` → advisory not fail; after `git add .lattice/` → no advisory.

## Anticipated decisions

- `pre-resolved` — advisory (not hard fail) per ADR-011; these are tracked-by-design, not leak.
- `pre-resolved` — guidance is one-time (suppressed once `.lattice/` is committed).
- `agent-decides` — guidance wording: reversible.

## Pending decisions

(none)

## blocked_by

(none)
