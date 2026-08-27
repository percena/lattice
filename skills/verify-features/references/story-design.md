# Story design — oracles, invariant bundle, mutation discipline

A story is a `run-e2e` heredoc (one Bash invocation, one JSON out) — this reference decides **what the story asserts**. Substrate mechanics live in `../../run-e2e/SKILL.md`; do not fork them.

## Oracle hierarchy (DEFAULT 8)

| Tier | Source | Assertion strength |
| --- | --- | --- |
| spec-derived | `spc-N A*` / `tkt-N` acceptance text | Assert the stated behavior literally (counts, states, messages, redirects) |
| doc-derived | README/docs claim | Assert the documented outcome; looser on exact copy |
| generic | crawl-discovered, no docs | Invariant bundle only |

Every story header cites the oracle it asserts (`oracle: spc-104 A2`); the map row and the story must agree. **A pass may never be recorded against a weaker oracle than the map row carries** — if the spec says "sorted by date" and the story only checked "table renders", that is not a pass.

## Universal invariant bundle (DEFAULT 7 — every story, appended to its assertions)

- `pageErrors.length === 0`
- `consoleErrors` empty after removing the story-header allowlist (`console_allow: [...]`)
- `httpErrors` empty after the allowlist — first-party 4xx/5xx and failed requests (run-e2e capture)
- No dead end: the flow's final page has at least one navigational affordance and is not an error page
- **Round-trip** (mutation stories only): perform the mutation → `page.reload()` (or re-navigate) → assert the change persisted. UI-level success toasts do not count as persistence.

## Per-feature story set

| Story | When | Shape |
| --- | --- | --- |
| happy path | always | The feature's primary flow to its expected outcome |
| edge | oracle defines boundaries | Empty states, limits, pagination edges, long/unicode input |
| negative | oracle defines rejection | Invalid input rejected WITH feedback; unauthorized access refused (expect the auth wall — inverse of the fail-loud check) |

Keep one feature-flow per story; shared setup (login, seed record) is repeated per story, not extracted into a runner (ADR-002 §2).

## Mutation discipline (INVARIANT 2)

- Story header `mutations:` must equal the map row's class; a `safe`/`destructive` story refuses to run when the target origin is not in `.lattice/config.yaml` `e2e_env`.
- `safe` stories clean up after themselves when the app allows it (delete the record they created) and say so in the JSON; leftovers are reported, not hidden.
- `destructive` stories exist only for rows carrying written operator authorization, and always end at the confirmation boundary unless the authorization explicitly covers execution.

## Risk ranking (DEFAULT 9)

Order waves by: features touched by the change set under verification → `destructive`/`safe` surfaces (auth, data writes) → previously-`fail`/`blocked` rows → stale `pass` rows (oldest `last-verified` first) → fresh `pass` rows last.
