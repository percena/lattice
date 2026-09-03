# Decision policy (Lattice unattended law)

How an agent resolves a mid-execution decision **without a human present**.
Decision resolution is a **total function**: every decision either resolves from durable sources or parks — an unattended run never blocks on a question. (ADR-004 §2, `spc-42` A1)

Applies to any EXECUTE-state agent (start-work, batch-work spawn briefs). Attended sessions may still PCA-batch; this policy is the floor when no one is watching.

## Resolution chain — INVARIANT, first hit wins

| # | Source | Notes |
| --- | --- | --- |
| 1 | Ticket AC / binder `## Approach` | The slice's own contract outranks everything |
| 2 | Spec `## Decisions` | Principal, user-confirmed |
| 3 | ADR | Cross-feature law |
| 4 | `.lattice/preferences.md` | Severity applies: INVARIANT parks, DEFAULT journals, HINT just applies. Spec/ADR always outrank preferences |
| 5 | Default heuristics | In order: match codebase convention > minimal public surface > most reversible option |
| 6 | Park & pivot | No source resolves it → see matrix below; never block, never invent |

Cite the winning source (see journal contract). If two sources conflict, the lower number wins.

## Capture duty — INVARIANT

Chain source #4 only resolves what actually reaches the file. When the operator states a **durable work preference** mid-session (stack choice, process policy, taste), the **active skill** writes it to `.lattice/preferences.md` **at utterance time** — dated, provenance `operator-stated` (a direct entry; the ×2 promotion path is only for journal-derived candidates) — and confirms to the operator in one line. Never wait to be reminded: a preference file the operator must maintain by reminder defeats its purpose.

What counts — capture **routes**, never swallows:

| Operator statement is… | Destination |
| --- | --- |
| Durable + cross-ticket (stack choice, process policy, taste) | `.lattice/preferences.md` — write now, at utterance time |
| Feature-scoped decision (this Spec's shape) | Spec `## Decisions` |
| System-shape law (cross-feature architecture) | ADR |

## Observation duty — DEFAULT

Capture duty's twin for **agent observations**. Mid-ticket an agent often notices a defect **outside its ticket's declared `paths`** (a stale header, a wrong count, a broken link). The active skill writes it to the active ticket's binder `## Notes` **at notice time** — one grep-able line, canonical form:

```
- NOTICED: <repo-relative path or area> — <one-line defect statement> (out-of-paths, <date>)
```

Then move on. DEFAULT, not INVARIANT: the duty must never block or grow the ticket — the queue exists so `review-delivery` sweeps it into its digest's Findings (round-scoped: the reviewed ticket set's binders; a periodic repo-wide `grep -rn '^- NOTICED:' .lattice/tickets/` catches lines outside any reviewed round), not so the noticing agent detours.

What counts — capture **routes**, never swallows:

| Noticed defect is… | Destination |
| --- | --- |
| Inside the ticket's declared `paths` | Just fix it now — in scope, no queue entry |
| Outside the ticket's `paths` (any repo defect beyond the slice) | Binder `## Notes` `- NOTICED:` line — write now, at notice time; never expand scope, never silently drop |
| Out-of-paths and `gh` is cheap + authorized | Optionally ALSO `gh issue create`, referenced in the line; the binder line is the mandatory part |

## Reversibility × blast-radius matrix — INVARIANT

Classify the decision before acting:

