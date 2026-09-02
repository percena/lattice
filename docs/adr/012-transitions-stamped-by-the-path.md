# ADR 012: Transitions are stamped by the path, not by the agent — ledger coverage is the conformance sensor

- **Status:** Accepted
- **Date:** 2026-09-02
- **Deciders:** operator, Claude
- **Related:** `spc-337`, `rev-20260902-015425Z`, `spc-254`, `spc-270`
- **Related ADRs:** extends `ADR-004` §6 (binder `status` SoT — narrows *who writes it*), `ADR-007` §4/§8 (five-piece contract, escape metrics — adds the coverage metric), `ADR-011` (amends the batch-marker heartbeat claim)

## Context

`rev-20260902-015425Z` measured the M2 state machine against this repository's own 150 ticket binders instead of against its documentation. The design describes 8 states and 21 legal edges; production ledgers show 5 distinct edges, `queued → in-progress` recorded once, zero side-state occurrences, and 119/150 closed binders with no transition ledger at all. Three of the five most recent tickets were closed by hand-editing the `| status |` row in a commit, invisible to CI because the replay validator only inspects ledgers that already exist. `transition-api.py` also resolves the ledger file from the *current working directory* while its callers stage it from the *binder path*, so a finish run from any non-toplevel cwd silently drops the ledger (tkt-335 is the observed case).

The mechanism behind all of these is the same: the edges most often walked (`queued → in-progress`, `in-progress → pr-open`, fuse/blocked `→ deferred`, triage `→ queued`, cancel) have **no script writer** — prose instructs the agent to remember to edit the file — while the points every ticket necessarily passes through (`ensure-workspace --bind`, a successful `gh pr create`, the batch barrier, morning triage) are *already scripts* that do not stamp. ADR-007 predicted this: advisory rules fail silently under long context; loud tool-level refusals and scripted paths hold.

Post-merge bookkeeping has the mirror problem: the Finish ledger requires the operator to commit directly to the integration branch from the main clone (150 direct pushes vs 157 PR merges in nine days), which is the exact path `profile: strict` forbids, and is non-atomic (issues close before the ledger is pushed).

## Decision Drivers

- Conformance, not modelling, is what makes a state machine worth its maintenance cost; an edge nobody walks costs attention budget for nothing.
- The cheapest reliable stamp is one the agent cannot skip because it is inside a step the agent cannot skip.
- A guarantee that is not measured is not a guarantee (ADR-007 §8 measures *escapes*; it did not measure *coverage*).
- Wildcard edges (`any → closed`) make the replay validator unable to distinguish a merge from a cancel from a skipped lifecycle.
- Human clones must not have to write to the integration branch for bookkeeping; derived facts (mergedAt) already live in GitHub.

## Considered Options

- **Keep status quo** — prose reminders + advisory hooks. Good: zero code. Bad: measured 5/21 edge coverage and hand-edited terminal states; every new prose rule widens the drift surface.
- **Option A — More prose + stricter Common Rationalizations tables.** Rejected: the failure is silent omission, not misunderstanding; prose cannot make an omitted step loud.
- **Option B — Move every stamp into the path point that already exists, guard direct edits, measure coverage (chosen).** Good: no new agent duties, the stamp rides a step the agent must take anyway; hand edits become tool-level refusals; coverage becomes a CI number. Bad: touches four safety-critical scripts and the hook set; needs a migration cutoff for legacy binders.
- **Option C — Replace binders with a database/state service.** Rejected: contradicts the transparent-Markdown, grep-able, agent-portable posture (ADR-004 §3).

## Decision

