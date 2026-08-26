---
name: create-tickets
description: "Split already-locked Spec or COMMITTED scope into GitHub issues and binders — batch delivery meta, covers, ship plan, parallel groups, POST_SPLIT fidelity. Use when the user wants tickets, issue slices, delivery breakdown, parallel ticket groups, or trackable work items after scope is clear. Not for fuzzy product align (create-spec), implementing code (start-work), or opening/merging PRs."
allowed-tools: Bash Read Grep Glob AskUserQuestion
metadata:
  agents: "claude-code,codex"
---

# Create tickets

Turn **already locked** scope into GitHub issues + binders.  
**Delivery meta host:** one batch for slices / ship / parallel — not whole-product re-align.  
**POST_SPLIT_CHECK** before "ready for parallel start-work."  
Fuzzy product scope → **`create-spec`**.

Each issue + binder must be **self-contained**; cite Spec by id/path — do not paste the full Spec.

**Runtime path:** before executing skill-owned files, set `LATTICE_SKILL_ROOT` to the absolute directory containing this loaded `SKILL.md` (Claude may already provide `CLAUDE_SKILL_DIR`). Never infer it from consumer cwd.

## Load on demand

| When | Read |
| --- | --- |
| Labels, independence, parent-link policy | `references/policy.md` |
| Full gh create / binder / media recipes | `references/flow.md` |
| Anticipated-decisions scan + Approach recipe | `references/flow.md` §2.2 |
| Disposition matrix (reversibility × blast radius) | `../_lattice-lib/references/decision-policy.md` |
| Issue / binder body shapes | `references/templates/` |
| Constraint severity labels | `../_lattice-lib/references/constraint-language.md` |
| Delegation and accountable ownership | `../_lattice-lib/references/orchestration-patterns.md` |

## When to use / When NOT

| Use | Not — use instead |
| --- | --- |
| Split locked Spec/COMMITTED into GH issues + binders | Fuzzy Why/In/Out → `create-spec` |
| Delivery meta: covers, ship plan, parallel groups | Implement product → `start-work` |
| POST_SPLIT fidelity before parallel EXECUTE | Open/merge PR → `create-pr` / `finish-work` |
| **Adopt** existing GH issue(s) into binders (append-only) | Greenfield issue create when no issue exists yet |

## Core rules

### INVARIANT (fail closed)

1. **Locked scope required** — Why/In/Out/Acceptance (or Spec). Fuzzy → create-spec; **no ticket fiction**.
2. **POST_SPLIT_CHECK** when Spec has `A*` — fail closed on orphan A* / invented scope.
3. **Independence gates** before any `parallel_group` (solo-merge, contracts, paths, blocked_by, covers).
4. **Accountable issue/binder ownership** — exact targets and scope remain owned by the host; bounded creation/writes may be delegated when authority is explicit and the host verifies ids, bodies, and binders.
5. **No product implementation** here.
6. **Shippable cwd evidence** for binder writes — run `assert-shippable-cwd`. Default to one worktree for same-pass Review+tickets/Spec/ADR; explicit reasoned workspace/base-direct escapes permitted.

### DEFAULT

