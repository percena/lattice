# tkt-95-docs-truth

> **TL;DR:** Every doc statement contradicting shipped reality gets amended or corrected — ADR-002 marker amendment, README tier count, getting-started preferences.md coverage, day-phase, CHANGELOG provenance, config tunables
> **Kind:** docs · **Priority:** P2
> **Path:** (ticket-only) → tkt-95 → (pr-…)

| Field | Value |
| --- | --- |
| kind | docs |
| priority | P2 |
| labels | documentation, P2 |
| github | https://github.com/percena/lattice/issues/95 |
| status | pr-open |
| adopted | false |
| summary | ADR-002 dated amendment (env gate → marker) + README/getting-started/day-phase/CHANGELOG/config corrections |
| spec | none — audit rev-20260827-033352Z F7 |
| covers | audit F7 |
| blocked_by | (none) |
| parallel_group | G1 (wave 1) |
| paths | docs/adr/002-lattice-skill-gap-bridge-adaptations.md, docs/adr/003-review-code-extended-axes-and-solution-oriented-findings.md, docs/adr/README.md, README.md, docs/getting-started.md, docs/day-phase.md, CHANGELOG.md, .lattice/config.yaml |
| solo_merge | yes |
| **primary_ticket** | tkt-95 (this issue) |
| **related_tickets** | tkt-82 (zh sync that caught the tier count), tkt-33 (marker mechanism ADR-002 must now cite) |
| **worktree_bind** | tkt-95-docs-truth |
| worktree | sibling …/lattice.worktrees/tkt-95-docs-truth/ |
| prs | pr-97 — https://github.com/percena/lattice/pull/97 |

## Acceptance (this slice)

- [x] **A1** ADR-002: dated amendment (env gate → `.lattice/.batch-work-active` marker, cites tkt-33/0.2.0); adr/README amend column; ADR-002 ↔ ADR-004 cross-refs symmetric; ADR-003 `pr-N` placeholder resolved
- [x] **A2** README.md tier intro count correct; tier labels consistently cased
- [x] **A3** getting-started: preferences.md in ensure-lattice list + "what gets committed"; next-docs links include workflow-fsm + day-phase; day-phase "landing separately" corrected
- [x] **A4** CHANGELOG 0.2.3 provenance line corrected (two-PR shared train cut; capture-law bullet attributed to tkt-84)
- [x] **A5** config.yaml comments document `batch_timebox_*` + `batch_fuse_threshold`; full `ci-local` green

## Approach

ADR discipline: append a dated **Amendment** block under §3 (never rewrite accepted text), update the ADR index row, add the missing Related-ADRs line. README/getting-started/day-phase/CHANGELOG edits are line-targeted per the audit's citations. config.yaml gains a commented block naming the two batch tunables with defaults (values stay absent — defaults apply). zh README: re-sync only strings whose meaning changes (tier count already correct on zh side).

## Anticipated decisions

- Whether ADR-002's "10-skill lifecycle" count is amended too — pre-resolved: yes, same amendment block (one dated block, all corrections)
- CHANGELOG edit form for a released entry — disposition: agent-decides (in-place correction of a factual provenance note is acceptable for released entries when the artifact itself was wrong at release time; journal)

## Decision journal

- 2026-08-27 — **ADR-003 placeholder resolution verified before writing:** `gh pr view 39` → "feat: extend review-code with CI/CD, syntax/lint, docs-sync, interface-impact axes + solution-oriented findings (#38)", merged 2026-08-25T11:18:01Z; `git log --all` shows the same merge (aa509bb). Header `pr-N (to be opened)` → `pr-39`.
- 2026-08-27 — **ADR-003 ticket id corrected tkt-35 → tkt-38 (coordinator scope addition):** verified `gh issue view 38` = "review-code skill: add CI/CD, syntax/lint, docs-sync, interface-impact axes…" while issue #35 = "ci: split lint.yml heavy jobs into path-filtered workflow"; binder `.lattice/tickets/tkt-35-review-code-extended-axes/README.md` github row points at issue #38 and `prs: pr-39`. Fixed on lines 6 and 64 (header Related + Follow-ups); binder dir rename is tkt-90's.
- 2026-08-27 — **CHANGELOG released-entry edit form (pre-dispositioned agent-decides):** in-place correction of the 0.2.3 provenance intro line — the artifact was factually wrong at release time (commit 50efefb shows #88 shared tkt-81's 0.2.3 train cut byte-identical, so the release was a two-PR shared train cut, not "single-PR bump"). No new 0.2.4 entry added (tkt-90 owns it).
- 2026-08-27 — **config tunables documented in BOTH surfaces:** `.lattice/config.yaml` is tracked (`git ls-files` confirms) → live file edited; the generator template is the heredoc in `skills/_lattice-lib/scripts/lattice-init.sh` (bundled path) → same comment block added there, firing the bundled-change version cut: canonical 0.2.4 blobs copied byte-for-byte from the pre-staged train-cut-0.2.4 scratchpad over `.claude-plugin/marketplace.json` + `plugins/lattice/.claude-plugin/plugin.json` (train note in PR).
- 2026-08-27 — **zh README untouched:** 分五类 count already correct; Chinese tier labels carry no casing, so no inconsistency to mirror.

## Pending decisions

## Attempts

## Notes

- workflow-fsm.md corrections deliberately NOT here (tkt-90 owns that file); registration surfaces NOT here (tkt-94)

## References

- rev-20260827-033352Z F7 · docs/adr/template.md (amendment form) · tkt-33 (marker fix)

## Lineage

- Parent spec: none (ticket-only) · Primary ticket: **tkt-95** · Parallel group: **G1 (wave 1)** · Worktree bind: `tkt-95-docs-truth`

## Finish
