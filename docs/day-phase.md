# Day phase (attended planning recipe)

How a business requirement becomes a night-executable ticket batch, spending human attention only where it is irreplaceable. The goal: **front-load the night's questions into the cheap attended window** — path divergence at night comes from missing shared priors, not agent weakness.
Sources: `spc-42` · `ADR-004` §1–2 · `rev-20260826-141124Z` (Finding 2). State-machine view: [workflow-fsm.md](./workflow-fsm.md) (M1). Morning triage (the attended counterpart — consuming the night's batch): [morning-triage.md](./morning-triage.md).

---

## 1. The recipe

| # | Step | Who | Output |
| --- | --- | --- | --- |
| 1 | Business requirement | PM (human) | the problem, in business terms |
| 2 | Solution-proposal rev | AI | a `rev-…` with 2–3 candidate architectures + one recommendation |
| 3 | Macro sign-off | human | a multiple-choice answer — not an essay |
| 4 | `create-spec` | AI | locked Spec (`spc-N`) with acceptance criteria |
| 5 | `create-adr` (conditional) | AI | ADR — only when the decision is cross-feature law |
| 6 | `create-tickets` | AI | issues + binders, with anticipated-decisions scan + `## Approach` |

### Step 2 — the solution-proposal rev

The AI does the **evidence pass** — it never asks the human for facts it can dig out of the repo itself. The proposal presents **2–3 candidate architectures**, each with:

| Field | Meaning |
| --- | --- |
| touch-set | files/modules the option changes |
| risks | what can go wrong, and where |
| reversibility | how cheap it is to back out |
| trade-offs | what each option buys and costs |

Plus exactly **one recommendation**, and a **considered-and-rejected attestation**: the proposal must state which alternatives it examined and why they lost — coverage is claimed explicitly, not assumed.

### Step 3 — macro sign-off

The human answers a multiple-choice question (pick an option / adjust a parameter), not an essay question. This is the first human-owned transition on the attention-contract white-list (ADR-004 §1).

### Step 6 — create-tickets additions

Two mechanisms move night-time questions into this attended step (mechanism: `spc-42` A5, landed — tkt-48, v0.2.0):

- **Anticipated-decisions scan** — per proposed ticket, the agent dry-runs the implementation against real code and lists expected decision points; each gets a disposition `pre-resolved | agent-decides | must-ask`, batch-confirmed now, not serially at night.
- **`## Approach` authoring** — 5–10 lines of implementation sketch + touch-set written at split time, while the planner has global context and the human is present.

---

## 2. Dialogue protocol

The architecture dialogue that produces the proposal rev is **evidence-first** and **narrative-driven**, in rounds:

```text
current state (repo audit, by the AI)
   → pain narrative (by the human)
   → ideal mode
   → gap analysis
   → prioritized proposals (human selects)
```

**Every architecture dialogue ends with a rev — chat is not L0.** If the conversation produced a direction, it is distilled into a `rev-…` artifact (`create-review`); undistilled chat evaporates and cannot anchor a Spec, a ticket, or a night run.
