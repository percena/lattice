# Morning triage (attended recipe)

How a human triages a night batch's artifacts before merging — spending attention only where it is irreplaceable. The **attended counterpart** to [day-phase.md](./day-phase.md) (M1 planning) and the M2/M3 consumption side of [workflow-fsm.md](./workflow-fsm.md).
Sources: `spc-42` · `ADR-004` §1–2 · `rev-20260827-102420Z` (Finding 4).

> **One-line summary:** read the digest → ratify decisions → disposition stuck tickets → review deferred tickets → consume verdicts → reconcile GitHub↔binder state → finish-work per PR.

---

## The recipe

| # | Step | Who | Output |
| --- | --- | --- | --- |
| 1 | Read the digest | human | ranked PR list + ratification queue + NOTICED sweep |
| 2 | Ratify decision-journal entries | human | ratified entries (×2 → promotion proposal) |
| 3 | Disposition stuck tickets | human | unblock / re-scope / cancel decisions |
| 4 | Review deferred tickets (stamped at trip time) | human | re-queue / fix-fuse / cancel decisions |
| 5 | Consume PR verdicts | human | merge / ratify-then-merge / deep-review per PR |
| 5.5 | Reconcile GitHub↔binder state | human | `reconcile-state.sh` per binder — drift list + manual recovery |
| 6 | Run finish-work per PR | human | merged PRs + cleanup + Finish ledger |

### Step 1 — read the digest

If the night ran with `batch-work --with-review`, the `review-delivery` skill produced a **morning digest** (persisted under `.lattice/reviews/`, `kind: digest`). Open it. It contains:

- A **ranked PR table** with one triage class per PR: `auto-pass` (all four axes clean — may merge on the digest alone) · `ratify-then-pass` (clean except pending decisions) · `deep-review` (material findings — read the PR itself).
- A **decision-ratification queue** (Axis 3): pending decisions first, then journal entries by blast radius. Entries ratified ×2 get a preference-promotion proposal.
- A **NOTICED sweep** (Axis 4b): out-of-paths observations from the set's binders, each with a disposition (`ticket` · `one-liner` · `wontfix`).

Skill: `review-delivery` (`skills/review-delivery/SKILL.md` §5, triage classes `:99-106`).

If no digest exists (batch ran without `--with-review`), triage PRs individually via `gh pr list` + `gh pr diff`.

### Step 2 — ratify decision-journal entries

The M3 knowledge machine (`workflow-fsm.md` §2 M3 table) routes self-decisions through morning **decision ratification** (human-owned, ADR-004 §1 white-list item 2). For each journal entry in the digest's ratification queue:

- **Ratify** (accept the self-decision as sound) → mark it ratified in the binder's `## Decision journal`.
- **Reject** (disagree) → the decision was already implemented; rejection means a Spec revision or rework path, not a journal-entry state change.
- An entry **ratified ×2** (counted across digests, `review-delivery` Axis 3) gets a **preference-promotion proposal** → the human accepts or defers. Accepted → written to `.lattice/preferences.md` with provenance and severity (INVARIANT / DEFAULT / HINT).

Skill: `_lattice-lib/references/decision-policy.md` (ratification + ×2 promotion path).

### Step 3 — disposition stuck tickets

A ticket that hit fallback bounds stamps `status: stuck` + `wait_reason` (`unblock` | `re-scope`) so morning triage routes two different dispositions from one state (`start-work:90`, `workflow-fsm.md` §2 M2 table). Three exits, **operator-chosen**:

| `wait_reason` | Disposition | Action | Next state |
| --- | --- | --- | --- |
| `unblock` | Answer the question / fix the env | Stamp `queued` (re-queue into a later batch) | `stuck → queued` |
| `re-scope` | Scope escape = planning defect | Revise Spec/ticket via `create-spec` / `create-tickets` | `stuck → M1` (Spec revision) |
| (either) | Cancel the ticket | Stamp `closed` without merge via `finish-ledger.sh --cancel --reason "<text>" (--closed-at <ts> \| --issue M) --binder <path>` (no PR row, no `mergedAt`; requires human reason + firm close time or a gh-verified CLOSED issue) | `any → closed` |

