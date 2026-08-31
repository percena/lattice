# tkt-278-remove-gitignore-snippet-materialization

> **TL;DR:** Stop persisting .lattice/gitignore.snippet in lattice-init.sh; write the ignore block inline to .gitignore (or echo to stdout); migrate-clean stray files
> **Kind:** feat · **Status:** pr-open · **Priority:** P1
> **Path:** spc-277 → tkt-278 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | feat,P1 |
| github | https://github.com/percena/lattice/issues/278 |
| status | pr-open |
| adopted | false |
| summary | Stop persisting .lattice/gitignore.snippet; write block inline to .gitignore; echo to stdout for manual merge; migrate-clean stray files |
| spec | spc-277 — Eliminate .lattice/gitignore.snippet leak (path: ../../specs/spc-277-gitignore-snippet-leak.md) |
| covers | A1, A2, A3, A4, A5, A6 |
| blocked_by | (none) |
| parallel_group | (none — path-overlap, one-PR) |
| paths | skills/_lattice-lib/scripts/lattice-init.sh, skills/_lattice-lib/scripts/tests/lattice-init.bats, .gitignore |
| solo_merge | yes |
| primary_ticket | tkt-278 |
| related_tickets | (none) |
| worktree_bind | spc-277-gitignore-snippet-leak |
| prs | pr-280 — https://github.com/percena/lattice/pull/280 |
| created | 2026-08-31T00:00:00Z |
| updated | 2026-08-31T00:00:00Z |

## Why

`lattice-init.sh` persists `.lattice/gitignore.snippet` every run. Its self-ignore line only takes effect once the block is merged into `.gitignore`; partial/older/direct-call consumer repos see it as an untracked file leaking into the active branch. See `spc-277` for the full problem + reviewed leak paths.

## Scope (this slice)

Single cohesive fix (path-overlap → one-PR, one worktree):

- Remove `SNIPPET_FILE` materialization (`lattice-init.sh:148-173`).
- Keep the Lattice ignore block inline; `--write-gitignore` writes it directly to `.gitignore` (idempotent, no transient file).
- Without `--write-gitignore`, echo the block to stdout for manual merge (replaces the "merge the file" tip).
- One-shot migration: `rm -f` any pre-existing stray `.lattice/gitignore.snippet`.
- Remove the snippet self-ignore line from the block content.
- Remove `gitignore.snippet` from `assert_managed_paths_safe` managed-path list.
- Update `tests/lattice-init.bats` assertions.
- Clean the now-dead `.lattice/gitignore.snippet` rule from this repo's `.gitignore`.

## Acceptance (this slice)

- [x] **A1** `lattice-init.sh` never creates `.lattice/gitignore.snippet` on any code path.
- [x] **A2** `--write-gitignore` writes the block directly from inline content to `.gitignore`, idempotent.
- [x] **A3** No-flag run echoes the block to stdout; no untracked file produced.
- [x] **A4** Migration removes a pre-existing stray `.lattice/gitignore.snippet`.
- [x] **A5** `lattice-init.bats` updated and green.
- [x] **A6** This repo `.gitignore` dead rule removed.

## Ship plan

one-PR, one worktree (already bound: `spc-277-gitignore-snippet-leak`).
