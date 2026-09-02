---
name: review-lineage
description: "Periodic lineage mining over the whole repo: running data (binders, ledgers, git history) + documented claims + history archaeology → ranked insights and ticket drafts in a rev- (kind audit) with a metrics delta. Use weekly or after a batch soak, when you want to know what the repo actually delivered versus what its docs promise. Never files issues, never merges, never edits product code or binders. Not review-delivery (one delivered ticket set), not create-review (a decision-support write-up), not verify-features (runtime bugs)."
allowed-tools: Bash Read Grep Glob AskUserQuestion
metadata:
  agents: "claude-code,codex"
  domain: quality-side-path
---

# Review Lineage

**Periodic lineage-mining side-path.** Compares the repo's **design** (Specs, ADRs, SKILL prose, `transition_table`) with its **running data** (binders, transition ledgers, `git log`) and with what the docs **promise** (executable claim probes), then clusters what it finds by root cause, ranks by impact × decidability, and ends in a `rev-` (kind `audit`) whose Proposed-tickets table the operator hands to `create-tickets`. It is the method of `rev-20260902-015425Z` made repeatable (spc-369 D1–D3, ADR-012 §4).

Sensors are scripts; judgement is the model. Every run writes a metric snapshot so the next run reads a **delta** instead of starting from zero.

**Runtime path:** before executing skill-owned files, set `LATTICE_SKILL_ROOT` to the absolute directory containing this loaded `SKILL.md` (Claude may already provide `CLAUDE_SKILL_DIR`). Never infer it from consumer cwd.

## Load on demand

| When | Read |
| --- | --- |
| Layer commands, fan-out, verify-then-report accounting, ranking rubric, delta reading | `references/method.md` |
| Naming an insight (class id, detection hint, worked example) | `references/insight-taxonomy.md` |
| Writing the `rev-` | `references/templates/lineage-audit.md` |
| L2 probe registry + per-repo overlay format | `references/probes.md` |
| Audit law (six elements; verify-then-report INVARIANT; comparison matrix for kind `audit`) | `../create-review/references/audit-recipe.md` |
| Review ids, `.lattice/reviews/` home, outcome enum, Review-only base write | `../create-review/SKILL.md` |
| Ticket-batch shape the Proposed-tickets table must match | `../create-tickets/references/flow.md` §2 |
| Delegation and accountable ownership | `../_lattice-lib/references/orchestration-patterns.md` |

## When to use / When NOT

| Use | Not — use instead |
| --- | --- |
| Weekly / post-soak: "what did we actually deliver vs. what we documented?" over the **whole** repo | Triage one night's delivered ticket set (fidelity, coherence, merge order) → `review-delivery` |
| Trend questions: is ledger coverage rising, are direct-to-base commits falling, which modelled edges are never walked | A design compare, dogfood note, or postmortem someone asked for → `create-review` |
| Turning `- NOTICED:` piles, probe failures, and recurring fix classes into ranked ticket drafts | Runtime bug hunting against a running build → `verify-features`; one PR's diff → `review-code` |
| Feeding M3 (insight → preference / ADR / ticket proposal) with evidence | Filing the tickets → `create-tickets` (this skill only drafts them); fixing anything → `start-work` |

## Invariants (must hold)

| INVARIANT | Detail |
| --- | --- |
| Artifact-only | Evidence is `.lattice/**`, `git`, the tree, and the sensors' output. Never implementer transcripts, chat logs, or session files; a chain that cannot be understood from artifacts is itself a finding |
| Verify-then-report | A sensor line, a delegated sweep, or a `- NOTICED:` claim enters **Findings** only after you re-run it against the tree (exact `file:line`, command output, count). Non-reproducing claims are **dropped and counted** in `## Method` (`audit-recipe.md` §2) |
| Never files, merges, or edits | No `gh issue create`, no `gh pr merge`/`edit`, no edits to product code, tests, binders, Specs, or ADRs. The only write is the `rev-` (+ the snapshot the metrics script writes). Ticket drafts are rows in a table the operator confirms (ADR-004 §1 attention contract; `preferences.md` "Review-findings → tickets") |
| Bounded | One pass per invocation; ≤ 7 Findings in the body, overflow to `## Appendix`; no re-audit loops. Timebox stated in Method |
| Sensors are scripts, judgement is the model | Numbers come from `lineage-metrics.sh` / `claim-probes.sh` (deterministic, CI-runnable, no LLM inside); clustering, ranking, insight naming, and ticket drafting are yours — never hand-count what a sensor reports, never let a sensor's severity substitute for ranking |
| Snapshot is committed, append-only | `lineage-<UTC>.json` under `<home>/reviews/metrics/` is project knowledge (ADR-011 §1); never rewrite an older snapshot |

## Inputs

| Flag | Meaning | Default |
| --- | --- | --- |
| `--since <Nd\|ISO\|ref>` | git window for base-branch commit mix + history archaeology (passed to `lineage-metrics.sh`) | `30d` |
| `--home <path>` | Lattice home to mine | `LATTICE_HOME` or `<repo>/.lattice` |
| `--gh` | Also reconcile binders that findings name against GitHub (`reconcile-state.sh --binder <path>`, one call per binder) | off — the audit is offline by default (spc-369 Out of scope) |