1. **Stamps live at path points, never in prose.** Every M2 `status` write is performed by the script that owns the step the ticket is passing through: `ensure-workspace --bind tkt` stamps `queued → in-progress`; a successful `gh pr create` stamps `→ pr-open` (create-pr script step + plugin PostToolUse hook); the batch barrier stamps `stuck`/`deferred` for every non-ok class (including `failed`); `finish-ledger` stamps `→ closed`; morning-triage edges (`deferred|stuck → queued`, cancel) are `transition-api.py commit` commands, not file edits. A SKILL/flow document may no longer instruct an agent to "stamp the binder"; it names the script that does.
2. **Direct edits to the `| status |` row are refused.** The L3 PreToolUse Write/Edit hook denies any edit that changes a ticket binder's status value and names the transition command instead. Scripts (which do not pass through the tool hook) remain the only writers.
3. **No wildcard edges.** `any → closed` is replaced by explicit `pr-open → closed` (merge), `queued|in-progress → closed` (merge, counted as `direct-jump` and journaled as an `anomaly:` line), and explicit cancel edges from every working state that require a reason trace. The transition table remains the SoT; docs and the vendored validator copy stay parity-tested.
4. **Ledger coverage is a first-class conformance metric.** The ledger file is resolved from the binder's Lattice home, never from cwd. A terminal binder without a ledger is a validator error for binders created on or after 2026-09-02 (legacy binders enter the warning baseline and ratchet down). Queue-health reports coverage and direct-jump counts next to the escape counts of ADR-007 §8.
5. **Post-merge bookkeeping is event-driven, with a scripted fallback.** The Finish ledger is written by a GitHub Action on `pull_request: closed` (merged) committing as a bot; consumers without Actions use a single idempotent, resumable `finish-work` script. Human clones stop pushing bookkeeping commits to the integration branch. (Direction recorded here; implementation is a follow-up Spec after the conformance slice has soaked one dogfood cycle.)
6. **Spec `done` is guarded and soaked.** A Spec may flip to `done` only when all child binders are closed, its `prs` list equals the child PR union, and at least one dogfood cycle has passed since the last child merge. Acceptance checkboxes cite the test or fault-injection case that proves them. (Direction; implementation follows §5.)
7. **Binder machine fields move to YAML front matter** (same substrate as Spec/Review) in a later Spec with lazy migration; until then `binder_rows.py` is the only parser.

## Consequences

- **Positive:** the walked path and the modelled path converge; the agent loses four "remember to stamp" duties; hand-edited terminal states become impossible from the Edit tool; CI gains a number (ledger coverage) that says whether the FSM is real; cancel vs merge vs skipped-lifecycle become distinguishable in the ledger.
- **Negative / trade-offs:** four safety-critical scripts and the hook set change in one program (mitigated: per-writer regression bats, fault-injection acceptance); a legacy cutoff date is a permanent constant in the validator; the PostToolUse stamp hook is Claude-specific and therefore defense-in-depth only (the create-pr script step is the portable path).
- **Amends:** ADR-004 §6 "orchestrators, digests, validators, and metrics read and write this field" → *read* freely; *write* only via the path-point scripts in §1. ADR-011 "batch-work re-touching the marker each wave (heartbeat)" was aspirational; `spc-337` A6 makes it real (wave touches the marker at each barrier).
- **Follow-ups:** `spc-337` (conformance slice: §1–§4 plus coordinator wiring and finish-work prose repair); a follow-up Spec for §5–§7 after one dogfood cycle.
- **Verification:** `validate-lattice-artifacts.py` `closed_without_ledger` + replay; `queue-health.sh --section` ledger coverage row; plugin bats for the status-row guard and the PostToolUse stamp; `transition-parity.bats` for the explicit-edge table.

## Status history

- 2026-09-02: Proposed → Accepted (operator sign-off on `rev-20260902-015425Z` recommendations; F3 = bot + script fallback, F7 = front matter in a later Spec).

## Notes

Rejected alternatives and the measurement method live in `rev-20260902-015425Z`. The `2026-09-02` cutoff in §4 is the date this ADR was accepted; binders created before it predate the ledger contract and are baselined, not rewritten (spc-270 D1: no historical rewrite).

---

_Not a Lattice bloodline/graph node. Cite from Spec/PR/Review with `ADR-012` or this path._
