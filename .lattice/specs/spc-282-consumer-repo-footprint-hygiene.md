---
# status: draft | locked | done | superseded
id: spc-282
slug: consumer-repo-footprint-hygiene
title: Consumer-repo footprint hygiene — relocate runtime state, bootstrap tracked gitignore
kind: chore
status: done
mode: C
priority: P1
summary: "Stop Lattice temp files leaking into fresh customer repos: relocate runtime state out-of-tree, bootstrap tracked gitignore, fix onboarding."
created: 2026-08-31
updated: 2026-08-31
tickets: [tkt-283, tkt-284, tkt-285, tkt-286, tkt-287]
prs: []
reviews: []
supersedes: []
superseded_by: null
---

# Spec: Consumer-repo footprint hygiene — relocate runtime state, bootstrap tracked gitignore

> **TL;DR:** Lattice is installed on a customer's system and used across many repos, including fresh repos with no pre-existing Lattice gitignore; runtime gate markers, coordination state, and atomic-write temps leak as untracked dirt. Relocate pure per-clone runtime state to `$XDG_STATE_HOME/lattice/<repo-fingerprint>/`, bootstrap tracked `.lattice/.gitignore` + `docs/adr/.gitignore` for residual co-located temps, and make the commit-`.lattice/` onboarding contract explicit.
> **Kind:** chore · **Status:** done · **Mode:** C · **Priority:** P1
> **Path:** spc-282 → tkt-… → pr-…

## Why

Lattice is not a standalone product — it is a workflow tool installed on a customer's system and used across many repos. A systematic audit of every disk-write path in `skills/**`, `plugins/**`, and `_lattice-lib/**` surfaced three problems that are invisible inside the Lattice monorepo (which happens to have a complete `.lattice/.gitignore` and root `.gitignore`) but leak in **every fresh customer repo**:

1. **Three inconsistent gitignore sources.** The monorepo root `.gitignore` is complete-ish; a scoped `.lattice/.gitignore` (single line: `.batch-work-active`) is **never created** by `lattice-init.sh` in a consumer repo; and the inline ignore block appended to the consumer's root `.gitignore` is a **subset** missing `.lattice/.transition-leder/*.lock`, `.lattice/.coordinator/`, `.lattice/.batch-merge-authorized`, and `docs/adr/` temps. The `flow.md:168` comment claiming "MAIN `.lattice/.gitignore` tolerates it" is **stale for fresh consumer repos**.

2. **Seven leak classes** of runtime/temp files surface as untracked dirt in a fresh customer repo — `.batch-work-active` (B1), `.batch-merge-authorized` (B2), `.coordinator/` json + `.lock` + `.state.XXX` temps whose `.state.` prefix misses the `.lattice/**/.*.tmp` pattern (B3–B5), transition-ledger `.lock` sidecars (B7), and `docs/adr/` lock dirs + atomic-write temps (B14–B17). An interrupted batch or a `finish-work` that misses its `--remove` step leaves residue that accumulates across runs.

3. **Onboarding contract gap.** `ensure-lattice.sh` scaffolds `.lattice/preferences.md`, `.lattice/config.yaml`, and `.lattice/README.md` onto MAIN as **tracked-by-design** decision-chain artifacts, with no auto-commit and no guidance — the "Preferences file appearing in main branch" symptom — and `check-base-residue.sh` mis-flags the legitimate first-scaffold as leak residue.

The historical precedent is `spc-277` / `tkt-278` (commit `b91627b`): a persisted generated-config file (`.lattice/gitignore.snippet`) under `.lattice/` was itself a leak source and was **eliminated in favor of inline emission**. This Spec generalizes that principle from one file to the whole runtime-state class, and locks the overall footprint contract for an arbitrary customer repo.

**User value:** a customer who installs Lattice and runs batch-work / create-spec / create-tickets in a fresh repo sees **zero Lattice temp-file leakage** regardless of whether they ever touch a `.gitignore`, and a clear one-time message telling them `.lattice/` is meant to be committed.

## In scope

- Relocate batch-work gate markers (`.batch-work-active`, `.batch-merge-authorized`) from `<MAIN>/.lattice/` to `$XDG_STATE_HOME/lattice/<repo-fingerprint>/` (macOS fallback `$HOME/.local/state/lattice/`), keyed by `sha1("$(git rev-parse --git-common-dir)" abs path)[:12]` so all sibling worktrees of one MAIN clone resolve to one single-gate-point marker.
- Relocate the coordinator spine (`.coordinator/` json + `.lock` + `.state` temps) to the same state dir.
- Relocate transition-ledger `.jsonl.lock` flock sidecars to the state dir (the `.jsonl` stays committed).
- Bootstrap a **tracked** `.lattice/.gitignore` (in consumer repos via `lattice-init.sh`) as the single source of truth for the `.lattice/` residual temp subclass (`**/.*.tmp`, plus any remaining co-located locks); de-duplicate the root inline block to carry only non-`.lattice` entries.
- Bootstrap a **tracked** `docs/adr/.gitignore` covering ADR atomic-write temps + mutex lock dirs (`.create-adr.lock/`, `README.lock/`, `.*.tmp*`); harden EXIT-trap cleanup.
- Onboarding contract: `ensure-lattice.sh` / `lattice-init.sh` emits a one-time "`.lattice/` is meant to be committed; run `git add .lattice/` once" guidance line when scaffolding tracked bootstrap files; `check-base-residue.sh` treats scaffolded-once files (`preferences.md`, `config.yaml`, `README.md`) as expected-dirt-once (advisory, not hard-residue fail).
- Stale-marker GC: `start-work` scans the state dir for entries whose mtime predates a configurable threshold (default 24h) and removes them as orphan-batch residue.
- One-shot migration: remove now-relocated in-repo files (`.batch-work-active`, `.batch-merge-authorized`, `.coordinator/`) from existing clones on first run after upgrade.
- Amend `ADR-008` / `spc-186` A1 "single gate point" location reference; fix stale `flow.md:168` prose.

