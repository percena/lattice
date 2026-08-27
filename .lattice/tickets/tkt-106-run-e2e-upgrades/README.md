# tkt-106-run-e2e-upgrades

> **TL;DR:** run-e2e catches the two missing bug classes (silent HTTP failures via httpErrors capture; UI-success-without-persistence via the round-trip recipe) and stories become traceable to the feature map via a header convention + catalog path
> **Kind:** feat · **Priority:** P2
> **Path:** spc-104 → tkt-106 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/percena/lattice/issues/106 |
| status | queued |
| adopted | false |
| summary | httpErrors in schema+pattern, story header (feature id/oracle/mutations), round-trip recipe, .lattice/e2e/stories/ catalog |
| spec | spc-104 — runtime verification loop |
| covers | A3, A5 |
| blocked_by | tkt-105 (header references feature-map ids; train order) |
| parallel_group | G1 (wave 2; path-disjoint with tkt-107/tkt-108) |
| paths | skills/run-e2e/SKILL.md, skills/run-e2e/references/story-template.md, skills/run-e2e/examples/smoke-test.story.md |
| solo_merge | yes (after tkt-105) |
| **primary_ticket** | tkt-106 (this issue) |
| **related_tickets** | tkt-105 (map/story linkage), tkt-16/tkt-31 (skill origin) |
| **worktree_bind** | tkt-106-run-e2e-upgrades |
| worktree | sibling …/lattice.worktrees/tkt-106-run-e2e-upgrades/ |
| prs | (none yet) |

## Acceptance (this slice)

- [ ] **A1** `httpErrors` array in the JSON schema (first-party 4xx/5xx via `page.on('response')` + `requestfailed`), subscription registered before navigation, wired through Core rules / Flow / Verification / template / example; allowlist note for expected failures
- [ ] **A2** story header convention (feature id, oracle citation, `mutations: none|safe|destructive`) in template + example
- [ ] **A3** mutation round-trip recipe (create → reload → assert persisted) + story catalog convention `.lattice/e2e/stories/*.story.md`
- [ ] **A4** ci-local green; carries the shared 0.3.0 cut byte-identically

## Approach

Additive edits keeping run-e2e a pattern, not a runner (ADR-002 §2). httpErrors mirrors the existing consoleErrors/pageErrors discipline: subscribe before nav, separate array, first-party filter (same-origin or operator-listed API origins), reason codes. Story header = a small front-matter block at the top of `*.story.md` files (docs convention, not parsed by tooling yet). Round-trip recipe added beside the fail-loud auth section with a worked snippet. Catalog path documented in SKILL.md Flow + template intro.

## Anticipated decisions

- First-party filter definition — agent-decides (same-origin by default + optional origin allowlist in the story header); journal
- Whether 4xx on expected-negative stories fails — pre-resolved: the story's own oracle decides; the bundle default treats unexpected 4xx/5xx as fail, header may allowlist

## Decision journal

## Pending decisions

## Attempts

## Notes

- Do not touch _lattice-lib or the validator here — tkt-105 owns map-side definitions

## References

- spc-104 A3 / Decision 2 · rev-20260827-042618Z §Key decisions 8

## Lineage

- Parent spec: **spc-104** (#104) · Primary ticket: **tkt-106** · Parallel group: **G1 (wave 2)** · Worktree bind: `tkt-106-run-e2e-upgrades`

## Finish
