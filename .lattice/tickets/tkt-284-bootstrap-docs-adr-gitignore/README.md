# tkt-284-bootstrap-docs-adr-gitignore

> **TL;DR:** Bootstrap tracked docs/adr/.gitignore for ADR atomic-write temps + mutex lock dirs; harden EXIT traps.
> **Kind:** chore · **Status:** queued · **Priority:** P2
> **Path:** spc-282 → tkt-284 → (pr-…)

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P2 |
| labels | chore,P2 |
| github | https://github.com/percena/lattice/issues/284 |
| status | pr-open |
| adopted | false |
| summary | Bootstrap tracked docs/adr/.gitignore covering ADR temps + lock dirs; harden EXIT-trap cleanup |
| spec | spc-282 — Consumer-repo footprint hygiene (path: ../../specs/spc-282-consumer-repo-footprint-hygiene.md) |
| covers | A4 |
| blocked_by | (none) |
| parallel_group | wave-1 (with 283, 285; no path overlap) |
| paths | skills/_lattice-lib/scripts/lattice-init.sh, skills/create-adr/scripts/claim-adr-file.sh, skills/create-adr/scripts/append-adr-index-row.sh, docs/adr/.gitignore (new) |
| solo_merge | yes |
| primary_ticket | tkt-284 |
| related_tickets | (none) |
| worktree_bind | spc-282-consumer-repo-footprint-hygiene |
| prs | pr-289 — https://github.com/percena/lattice/pull/289 |
| created | 2026-08-31T00:00:00Z |
| updated | 2026-08-31T15:10:10Z |

## Why

`docs/adr/` has no `.gitignore`. `claim-adr-file.sh` and `append-adr-index-row.sh` leave lock dirs (`.create-adr.lock/`, `README.lock/`) and atomic-write temps (`.NNN-slug.tmp.XXXXXX`, `.README.md.tmp.XXXXXX`) that crash-leak as untracked dirt in a fresh customer repo. The atomic-write temps must stay co-located with their target (`os.replace`/`mv` atomicity requires same filesystem), so they cannot relocate out-of-repo — they need a tracked gitignore.

## Scope

- `lattice-init.sh` (or `ensure-lattice.sh`): bootstrap a tracked `docs/adr/.gitignore` covering `.create-adr.lock/`, `README.lock/`, `.*.tmp*` (idempotent block).
- Verify/harden EXIT-trap cleanup in `claim-adr-file.sh` + `append-adr-index-row.sh` (already present; confirm crash-safe on signal, not just exit).
- Tests: `claim-adr-file` + `append-adr-index-row` bats gain a crash-simulation assertion (no untracked `docs/adr/` file left).

## Approach

1. Add `docs/adr/.gitignore` bootstrap to `lattice-init.sh` (same idempotent marker-block style as the root inline block).
2. Re-read `claim-adr-file.sh:17,20` + `append-adr-index-row.sh:26` EXIT traps; confirm `rm -f`/`rmdir` covers SIGTERM not just EXIT; add `trap … TERM INT EXIT` if needed.
3. bats: simulate a mid-write crash (kill before `os.replace`); assert `git status -- docs/adr` is clean (temps gitignored or removed).

## Anticipated decisions

- `pre-resolved` — `docs/adr/.gitignore` is tracked (committed) per ADR-011.
- `pre-resolved` — atomic-write temps stay co-located (rename atomicity requires same filesystem); covered by gitignore, not relocation.
- `agent-decides` — exact gitignore pattern wording (`.tmp*` vs `.*.tmp*`): reversible.

## Decision journal

- 2026-08-31T15:10:10Z — direct jump: queued → pr-open (in-progress stamp skipped; PR #289) [WARN — signal logged, not silently lost]

## Pending decisions

(none)

## blocked_by

(none)