## Out of scope

- Configurable footprint model (in-repo vs out-of-repo switch) — rejected (ADR-011 Option C); a customer who wants zero `.lattice/` can add `.lattice/` to their root `.gitignore` themselves; Lattice does not own that switch.
- Relocating project knowledge (specs, tickets, binders, preferences, lineage, ADRs) out-of-repo — these are project-specific and must travel with the code (ADR-011 Option B rejected).
- Relocating atomic-write temps that must stay co-located with their committed target (rename atomicity requires same filesystem) — covered by bootstrapped gitignore, not relocation.
- Changing the batch-work spawn-mode law (ADR-008) — only the gate **location** is amended, not the spawn-mode/process-isolation law.
- Re-architecting the activated-skills marker root (`${XDG_RUNTIME_DIR}/activated-skills/`) — it is already correctly out-of-repo (Category D, clean).

## Acceptance

- [x] **A1** Batch gate markers relocate. `batch-merge-gate.sh` (both `plugins/lattice/hooks/lib/` and `skills/finish-work/scripts/`) resolves `.batch-work-active` + `.batch-merge-authorized` at `$XDG_STATE_HOME/lattice/<fingerprint>/` (macOS `$HOME/.local/state/lattice/<fingerprint>/`) via `git rev-parse --git-common-dir` + sha1, not at `<MAIN>/.lattice/`. `batch-work` skill prose + `references/flow.md` recipe updated. `LATTICE_BATCH_GATE_HOME` override preserved for tests. The `.lattice/.gitignore` `.batch-work-active` line is removed (now dead). The merge hook remains fail-closed: marker present ⇒ `gh pr merge` blocked; marker absent ⇒ allowed (unchanged). All sibling worktrees of one MAIN clone resolve one marker (single-gate-point preserved).
- [x] **A2** Coordinator state relocates. `coordinator.py` `state_dir` writes `.coordinator/<batch-id>.json` + `.lock` + `.state` temps to the state dir keyed by the same fingerprint. `run-process-wave.sh` / `spawn-ticket-process.sh` updated if they reference the old path. Resume across sessions still works (state dir persists on disk).
- [x] **A3** `.lattice/.gitignore` bootstrapped + de-duplicated. `lattice-init.sh` writes a tracked `.lattice/.gitignore` into consumer repos containing the residual `.lattice/` temp subclass (`**/.*.tmp`, any remaining co-located locks not relocated, `.ids/`). The root inline block stops duplicating `.lattice/**` entries (carries only non-`.lattice` entries like `.worktrees/` defensive override). The monorepo's own `.lattice/.gitignore` is reconciled to match.
- [x] **A4** `docs/adr/.gitignore` bootstrapped. `lattice-init.sh` (or `ensure-lattice.sh`) writes a tracked `docs/adr/.gitignore` covering `.create-adr.lock/`, `README.lock/`, `.*.tmp*` so ADR atomic-write temps + mutex lock dirs never surface as untracked dirt. EXIT-trap cleanup in `claim-adr-file.sh` + `append-adr-index-row.sh` hardened (already present; verify).
- [x] **A5** Onboarding contract. `ensure-lattice.sh` / `lattice-init.sh` emits a one-time guidance line when scaffolding tracked bootstrap files (`.lattice/preferences.md`, `config.yaml`, `README.md`) stating `.lattice/` is meant to be committed. `check-base-residue.sh` treats scaffolded-once bootstrap files as expected-dirt-once (advisory message, not a hard residue fail) so the legitimate first-scaffold is not mis-flagged.
- [x] **A6** Stale-marker GC. `start-work` scans the state dir (`$XDG_STATE_HOME/lattice/` / `$HOME/.local/state/lattice/`) for marker entries whose mtime predates a configurable threshold (default 24h, overridable) and removes them as orphan-batch residue. GC only removes stale entries; it never creates markers. A crashed batch does not leave a permanent open gate.
- [x] **A7** Migration + doc amendment. One-shot migration removes now-relocated in-repo files (`.batch-work-active`, `.batch-merge-authorized`, `.coordinator/`) from existing clones on first run after upgrade (read-then-delete; runtime state, no data loss). `ADR-008` + `spc-186` A1 "single gate point" location reference amended to the state dir. Stale `skills/batch-work/references/flow.md:168` "MAIN `.lattice/.gitignore` tolerates it" prose fixed. ADR-011 Status flipped Proposed → Accepted once tickets land.

