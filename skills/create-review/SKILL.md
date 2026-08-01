---
name: create-review
description: "Write a durable Lattice Review note (rev-…) with findings and a required outcome (inform_only/spawn_*). Use when the user wants a design compare, dogfood note, postmortem, or architecture reconciling write-up under .lattice/reviews. Not for GitHub PR review comments or PR change-set bug/production checks (use review-code / review-production)."
allowed-tools: Bash Read Grep Glob AskUserQuestion
metadata:
  agents: "claude-code,codex"
---

# Create Review

Record **decision support** as a Lattice **Review report** (`rev-…` + `outcome`).  
**Terminology:** this is **not** GitHub PR review comments, and **not** the optional PR change-set skills `review-code` / `review-production`. Product name stays **Review** (not renamed to “report” as a skill id).

**IDs (R1):** bare id `rev-YYYYMMDD-HHMMSSZ` (UTC), optional `-` + 2–4 `[a-z0-9]` collision suffix.  
Legacy `rev-<digits>` remains valid forever. Allocate via `next-artifact-id.sh --kind rev --claim` (prints the token after `rev-`).

**Runtime path:** before executing skill-owned files, set `LATTICE_SKILL_ROOT` to the absolute directory containing this loaded `SKILL.md` (Claude may already provide `CLAUDE_SKILL_DIR`). Never infer it from consumer cwd.

## Load on demand

| When | Read |
| --- | --- |
| Homes, outcomes, lineage policy | `references/policy.md` |
| Review file shape | `references/templates/review.md` |
| Delegation and accountable ownership | `../_lattice-lib/references/orchestration-patterns.md` |

## When to use / When NOT

| Use | Not — use instead |
| --- | --- |
| Design compare, dogfood note, architecture reconciling write-up | PR change-set bugs/readability → `review-code` |
| Durable `rev` with mandatory `outcome` | Production-readiness checklist → `review-production` |
| Research that may `spawn_spec` / `spawn_tickets` | Lock delivery contract → `create-spec`; implement → `start-work` |

## Core rules


1. **Self-contained** findings + recommendations; cite evidence paths.  
1b. **Problem Audit (DEFAULT):** before solution Findings, audit validity / info sufficiency / hidden issues (`references/policy.md`). Insufficient **must-have** info → stop inventing solutions. Explicit one-line skip only when the question is already crisp.  
2. **When concluding (INVARIANT):** set `status: concluded` and **exactly one** `outcome`:  
   `inform_only` | `spawn_spec` | `spawn_tickets` | `spawn_fix` | `needs_grill`  
3. **Never** bind a shippable worktree to `rev-` alone (INVARIANT).  
4. **related_*** edges use **bare ids** on L0 (`rev-YYYYMMDD-HHMMSSZ` or legacy `rev-N`); bloodline = L0 + GitHub.  
5. **Homes:** `.lattice/reviews/` (flat — in-flight and historical together).  
6. System-shape **decisions** may be promoted to `docs/adr/NNN` (manual 3-digit — **not** R1, not `next-artifact-id`); exploration stays in Review.  
7. **No product implementation (INVARIANT).** One accountable owner concludes the Review and validates its evidence/outcome; bounded drafting or disjoint evidence work may be delegated (`orchestration-patterns.md`).
8. **Workspace for Review writes (DEFAULT — co-create):**
   - **Review-only** (user only asked for a Review / `inform_only`; no Spec, ticket binder, or new ADR in the same request) → **team-base write OK** (`.lattice/reviews/`). Do **not** open a worktree just to record a Review; commit on `dev`/`main`/… is fine.  
   - **Review + Spec and/or ticket binder and/or new ADR** in the same pass defaults to **one** shippable worktree and co-created artifacts. A reasoned unbound workspace or explicitly authorized clean base-direct path is permitted.
   - Still **never** bind a shippable worktree to `rev-` alone. Spec / ticket binders / product code need a shippable path with default bind or explicit reasoned-unbound evidence.

## Flow

