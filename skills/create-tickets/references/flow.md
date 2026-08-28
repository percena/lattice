# create-tickets full flow (reference)

**Progressive disclosure:** day-to-day use short `../SKILL.md`.  
**Policy:** `policy.md` · **Templates:** `templates/` · **Constraints:** `../../_lattice-lib/references/constraint-language.md`

---

## Contents

- [0. Ensure Lattice + shippable cwd](#0-ensure-lattice-shippable-cwd)
- [0.5 Adopt existing issue recipe](#05-adopt-existing-issue-recipe)
- [1. Read scope](#1-read-scope)
- [2. Propose ticket set (one batch — delivery meta only)](#2-propose-ticket-set-one-batch-delivery-meta-only)
  - [Ship plan](#ship-plan)
  - [Proposed tickets](#proposed-tickets)
- [2.2 Anticipated-decisions scan + Approach authoring (same batch)](#22-anticipated-decisions-scan--approach-authoring-same-batch)
- [2.5 POST_SPLIT_CHECK (when Spec has `A*`)](#25-postsplitcheck-when-spec-has-a)
- [3. Create with gh](#3-create-with-gh)
- [3.5 Local binder + Spec edges (after each create)](#35-local-binder-spec-edges-after-each-create)
- [4. Handoff](#4-handoff)
- [Media upload (when local paths present)](#media-upload-when-local-paths-present)

## 0. Ensure Lattice + shippable cwd

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")
bash "$LIB/ensure-lattice.sh"
bash "$LIB/assert-shippable-cwd.sh"   # binder writes HARD-shippable
```

Remote-only `gh issue create` may run on team base *before* binders; do **not** write `.lattice/tickets` on base.  
If this pass also creates a Lattice Review (or Spec/new ADR), open the shippable worktree **before** any of those durable L0 writes — co-create in one tree.

## 0.5 Adopt existing issue recipe

When the user passes an existing issue number (or asks to “wrap” `#M`):

```bash
gh issue view "$M" --json number,title,body,state,labels,url
# Do NOT: gh issue create for the same intent
# Do NOT: gh issue edit --body to replace operator prose
mkdir -p "$PH/tickets/tkt-${M}-<slug>"
# Write README from ticket-binder.md: adopted: true, github URL, extracted Acceptance
# Optional one comment:
# gh issue comment "$M" --body "Lattice adopted: binder \`.lattice/tickets/tkt-${M}-…/\`; Spec: spc-N (if any)."
# Soft-fail labels / project / parent as create path
```

Then POST_SPLIT if Spec has `A*`; hand off to `start-work tkt-M`.

## 1. Read scope

From locked Spec, COMMITTED card, or user plan. Prefer Spec `A*`.  
Fuzzy / empty Acceptance → **create-spec** (no ticket fiction).

## 2. Propose ticket set (one batch — delivery meta only)

```markdown
### Ship plan
- **Ship:** one-PR | multi-PR
- **Primary ticket:** (Fixes row) | n/a if multi-PR
- **Why:** path-overlap → one-PR; independent concurrent EXECUTE → multi-PR

### Proposed tickets
| # | title | covers | paths (approx) | blocked_by | parallel_group | solo-merge |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | … | A1 | skills/foo/… | none | G1 | yes |

Spec primary / parent: #N (= spc-N, label:epic) — link each delivery child as GH sub-issue (including a single child)
Foundation serial (optional): …

Reply **go**, edit rows, or **single issue instead** (ticket-only / no Spec).
```

**Defaults:** shared hot paths / foundation → **Ship: one-PR**, serial, one worktree. Do not invent multi-PR only because N>1.  
**Parent:** Spec primary #N is the GH sub-issue parent for every delivery ticket under Spec; do not invent a second epic issue; do not dual-role primary as the delivery ticket.

**Independence → parallel worktrees:** gates pass + concurrent EXECUTE → multi-PR, one sibling worktree per concurrent tkt. Same Spec is fine.

**One quiz batch after table:** granularity ok? dependencies correct? merge/split any rows?

Skip table only when user already ordered exact titles **and** independence is obvious (still fill blocked_by / paths + ship plan).

## 2.2 Anticipated-decisions scan + Approach authoring (same batch)

Per proposed ticket, **before** presenting the section-2 batch. Split time is when global context + the human are present — front-load the night's questions here (spc-42 A5, ADR-004 §2).

**Dry-run (read-only):** open the modules the ticket's approx `paths` touch; walk the planned change against real code. No product edits — INVARIANT 5 still holds. List the decision points you expect the implementer to hit: error semantics, naming, library/dependency choice, edge behavior, config/API surface, test placement.

**Disposition each point** per `../../_lattice-lib/references/decision-policy.md` (reversibility × blast-radius matrix):

| Disposition | When | Lands as |
| --- | --- | --- |
| `pre-resolved(<source>)` | Answer already exists (Spec Decisions / ADR / preferences) or planner settles it now — confirm in the batch | `## Anticipated decisions` line citing the source |
| `agent-decides` | Reversible **and** ticket-local only | Night agent self-decides + `## Decision journal` |
| `must-ask` | Irreversible or cross-contract with no existing source | Question in the batch; unanswered → `## Pending decisions` |

Anything irreversible or cross-contract is **never** `agent-decides` — it is `pre-resolved` (settled now) or `must-ask`. When unsure whether a point is cross-contract, treat it as cross-contract (decision-policy DEFAULT).

**Present in the SAME batch** as the ticket table — one delivery-meta round, never serial questioning. Append to the section-2 proposal:

```markdown
### Decision dispositions
| tkt | decision point | disposition | proposed resolution / question |
| --- | --- | --- | --- |
| 1 | error type for parse failures | pre-resolved (Spec D2) | reuse `LatticeError` — confirm |
| 1 | retry semantics on flaky fetch | must-ask | at-most-once or backoff? default: at-most-once |
| 2 | helper naming in lib/ | agent-decides | codebase convention; journaled at night |
```

The same **go / edit rows** reply covers dispositions. Must-ask items the user does not resolve become binder `## Pending decisions` (question · context · default-if-unanswered) at binder-write time — the night agent parks & pivots on them, never blocks.

**Author `## Approach` per ticket:** 5–10 line implementation sketch + touch-set (files this slice edits), written now with global context — it is chain source #1 for the night agent's decision resolution.

## 2.5 POST_SPLIT_CHECK (when Spec has `A*`)

After proposal **and** after binders:

| Check | Pass | Fail → |
| --- | --- | --- |
| Cover partition | Every `A*` covered or deferred | Re-slice |
| No orphan invent | Scope ⊆ Spec In/Acceptance/Decisions | Drop fiction |
| No silent contradict | No reverse of Decisions / Out | Fix ticket or Spec |
| covers honesty | ids exist on Spec | Fix ids |
| Ship/DAG coherence | blocked_by + parallel_group + paths match gates | Fix plan |

Fail closed → no “ready for parallel start-work.” Pass → short covers map + ship/DAG in handoff.

## 3. Create with gh

Prefer template `templates/github-issue.md`. Required M/C labels: kind + priority.

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
bash "$SKILL_ROOT/scripts/sync-github-labels.sh"   # once if labels missing
ISSUE_URL=$(gh issue create --title "<plain summary>" --label "feat,P2" --body-file …)
# Optional GitHub Project (soft-fail; no-op when unset) — monorepo docs/github-surface.md §2
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")
bash "$LIB/github-project-add.sh" "$ISSUE_URL" || true
# Delivery ticket under Spec primary — soft-fail; never blocks create
# SPEC_PRIMARY_N = issue number of spc-N (primary tracker, label:epic).
# Link when Spec primary exists and this issue is not the primary itself (incl. N=1 child).
# Skip when ticket-only / no Spec primary / cross-Spec shared foundation (explicit).
if [[ -n "${SPEC_PRIMARY_N:-}" && "$SPEC_PRIMARY_N" =~ ^[0-9]+$ ]]; then
  CHILD_N=$(printf '%s' "$ISSUE_URL" | grep -oE '[0-9]+$')
  if [[ "$CHILD_N" != "$SPEC_PRIMARY_N" ]]; then
    bash "$LIB/github-issue-parent-add.sh" --parent "$SPEC_PRIMARY_N" --child "$ISSUE_URL" || true
  fi
fi
```

Plain titles. Capture numbers/URLs; list for user. Issue body still includes `Parent: #N` prose. Prefer native GH sub-issue link over only a parent comment.

## 3.5 Local binder + Spec edges (after each create)

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")
# shellcheck source=/dev/null
source "$LIB/_lattice-home.sh"
PH=$(lattice_default_home || echo "${LATTICE_HOME:-.lattice}")
DIR="$PH/tickets/tkt-${N}-${SLUG}"
mkdir -p "$DIR/assets"
# Fill templates/ticket-binder.md → $DIR/README.md
```

- Fill `## Approach` + `## Anticipated decisions` from the §2.2 scan; user-unresolved must-ask items → `## Pending decisions`.
- Rename `tkt-pending-<slug>` → `tkt-N-<slug>` if needed. **Never** pre-guess the number — create the issue first, capture N from the URL, then rename. The validator (`validate-lattice-artifacts.py`) errors when dir N ≠ github issue N, and warns `phantom_binder_smell` when a numeric dir carries a placeholder `github` field (tkt-155).
- Spec front matter `tickets: […, tkt-N]` bare ids.
- id = GitHub issue number always. The binder `github` field URL must point to that same issue.

## 4. Handoff

L0 edges accurate. Return issue #s + binder paths for `start-work` bind and later `create-pr` Fixes/Refs + Spec line.

## Media upload (when local paths present)

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")
UP="$LIB/upload-github-asset.sh"
bash "$UP" "<file-path>"
```

Embed returned URLs. No local media → skip. No separate attach skill.