7. Prefer **vertical slices** over horizontal chore piles when splitting.
8. Batch delivery meta in **one** round (not serial trivia; not re-open product principals on Spec).
9. Path-overlap / serial foundation → **Ship: one-PR**, one worktree.
9b. **Anticipated-decisions scan + `## Approach` at split time** — per proposed ticket, dry-run the implementation against real code (read-only) and emit expected decision points (error semantics, naming, library choice, edge behavior …) into binder `## Anticipated decisions`, each dispositioned `pre-resolved | agent-decides | must-ask` per `decision-policy.md` (irreversible / cross-contract is **never** `agent-decides`). Pre-resolved items are confirmed inside the **one** delivery-meta batch (rule 8 — no extra rounds); must-ask items the user leaves unresolved become `## Pending decisions`. Author `## Approach` (5–10 line sketch + touch-set) per ticket. Recipe: `flow.md` §2.2.
10. **Any delivery ticket under Spec (`spc-N` primary #N, child ≠ primary):** after each child create, soft-fail link child as **GitHub sub-issue of Spec primary #N** (including single-ticket). Tickets stay full independent issues. Ticket-only (no Spec primary) → no parent.

### HINT

11. User said "just one ticket" → one issue even if C.
12. Labels: sync via `scripts/sync-github-labels.sh` when create fails on missing labels.
13. Parent hierarchy ≠ `blocked_by` ≠ ship plan — do not overload sub-issues for deps or packing.

### Adopt existing issue (append-only)

When the operator already has GitHub issue `#M` (hand-created or external):

| Do | Don't |
| --- | --- |
| Reuse `#M` as `tkt-M` — **no** second `gh issue create` for same intent | Guess a new number or dual-track ids |
| Write binder `tkt-M-*/README.md` with `adopted: true`; extract Why/Scope/Acceptance | **Rewrite** issue title/body to Lattice template |
| Optional **one** adopt comment (binder path, Spec, covers) | Spam comments; edit body to force checkboxes |
| Soft-fail labels / Project / Spec parent sub-issue link | Strip operator labels; hard-fail create on parent link |
| POST_SPLIT when Spec has `A*` (covers partition) | Ticket fiction outside Spec |

`start-work` runs **ADOPT_CHECK** when L0 is incomplete; this skill owns the **from-issue binder recipe** when invoked as create-tickets adopt.

## When to split

| Situation | Output |
| --- | --- |
| Ticket only (no Spec primary) | **One** issue (no sub-issue required) |
| Spec primary exists + 1 delivery slice | **One** delivery issue as **sub-issue of Spec primary #N**; do **not** dual-role primary as the ticket |
| Spec primary + multiple slices | **N** delivery issues as sub-issues of Spec primary #N; do **not** invent a second epic issue |
| User said one ticket and no Spec | One issue even if C |

## Independence gates (N > 1)

| Gate | Fail → |
| --- | --- |
| **Solo-merge** | Merge into another slice or defer |
| **Contracts** | Serial foundation ticket first |
| **Paths** | Drop from parallel group or re-slice |
| **Blocked by** | Wrong group / order |
| **covers** | Add covers or split Acceptance |

Parallel degree ≥ 2 → one sibling worktree per concurrent tkt. Path-overlap → one worktree / one-PR.

## Short path

1. Step 0: ensure-lattice + assert-shippable-cwd (`flow.md`).
2. Read locked Spec / COMMITTED.
2b. Per proposed ticket: read-only dry-run against real code → draft `## Approach` (5–10 lines + touch-set) + anticipated decision points dispositioned `pre-resolved | agent-decides | must-ask` (`flow.md` §2.2).
3. Propose ship plan + ticket table + decision dispositions (one batch).
4. POST_SPLIT_CHECK.
4b. Duplicate-work precheck (advisory, DEFAULT): for each proposed ticket title, run `check-duplicate-work.sh --title "…" --skip-remote` (in `_lattice-lib/scripts/`) before `gh issue create`. Review ⚠️ overlaps; never blocks (advisory, exits 0).
5. `gh issue create` + labels; optional Project add (soft-fail); under Spec primary → soft-fail sub-issue parent link (including N=1); write binders (incl. `## Approach` + `## Anticipated decisions` from 2b; unresolved must-ask → `## Pending decisions`); update Spec.tickets.
6. Handoff issue #s + binder paths for `start-work`.

After each successful create, best-effort board add (opt-in; never blocks create):

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")
bash "$LIB/github-project-add.sh" "$ISSUE_URL" || true
# Delivery ticket under Spec primary #N (N≥1) — soft-fail; never blocks create:
# bash "$LIB/github-issue-parent-add.sh" --parent "$SPEC_PRIMARY_N" --child "$ISSUE_URL" || true
```

Full recipes (gh body, binder mkdir, media, parent link): **`references/flow.md`**. Policy: **`references/policy.md`**.

## Anti-patterns

Structural Don’ts (time-pressure / invent-scope excuses → **Common Rationalizations**):

| Don't | Why |
| --- | --- |
| Template-overwrite hand-created issue body | Append-only |
| Create second issue for same adopted intent | Id SoT is existing `#M` |
| Hard-fail create when parent link fails | Soft-fail only; prose Parent + L0 still recover |
| Nested multi-level sub-issue trees by default | One level: Spec primary → delivery tickets |
| Use sub-issue instead of `blocked_by` | Hierarchy ≠ dependency |
| Dual-role Spec primary as sole delivery ticket | Spec-then-ticket ⇒ ≥2 issues |
| Skip parent link when Spec exists but only one ticket | N=1 under Spec still sub-issue |

## Relationship

| Skill | Role |
| --- | --- |
| `create-spec` | First-pass PCA + `spc-n` |
| `start-work` | Workspace bind + EXECUTE |
| `create-pr` | Fixes/Refs + Spec line |

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| "Spec is fuzzy — invent tickets anyway" | Fail closed → create-spec |
| "Skip POST_SPLIT — covers are obvious" | Fail closed |
| "N tickets means N parallel worktrees/PRs" | Independence + ship plan |
| "Labels can wait" | M/C require kind + priority |
| "Issue without local binder is fine" | Binder required for workspace recovery |
| "Ship all tickets in parallel to hit the date" | Gates + path-overlap still apply under deadline |
| "Boss said open issues now, align later" | No ticket fiction; align first |
| "Sub-issue means no binder / no self-contained body" | Still full issue + binder |
| "Parent k/n closed ⇒ Spec done" | Progress ≠ Acceptance; finish-work still checks boxes |
| "Scan decisions later, at start-work" | Split time is when global context + the human are present; night questions are cheapest now |
| "Confirm pre-resolved items one by one as they come up" | Dispositions ride the single delivery-meta batch — never serial questioning |
| "Only one ticket under Spec — skip sub-issue / dual-role primary" | Spec-then-ticket ⇒ ≥2 issues; N=1 child still sub-issue |

## Red Flags

- Tickets whose Scope is not in Spec In/Acceptance/Decisions
- Parallel group sharing overlapping hot paths
- Missing covers for Spec A* without deferred note
- Implementing product code while filing issues
- Mass-creating issues from a fuzzy prompt under time pressure

## Verification

- [ ] Locked Spec or COMMITTED-like scope loaded
- [ ] Ship plan declared (one-PR \| multi-PR) with gates when N>1
- [ ] POST_SPLIT_CHECK pass (cover partition, no invent, no contradict)
- [ ] Each issue created with labels + body; binder README written; paths printed
- [ ] Spec.tickets L0 updated with bare `tkt-N` ids
- [ ] Under Spec primary: soft-fail parent link attempted for each delivery child (incl. N=1); ticket-only path skipped intentionally
- [ ] Per ticket: `## Approach` (sketch + touch-set) + `## Anticipated decisions` dispositions written at split time; no irreversible/cross-contract item marked `agent-decides`
- [ ] Pre-resolved items confirmed inside the one delivery-meta batch; user-unresolved must-ask landed in `## Pending decisions`
- [ ] No product implementation
