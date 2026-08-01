# tkt-<id>-<semantic-slug>

<!-- Binder is a thin recovery card (not a second issue tracker).
     required: kind, priority, github, status, acceptance, primary_ticket / worktree_bind when shipping
     recommended: covers, spec, summary/TL;DR, Path
     optional (parallel / C): blocked_by, parallel_group, paths, solo_merge, related_tickets -->

> **TL;DR:** <one sentence slice — standalone>
> **Kind:** feat · **Status:** open · **Priority:** P2
> **Path:** spc-N → tkt-<id> → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | feat, P2 |
| github | https://github.com/<org>/<repo>/issues/<id> |
| status | open |
| adopted | false | true — **true** when GH issue body is hand-created / append-only; land uses binder-first Acceptance |
| summary | ≤120 chars |
| spec | spc-N — <one-line> (path: ../../specs/spc-N-<slug>.md) |
| covers | A1, A2 |
| blocked_by | (none \| #N) |
| parallel_group | G1 \| (serial) |
| paths | approx globs this slice may touch |
| solo_merge | yes \| no |
| **primary_ticket** | tkt-<id> (this issue) — owner of the ship when this tree has one PR |
| **related_tickets** | (none \| tkt-… sub/Refs tickets on the same PR) |
| **worktree_bind** | `tkt-<id>-<slug>` \| `spc-<n>-<slug>` \| full branch name (open-time bind; rebind optional) |
| worktree | sibling `…/<repo>.worktrees/<worktree_bind or branch>/` (**default for shippable**) |
| prs | (none \| pr-P / URL) |

## Acceptance (this slice)

<!-- Mirror Spec A* ids this ticket owns (light RTM). Do not re-grill whole Spec here. -->
- [ ] **A1** <slice criterion>
- [ ] **A2** <slice criterion>

## Notes

<!-- Sub-tickets: serial extras on the same PR stay related_tickets + PR Refs.
     Default: one sibling worktree per ship slot. New worktree only when
     parallel degree ≥ 2 and independence gates pass. -->

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-N` (path above) — do not duplicate full Spec here
- ADR: cite only if this slice implements a cross-feature decision (`ADR-NNN`)
- Worktree policy: one tree ↔ one PR; spc\|tkt open binds

## Lineage

- Parent spec: **spc-N**
- Parent issue (GH sub-issue of Spec primary when Spec exists): **#N** | none (ticket-only)
- Primary ticket: **tkt-<id>**
- Related / sub-tickets: …
- Covers: **A1, A2**
- Blocked by: … (dependency DAG — not parent)
- Parallel group: …
- Worktree bind: …
- Child PRs: … (GitHub Fixes/Refs is SoT)

## Assets

Local files in `./assets/`. Prefer media upload (`create-pr` / `create-tickets` shared script) for durable GH URLs in the **GitHub issue** body.

## Finish

- (none yet)
- <!-- After merge: keep ONE ## Finish section. Example:
     pr-P merged: YYYY-MM-DD — https://github.com/<org>/<repo>/pull/P
     issue #N closed: YYYY-MM-DD — https://github.com/<org>/<repo>/issues/N
     Use firm GH dates; check off Acceptance; update Notes/status together. -->