### 0. Ensure Lattice ready + choose write home (deterministic — required)

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
mkdir -p "$PH/reviews"
N=$(bash "$LIB/next-artifact-id.sh" --kind rev --claim)  # token after rev-
```

**Same-pass co-create?** If the user also wants Spec / tickets / new ADR **now** (or outcome will immediately run `create-spec` / `create-tickets` in this turn):

```bash
# Open one shippable tree first (bind spc/tkt — never rev-). Then cd into returned path.
bash "$LIB/ensure-workspace.sh" --mode worktree --bind spc --id <N-or-pending> --slug <slug>
# or --bind tkt when a delivery ticket id is already known
bash "$LIB/assert-shippable-cwd.sh"
# Write rev + Spec/ADR/ticket binders only after cwd is the worktree
```

**Review-only** (no Spec/ticket/ADR in this pass): do **not** call `assert-shippable-cwd` / `ensure-workspace` just for the Review — team base is fine.

### 2. Write

Fill template → `$PH/reviews/rev-${N}-<slug>.md`.  
On co-create, `$PH` resolves from the **worktree** checkout after `cd` — same relative `.lattice/reviews/` path, feature tip.  
Front matter: `id: rev-${N}` (full bare id including `rev-` prefix + token).

| Field | Notes |
| --- | --- |
| `kind` | design / research / dogfood / … |
| `status` | open → concluded |
| `outcome` | required when concluded |
| `related_specs` / `related_tickets` / `related_prs` | bare ids |

### 3. Lineage + next steps

```bash
# related_* on Review + Spec.reviews are enough
```

| outcome | Next |
| --- | --- |
| `spawn_spec` | Same-pass co-create → already in worktree → `create-spec` here. Deferred handoff → `create-spec` later (opens its own worktree) |
| `spawn_tickets` | Same-pass → worktree first, then `create-tickets`. Deferred → `create-tickets` later |
| `spawn_fix` | ticket + implement path (worktree with `tkt-` / `spc-` bind) |
| `needs_grill` | `create-spec` (first-pass align); co-create if Spec is in this pass |
| `inform_only` | stop (Review-only on base is fine) |

## Anti-patterns

| Don’t | Why |
| --- | --- |
| Conclude without `outcome` | Unfinished note |
| Treat Review as Spec | No delivery contract |
| Open worktree on rev- only | Not a delivery unit |
| Force worktree just to write a **Review-only** note | Base commit of `.lattice/reviews/` is intentional when no Spec/ticket/ADR follows in-pass |
| Write Review on base **then** open worktree for Spec/tickets in the **same** request | Co-create → one worktree first; write rev + Spec/ADR/tickets together |
| Put full ADR process only in Review forever | Promote Accepted decisions to `docs/adr/` |

## Relationship

- **`create-spec`** — after `spawn_spec`; same-pass Review+Spec co-creates in one worktree.  
- **`create-tickets` / `start-work`** — delivery path; same-pass Review+tickets share that worktree.  
- **`finish-work`** — may update `related_prs` when land was spawned from a Review.

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| "This is a PR code review comment" | Lattice Review ≠ GH PR review; different artifact + outcome |
| "Must open worktree to write rev" | **Review-only** may write on team base; never bind shippable tree to `rev-` alone |
| "Write rev on main first, then worktree for Spec — cleaner" | Same-pass Review+Spec/ticket/ADR → **one** worktree first; avoid base Review + second tree |
| "Conclude without outcome — we'll decide later" | `status: concluded` requires exactly one outcome |
| "A delegate wrote it, so the host need not review it" | One accountable owner must validate the final Review and outcome |
| "Exploration can live forever without ADR promote" | Cross-feature system law → `docs/adr/` |
| "Lead wants a code review of this PR as a rev" | PR change-set → `review-code` / `review-production`; this skill is decision-support report |

## Red Flags

- Concluded Review missing `outcome`
- Binding ensure-workspace to `rev-…`
- Same-pass Review+Spec/ticket/ADR silently using team base without an explicit escape
- Inventing delivery without spawn_* / needs_grill handoff
- Pasting chat-only conclusions without evidence paths
- Concluded without outcome under time pressure
- Treating PR diff review as Lattice Review without spawn path

## Verification

- [ ] `ensure-lattice` ran
- [ ] Review-only: no `assert-shippable-cwd` / worktree solely for `rev`; co-create: worktree + `assert-shippable-cwd` before any durable write
- [ ] Id allocated (R1 timestamp or legacy) and file under `.lattice/reviews/`
- [ ] Findings self-contained with evidence paths (file paths cited)
- [ ] Review path printed under `.lattice/reviews/`
- [ ] If concluded: exactly one valid `outcome`
- [ ] No product implementation; no shippable worktree bind to rev alone
