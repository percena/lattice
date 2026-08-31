---
id: spc-277
slug: gitignore-snippet-leak
title: Eliminate .lattice/gitignore.snippet leak into consumer active branches
kind: feat
status: locked
mode: M
priority: P1
summary: "Stop persisting .lattice/gitignore.snippet; write block inline to .gitignore so it never surfaces as untracked in consumer repos"
created: 2026-08-31
updated: 2026-08-31
tickets: []
prs: []
reviews: []
supersedes: []
superseded_by: null
---

# Spec: Eliminate .lattice/gitignore.snippet leak into consumer active branches

> **TL;DR:** `lattice-init.sh` materializes `.lattice/gitignore.snippet` every run; its self-ignore line only works after the block is merged into `.gitignore`, so partial/older/direct-call consumer repos see it as an untracked file in `git status`. Stop persisting the file — keep the block inline, write `.gitignore` directly, echo to stdout for manual merge.
> **Kind:** feat · **Status:** locked · **Mode:** M · **Priority:** P1
> **Path:** spc-277 → tkt-… → pr-…

## Why

`lattice-init.sh` unconditionally writes `.lattice/gitignore.snippet` (a "merge helper" copy of the Lattice ignore block). The file is meant to be merged into the consumer repo's `.gitignore`, and the block contains a self-ignore line `.lattice/gitignore.snippet`. But that self-ignore only takes effect **after** the block is in `.gitignore`. This is a chicken-and-egg: until merged, the snippet itself surfaces as an **untracked file in `git status`** — it leaks into the active branch.

Leak paths (reviewed and confirmed):

1. **`ALREADY` heuristic too wide** (`lattice-init.sh:199-205`): any `.lattice/lineage/|BOARD.md|.ids/` rule in `.gitignore` marks the block "already merged" and skips the append. If that pre-existing `.gitignore` lacks the snippet self-ignore line, the snippet leaks. Hits: consumers that hand-added partial rules, ran an older Lattice install, or were partially configured.
2. **Direct `lattice-init.sh` without `--write-gitignore`** always creates the file without merging → guaranteed leak.
3. The file is **obsolete**: block content is an inline heredoc; `ensure-lattice.sh` already defaults `--write-gitignore=true`; the "manual merge helper" use-case is vestigial.

Unacceptable hygiene: every consumer repo can hit this; the file must never appear as untracked in a branch.

## In scope

- Remove persistent `.lattice/gitignore.snippet` creation from `lattice-init.sh` (all code paths).
- Keep the Lattice ignore block as inline content in the script; `--write-gitignore` writes it directly to `.gitignore` (idempotent, no transient file).
- Without `--write-gitignore`, echo the block to stdout for manual merge (replaces the "merge the file" tip).
- One-shot migration: on run, `rm -f` any pre-existing stray `.lattice/gitignore.snippet`.
- Remove the snippet self-ignore line from the block content (no file → no self-ignore needed).
- Remove `gitignore.snippet` from `assert_managed_paths_safe` managed-path list.
- Update `lattice-init.bats` assertions.
- Clean the now-dead `.lattice/gitignore.snippet` rule from this repo's `.gitignore`.

## Out of scope

- Rewriting the `ALREADY` heuristic itself (moot once no file is created; left as-is to avoid scope creep).
- Changing `ensure-lattice.sh` default `--write-gitignore=true` (already correct).
- Any change to `.lattice/.gitignore` or other managed paths.

## Acceptance

- [ ] **A1** `lattice-init.sh` never creates `.lattice/gitignore.snippet` on any code path (with/without `--write-gitignore`).
- [ ] **A2** `--write-gitignore` writes the Lattice ignore block directly from inline content to `.gitignore`, idempotent (marker present → no double-append; no transient file touched).
- [ ] **A3** Running `lattice-init.sh` without `--write-gitignore` produces no untracked file; the block is echoed to stdout for manual merge.
- [ ] **A4** One-shot migration: a pre-existing stray `.lattice/gitignore.snippet` (from an old run) is removed on the next `lattice-init.sh` run.
- [ ] **A5** `lattice-init.bats` updated: asserts `.lattice/gitignore.snippet` does **not** exist and (with `--write-gitignore`) the block is in `.gitignore`; existing suite green.
- [ ] **A6** This repo's `.gitignore` dead rule `.lattice/gitignore.snippet` removed (or confirmed harmless-and-removed).

## Non-goals

- Building a "worktree-local snippet" variant — the snippet serves the consumer root `.gitignore`, which is worktree-agnostic; a worktree placement does not solve the leak.

## Decisions (principal, user-confirmed)

1. **Do not persist the file** (over "keep file + fix the heuristic"). Removing the file eliminates the leak at the root across every consumer config; fixing only the `ALREADY` heuristic would remain fragile to any future hand-edit of `.gitignore`. Confirmed by user.
2. **Inline block + direct `.gitignore` write** (over "temp file then delete"). The block is already an inline heredoc; a temp file is needless indirection.
3. **Echo to stdout for manual-merge mode** (over "force `--write-gitignore` always"). Keeps the escape hatch for repos that prefer manual review; the agent entrypoint already defaults to write.

## Agent-assumed (secondary)

- Spec id `spc-277` from primary GitHub issue #277 (team SoT).
- Migration cleanup is best-effort `rm -f` (never fails the run if absent).

## Risks / open questions

- Consumers that intentionally committed `.lattice/gitignore.snippet` (against guidance) will see it deleted on next run — acceptable, the file was never meant to be tracked.

## References

- Primary: GitHub issue #277 (epic)
- Code: `skills/_lattice-lib/scripts/lattice-init.sh`, `skills/_lattice-lib/scripts/ensure-lattice.sh`

## Links / bloodline (L0)

- Tickets: (pending split — `tkt-N`)
- PRs: (pending — prefer GitHub `Fixes`)
- Reviews: (none)
