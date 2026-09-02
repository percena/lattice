# ADR 011: Consumer-repo footprint hygiene — relocate runtime state, bootstrap tracked gitignore

- **Status:** Accepted
- **Date:** 2026-08-31
- **Deciders:** maintainers
- **Related:** `spc-282`, `spc-277`, `spc-186`, `spc-254`, `ADR-008`, `ADR-007`
- **Related ADRs:** amends ADR-008 §"single gate point" (the gate location, not the spawn-mode law)

## Context

Lattice is not a standalone product — it is a workflow tool **installed on a customer's system** and used across many repos, including fresh customer repos that have **no pre-existing Lattice gitignore**. The tool writes files into the host repo as part of its normal operation (gate markers, coordination state, atomic-write temps, scaffolded decision-chain artifacts). A systematic audit of every disk-write path in `skills/**`, `plugins/**`, and `_lattice-lib/**` surfaced three problems that are invisible inside the Lattice monorepo but leak in every fresh consumer repo:

1. **Three inconsistent gitignore sources.** The monorepo root `.gitignore` is complete-ish; a scoped `.lattice/.gitignore` (single line: `.batch-work-active`) is **never created** by `lattice-init.sh` in a consumer repo; and the inline ignore block appended to the consumer's root `.gitignore` is a **subset** missing several paths (`.lattice/.transition-ledger/*.lock`, `.lattice/.coordinator/`, `.lattice/.batch-merge-authorized`, `docs/adr/` temps). The `.lattice/.gitignore` "tolerates it" comment in `skills/batch-work/references/flow.md:168` is **stale for fresh consumer repos**.

2. **Seven leak classes** of runtime/temp files that surface as untracked dirt in a fresh customer repo — `.batch-work-active`, `.batch-merge-authorized`, `.coordinator/` (json + `.lock` + `.state.XXX` temps whose `.state.` prefix misses the `.lattice/**/.*.tmp` pattern), transition-ledger `.lock` sidecars, and `docs/adr/` lock dirs + atomic-write temps. A batch run that is interrupted, or a `finish-work` that does not reach its `--remove` step, leaves residue that accumulates across runs.

3. **Onboarding contract gap.** `ensure-lattice.sh` scaffolds `.lattice/preferences.md`, `.lattice/config.yaml`, and `.lattice/README.md` onto the MAIN clone as **tracked-by-design** decision-chain artifacts, but with no auto-commit and no guidance. In a fresh consumer repo these surface as untracked dirt — the "Preferences file appearing in main branch" symptom — with no message telling the operator that `.lattice/` is meant to be committed.

The historical precedent is `spc-277` / `tkt-278` (commit `b91627b`): a persisted generated-config file (`.lattice/gitignore.snippet`) under `.lattice/` was itself a leak source and was **eliminated in favor of inline emission**. The same "don't persist generated config; emit inline or relocate out-of-tree" principle applies to the gaps here, but the broader question — what is Lattice's overall footprint contract in an arbitrary customer repo? — outlives that one ticket and needs durable law.

## Decision Drivers

- **Zero cooperation assumption.** A fresh customer repo has no Lattice-aware `.gitignore`; Lattice must not assume the host repo will ignore its temp files.
- **Single gate point preserved.** The batch-work merge gate (spc-186 A1, ADR-008) requires that all sibling worktrees of a MAIN clone resolve to **one** gate marker. Any relocation must preserve this — a per-worktree marker was explicitly retired by spc-186 A1.
- **Fail-closed stays fail-closed.** A marker that the OS clears mid-batch must not silently open the merge gate beyond today's behavior (today: absent marker ⇒ merge allowed; the risk is a premature open during a still-running batch).
- **Atomic-write temps must stay co-located.** `os.replace` / `mv`-based atomic writes (binder mutation, ADR publication) require the temp file and target on the **same filesystem**; these cannot be relocated out-of-repo.
- **Project knowledge travels with the code.** Specs, tickets, binders, preferences, lineage, and ADRs are project-specific and must remain committable in `.lattice/` + `docs/adr/` so they version with the code and share across collaborators.
- **Cross-session persistence.** Runtime gate state must survive across ephemeral Bash sessions in spawned agents (this is why the earlier `BATCH_WORK=1` env-var gate was abandoned).

## Considered Options

