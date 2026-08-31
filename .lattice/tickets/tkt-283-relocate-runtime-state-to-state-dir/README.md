# tkt-283-relocate-runtime-state-to-state-dir

> **TL;DR:** Introduce repo-fingerprint state dir; relocate batch gate markers + coordinator + ledger .lock out-of-repo; bootstrap tracked .lattice/.gitignore for residual temps.
> **Kind:** chore · **Status:** open · **Priority:** P1
> **Path:** spc-282 → tkt-283 → (pr-…)

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P1 |
| labels | chore,P1 |
| github | https://github.com/percena/lattice/issues/283 |
| status | closed |
| adopted | false |
| summary | Relocate runtime state (batch markers, coordinator, ledger .lock) to $XDG_STATE_HOME/lattice/<fingerprint>/; bootstrap tracked .lattice/.gitignore for residual co-located temps |
| spec | spc-282 — Consumer-repo footprint hygiene (path: ../../specs/spc-282-consumer-repo-footprint-hygiene.md) |
| covers | A1, A2, A3 |
| blocked_by | (none — foundation) |
| parallel_group | wave-1 (with 284, 285; path-overlap internal → one-PR) |
| paths | plugins/lattice/hooks/lib/batch-merge-gate.sh, skills/finish-work/scripts/batch-merge-gate.sh, skills/batch-work/scripts/lib/coordinator.py, skills/_lattice-lib/scripts/transition-api.py, skills/_lattice-lib/scripts/lattice-init.sh, skills/_lattice-lib/scripts/lattice-state-home.sh (new), .lattice/.gitignore, skills/batch-work/SKILL.md, skills/batch-work/references/flow.md |
| solo_merge | yes |
| primary_ticket | tkt-283 |
| related_tickets | tkt-286 (GC needs state dir), tkt-287 (migration needs final layout) |
| worktree_bind | spc-282-consumer-repo-footprint-hygiene |
| prs | pr-288 — https://github.com/percena/lattice/pull/288 |
| created | 2026-08-31T00:00:00Z |
| updated | 2026-08-31T15:07:30Z |

## Why

Fresh customer repos have no pre-existing `.lattice/.gitignore`; runtime gate markers (`.batch-work-active`, `.batch-merge-authorized`), the coordinator spine (`.coordinator/` json + `.lock` + `.state` temps whose `.state.` prefix misses the `.lattice/**/.*.tmp` pattern), and transition-ledger `.jsonl.lock` sidecars all surface as untracked dirt. Per ADR-011 Model A, pure per-clone runtime state relocates out-of-repo to `$XDG_STATE_HOME/lattice/<repo-fingerprint>/` (macOS `$HOME/.local/state/lattice/`), keyed by `sha1("$(git rev-parse --git-common-dir)" abs path)[:12]` so all sibling worktrees of one MAIN clone resolve one single-gate-point marker (spc-186 A1 preserved).

## Scope

- New `lattice-state-home.sh` helper in `_lattice-lib`: resolves `$XDG_STATE_HOME/lattice/` (or `$HOME/.local/state/lattice/`) + fingerprint; `LATTICE_STATE_HOME` override for tests.
- `batch-merge-gate.sh` (both `plugins/lattice/hooks/lib/` and `skills/finish-work/scripts/`): resolve `.batch-work-active` + `.batch-merge-authorized` at state dir; `LATTICE_BATCH_GATE_HOME` override preserved (re-pointed to state dir).
- `coordinator.py`: `state_dir` → `<state-home>/.coordinator/`; `run-process-wave.sh` / `spawn-ticket-process.sh` updated if they reference the old `.lattice/.coordinator/` path.
- `transition-api.py`: `.jsonl.lock` sidecar path → `<state-home>/.transition-ledger/<ticket>.lock` (the `.jsonl` stays committed in-repo).
- `lattice-init.sh`: bootstrap a **tracked** `.lattice/.gitignore` in consumer repos containing the residual `.lattice/` temp subclass (`**/.*.tmp`, `.ids/`, any remaining co-located locks); de-duplicate the root inline block to carry only non-`.lattice` entries (`.worktrees/` defensive override).
- Remove the now-dead `.batch-work-active` line from the monorepo `.lattice/.gitignore`.
- Update `batch-work/SKILL.md` + `references/flow.md` recipe: marker written to state dir, not `<MAIN>/.lattice/`.
- Tests: `batch-merge-gate.bats` + `intercept-gh-pr-merge.bats` + a fresh-repo zero-leak assertion (`mktemp -d` repo → `lattice-init` → assert `git status` shows no Lattice temp).

## Approach

1. `lattice-state-home.sh`: `fingerprint = sha1($(git rev-parse --git-common-dir) abspath)[:12]`; `STATE_HOME = ${LATTICE_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/lattice}/$fingerprint`; mkdir -p.
2. `batch-merge-gate.sh`: replace `<MAIN>/.lattice/` resolution (`git rev-parse --git-common-dir` + `.lattice/`) with `lattice-state-home.sh` output; keep `LATTICE_BATCH_GATE_HOME` test override.
3. `coordinator.py`: `state_dir = Path(state_home)/.coordinator`; reuse helper via subprocess or Python re-implementation (keep parity).
4. `transition-api.py`: lock path = `state_home/.transition-ledger/<ticket>.lock`.
5. `lattice-init.sh`: write `.lattice/.gitignore` (idempotent block, like the root inline block) with residual temp subclass; inline block drops `.lattice/**` duplicates.
6. `batch-work` skill prose + `flow.md` recipe updated to `printf … > $(lattice-state-home)/.batch-work-active`.

## Anticipated decisions

- `pre-resolved` — state dir = `$XDG_STATE_HOME` (not cache): fail-closed gate needs cross-session persistence; cache may be auto-cleaned (fail-open risk). (ADR-011)
- `pre-resolved` — fingerprint = sha1[:12] of common-dir abs path: single-gate-point preserved across sibling worktrees. (ADR-011)
- `pre-resolved` — `.lattice/.gitignore` is tracked (committed), single source of truth for `.lattice/` temp subclass; root inline block de-duplicated. (ADR-011)
- `agent-decides` — helper script name (`lattice-state-home.sh`) and exact state-dir env var (`LATTICE_STATE_HOME`): reversible, local convention.
- `agent-decides` — coordinator.py fingerprint parity (subprocess vs Python reimpl): pick whichever matches existing `transition-api.py` style.

## Pending decisions

(none)

## blocked_by

(none — foundation ticket; introduces the state-dir + fingerprint helper that 286/287 consume)

## Finish

- pr-288 merged: 2026-08-31T15:06:05Z — https://github.com/percena/lattice/pull/288 (base merge)
- issue #283 closed: 2026-08-31T15:06:40Z — https://github.com/percena/lattice/issues/283