| Decision is… | Attended | Unattended |
| --- | --- | --- |
| **Reversible + ticket-local** (undoable within this ticket's `paths`) | Self-decide + journal | Self-decide + journal |
| **Irreversible OR cross-contract** (public API, schema, another ticket's surface, Spec/ADR territory) | PCA batch (explicit, not silent) | **Park & pivot** |

**Park & pivot** (unattended): record the question in the binder `## Pending decisions`; implement up to the boundary behind the **most reversible seam** (interface, flag, stub — whatever is cheapest to redo); mark the PR `needs-decision`; continue other work. A night is never lost to one question.

## Journal contract — INVARIANT

Every self-decision gets a binder `## Decision journal` entry that **cites which chain source resolved it** (e.g. `preferences.md DEFAULT: …`, `heuristic: codebase convention`). No uncited self-decisions — the citation is what lets the morning human ratify in seconds and lets twice-ratified entries promote into preferences (`spc-42` A3).

| Entry carries | Example |
| --- | --- |
| The decision | "Error type: reuse `LatticeError`, no new hierarchy" |
| Chain source (by number + quote/path) | "5 — codebase convention (`lib/errors.py`)" |
| Reversibility call | "reversible, ticket-local" |

## Auto-Decided tag — spc-433

When `start-work --unattended` is active, every `agent-decides` resolution also gets:

- A code comment at the decision point: `// Auto-Decided: <one-line reason>` (or `# Auto-Decided:` for Python/Shell)
- A `## Auto-Decided` section in the PR body aggregating all auto-decisions with file:line + reason + chain source
- `review-code` highlights all `Auto-Decided:` lines as priority-review items in the docs-sync axis (spc-433 A5)

The tag makes self-decisions grep-able (`grep -rn 'Auto-Decided:' .`) and visible to the morning human without reading the full Decision journal. The binder `autonomy` field (0-4, `autonomy-rubric.md`) scopes which items may be `agent-decides` in unattended mode — items on tickets with autonomy < 2 are upgraded to `must-ask` and parked.

## Defaults and hints

| Label | Rule |
| --- | --- |
| DEFAULT | When unsure whether a decision is cross-contract, treat it as cross-contract (park is cheap; unwinding is not) |
| DEFAULT | Batch parked questions per ticket — one `## Pending decisions` list, not a drip |
| HINT | Prefer seams the repo already uses (existing flags/interfaces) over inventing new indirection to park behind |

## How skills use this

| Skill | Use |
| --- | --- |
| `start-work` | EXECUTE step: mid-EXECUTE decisions resolve via this chain; attended new-principal PCA rule unchanged |
| `batch-work` | Injects this policy into spawn briefs (lands with `spc-42` A7) |
| `review-delivery` | Reads journals/pending decisions to build the ratification queue (`spc-42` A6) |

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| "No source covers it — I'll pick something reasonable" | Heuristics (step 5) *are* the covered path; beyond them, park & pivot. Inventing principals is a fail |
| "Asking is safer than deciding" | Unattended, blocking loses the night. Reversible+local decisions are yours — decide and journal |
| "It's probably reversible" | "Probably" means classify it cross-contract and park |
| "I'll journal the batch of decisions at the end" | Journal at decision time; end-of-run reconstruction drops citations |
| "Preferences say X but the Spec implies Y" | Spec/ADR outrank preferences — chain order is the law |
| "Parking means the ticket failed" | Parked-with-seam + pending question is delivered work (see `fallback-policy.md`) |
| "Operator stated a preference — I'll note it in the PR body" | PR bodies aren't the lookup chain; a preference not in `.lattice/preferences.md` never resolves a future decision. Capture at utterance time (§Capture duty) |
| "I noticed an out-of-paths defect — I'll mention it in the PR body" | PR bodies are not swept; the binder `## Notes` `NOTICED:` line is — `review-delivery` greps exactly `^- NOTICED:`. Capture at notice time (§Observation duty) |

## Verification

Before claiming EXECUTE handled its decisions correctly:

- [ ] Every self-decision has a `## Decision journal` entry citing its chain source
- [ ] No decision was resolved by inventing a principle outside the chain
- [ ] Irreversible / cross-contract items sit in `## Pending decisions` with a reversible seam in the code, not a guess
- [ ] PR carries `needs-decision` when pending decisions exist
- [ ] Unattended run never stopped to wait on a human answer
- [ ] Operator-stated durable preferences were written to `.lattice/preferences.md` at utterance time (dated, `operator-stated`) with a one-line confirmation — none left in chat, memory, or the PR body
- [ ] Out-of-paths defects noticed mid-ticket each have a binder `- NOTICED:` line written at notice time — `grep -rn '^- NOTICED:' .lattice/tickets/` shows the queue; none left in chat or the PR body

See `constraint-language.md` for severity semantics · `fallback-policy.md` for when to stop trying.
