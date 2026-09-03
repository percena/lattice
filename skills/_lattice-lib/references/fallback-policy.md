# Fallback policy (Lattice bounded-loop law)

What an unattended agent does when a path fails: **pivot over retry, stop with a ledger**.
Every autonomous loop declares an upper bound; a stuck ticket with a complete `## Attempts` ledger and one well-formed question is a **first-class deliverable**, not a failure. (ADR-004 §5, `spc-42` A2)

Applies to any EXECUTE-state agent; batch-work injects it into spawn briefs (wiring lands with `spc-42` A7 — until then this file is the policy of record).

## Pivot over retry — INVARIANT (articulated-difference rule)

Before **any** retry, write to the binder `## Attempts`:

| Field | Content |
| --- | --- |
| What I believe failed | The actual cause, not the symptom ("test timeout" → "fixture spawns a real server") |
| What will differ | The concrete change in the next try |

**No articulable difference → no retry.** Re-running the same thing hoping is the banned move. If the cause is unknown, the next step is diagnosis or a pivot to a different path — logged the same way.

## Caps — INVARIANT

| Cap | Bound |
| --- | --- |
| Tries per path | ≤ 2 |
| Distinct paths per ticket | ≤ 3 |
| Per-ticket timebox | Wall-clock budget from the spawn brief; DEFAULT per mode (S/M/C), tunable in `.lattice/config.yaml` |

Any cap hit → stop, finish the ledger, write the one question (below). Caps are per **ticket**, not per session — a resumed agent inherits the existing `## Attempts` count.

## Early-stop signals — INVARIANT (stop before the caps)

| Signal | Meaning | Action |
| --- | --- | --- |
| Same error twice | No new information is being generated | Stop the path |
| Fix requires touching files outside the ticket's `paths` | **Scope escape** — a planning defect, not an execution problem | Stop the ticket; route to Spec/ticket revision, do not widen scope |

## Batch fuse — policy (batch-work wiring is a later ticket)

When the failed/stuck ratio of a batch **layer** exceeds the threshold (DEFAULT 50%, tunable in `.lattice/config.yaml`), the failure is systemic — broken base or environment, not per-ticket bad luck:

- **Halt subsequent layers** — do not launch the next layer into a broken base.
- **Graceful-drain running agents** — let in-flight tickets finish their current attempt and write their ledgers; no mid-write kills.

## Budget circuit breaker — policy (spc-433; batch-work wiring)

When the cumulative batch wall-clock or retry count exceeds the budget ceiling (DEFAULT 60 minutes / 5 retries, tunable in `.lattice/config.yaml` `batch_budget_minutes` / `batch_budget_retries`; `0` disables), the batch has consumed its allocated resources:

- **Halt subsequent layers** — budget exhausted, not a failure but a resource ceiling.
- **Graceful-drain running agents** — same drain path as the fuse: finish current attempt, write ledgers, no mid-write kills.
- **Stamp never-spawned tickets** `deferred` + `wait_reason: budget-exhausted` (parallels `fuse-halt`).
- Distinct from the **fuse**: fuse trips on *failure ratio* (systemic breakage); budget trips on *resource consumption* (ceiling reached). Both may trip at the same barrier; report both if so.

The budget circuit breaker is **per-batch**, not per-ticket. Per-ticket timebox remains `batch_timebox_S/M/C`. The budget is the outer bound on the entire batch run — useful for night-batch scenarios where you need the batch to finish within a fixed window regardless of individual ticket outcomes.

**Two `--budget` flags, two semantics (spc-458 D2):** batch-work `--budget` is this per-batch ceiling and stamps *never-spawned* tickets `deferred` + `budget-exhausted`; start-work `--budget` is a *per-ticket* outer bound whose trip stamps the running ticket `stuck` + `wait_reason: unblock` (the watchdog edge) — see `start-work/SKILL.md` step 7. A ticket is never stamped `budget-exhausted` by start-work, and batch-work never stamps `stuck` for a budget trip.

## Stuck-with-ledger — the success framing

A ticket stopped under this policy delivers:

| Deliverable | Where |
| --- | --- |
| Complete `## Attempts` ledger (every try: believed cause + delta + result) | Binder |
| **One well-formed question** — the single answer that would unblock, not a dump | Binder (`## Pending decisions` when it is a decision; `## Attempts` closing entry otherwise) |
| `status: stuck` | Binder field table |

The morning human starts from a map of dead ends, not from zero. HINT: rank the question's candidate answers if you have evidence — a multiple-choice question is cheaper to answer than an essay question.

## How skills use this

| Skill | Use |
| --- | --- |
| `start-work` | EXECUTE step: unattended fallback follows this policy (attended sessions may ask instead of parking) |
| `batch-work` | Spawn-brief injection + fuse/watchdog wiring (`spc-42` A7) |
| `review-delivery` | Reads Attempts ledgers; stuck-with-good-ledger triages as deliverable, not defect (`spc-42` A6) |

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| "One more retry will probably do it" | No articulated difference, no retry — "probably" is the tell |
| "Different error message, so it's new information" | Same cause re-skinned is the same error; ledger the cause, not the string |
| "The fix is just one small file outside my paths" | Scope escape is a stop signal at any size — it is a planning defect to report, not a permission to widen |
| "Stopping makes me a failed agent" | Stop-with-ledger is process success; burning the timebox on a dead end is the failure |
| "I'll write up the attempts once something works" | Ledger before retry is the retry's precondition, not its epilogue |
| "Half the layer failed but my ticket is fine" | Fuse is batch-level law; a systemic signal outranks local optimism |

## Verification

Before claiming a stop (or a batch halt) followed policy:

- [ ] Every retry has a prior `## Attempts` entry with believed cause + articulated delta
- [ ] No path exceeded 2 tries; no ticket exceeded 3 paths or its timebox
- [ ] Same-error-twice and scope-escape stops happened at the signal, not at the cap
- [ ] Stopped ticket has `status: stuck`, a complete ledger, and exactly one well-formed question
- [ ] Fuse trip: subsequent layers halted, running agents drained gracefully, ledgers intact

See `constraint-language.md` for severity semantics · `decision-policy.md` for park & pivot on decisions.
