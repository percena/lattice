---
name: start-work
description: "Start or resume work on a ticket/Spec: light classify, load locked binders, ensure sibling worktree, hand off to implement (or setup-only stop). Use when starting work, continuing tkt-N/spc-N, ensuring workspace, or one-shot orchestrate. Not for opening a PR, merging, or first-pass product align alone (use create-spec)."
allowed-tools: Bash Read Grep Glob AskUserQuestion
argument-hint: "[tkt-N | spc-N | setup-only | #N]"
metadata:
  agents: "claude-code,codex"
---

# Start work

**Implement / resume entry.** CLASSIFY → load L0 → WORKSPACE → EXECUTE (or setup-only stop).  
**First-pass product align** → **`create-spec`**. Ticket meta → **`create-tickets`**. This skill does **not** solely host first-pass grill.  
Does **not** replace domain skills or `create-pr`.

Templates: co-installed `create-spec` / `create-review` `references/templates/` (no local copies). Do **not** require monorepo `docs/` to run.

**Runtime path:** before executing skill-owned files, set `LATTICE_SKILL_ROOT` to the absolute directory containing this loaded `SKILL.md` (Claude may already provide `CLAUDE_SKILL_DIR`). Never infer it from consumer cwd.

## Load on demand

| When | Read |
| --- | --- |
| Profiles, labels, bloodline, ADOPT edges | `references/policy.md` |
| M/C multi-ticket ship plan / parallel packing | `references/full-flow.md` |
| Greenfield / fuzzy PCA dialect detail | `references/align-policy.md` (or delegate `create-spec`) |
| Severity labels INVARIANT/DEFAULT/HINT | `../_lattice-lib/references/constraint-language.md` |
| Delegation and accountable ownership | `../_lattice-lib/references/orchestration-patterns.md` |
| Claiming shippable / tests green | `../_lattice-lib/references/definition-of-done.md` |

Do **not** pre-load every reference; stay on this file for locked resume + S path.

## When to use / When NOT

| Use | Not — use instead |
| --- | --- |
| Start/resume `tkt-N` / `spc-N`, ensure workspace, EXECUTE | Open PR → `create-pr` |
| Setup-only stop before product code | Merge/cleanup → `finish-work` |
| One-shot orchestrate (delegates create-spec when fuzzy) | First-pass align alone → `create-spec`; PR bugs → `review-code` |

## Step 0 (every run)


```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")
bash "$LIB/ensure-lattice.sh"
# Before shippable L0 write on team base:
bash "$LIB/assert-shippable-cwd.sh" || {
  bash "$LIB/ensure-workspace.sh" --mode worktree --bind tkt --id N --slug <slug>
  # cd to JSON path / honour cd_hint — re-run assert
}
```

## Invariants (must hold)

| INVARIANT | Detail |
| --- | --- |
| Classify | Announce `mode: S\|M\|C` + one-line reason; unsure → **M** |
| Safe starting state | Default: Spec/ticket binders/product code/new ADR after WORKSPACE. Explicit user-authorized base-direct may use `assert-shippable-cwd --allow-base-write --reason …` from a clean tree |
| Workspace identity | Default: `--bind tkt\|spc`. Escape: semantic `--branch` + `--allow-unbound --reason …`; fake zero ids remain forbidden |
| Resume | Locked `tkt`/`spc` → **skip** full product BATCH_CONFIRM; load L0 from files |
| Align host | Greenfield fuzzy → **delegate `create-spec`** (same PCA dialect); do not invent a second grill |
| Mid-EXECUTE principals | New irreversible/high-stakes axis → explicit PCA batch (not silent) |
| COMMITTED before product EXECUTE | S may be implicit when fully determined |
| Accountable orchestration | One owner controls classification, authority, bind/evidence, and final validation; bounded delegation is allowed (`orchestration-patterns.md`) |
| No `/implement` skill | EXECUTE is a state; setup-only stops when asked |
| Self-contained artifacts | Spec/ticket/PR/Review readable without chat |

## Defaults and escapes

| DEFAULT | Escape / HINT |
| --- | --- |
| Shippable → sibling **worktree** (`strict`) | User-explicit branch/base-direct or reasoned unbound workspace; make equivalent ownership/isolation evidence visible |
| Degree ≥ 2 independent tickets → one worktree per concurrent tkt | Path-overlap / serial foundation → **one-PR**, one tree |
| Batch 2–5 principals with recommendation | S: 0–1 only if acceptance missing |
| After EXECUTE → `create-pr` for SHIP | Do not open PR inside this skill by default |

## S path (short)

1. INTAKE + CLASSIFY → announce mode.  
2. If `tkt-N` / `spc-N` **with locked L0** → **resume** (load binder/Spec, skip re-grill).  
3. Else if **existing GH issue `#M`** / `tkt-M` **without complete L0** → **ADOPT_CHECK** (portable detail in `references/policy.md`) — **append-only** on issue body; write binder; optional Spec/comment; soft-fail edges.  
4. Else if fuzzy greenfield → **delegate `create-spec`** (then tickets if needed).  
5. COMMITTED card (Why / In / Out / Acceptance / mode / workspace / ship).  
5b. Duplicate-work precheck (advisory, DEFAULT): run `check-duplicate-work.sh --title "<ticket title>"` (in `_lattice-lib/scripts/`) before `ensure-workspace`. Review ⚠️ overlaps; never blocks (advisory, exits 0).  
6. WORKSPACE: `ensure-workspace --mode worktree --bind tkt|spc …` (or light/user branch escape). **cd** to path.  
7. EXECUTE under the accountable owner **unless** setup-only → stop with `/start-work tkt-N` hint. Bounded delegation is allowed.
   - DEFAULT: no forced TDD; use the bound workspace unless an escape is explicit; new irreversible axis → PCA batch.
   - `NOTICED BUT NOT TOUCHING:` out-of-ticket cleanup → later ticket, do not fold in.  