Never silently retry a `stuck` ticket — the Attempts ledger and caps carry across sessions (`fallback-policy.md`). A `stuck` ticket with a complete ledger and one well-formed question is a first-class deliverable (ADR-004 §5).

Skill: `start-work` (`skills/start-work/SKILL.md:87-90` — stuck resume enumeration).

### Step 4 — review deferred tickets (fuse-halted / abandoned / spec-superseded)

Since tkt-137 (ADR-004 Amendment, Option B), batch-work stamps `deferred` + a reason (`fuse-halt` / `blocked-by-failure`) **at trip time** — the SoT already says "not schedulable" (`workflow-fsm.md` §1 fuse edge). Since tkt-190 (spc-186 A3), spec-supersede stamps a superseded Spec's still-active child binders `deferred` + `spec-superseded` **at supersede time** (generalizing the trip-time principle — the work is obsolete the moment the Spec is superseded, not at land-time drift). The morning step is therefore a *review* of the deferred set, not a stamping pass:

- **Re-schedule** → flip `deferred → queued` (human transition, `workflow-fsm.md` §2 M2 table).
- **Transient fuse** (broken base, env failure) → fix the root cause, flip `deferred → queued`, re-run the batch.
- **Abandoned** → cancel via `finish-ledger.sh --cancel` (Step 3 table).
- **Spec-superseded** → re-plan under the superseding `spc-N` (re-point `spec:` / `covers:`, flip `deferred → queued`) or cancel via `finish-ledger.sh --cancel`. Side-state children (parked / stuck / rework) and `pr-open` children are NOT auto-stamped (they hold an external signal or an open PR) — disposition them under the superseding Spec manually.