- **Option A — Relocate runtime state out-of-repo; bootstrap tracked gitignore for residual co-located temps; fix onboarding.** Pure per-clone runtime state (batch markers, coordinator spine, flock sidecars that protect committed files) moves to `$XDG_STATE_HOME/lattice/<repo-fingerprint>/` (macOS fallback `$HOME/.local/state/lattice/`). Atomic-write temps that must stay co-located with their committed target get covered by a Lattice-bootstrapped **tracked** `.lattice/.gitignore` + `docs/adr/.gitignore`. The onboarding contract makes "commit `.lattice/`" explicit. (good: zero temp leakage in fresh repos, gate semantic preserved via fingerprint, project knowledge still travels with code; bad: loses in-repo `git status` visibility of the marker, needs a stale-marker GC, state dir must persist reliably across sessions.)
- **Option B — Relocate everything Lattice writes out-of-repo; `.lattice/` never appears.** Even specs/tickets/preferences move to `$HOME/.local/state/lattice/<fingerprint>/.lattice/`. (good: absolute zero repo pollution; bad: loses cross-collaborator sharing, cross-machine sync, and `git log` of decision history — Lattice's durable decision chain degrades to single-machine local state. Rejects the core value prop.)
- **Option C — Per-repo config flag `commit_footprint=true|false`.** Supports both A and B. (good: flexibility; bad: two code paths, doubled test matrix, and the default still has to be picked — which is A. Added complexity for a case that can be served by the customer gitignoring `.lattice/` themselves if they truly want B.)

Rejected: B rejects Lattice's durable decision chain value; C adds a config surface whose default is A, and a customer who genuinely wants B can simply add `.lattice/` to their root `.gitignore` — Lattice does not need to own that switch.

## Decision

We adopt **Option A**. Three policies form one footprint contract:

1. **Project knowledge stays in-repo and is meant to be committed.** `.lattice/{specs,tickets,lineage,reviews,preferences.md,config.yaml,README.md,.transition-ledger/*.jsonl}` and `docs/adr/**` remain where they are — they are project-specific knowledge that must travel with the code. No relocation.

2. **Pure per-clone runtime state relocates OUT of the repo tree** to a state directory keyed by a repo fingerprint:

   ```
   $XDG_STATE_HOME/lattice/<fingerprint>/        (macOS fallback: $HOME/.local/state/lattice/<fingerprint>/)
   <fingerprint> = sha1("$(git rev-parse --git-common-dir)" absolute path)[:12]
   ```

   The fingerprint resolves to one directory per MAIN clone, so all sibling worktrees of that clone hit the **same** directory — the single-gate-point semantic is preserved (spc-186 A1). Relocate: `.batch-work-active`, `.batch-merge-authorized`, the `.coordinator/` spine (json + `.lock` + `.state` temps), and transition-ledger `.jsonl.lock` flock sidecars. The merge hook (`batch-merge-gate.sh`) and `coordinator.py` resolve this directory the same way they currently resolve `<MAIN>/.lattice/` — by walking `git rev-parse --git-common-dir`, then hashing, then substituting the state-dir root. `LATTICE_BATCH_GATE_HOME` remains as the test/manual override.

3. **Atomic-write temps that MUST stay co-located** (binder `.ratify/.finish-ledger/.stamp-pr-open/.bump-fix-cycle/.supersede/.ci-gate *.tmp`, ADR `.tmp.XXXXXX` + lock dirs) remain in-tree because `os.replace`/`mv` atomicity requires the same filesystem. They are covered by a **tracked** `.lattice/.gitignore` and a new tracked `docs/adr/.gitignore`, both **bootstrapped by `lattice-init.sh`** into consumer repos as part of Lattice's committed footprint. The `.lattice/.gitignore` becomes the single source of truth for the `.lattice/` temp subclass; the root inline block is de-duplicated to carry only non-`.lattice` entries (`.worktrees/` defensive override case).

**Onboarding contract:** `ensure-lattice.sh` / `lattice-init.sh` emits a one-time guidance line when it scaffolds `.lattice/preferences.md` (or any tracked-by-design bootstrap file) onto MAIN stating that `.lattice/` is meant to be committed and the operator should `git add .lattice/` once. `check-base-residue.sh` treats scaffolded-once bootstrap files (`preferences.md`, `config.yaml`, `README.md`) as **expected-dirt-once** (advisory, not a hard residue fail) so that the legitimate first-scaffold is not mis-flagged as leak residue.

**Stale-marker GC:** `start-work` (the natural batch-entry skill) scans the state dir for entries whose mtime predates a configurable threshold (default 24h) and removes them as orphan-batch residue, so a crashed batch does not leave a permanent open gate. The batch marker is fail-closed by absence (same as today); GC only removes stale entries, never creates them.

## Consequences

- **Positive:**
  - Fresh customer repos have zero Lattice temp-file leakage regardless of whether the operator ever touches a `.gitignore`.
  - The batch-work merge gate remains fail-closed and single-gate-pointed; all sibling worktrees resolve one marker via the common-dir fingerprint.
  - Project knowledge (specs/tickets/preferences/lineage/ADR) still travels with the code, stays versioned, and shares across collaborators.
  - The gitignore layering becomes one source of truth per directory (`.lattice/.gitignore` for the `.lattice/` temp subclass, `docs/adr/.gitignore` for ADR temps) instead of three drifting copies.
  - `spc-277`'s "don't persist generated config; relocate or emit inline" principle is generalized from one file to the whole runtime-state class.
- **Negative / trade-offs:**
  - The marker is no longer visible in `git status` as untracked dirt — the "cleanup visibility" affordance relied on by the old `.lattice/.gitignore` comment is gone. Replaced by `batch-merge-gate.sh --status` + the stale-marker GC. Acceptable: in a consumer repo that visibility was exactly the pollution being complained about.
  - The state dir must persist across sessions and not be aggressively auto-cleaned by the OS. `$XDG_STATE_HOME` / `$HOME/.local/state/` is the right XDG category (state, not cache); still, a crash mid-batch + an OS cleanup could open the gate prematurely. Mitigated by the stale-marker GC operating on mtime and by batch-work re-touching the marker each wave (heartbeat).
  - One-time migration: existing Lattice monorepo + any consumer repos with residual in-repo `.batch-work-active` / `.coordinator/` / `.batch-merge-authorized` need a one-shot cleanup pass to remove the now-relocated files. The migration is read-then-delete (no data loss — the state is runtime, not knowledge).
- **Follow-ups:** `spc-282` splits this into tickets — batch-gate marker relocation, coordinator relocation, `.lattice/.gitignore` + `docs/adr/.gitignore` bootstrap, onboarding contract, stale-marker GC, doc/prose amendment (ADR-008 / spc-186 A1 "single gate point" definition update + stale `flow.md` comment fix).
- **Verification:**
  - `batch-merge-gate.sh --status` reports the resolved state-dir path and marker presence.
  - A fresh-clone simulation test (`mktemp -d` repo → `lattice-init` → `batch-work` → assert `git status` shows zero Lattice temp files) lands in the test suite.
  - `check-base-residue.sh` no longer flags scaffolded bootstrap files as residue.
  - `ensure-lattice.bats` gains a "fresh repo leaves no untracked Lattice temp" assertion.

## Status history

- 2026-08-31: Proposed (drafted alongside `spc-282` scope lock).
- 2026-08-31: Proposed → Accepted — tkt-283..287 landed (A1-A7): runtime state relocated to `$XDG_STATE_HOME/lattice/<repo-fingerprint>/`, tracked `.lattice/.gitignore` + `docs/adr/.gitignore` bootstrapped, onboarding contract + stale-marker GC + migration shipped. Fresh-customer-repo zero-leak verified.

## Amendment (2026-09-02, spc-337 / tkt-342)

The per-wave marker **heartbeat** this ADR relied on ("batch-work re-touching the marker each wave") is now implemented, and marker **creation is scripted**:

- `skills/finish-work/scripts/batch-merge-gate.sh --create --batch-id <id>` writes the `.batch-work-active` marker (`batch-id:` + `started:` lines) at the state home; idempotent for the same id, refuses a different id without `--force`. `batch-work` prose no longer hand-`printf`s the marker.
- `batch-merge-gate.sh --touch` refreshes the marker mtime. `skills/batch-work/scripts/run-process-wave.sh` calls it at the end of every barrier whenever `--batch-id` is set (the canonical SKILL/flow invocation now passes it), so the mtime-based stale-marker GC never reaps a live batch. An absent marker or missing gate script is a warning, never a wave failure.

Verification: `skills/finish-work/scripts/tests/batch-merge-gate.bats` (create / idempotent / refuse / force / touch) and `skills/batch-work/scripts/tests/run-process-wave.bats` (`--touch` called at the barrier when `--batch-id` is set; end-to-end mtime advance).

## Notes

The full disk-write catalog that informed this decision (Categories A–E, 30+ paths across `skills/**`, `plugins/**`, `_lattice-lib/**`) is recorded in `spc-282` Acceptance evidence. The "good" out-of-tree writes already in place (`${TMPDIR}` scratch, the uid-namespaced `${XDG_RUNTIME_DIR}/activated-skills/` root) confirm the relocation pattern is precedented and works on both macOS and Linux. ADR-008's spawn-mode law is unaffected; only its "single gate point at `<MAIN>/.lattice/`" location reference is amended to the state dir.

---

_Not a Lattice bloodline/graph node. Cite from Spec/PR/Review with `ADR-011` or this path._