## Process

### 0. Sensors (mechanical — scripts only)

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")
bash "$LIB/ensure-lattice.sh"
# shellcheck source=/dev/null
source "$LIB/_lattice-home.sh"
PH=$(lattice_default_home || echo "${LATTICE_HOME:-.lattice}")
OUT=$(mktemp -d)
bash "$SKILL_ROOT/scripts/lineage-metrics.sh" --home "$PH" --since "${SINCE:-30d}" --md > "$OUT/metrics.md"   # L1: writes $PH/reviews/metrics/lineage-<UTC>.json + prints the delta
bash "$SKILL_ROOT/scripts/claim-probes.sh"    --home "$PH" --md > "$OUT/probes.md"                            # L2: always exit 0; fail rows are candidates, not findings
[[ -f tools/validate-lattice-artifacts.py ]] && python3 tools/validate-lattice-artifacts.py > "$OUT/validator.txt" 2>&1 || true
```

Nonzero exit from a sensor (other than the validator's warning exit) = stop and report; do not hand-compute the metric it failed to produce. With `--gh`, run `bash "$LIB/reconcile-state.sh" --binder <path> --json` for each binder a candidate finding names (Step 2), never for the whole tree.

### 1. History archaeology (`audit-recipe.md` §5)

Read the shape of the window, not individual commits: base-branch commit mix (PR merges vs direct commits vs `finish(` stamps — from the metrics), **recurrence** (the same file in ≥ 2 `fix(` commits, the same commit-subject class repeated — commands in `method.md` L3), **reopened classes** (a defect an earlier `rev-` marked fixed that appears again), and the **age** of the `- NOTICED:` backlog (dates in the lines vs today; which digest last dispositioned any). Every archaeology item is marked *still-open* or *already-addressed-by-later-work* against later commits — checked, not assumed.

### 2. Claim reconciliation (`audit-recipe.md` §4)

For **every** `fail` probe row: re-run the probe's command yourself (the `--md` evidence cell is truncated to 200 chars), read the code at the exact promise, and decide whether the doc or the tool is wrong — disagreement is a finding whichever side is right. Then **sample** claims no probe covers: ≥ 3 `Verification:` bullets from ADRs and ≥ 3 checked `A*` boxes from `done` Specs, executed against the tree (run the named test, open the named script at the named line). Record what you executed in Method.

### 3. Clustering + ranking (`audit-recipe.md` §6, ADR-007 §3)

Group candidates by **root cause**, not by file (one parser gap explaining five miscounts is one cluster). Rank clusters with the rubric in `method.md`: **impact** = blast radius × frequency in the window; **decidability** = can a script/validator/hook recognise the violation without ambiguity (ADR-007 §3). High-impact + decidable → ticket draft pairing repair **with** the guard that prevents recurrence; high-impact + undecidable → a `needs_decision` row, never a ticket that pretends to enforce it. Name each cluster's insight class from `insight-taxonomy.md`.

### 4. Write the `rev-` (kind `audit`)

```bash
N=$(bash "$LIB/next-artifact-id.sh" --kind rev --claim)      # token after rev-
mkdir -p "$PH/reviews"; REV="$PH/reviews/rev-${N}-lineage-audit-<slug>.md"
```

Fill `references/templates/lineage-audit.md`: TL;DR, **Metrics delta** (paste `$OUT/metrics.md` headline + the tables the findings cite), **Probe results** (paste `$OUT/probes.md`), Comparison matrix (kind `audit` requires one — `create-review` rule 1b), Findings (≤ 7: severity · failure scenario · `file:line` evidence · cluster · taxonomy id), Insights, **Proposed tickets** (the `create-tickets` §2 column shape, extended with `kind | priority | why`), Outcome, **Method** (sweeps run, commands executed for reconciliation, sensors' timestamps/snapshot path, **dropped-claim count**), References. Front matter: `id: rev-${N}`, `kind: audit`, `status: concluded`, exactly one `outcome`, `related_*` bare ids. A Review-only write on the team base is allowed (`create-review` rule 8); when the run is part of a ticket, write it in that ticket's worktree. Print the path.

### 5. Hand-off

| Outcome | When | Next |
| --- | --- | --- |
| `spawn_tickets` | ≥ 1 decidable, high-impact cluster with a repair + mechanism draft | Operator reviews the Proposed-tickets table → `create-tickets` (batch or `single issue instead`); this skill files nothing |
| `needs_decision` | The top cluster is important but undecidable or cross-contract (e.g. a convention change) | Row appended by the operator to `.lattice/reviews/needs-decision.md`; morning triage picks an option, then outcome updates |
| `inform_only` | Every finding is already addressed or accepted; the value is the delta | Stop; the snapshot is the deliverable |

Print the rev path, the outcome, and the Proposed-tickets table to stdout. Do not run `create-tickets` yourself unless the operator asked for it in the same turn (then it opens its own shippable workspace — never bind a worktree to `rev-` alone).

## Outputs

- `<home>/reviews/rev-<token>-lineage-audit-<slug>.md` (kind `audit`, concluded, one outcome)
- `<home>/reviews/metrics/lineage-<UTC>.json` (written by `lineage-metrics.sh`; commit it with the rev)
- stdout: rev path · outcome · Proposed-tickets table · dropped-claim count

## Relationship

| Skill | Boundary |
| --- | --- |
| `review-delivery` | One delivered set, per-PR triage digest (`kind: digest`). This skill is whole-repo, periodic, trend-based; it reads digests as history, never replaces them |
| `create-review` | Owns ids, home, outcome enum, audit recipe. This skill is a specialised `kind: audit` producer that adds sensors + the ticket-draft table |
| `create-tickets` | The only writer of issues/binders. Consumes the Proposed-tickets table as its §2 batch |
| `verify-features` | Runtime behaviour of a build. This skill never runs the product |
| `_lattice-lib` | `queue_health.py`, `transition_table.py`, `reconcile-state.sh`, `next-artifact-id.sh` are reused, never re-implemented (spc-369 D5) |

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| "The probe says `fail`, that is the finding" | A probe row is a candidate. Re-run its command, read the promise, cite `file:line`; the row's severity is reporting weight, not your rank |
| "The metrics table already has the number, I'll quote it" | Quote it in **Metrics delta**; a Finding needs the mechanism behind the number (which regex, which writer, which commit) verified in the tree |
| "This `- NOTICED:` line from a binder is evidence" | It is a claim by a past agent. Reproduce it or drop it and count the drop — several NOTICED lines in this repo describe states that later work already changed |
| "Filing the three obvious tickets now saves the operator a step" | Never. `gh issue create` is `create-tickets`' write under operator confirmation (ADR-004 §1). Draft the rows; the operator says go |
| "I'll fix the one-line regex while I'm here" | No product, test, binder, or doc edits from this skill. The fix goes in a ticket draft paired with its guard |
| "19 never-walked edges — obviously dead design, recommend deleting them" | Rare-path edges (`stuck`, `deferred`) are *meant* to be rare. Modelled-but-unwalked is an insight to state with its base rate, not a deletion order; undecidable → `needs_decision` |
| "The delta is all ▲, the process is getting worse" | Read the delta guide first: a ▲ in ledger entries or walked edges is health; a ▲ in direct commits with a flat `finish(` count is the real signal |
| "Ten findings are all important, I'll list them all" | ≤ 7 in the body, rest in the Appendix. Bounded is an invariant; ranking is the job |
| "Skip the comparison matrix, this is an audit not a design compare" | `kind: audit` is decision support; recommendations without the matrix are not credible (`audit-recipe.md` Composition) |
| "The snapshot is noise in the diff, I'll pass `--no-snapshot`" | The snapshot is the baseline the next run diffs against (spc-369 D3). Commit it |

## Red Flags

- Any `gh issue create`, `gh pr merge`, `gh pr edit`, or an edit to a file outside `<home>/reviews/`
- A Finding without a re-run command or `file:line`, or a Method section without a dropped-claim count
- Hand-counted binders/ledgers/commits where a sensor field exists, or a sensor that failed and was "estimated"
- More than 7 Findings in the body; a Proposed-tickets table whose columns do not match `create-tickets` §2
- A `needs_decision` cluster written up as a ticket with an enforcement promise it cannot keep (ADR-007 §3)
- Reading transcripts or session files to "understand" a drift
- Concluding without `outcome`, or `spawn_tickets` with an empty Proposed-tickets table
- Snapshot not written (`--no-snapshot`) or not committed alongside the rev

## Verification

Before claiming the audit is done:

- [ ] Step 0 ran all three sensors via scripts; `lineage-metrics.sh` printed the snapshot path and the file exists under `<home>/reviews/metrics/`
- [ ] Every `fail` probe row was re-run by hand (full evidence, not the 200-char cell) and each is in Findings, Appendix, or the dropped list
- [ ] ≥ 3 ADR `Verification:` bullets and ≥ 3 `done`-Spec `A*` boxes were executed against the tree; commands listed in Method
- [ ] History archaeology done: commit mix, recurrence (files in ≥ 2 `fix(` commits), NOTICED age; each item marked still-open / addressed
- [ ] Findings ≤ 7, each with severity · failure scenario · `file:line` · cluster · taxonomy id; clusters are by root cause
- [ ] Ranking rubric applied (impact × decidability); undecidable-but-important items are `needs_decision` rows, not tickets
- [ ] Comparison matrix present; Proposed-tickets table in `create-tickets` §2 shape, each row pairing repair with its guard
- [ ] Rev under `<home>/reviews/` with R1 id, `kind: audit`, `status: concluded`, exactly one `outcome`, bare `related_*` ids; validator OK on it
- [ ] Method records: sensors' timestamps + snapshot path, sweeps run, commands executed, **dropped-claim count**, timebox
- [ ] No issue filed, nothing merged, no product/binder/doc edited; rev path + outcome + table printed to stdout
