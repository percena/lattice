---
name: review-delivery
description: "Artifact-only chain review of a delivered ticket set (spc-N | --ids tkt list | batch report): semantic A*→evidence fidelity, cross-PR coherence with a throwaway integration build, decision-ratification queue, per-PR findings — emitted as a ranked morning digest (auto-pass | ratify-then-pass | deep-review) with per-axis attestation. Use after a batch/night delivery, before human merges. Never merges, never a merge gate. Not single-PR review (review-code), not production checklist (review-production), not a decision-support report (create-review)."
allowed-tools: Bash Read Grep Glob AskUserQuestion
metadata:
  agents: "claude-code,codex"
  domain: quality-side-path
---

# Review Delivery

**Chain-review side-path.** Reviews the **delivered chain** — Spec A* ↔ tickets ↔ PRs ↔ code — for a whole ticket set, from **durable artifacts only**, and emits a ranked **morning digest**. It is how the morning human triages a night's PRs without re-deriving context PR by PR. (spc-42 A6/A3, ADR-004 §4)

**Runtime path:** before executing skill-owned files, set `LATTICE_SKILL_ROOT` to the absolute directory containing this loaded `SKILL.md` (Claude may already provide `CLAUDE_SKILL_DIR`). Never infer it from consumer cwd.

## Load on demand

| When | Read |
| --- | --- |
| Axis procedures (fidelity map, integration build, decision queue, per-PR pass) | `references/axes.md` |
| Digest file shape + attestation blocks | `references/templates/digest.md` |
| Per-PR material-finding bar (reused contract — do not fork) | `../review-code/SKILL.md` §“Material finding bar” + `../review-code/references/finding-contract.md` |
| Digest id/persistence conventions | `../create-review/SKILL.md` (R1 ids, `.lattice/reviews/` home) |
| Decision-journal / preferences lifecycle | `../_lattice-lib/references/decision-policy.md` |

## When to use / When NOT

| Use | Not — use instead |
| --- | --- |
| Morning after a `batch-work` night run: triage every open PR of the set | One PR / dirty WT / branch bug pass → `review-code` |
| A Spec's ticket set is delivered (PRs open) and you want fidelity + coherence + merge order | Production-readiness checklist on one PR → `review-production` |
| Ranked ratification queue for overnight self-decisions + parked questions | Durable decision-support report / design compare → `create-review` |
| Preference-promotion proposals from twice-ratified journal entries | Merge-time base alignment + merge → `finish-work` (its mini-review is a bounded projection, not this skill) |
| | Implement fixes for findings → `start-work` / rework loop (this skill never edits product code) |

## Invariants (must hold)

| INVARIANT | Detail |
| --- | --- |
| Artifact-only independence | Context comes **exclusively** from `build-review-context.sh` output + the durable artifacts it lists (Spec, ADRs, binders incl. journals/attempts, PR bodies + diffs, batch report, test evidence). **Never** implementer transcripts, chat logs, or agent session files — even when available. If the chain cannot be understood from artifacts alone, that gap **is itself a finding** (severity per impact), not a license to go read transcripts |
| Never merges, never a merge gate | This skill runs no `gh pr merge` and its verdicts gate nothing: `finish-work`'s HARD gates (batch marker, alignment) are unchanged. `auto-pass` is a *recommendation* to the human |
| Per-axis attestation | Every axis in the digest states **what was checked + verdict**. A bare LGTM / “looks fine” is forbidden — an axis without an attestation block is an unfinished review |
| Rebase voids verdict | A materially changed rebase (conflict resolution or non-trivial diff change after base update) **voids** this digest's verdict for that PR; clean rebases carry it. Note this in the digest footer |
| Read-only on product code | May run builds/tests on throwaway branches; never commits fixes, never edits binders except not-at-all — findings go in the digest, rework is dispatched separately |
| Bounded | One pass per invocation; no autonomous re-review loops (batch-work `--with-review` owns the bounded fix cycle, spc-42 A7) |

## Inputs

Exactly one:

| Input | Resolution |
| --- | --- |
| `spc-N` | Ticket set from Spec front matter `tickets:` list |
| `--ids tkt-43,tkt-44,…` | Explicit ticket set |
| batch report path | Ticket set = `tkt-N` ids in the `batch-work` report |

## Process

### 0. Assemble context (mechanical — script only)

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")
bash "$LIB/ensure-lattice.sh"
bash "$LIB/build-review-context.sh" --spec N        # or --ids 43,44 | --batch-report <path>
```

The manifest lists Spec, cited ADRs, each binder, PR rows (binder `prs` + `gh` fallback), and which evidence sections (`## Approach`, `## Decision journal`, `## Attempts`) carry content. Its **Gaps** section seeds artifact-insufficiency findings. Missing binder → the script fails loud; stop and report, do not improvise a partial review.

Read PR bodies + diffs via `gh pr view` / `gh pr diff` for the PR numbers the manifest names. That is the whole context universe.

### 1. Axis 1 — requirement fidelity (semantic A* → evidence)

Map every Spec `A*` this set covers to concrete evidence (code, tests, docs) in the PRs — semantic mapping, not checkbox echo. Flag **orphan criteria** (covered A* with no evidence) and **ticket-less code** (PR changes no A*/ticket explains). Procedure: `references/axes.md`.

### 2. Axis 2 — cross-PR coherence + throwaway integration build

Interface fit between the set's PRs, duplicated/conflicting solutions, then a **throwaway pre-merge integration build**: octopus-merge the PR heads onto the base in DAG order on a disposable branch, run repo validators/tests, record results, **discard the branch**. Merge conflicts or integration-only failures are findings. Recipe: `references/axes.md`.

### 3. Axis 3 — decision-ratification queue (+ A3 promotion proposals)

Collect `## Decision journal` + `## Pending decisions` entries across all binders. Rank: pending (blocking) first, then journal entries by blast radius. A journal entry **ratified twice** (this digest counts prior ratifications recorded in `.lattice/preferences.md` history/digests) gets a **preference-promotion proposal** in the digest per `decision-policy.md`. Procedure: `references/axes.md`.

### 4. Axis 4 — per-PR findings (review-code contract, reused)

For each PR run the **review-code material-finding bar** — severity + failure scenario + evidence + confidence + recommended solution. Do **not** fork a parallel contract; this is a containment of `review-code`'s bar, like finish-work's mini-review.

### 4b. NOTICED sweep (Observation-duty queue)

Sweep the set's binders for out-of-paths observations — `grep -rn '^- NOTICED:'` over the reviewed tickets' binder dirs (`.lattice/tickets/tkt-N-*/`). Every hit lands in the digest's Findings section with one disposition: `ticket` (point to / propose one) | `one-liner` (trivial — name the fix) | `wontfix` (say why). Round-scoped by default; never dropped silently — the queue drains only through dispositions (`../_lattice-lib/references/decision-policy.md` §Observation duty).

### 5. Emit — digest + stdout

Persist under `.lattice/reviews/` with create-review id conventions (`next-artifact-id.sh --kind rev --claim`; front matter `kind: digest`), template: `references/templates/digest.md`. Print the same digest to stdout.

Every PR gets exactly one triage class, ranked, with a DAG-respecting recommended merge order:

| Class | Meaning |
| --- | --- |
| `auto-pass` | All four axes attested clean for this PR — human may merge on the digest alone (still human-owned) |
| `ratify-then-pass` | Clean except pending decisions / journal entries awaiting ratification — ratify, then merge |
| `deep-review` | Material findings or artifact insufficiency — human reads the PR itself |

## Trust calibration (documented hooks; tooling out of spc-42 scope)

- **Sampling convention:** the team periodically hand-reviews a random `auto-pass` PR (suggested ≥1 per digest week) and records disagreement in the next digest — attestation is only trustworthy while sampled.
- **Escaped-defect metric (shipped — spc-104/tkt-107):** bug binders carry `found_by` / `escaped_from: pr-N — digest rev-… (auto-pass)` lineage rows, written by the verify-features tracing recipe (`../verify-features/references/triage.md` §Escape tracing) — never guessed. Every digest counts escapes (since-last + cumulative, `auto-pass` vs `ratify-then-pass`) in its "Escaped defects" block; recipe in `references/axes.md` §Escaped-defect count. Accumulated escapes calibrate how much `auto-pass` may be trusted.

