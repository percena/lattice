# tkt-189-status-vocab-guard

> **TL;DR:** Single-source the ticket status vocabulary + coupled-field rules into one machine-readable module; add a side-state guard to stamp-pr-open so parked/stuck/rework are not silently overwritten by a pr-open stamp without an operator-adjudicated override.
> **Kind:** feat · **Priority:** P1
> **Path:** spc-186 A2 → tkt-189 → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P1 |
| labels | feat, P1 |
| github | https://github.com/percena/lattice/issues/189 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| adopted | false |
| summary | single-source status vocabulary + stamp-pr-open side-state guard (ADR-007 five-piece contract) |
| spec | spc-186 |
| covers | A2, A8 |
| blocked_by | (none) |
| parallel_group | g1 (layer 1) |
| paths | skills/_lattice-lib/scripts/lib/status_vocab.py; tools/validate-lattice-artifacts.py; skills/_lattice-lib/scripts/reconcile-state.sh; skills/_lattice-lib/scripts/finish-ledger.sh; skills/_lattice-lib/scripts/stamp-pr-open.sh; docs/workflow-fsm.md |
| solo_merge | (none) |
| **primary_ticket** | true |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-189-status-vocab-guard` |
| worktree | sibling `…/lattice.worktrees/tkt-189-status-vocab-guard/` |
| prs | pr-199 — https://github.com/percena/lattice/pull/199 |

## Why

The working-status vocabulary (`queued | in-progress | parked | stuck | pr-open | rework | deferred`) was duplicated across four sites: `reconcile-state.sh`, `validate-lattice-artifacts.py`, `finish-ledger.sh`, and `docs/workflow-fsm.md`. Drift was inevitable (each new side state had to be added in four places). Separately, `stamp-pr-open.sh` guarded only `closed` — it silently overwrote `parked`/`stuck`/`rework` → `pr-open`, losing the external signal those side states carry (parked = irreversible decision pending; stuck = needs human investigation; rework = PR returned with findings). A direct `queued → pr-open` jump (agent forgot the in-progress stamp) also lost the "started" signal silently.

## Acceptance (this slice)

- [x] **A2.1** ONE machine-readable status vocabulary + coupled-field rules in `skills/_lattice-lib/scripts/lib/status_vocab.py`, consumed by the three scripts; `tools/validate-lattice-artifacts.py` keeps a vendored copy + a byte-equality bats test (the binder_rows.py precedent).
- [x] **A2.2** `reconcile-state.sh`, `finish-ledger.sh`, `stamp-pr-open.sh` derive their status sets from the single source (no duplicated sets).
- [x] **A2.3** `stamp-pr-open.sh` refuses to flip `parked`/`stuck`/`rework` → `pr-open` without `--force-side-state --reason "..."`; the override writes a structured trace to the binder ## Decision journal (operator-adjudicated, ADR-007 sec.5b).
- [x] **A2.4** `queued → pr-open` direct jump: allowed + WARN journal entry (in-progress stamp stays default; the jump is logged, not silently lost).
- [x] **A2.5** bats tests: vocabulary parity (byte-equality), side-state overwrite refused, override honored + traced.
- [x] **A8** The hard rule carries the ADR-007 five-piece contract: check (status row flip refused), message (REFUSED… would lose the X signal), escape channel (--force-side-state --reason), structured trace (## Decision journal entry), metric (the trace is the per-rule escape count sensor — surfaced by A5 morning digest in a sibling ticket).

## Anticipated decisions

- Whether to make `NONTERMINAL_RE` a compiled regex or expose the alternation string — disposition: agent-decides (expose both; the compiled regex `.pattern` is the parity-checked artifact). [resolved]
- Whether the direct `queued → pr-open` jump should be refused (force the in-progress stamp) — disposition: pre-resolved (spc-186 D5: allow + WARN; the in-progress stamp is the default but a jump is logged, not silently lost). [resolved]

## Decision journal

- 2026-08-29 — Lib module shape: `status_vocab.py` mirrors the `binder_rows.py` precedent (canonical lib + vendored validator copy + byte-parity bats). Added `SIDE_STATES` / `DIRECT_JUMP_SOURCES` policy sets alongside the enum so the guard reads machine-readable policy, not inline alternations. `NONTERMINAL_ALT` sorted by (-len, lex) for byte-stable pattern regardless of frozenset iteration order. [agent-decides — resolved]
- 2026-08-29 — `append_journal_trace` creates the `## Decision journal` section if absent (ratify.sh errors on a missing section; stamp-pr-open must stay robust for binders that omit it — the bats fixtures have no journal). Anchor insertion before the first standard tail section, else EOF. [discovered during implementation]
- 2026-08-29 — `RS_LIB` resolved with bash builtins only (`${BASH_SOURCE[0]%/*}` + `cd` + `pwd`): the reconcile-state gh-not-installed test runs a stripped PATH with no `dirname` coreutil; the sibling scripts use `$(dirname …)` but their tests preserve PATH. Declared before `export` to avoid shellcheck SC2155. [discovered during implementation]

## Pending decisions

## Attempts

## Notes

- The five-piece contract (A8): check = side-state flip refused; message = "REFUSED — binder status is `{prior}` (side state)… would silently lose the {prior} signal"; escape = `--force-side-state --reason`; trace = dated `## Decision journal` entry tagged `[operator-adjudicated — ADR-007 sec.5b]`; metric = the trace entries are the escape-frequency sensor (A5 surfaces counts).
- The guard runs after the prs-row stamp in-memory but before the atomic write; a refused flip raises before any persistence, so the binder stays byte-identical (test 16).
- `finish-ledger.sh` terminal flip uses `status_vocab.NONTERMINAL_RE.pattern` in its status-row regex — behavior-identical to the prior inline alternation (tests 29-39 green).

## References

- Spec: `spc-186` (A2 + A8)
- Law: `docs/adr/007-hard-limit-scope-law.md` (ADR-007 — five-piece contract + escape adjudication)
- Precedent: `skills/_lattice-lib/scripts/lib/binder_rows.py` (tkt-91 single-source pattern)
- FSM: `docs/workflow-fsm.md` sec.5

## Lineage

- Parent spec: spc-186
- Primary ticket: true

## Finish



- pr-199 merged: 2026-08-29T11:39:13Z — https://github.com/percena/lattice/pull/199 (base merge)
- issue #189 closed: 2026-08-29T11:39:24Z — https://github.com/percena/lattice/issues/189