8. Done implementing → VERIFY with **fresh command evidence** (DoD Iron Law: `../_lattice-lib/references/definition-of-done.md`) → `create-pr`.

### ADOPT_CHECK (existing issue, incomplete L0) — INVARIANT append-only

When intake is `#M` / “use this issue” and binder or edges are missing:

| Step | Action |
| --- | --- |
| 1 | `gh issue view M` — fail closed if missing |
| 2 | **Do not rewrite** issue title/body (operator SoT). Comments OK (prefer **one** adopt note). |
| 3 | **Do not** `gh issue create` a second number for the same delivery intent |
| 4 | Create/update binder `tkt-M-<slug>/README.md` — extract Why/Scope/Acceptance; set `adopted: true` in binder table |
| 5 | Gaps in Acceptance → PCA into **binder/COMMITTED** (or adopt comment), not invent into issue body |
| 6 | Optional new Spec (new epic issue + file) or link existing; soft-fail sub-issue parent under Spec primary |
| 7 | Soft-fail missing kind/priority labels + Project add |
| 8 | COMMITTED from issue (read-only) + binder + Spec → `ensure-workspace --bind tkt --id M` |

**Forbidden on adopt:** template-overwrite body; dual-role `#M` as Spec primary + sole delivery on Spec-then-ticket without operator intent; close/reopen issue during adopt.

## M/C path

Same invariants. Full recipes (Spec write, ticket create, ship plan tables, parallel packing, anti-pattern encyclopedia): **`references/full-flow.md`**.  
Policy tables (profiles, labels, bloodline): **`references/policy.md`**.

### BATCH_CONFIRM host

| Situation | Action |
| --- | --- |
| Resume locked `tkt`/`spc` | Skip full product batch |
| Existing issue, incomplete L0 | **ADOPT_CHECK** (append-only; no body rewrite) |
| Greenfield / fuzzy | Delegate **`create-spec`** |
| S/light-M session only | COMMITTED may suffice without Spec file |
| Mid-EXECUTE new principal | Must batch-confirm |

### COMMITTED card (emit and keep)

```markdown
## COMMITTED
- Why / In / Out / Acceptance
- mode: S|M|C
- Spec: none | spc-n
- Ticket: skip | one | split
- Issue: none | #N | pending
- Workspace: worktree | branch | …
- Workspace name: tkt-<id>-slug | spc-<n>-slug
- Ship: one-PR | multi-PR
- Primary ticket: none | tkt-N
- User-decided / Agent-assumed
```

Multi-ticket ≠ multi-PR — declare ship **before** EXECUTE (`full-flow.md`).

## Loading constraints

- Team base: read/orchestrate only by default; shippable writes require a workspace or the explicit clean base-direct escape.
- Non-interactive / CI: do not invent PCA answers — fail closed or setup-only.
- Classification, authority, workspace evidence, and ticket policy retain one explicit accountable owner; delegation must not create split ownership.

## Response style


- Classification + COMMITTED: visible and short.  
- PREP: silent.  
- No step narration theater.  
- User confirms: principal batches only.

## Relationship

| Skill | Role |
| --- | --- |
| `create-spec` | First-pass PCA + `spc-n` |
| `create-tickets` | Meta batch + POST_SPLIT + issues/binders |
| `create-review` | `rev` + outcome |
| `create-pr` / `finish-work` | SHIP / merge+cleanup |

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| "Small change — silently edit main" | Worktree is DEFAULT; base-direct requires explicit user authorization, a clean start, and recorded reason |
| "Resume means re-grill the whole product" | Locked tkt/spc → skip full BATCH_CONFIRM |
| "Manual issue — rewrite body to Lattice template" | **Append-only**: binder + comment; never pollute operator prose |
| "No binder — just EXECUTE on #M" | ADOPT_CHECK first; binder required for recovery/finish |
| "I'll implement first, open Spec/ticket later" | COMMITTED (and C Spec/tickets) before product EXECUTE |
| "Setup-only was soft; keep coding" | Explicit setup-only stops after workspace |
| "New irreversible API rename mid-EXECUTE — just decide" | New principal → PCA batch |
| "Delegation transfers accountability" | The host still owns scope, authority, integration, and fresh verification |
| "While setting up, fix unrelated lint on main" | Scope: ticket bind only; NOTICED BUT NOT TOUCHING |

## Red Flags

- Silent Specs/binders/product writes on team base without the explicit clean base-direct escape
- Unreasoned unbound worktrees or `tkt-0` / `spc-0` fake ids
- Sub-agent owns bind / classify / ticket policy
- Re-creating Spec on every resume
- Multi-ticket assumed multi-PR without ship plan
- Overwriting hand-created issue bodies during adopt
- Closing Issues during ADOPT_CHECK

## Verification

Before claiming workflow setup / EXECUTE handoff is done:

- [ ] Mode `S|M|C` announced with one-line reason
- [ ] COMMITTED card (or locked L0 resume) is explicit
- [ ] Shippable path: `assert-shippable-cwd` passes under the workspace or records the explicit clean base-direct escape (or pure throwaway no-PR)
- [ ] Ticket/Spec ids recorded when required by mode
- [ ] Setup-only stops without product implementation when requested