## Relationship

| Skill | Boundary |
| --- | --- |
| `review-code` | Per-PR finding contract source; single-change-set unit. This skill = whole-set chain unit |
| `review-production` | Ship checklist on one PR; different vocabulary (`go/no-go`) — never used here |
| `create-review` | Digest reuses its id + `.lattice/reviews/` persistence conventions with `kind: digest` |
| `batch-work` | Producer of the ticket set / report; `--with-review` (A7) chains this skill after the last layer |
| `finish-work` | Merge authority. Its HARD gates are untouched; a materially changed rebase there voids this digest's verdict for that PR |

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| “The implementer transcript is right there — one peek saves an hour” | Never. Transcripts anchor the reviewer to the implementer's reasoning and void third-party value. Artifact gap → finding |
| “Binder journal is empty; I'll reconstruct intent from the session log” | Same law. Report `artifact insufficiency` with the empty section as evidence |
| “All axes clean — just write LGTM” | Bare LGTM forbidden. Each axis attests what was checked + verdict |
| “Everything passed, so merge the easy ones while I'm here” | This skill never merges; merge is human via `finish-work`. Batch marker unchanged |
| “Deep-review verdict blocks the merge” | Nothing here gates. Triage classes are ranked advice; merge authority is unchanged |
| “Skip the integration build, the PRs are independent by design” | Independence gates bound *paths*, not semantics — the throwaway build is exactly what catches interface drift between PRs |
| “The digest can double as the review-code pass for each PR” | It embeds the review-code *bar* but stays set-scoped; a human wanting an interactive single-PR fix loop still runs `review-code` |
| “Rebase was probably clean, keep the verdict” | Only *verifiably* clean rebases carry a verdict; material change voids it |
| “A journal entry looks great — promote it to preferences directly” | Promotion requires ×2 ratification; the digest emits a *proposal*, the human ratifies |

## Red Flags

- Reading implementer transcripts, chat logs, or agent session files — under any justification
- A digest axis without an attestation block (what was checked + verdict)
- `gh pr merge`, marker removal, or any merge-adjacent action from this skill
- Presenting triage as a gate (“finish-work must not merge deep-review PRs”)
- Editing product code, tests, or binders during the review pass
- Integration branch left behind after the build (must be discarded)
- Per-PR findings that drop fields from the review-code contract (no failure scenario, no evidence, no recommended solution)
- Silent partial review after `build-review-context.sh` failed on a missing binder
- Promotion proposal for a once-ratified entry, or silent auto-promotion into `preferences.md`
- Digest not persisted (stdout only) or persisted outside `.lattice/reviews/`

## Verification

Before claiming the digest is done:

- [ ] Context assembled via `build-review-context.sh` (manifest in digest references); zero transcript reads
- [ ] Artifact gaps from the manifest surfaced as findings (or “none”)
- [ ] Axis 1: every covered A* mapped to evidence; orphan criteria + ticket-less code listed (or “none”)
- [ ] Axis 2: pairwise interface fit checked; throwaway integration build run in DAG order, results recorded, branch deleted
- [ ] Axis 3: decision queue ranked (pending first); ×2-ratified entries carry promotion proposals
- [ ] Axis 4: per-PR findings satisfy the review-code material bar (severity, failure scenario, evidence, confidence, recommended solution)
- [ ] NOTICED sweep run over the set's binders (`grep -rn '^- NOTICED:'`); every hit carries a disposition (ticket | one-liner | wontfix), or "none"
- [ ] Every PR has exactly one triage class + position in a DAG-respecting merge order
- [ ] Per-axis attestation present for every axis of every PR row (no bare LGTM)
- [ ] Digest persisted under `.lattice/reviews/` (`kind: digest`, R1 id) **and** printed to stdout
- [ ] No merge performed, no gate claimed; rebase-voids-verdict note present in the digest footer
