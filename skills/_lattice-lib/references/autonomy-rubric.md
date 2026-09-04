# Autonomy scoring rubric (spc-433)

Ticket-level autonomy score (0-4, 0-indexed per lattice convention). Set at split time by `create-tickets`; consumed by `batch-work --min-autonomy` (default 3) for night-batch filtering and by `start-work --unattended` for decision-chain activation.

## Scores

| Score | Label | Meaning | Night-batch | Decision scope |
| --- | --- | --- | --- | --- |
| **0** | Day-Interactive | Needs human for architecture/UI confirmation; logic fuzzy, high-risk core module | ❌ never | All cross-contract items `must-ask`; agent may not self-decide |
| **1** | Low | May need 1-2 human confirmations; partial acceptance criteria | ❌ skip + warn | Reversible local items `agent-decides`; cross-contract `must-ask` |
| **2** | Medium | Mostly self-sufficient; some edge cases undefined | ❌ skip + warn (default threshold 3) | Reversible items `agent-decides`; irreversible `must-ask` |
| **3** | High | Clear acceptance criteria, good test coverage, well-defined edges | ✅ night-batchable | Most items `agent-decides`; only irreversible cross-contract `must-ask` |
| **4** | Full | Pure docs/tests/pure functions; auto-mergeable; no side effects | ✅ auto-merge candidate | All items `agent-decides`; human review is 10-second scan |

## Scoring heuristics

Score the ticket based on these dimensions:

### Lower autonomy (→ 0) when:
- Touches core state machine, auth, payment, or data integrity paths
- Requires visual UI confirmation (cannot verify via test alone)
- Has architectural ambiguity (multiple valid approaches with different trade-offs)
- Modifies shared interfaces consumed by >2 modules
- Has no existing test coverage in the touch area
- Involves irreversible changes (migrations, schema, API breaking changes)

### Higher autonomy (→ 4) when:
- Pure documentation generation or correction
- Test supplementation for existing, well-specified functions
- Isolated pure-function logic with clear input→output contract
- Refactoring within a single module with no interface changes
- CI/green-gated changes with existing test coverage
- Cosmetic or formatting changes

### Default: 2 (medium)
When the scorer is unsure, default to 2. This means the ticket is mostly self-sufficient but may need 1-2 confirmations — safe for day-interactive, not safe for unattended night-batch.

## Relationship to other fields

| Field | Relationship |
| --- | --- |
| `kind` | `docs`/`test` lean high; `feat` in core modules leans low |
| `priority` | P0/P1 often high-risk → lower autonomy; P3 often low-risk → higher |
| `paths` | Broad touch-set across multiple modules → lower autonomy |
| `solo_merge` | `no` often signals coupling → lower autonomy |
| `covers` | Tickets covering only docs/test A* → higher autonomy |

## batch-work filter

`batch-work --min-autonomy <level>` (default 3) filters tickets below the threshold from night-batch execution. Filtered tickets stay `queued` with never-spawned reason `autonomy-below-threshold` — they are not failed, just deferred to day-interactive. The scripted step is `batch-work/scripts/autonomy-filter.py --min-autonomy N --home <lattice-home> tkt-A tkt-B …` (JSON `selected` / `skipped` / `missing_binder`; missing row → 2; `0` disables) — tkt-461. The validator (`validate-lattice-artifacts.py`) errors on a row outside 0–4 (`autonomy_out_of_range`) and warns when a C-mode Spec-bound ticket created after spc-433 landed has no row (`autonomy_missing`).

## start-work --unattended

When `start-work --unattended` is active, the autonomy score determines which `## Anticipated decisions` items may be resolved as `agent-decides`:
- Items marked `agent-decides` are honored only if the ticket's autonomy ≥ 2
- Items marked `agent-decides` on a ticket with autonomy < 2 are upgraded to `must-ask` and parked
- All `Auto-Decided` actions are tagged `// Auto-Decided: <reason>` + journaled per decision-policy.md

## Reference

- Spec: `spc-433` — Vibe Coding flow optimization (autonomy score, circuit breaker, unattended mode, context snapshot)
- Decision policy: `decision-policy.md` (self-decision chain)
- Fallback policy: `fallback-policy.md` (unattended caps)
