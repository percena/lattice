# tkt-74-deferred-validator

> **TL;DR:** Land tkt-65's two deferred sub-items — binder prs-format warning in the artifacts validator, preferences.md in lattice-init managed paths — with a 0.2.2 single-PR bump
> **Kind:** chore · **Priority:** P3
> **Path:** (ticket-only) → tkt-74 → (pr-…)

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P3 |
| labels | chore, P3 |
| github | https://github.com/percena/lattice/issues/74 |
| status | pr-open |
| adopted | false |
| summary | deferred validator items from tkt-65 + 0.2.2 bump (only bundled-touching ticket this round) |
| spec | none — deferred-from tkt-65 (#65, PR #71) |
| covers | tkt-65 deferral notes |
| blocked_by | (none) |
| parallel_group | G1 (parallel) |
| paths | tools/validate-lattice-artifacts.py, tools/tests/lattice-artifacts.bats, tools/tests/fixtures/lattice-artifacts/, skills/_lattice-lib/scripts/lattice-init.sh, skills/_lattice-lib/scripts/tests/lattice-init.bats, plugins/lattice/.claude-plugin/plugin.json, .claude-plugin/marketplace.json, CHANGELOG.md |
| solo_merge | yes |
| **primary_ticket** | tkt-74 (this issue) |
| **related_tickets** | tkt-73 (canonicalizes existing rows; this check stays warning-level so merge order is irrelevant) |
| **worktree_bind** | tkt-74-deferred-validator |
| worktree | sibling …/lattice.worktrees/tkt-74-deferred-validator/ |
| prs | pr-79 — https://github.com/percena/lattice/pull/79 |

## Acceptance (this slice)

- [x] prs-format warning fires on a malformed filled row fixture, silent on canonical `pr-N — <URL>` and on placeholders `(none…)`; bats green
- [x] lattice-init refuses a symlinked `preferences.md` (managed-paths list); bats green
- [x] 0.2.2 bump (plugin.json + marketplace.json) + CHANGELOG entry in this PR

## Approach

validate-lattice-artifacts: extend the binder field-table pass with a `prs_row_format` warning-level finding (reuse the `level` plumbing from tkt-44); fixtures: one malformed (`URL · pr-N — URL` shape), one canonical, one placeholder. lattice-init: add `preferences.md` to `assert_managed_paths_safe`; bats case with a symlinked preferences.md → refusal. Version: single-PR standard bump (this is NOT a train — only ticket touching bundled paths this round).

## Anticipated decisions

- Whether multi-PR rows (`pr-52 — URL, pr-53 — URL`) are canonical — disposition: agent-decides (accept comma-separated canonical entries; journal the grammar chosen)

## Decision journal

- 2026-08-26 · **prs-row grammar** (anticipated, agent-decides): a FILLED row is one or more entries joined by commas — canonical joiner `, `, regex accepts any whitespace after the comma; entry = `pr-N — <URL>` with N bare decimal (`[1-9][0-9]*`), exactly one space each side of an em dash (U+2014), URL `https?://` with no whitespace/commas. Multi-PR rows (`pr-52 — <URL>, pr-53 — <URL>`) are canonical. Exemption: a row that is entirely a `(none…)` parenthetical (covers `(none)`, `(none yet)`, `(none — rides tkt-5 PR)`); a placeholder *prefixed* legacy row (`(none) · pr-36 — <URL>`) is filled and warns. Rationale: em dash + spacing straight from the template canon (PR #71 item 1); comma joiner is the least ambiguous separator given URLs never contain commas; `·` rejected as joiner since it marks the legacy shapes tkt-73 is canonicalizing. Warning-level permanently per binder Notes. Live-repo effect measured: 15 prs_row_format warnings, all on legacy rows in tkt-73's scope, exit still 0.

## Pending decisions

## Attempts

## Notes

- Keep the check warning-level permanently (legacy content may reappear via adopt flows)
- CHANGELOG entry under a new `## [0.2.2]` heading; do not restructure existing entries

## References

- Deferral notes: tkt-65 binder + PR #71 body

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: **tkt-74** · Parallel group: **G1** · Worktree bind: `tkt-74-deferred-validator`

## Finish

- (none yet)
