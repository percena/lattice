# create-tickets policy (portable)

Shipped with `create-tickets`. No monorepo docs required.

## Contents

- [Role](#role)
- [Adopt existing issue / `--from-issue`](#adopt-existing-issue---from-issue)
- [Self-contained tickets](#self-contained-tickets)
  - [Lineage](#lineage)
- [Spec parent / GitHub sub-issues](#spec-parent-github-sub-issues)
- [When to split](#when-to-split)
- [Independence gates (N > 1)](#independence-gates-n-1)
- [POST_SPLIT_CHECK](#postsplitcheck)
- [Labels](#labels)
- [Templates](#templates)
- [Worktree pack after create (DAG)](#worktree-pack-after-create-dag)

## Role

| Owns | Does not own |
| --- | --- |
| Delivery meta batch (slices, covers, ship, parallel) | First-pass product/方案 grill → **`create-spec`** |
| Issues + binders + Spec.tickets edges | Product implementation |
| **POST_SPLIT_CHECK** Spec↔tickets fidelity | Merge-time checkbox check (`finish-work`) |

Fuzzy product scope → **create-spec**, not ticket fiction.  
`start-work` may orchestrate by **delegating** create-spec, not by re-owning a second grill dialect.

## Adopt existing issue / `--from-issue`

Hand-created or external GitHub issues are adopted **append-only**:

1. `gh issue view M` — fail closed if missing.  
2. **Do not** create a new issue for the same delivery intent (`tkt-M` = `#M`).  
3. **Do not rewrite** issue title/body. Optional single adopt comment.  
4. Write binder with `adopted: true`; extract Acceptance into binder (land SoT for adopted).  
5. Soft-fail kind/priority labels if missing; Project add; if Spec primary known → soft-fail parent link.  
6. Update Spec.`tickets` when under Spec; run POST_SPLIT when Spec has `A*`.  
7. Handoff: `/start-work tkt-M` (resume/adopt complete).

Skill-created issues (this skill's template body) remain editable for checkboxes at finish; adopted binders use binder-first Acceptance (finish-work).

## Self-contained tickets

Each GitHub Issue + local binder pair must stand alone:

| Piece | Must include |
| --- | --- |
| **Issue title** | Plain human summary |
| **Issue labels** | kind + priority (M/C): e.g. `feat,P2` |
| **Issue body** | Preview, Why, Scope (this slice), Acceptance, Lineage/refs |
| **Binder README** | kind, priority, links, acceptance, worktree name |

**Reference Spec** with id + path; do not paste the full Spec.

```markdown
### Lineage
- Spec: `spc-N` (`.lattice/specs/spc-N-….md`) — locked intent for artifact model
- Parent (GitHub sub-issue of Spec primary): #N | (none — ticket-only / no Spec primary)
- Blocked-by: (none | #N)   # dependency DAG — not the same as Parent
```

## Spec parent / GitHub sub-issues

| Rule | Detail |
| --- | --- |
| Ticket identity | Every slice is still a **full independent** GitHub issue (`tkt-N` = #N) + binder |
| When to link | Locked Spec `spc-N` / primary `#N` **and** child is a **delivery** ticket (≠ primary) → link as **sub-issue of Spec primary #N** (including a single child) |
| When not required | Ticket-only (no Spec primary); issue **is** the Spec primary; cross-Spec shared foundation ticket |
| Spec-then-ticket | **≥2 issues** — do **not** dual-role primary as sole delivery ticket |
| Extra epic issue | **Do not** create a second epic under Spec — Spec primary #N is the parent (create-spec labels primary **`epic`**) |
| SoT on conflict | GitHub parent/sub-issue wins; repair L0 `Spec.tickets` / body Parent |
| Soft-fail | Parent link failure never blocks `gh issue create` or binder write |
| Not a substitute for | `blocked_by`, ship plan, `covers` / POST_SPLIT, worktree packing |
| Depth | Default **one** level (Spec → tickets); no auto deep nesting |

Helper (always exit 0):

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")
bash "$LIB/github-issue-parent-add.sh" --parent "$SPEC_PRIMARY_N" --child "$ISSUE_URL" || true
```

## When to split

| Situation | Output |
| --- | --- |
| Ticket only (no Spec primary) | One issue (no sub-issue required) |
| Spec primary + one slice | One delivery issue as sub-issue of Spec primary #N |
| Spec primary + multiple slices | N vertical issues + sub-issue link to Spec primary #N |
| User said one ticket and no Spec | One issue |

Require locked Spec or COMMITTED-like scope first; else **create-spec**.

## Independence gates (N > 1)

Each ticket must declare (templates):

| Field | Meaning |
| --- | --- |
| **covers** | Spec `A*` owned by this slice |
| **paths** | Expected touch-set (approx globs) |
| **blocked_by** | Hard deps (`none` or `#N`) |
| **parallel_group** | e.g. `G1` or serial |
| **solo-merge** | Can land alone on green main? |

Path-overlapping tickets must **not** share a parallel group. Shared APIs/types belong on Spec/ADR before fan-out.  
Workspace: **shippable default is sibling worktree**. Parallel degree ≥ 2 → one sibling worktree per concurrent tkt. Dependent / path-overlapping tickets **pack into one worktree** (one PR: `Fixes` primary + `Refs` related). Independence gates stay required before multi-PR.

**Same Spec does not force serial:** path-independent G1 tickets → multi-worktree parallel EXECUTE.

## POST_SPLIT_CHECK

When a Spec with `A*` exists, after proposal and after binder write:

1. **Cover partition** — every `A*` covered or explicitly deferred.  
2. **No invent** — ticket scope ⊆ Spec In/Acceptance/Decisions.  
3. **No contradict** — tickets do not reverse Spec Decisions / Out.  
4. **covers honesty** — ids exist on Spec.  
5. **Ship/DAG coherence** with independence gates.

**Fail closed** → no “ready for parallel start-work” handoff; one batch gap report.  
**Pass** → short covers map + ship/DAG summary in handoff.

## Labels

Bootstrap: resolve the active skill root as above, then `bash "$SKILL_ROOT/scripts/sync-github-labels.sh"`.
Kinds: feat bug chore docs refactor perf test spike epic  
Priority: P0 P1 P2 P3 (default P2)

## Templates

- `references/templates/github-issue.md` → issue body  
- `references/templates/ticket-binder.md` → `.lattice/tickets/tkt-N-slug/README.md`

## Tests by default (behavior slices)

When a ticket adds or changes **user-visible features, business behavior, API contracts, schemas, migrations, parsing, routing, permissions, caching, or persistence**, Acceptance (issue and/or binder) should include tests **or** an explicit rationale plus the **nearest validation command**. Pure docs/policy/chore may mark tests N/A with a one-line reason. Not a TDD mandate; not a new skill.

## Worktree pack after create (DAG)

After issues exist, pack before EXECUTE:

| Slot rule | Workspace |
| --- | --- |
| Connected by `blocked_by` / path-overlap / same one-PR ship | **One** `--mode worktree` (serial in tree; sub-tickets `Refs`) |
| Same `parallel_group`, gates pass, multi-PR ship | **One worktree per concurrent tkt** |
| Default bind | `ensure-workspace.sh --mode worktree --bind tkt --id N --slug …` |
| Branch mode | User-explicit escape only — not the skill default |
