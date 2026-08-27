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
| status | closed |
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
| prs | pr-113 — https://github.com/percena/lattice/pull/113 |

## Acceptance (this slice)

- [x] **A1** `httpErrors` array in the JSON schema (first-party 4xx/5xx via `page.on('response')` + `requestfailed`), subscription registered before navigation, wired through Core rules / Flow / Verification / template / example; allowlist note for expected failures
- [x] **A2** story header convention (feature id, oracle citation, `mutations: none|safe|destructive`) in template + example
- [x] **A3** mutation round-trip recipe (create → reload → assert persisted) + story catalog convention `.lattice/e2e/stories/*.story.md`
- [x] **A4** ci-local green; carries the shared 0.3.0 cut byte-identically

## Approach

Additive edits keeping run-e2e a pattern, not a runner (ADR-002 §2). httpErrors mirrors the existing consoleErrors/pageErrors discipline: subscribe before nav, separate array, first-party filter (same-origin or operator-listed API origins), reason codes. Story header = a small front-matter block at the top of `*.story.md` files (docs convention, not parsed by tooling yet). Round-trip recipe added beside the fail-loud auth section with a worked snippet. Catalog path documented in SKILL.md Flow + template intro.

## Anticipated decisions

- First-party filter definition — agent-decides (same-origin by default + optional origin allowlist in the story header); journal
- Whether 4xx on expected-negative stories fails — pre-resolved: the story's own oracle decides; the bundle default treats unexpected 4xx/5xx as fail, header may allowlist

## Decision journal

- 2026-08-27 — **First-party definition:** same origin as `STORY_URL` (the app under test) **plus** origins listed in the story header `origins_allow` (APIs on other ports/hosts). Everything else (analytics, CDNs) is excluded from `httpErrors` entirely — third-party noise never enters the array. Templates carry an `isFirstParty(url)` helper mirroring this.
- 2026-08-27 — **`http_allow` semantics:** allowlist entries are `"<METHOD> <url-substring> <status>"` (e.g. `"POST /api/login 422"`). Allowlisted entries **stay in the `httpErrors` array** (evidence is never filtered); only the `no unexpected http errors` assertion filters through the allowlist — same semantics as `console_allow` in verify-features' story-design (bundle default: unexpected first-party 4xx/5xx fail, per binder pre-resolution the story's own oracle decides via the allowlist).
- 2026-08-27 — **Header placement:** header documented as a fenced yaml block at the top of `*.story.md` (docs convention, unparsed); the heredoc mirrors `origins_allow`/`http_allow` as `ORIGINS_ALLOW`/`HTTP_ALLOW` constants so the header states intent and the script enforces it — keeps run-e2e a pattern, not a runner (ADR-002 §2, no parsing layer).
- 2026-08-27 — **Round-trip weight:** documented as DEFAULT (per spc-104 Decision 2's invariant bundle wording, "mutation stories assert the round-trip"), placed as its own section directly after the fail-loud auth INVARIANT; destructive-authorization policy stays in verify-features — run-e2e only defines the pattern.

## Pending decisions

## Attempts

## Notes

- Do not touch _lattice-lib or the validator here — tkt-105 owns map-side definitions

## References

- spc-104 A3 / Decision 2 · rev-20260827-042618Z §Key decisions 8

## Lineage

- Parent spec: **spc-104** (#104) · Primary ticket: **tkt-106** · Parallel group: **G1 (wave 2)** · Worktree bind: `tkt-106-run-e2e-upgrades`

## Finish

- pr-113 merged: 2026-08-27T05:40:23Z — https://github.com/percena/lattice/pull/113 (base merge)
- issue #106 closed: 2026-08-27T05:40:28Z — https://github.com/percena/lattice/issues/106
