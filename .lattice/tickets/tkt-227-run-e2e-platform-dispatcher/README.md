# tkt-227-run-e2e-platform-dispatcher

<!-- Binder is a thin recovery card (not a second issue tracker). -->

> **TL;DR:** Make run-e2e platform-aware (macOS→ego-lite, Linux→camoufox-js via playwright-cli) with a confirm-first install gate.
> **Kind:** feat · **Status:** open · **Priority:** P2
> **Path:** spc-226 → tkt-227 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | feat, P2 |
| github | https://github.com/percena/lattice/issues/227 |
| status | closed |
| adopted | false |
| summary | Platform-split run-e2e preflight + two-backend SKILL.md + Linux story-template |
| spec | spc-226 — run-e2e platform dispatcher + confirm-first preflight (path: ../../specs/spc-226-run-e2e-platform-dispatcher.md) |
| covers | A1, A2, A3, A4, A5 |
| blocked_by | (none) |
| parallel_group | (serial) |
| paths | skills/run-e2e/scripts/**, skills/run-e2e/SKILL.md, skills/run-e2e/references/story-template-linux.md |
| solo_merge | yes |
| **primary_ticket** | tkt-227 |
| **related_tickets** | (none) |
| **worktree_bind** | spc-226-run-e2e-platform-dispatcher (spc-bound; rebinding to tkt optional — one PR, one tree) |
| worktree | sibling `…/lattice.worktrees/spc-226-run-e2e-platform-dispatcher/` |
| prs | pr-229 (https://github.com/percena/lattice/pull/229) |

## Acceptance (this slice)

- [x] **A1** macOS with `ego-browser` installed → `ensure-e2e-runtime.sh` exit 0, `E2E_BACKEND=ego`; missing → non-zero + install guidance, no auto-install.
- [x] **A2** Linux with camoufox-js + playwright-cli → exit 0, `E2E_BACKEND=camoufox`; missing either → non-zero + install guidance, no auto-install.
- [x] **A3** `run-e2e/SKILL.md` first step invokes the preflight; missing runtime surfaced to user for confirmation before install.
- [x] **A4** `run-e2e/SKILL.md` cites ADR-009 and documents both backends + primitives mapping.
- [x] **A5** `story-template-linux.md` exists and mirrors `story-template.md` structure.

## Notes

- Single delivery ticket, one PR (solo-merge). Worktree was bound to `spc-226` at
  spec-create time; rebind to `tkt-227` is optional since one tree ↔ one PR holds.
- ADR-009 lives uncommitted on `dev` base (ADR-only durable doc). This ticket's PR
  should commit ADR-009 + README index on base via the audited base-write escape, or
  land ADR-009 separately first.

## References

- GitHub issue body is SoT for long prose: https://github.com/percena/lattice/issues/227
- Spec: `spc-226` (path above) — do not duplicate full Spec here
- ADR: `ADR-009` → `docs/adr/009-platform-stratified-e2e-runtime.md`
- Worktree policy: one tree ↔ one PR; spc|tkt open binds

## Lineage

- Parent spec: **spc-226**
- Parent issue (GH sub-issue of Spec primary): **#226**
- Primary ticket: **tkt-227**
- Related / sub-tickets: (none)
- Covers: **A1, A2, A3, A4, A5**
- Blocked by: (none)
- Parallel group: (serial)
- Worktree bind: spc-226-run-e2e-platform-dispatcher
- Child PRs: pr-229 (https://github.com/percena/lattice/pull/229) — GitHub `Fixes #227` is SoT

## Assets

Local files in `./assets/`.

## Finish


- pr-229 merged: 2026-08-29T16:48:13Z — https://github.com/percena/lattice/pull/229 (base merge)
- issue #227 closed: 2026-08-29T16:48:35Z — https://github.com/percena/lattice/issues/227