Skill: `batch-work` (`skills/batch-work/SKILL.md` — binder `status` invariant: fuse-halted and blocked-by-failure tickets stamp `deferred` at trip time). `spec-supersede.sh` (`_lattice-lib/scripts/` — stamps child binders at supersede time; invoked from `create-spec`'s supersede path).

### Step 5 — consume PR verdicts

For each PR in the digest's ranked table, follow its triage class:

| Class | Meaning | Action |
| --- | --- | --- |
| `auto-pass` | All four axes attested clean | Merge on the digest alone (still human-owned — `finish-work`) |
| `ratify-then-pass` | Clean except pending decisions | Ratify the decisions (Step 2), then merge |
| `deep-review` | Material findings or artifact insufficiency | Read the PR itself; address findings before merge |

A **materially changed rebase** (conflict resolution or non-trivial diff change after base update) **voids** the digest's verdict for that PR — re-review is needed (`review-delivery:43`, `finish-work:62` rebase-verdict rule). A clean rebase carries the verdict.

Skill: `review-delivery` (`skills/review-delivery/SKILL.md:99-106` — triage classes; `:43` — rebase voids verdict).

### Step 5.5 — reconcile GitHub and binder state (interrupted recovery)

Before merging, verify that binder state matches what GitHub actually shows. A batch that was interrupted (fuse-halt, crash, manual abort) can leave binders stamped with a status or `pr-open` that no longer reflects the live issue/PR state. Run the read-only reconciliation check for each ticket binder in the batch:

```bash
bash "$REPO_ROOT/skills/_lattice-lib/scripts/reconcile-state.sh" \
  --binder .lattice/tickets/tkt-N-slug/README.md [--json]
```

The check is **read-only** — it mutates neither the binder nor GitHub. It detects:

| Drift class | Meaning |
| --- | --- |
| `closed_issue_working_binder` | GitHub issue is CLOSED but binder status is still working |
| `merged_pr_nonterminal_binder` | Referenced PR is MERGED but binder status is not terminal |
| `closed_pr_nonterminal_binder` | Referenced PR is CLOSED (without merge) but binder status is nonterminal |
| `open_pr_closed_binder` | Referenced PR is still OPEN but binder status is `closed` |
| `pr_open_missing_pr` | Binder status is `pr-open` but no PR is referenced in the `prs` field |
| `pr_open_unresolvable_pr` | Binder status is `pr-open` but the referenced PR does not exist on GitHub |
| `repo_identity_mismatch` | The binder's `github`/`prs` URLs point to a different repository than the binder's origin |

When GitHub is unreachable (auth failure, network down), the check returns `result: unknown` and a nonzero exit — it **never** reports a false clean result.

**Manual recovery route:** the check does not auto-repair. For each drift, the operator decides:

- **Binder stale** → update the binder (`status`, `prs`, `## Finish` ledger) to match GitHub, or re-run `finish-ledger.sh` if a merge was missed.
- **GitHub stale** → close the issue (`gh issue close`), merge or close the PR, or reopen if prematurely closed.
- **Repo identity mismatch** → fix the binder's `github`/`prs` URLs to point at the correct repository.
- Re-run `reconcile-state.sh` to confirm `ok: true` before proceeding to `finish-work`.

Skill: `_lattice-lib/scripts/reconcile-state.sh` (tkt-152).

### Step 6 — run finish-work per PR

For each PR the operator decides to merge (in DAG-respecting order — the digest recommends a merge order):

1. `finish-work pr <N>` — runs preflight (CI + base update + alignment-check HARD gate + mini-review scan).
2. `gh pr merge` (human-owned; the `.batch-work-active` marker is removed by finish-work at merge).
3. `close-fixed-issues.sh` closes the ticket's GitHub issue.
4. `finish-ledger.sh` stamps the binder's `## Finish` ledger (`mergedAt` + `status: closed`). For a cancel before any PR, use `finish-ledger.sh --cancel --reason "<text>" (--closed-at <ts> | --issue M) --binder <path>` (no PR row, no `mergedAt`; requires human reason + firm close time or a gh-verified CLOSED issue — an OPEN/unverifiable issue fails closed).

The batch marker (`.lattice/.batch-work-active`) prevented any agent from merging during the night. finish-work removes it after a successful human-driven merge.

Skill: `finish-work` (`skills/finish-work/SKILL.md` — Finish cycle, HARD gate = alignment-check).

---

## What NOT to do

| Don't | Why |
| --- | --- |
| Re-derive context PR by PR | The digest already did the chain review; trust it unless the verdict is voided |
| Silent-retry a `stuck` ticket | Attempts caps are per-ticket, not per-session; stuck exits are operator-chosen |
| Merge a `deep-review` PR without reading it | The class means the digest found material findings — read the PR |
| Trust `mergeable=MERGEABLE` alone | Mergeable is a git-tree statement, not a CI verdict (`finish-work:178`) |
| Leave `deferred` tickets without a decision | They were stamped at trip time; re-queue (`deferred → queued`) or cancel — an unreviewed deferred pile is an invisible queue |
| Merge without running `reconcile-state.sh` after an interrupt | A fuse-halt or crash can leave binder status/prs out of sync with GitHub; the check is read-only and catches drift before merge |

---

## Related

- **Day phase:** [day-phase.md](./day-phase.md) — the attended planning recipe (M1)
- **State machine:** [workflow-fsm.md](./workflow-fsm.md) §2 (transition tables), §3 (human-owned white-list), §5 (M2 SoT)
- **ADR-004** §1 (attention contract), §5 (bounded loops), §6 (binder status SoT)
- Skills: `review-delivery` · `start-work` · `batch-work` · `finish-work` · `_lattice-lib/references/decision-policy.md` · `_lattice-lib/references/fallback-policy.md`