## Non-goals

- We will **not** offer an in-repo-vs-out-of-repo config switch (ADR-011 Option C rejected); the default is Model A and a customer wanting Model B can gitignore `.lattice/` themselves.
- We will **not** relocate project-knowledge artifacts (specs/tickets/binders/preferences/lineage/ADRs) out-of-repo (ADR-011 Option B rejected — destroys the durable decision chain).
- We will **not** change the batch-work spawn-mode law (ADR-008); only the gate **location** moves.

## Decisions (principal, user-confirmed)

1. **Model A footprint contract** (user-confirmed via footprint-model question): project knowledge stays in `.lattice/` + `docs/adr/` (committed, travels with code); pure per-clone runtime state relocates out-of-repo to `$XDG_STATE_HOME/lattice/<fingerprint>/`; residual co-located atomic-write temps covered by bootstrapped tracked gitignore. — Cross-feature law recorded in `ADR-011`.
2. **Repo fingerprint = `sha1("$(git rev-parse --git-common-dir)" absolute path)[:12]`** — all sibling worktrees of one MAIN clone resolve to the same directory (single-gate-point preserved, spc-186 A1); different MAIN clones get different directories (correct — each clone is its own batch context).
3. **State dir category = `$XDG_STATE_HOME` (not cache, not runtime)** — state must persist across sessions (replaces the abandoned `BATCH_WORK=1` env-var gate) but is not project data. macOS fallback `$HOME/.local/state/lattice/`. Linux uses `$XDG_STATE_HOME` if set, else `$HOME/.local/state/lattice/`.
4. **`.lattice/.gitignore` is tracked (committed), not local-only** — it is part of Lattice's committed footprint in the repo, the single source of truth for the `.lattice/` temp subclass; the root inline block is de-duplicated to avoid two drifting copies.
5. **Stale-marker GC lives in `start-work`** (the natural batch-entry skill), operates on mtime, default 24h, overridable. Fail-closed-by-absence is unchanged (absent marker ⇒ merge allowed, same as today); GC only removes, never creates.
6. **One-shot migration is read-then-delete** — relocated files are runtime state, not knowledge; no data loss. No git history rewrite.

## Agent-assumed (secondary)

- `$XDG_STATE_HOME` is preferred over `$XDG_CACHE_HOME` because cache may be aggressively auto-cleaned by OS utilities (fail-open risk for a fail-closed gate); state is the correct XDG category for "persists across sessions, not project data."
- `LATTICE_BATCH_GATE_HOME` env var (already present as test override) is repurposed as the state-dir-root override; existing tests that `touch "$LATTICE_BATCH_GATE_HOME/.batch-work-active"` continue to work.
- The `activated-skills` marker root (`${XDG_RUNTIME_DIR}/activated-skills/`, Category D) is left as-is — already correctly out-of-repo.

## Risks / open questions

- **State-dir auto-clean risk:** if an OS utility clears `$XDG_STATE_HOME` mid-batch, the gate opens prematurely. Mitigated by stale-marker GC on mtime + batch-work re-touching the marker each wave (heartbeat). Acceptable: today an absent marker also allows merge; the only new risk is a premature open during a still-running batch, which the heartbeat bounds.
- **Lost `git status` visibility:** the marker no longer shows as untracked dirt. Replaced by `batch-merge-gate.sh --status` + GC. Acceptable in consumer repos (that visibility was the pollution being complained about).
- **Fingerprint collision:** sha1[:12] of the common-dir absolute path — collision probability across reasonable clone counts is negligible; two clones at the same absolute path on the same machine is impossible (the dir would already exist).
- **`docs/adr/.gitignore` in a repo that already commits `.gitignore` patterns differently** — the bootstrap is append-only/idempotent; if the customer has conflicting rules, the Lattice patterns are scoped to `docs/adr/` and `.lattice/` only.
- **Open:** does `.lattice/lineage/` (currently gitignored, derived) and `.lattice/BOARD.md` (gitignored, derived) remain derived/temp, or should they relocate too? Current decision: leave as derived (gitignored) — they are regenerable indexes, not primary knowledge. Verify in A3 implementation.

## References

- ADR: `ADR-011` → `docs/adr/011-consumer-repo-footprint-hygiene.md` (the cross-feature law)
- Prior Spec: `spc-277` (gitignore.snippet leak — the one-file precedent), `spc-186` (hard-limit closure / batch gate A1), `spc-254` (transition-ledger + coordinator spine), `spc-213` (batch-work process spawn)
- ADR: `ADR-008` (batch-work process-isolation spawn — gate location amended, spawn law unchanged), `ADR-007` (hard-limit scope law — human adjudicates merge)
- Issue: `#282` (epic primary)

<!-- required lists in front matter; body is recovery -->
## Links / bloodline (L0)

- Tickets: tkt-283 (A1,A2,A3), tkt-284 (A4), tkt-285 (A5), tkt-286 (A6), tkt-287 (A7)
- PRs: (none yet)
- Reviews: (none yet)
