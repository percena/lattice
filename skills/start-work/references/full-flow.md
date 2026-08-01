# start-work full flow (reference)

**Progressive disclosure:** use for M/C recipes only. Day-to-day: short `../SKILL.md` (S-path + invariants).  
**Policy:** `policy.md` · **Align:** `align-policy.md` · **Constraints:** `../../_lattice-lib/references/constraint-language.md` · **Orchestration:** `../../_lattice-lib/references/orchestration-patterns.md`

Labels: **INVARIANT** (must) · **DEFAULT** (happy path / escapes) · **HINT** (style).

---

## Contents

- [1. INTAKE + CLASSIFY (INVARIANT)](#1-intake-classify-invariant)
- [1.5 Resume-by-id (INVARIANT: no full re-grill)](#15-resume-by-id-invariant-no-full-re-grill)
- [1.6 ADOPT_CHECK (existing issue, incomplete L0)](#16-adoptcheck-existing-issue-incomplete-l0)
- [2. PREP (HINT)](#2-prep-hint)
- [3. BATCH_CONFIRM host](#3-batchconfirm-host)
- [4. COMMITTED card](#4-committed-card)
- [COMMITTED](#committed)
- [4.5 Spec + binder init (DEFAULT: M optional, C required)](#45-spec-binder-init-default-m-optional-c-required)
- [5. Ticket](#5-ticket)
- [6. WORKSPACE (INVARIANT before first shippable write)](#6-workspace-invariant-before-first-shippable-write)
- [7. EXECUTE handoff](#7-execute-handoff)
- [Response style (HINT)](#response-style-hint)
- [Anti-patterns (INVARIANT failures)](#anti-patterns-invariant-failures)
- [Relationship](#relationship)

## 1. INTAKE + CLASSIFY (INVARIANT)

Announce `mode: S|M|C` + one-line reason. Unsure → **M**.

| Signal | Mode |
| --- | --- |
| `tkt-N` / `#N` / existing **complete** binder | Resume ticket |
| `spc-N` / existing Spec | Resume Spec |
| `#M` / existing issue **without** complete L0 | **ADOPT_CHECK** (append-only) then bind `tkt-M` |
| setup only / don't implement | Setup-only stop after workspace |
| New work, no id | Normal classify → confirm path |

| Mode | Ticket default | Workspace DEFAULT | Confirm rounds |
| --- | --- | --- | --- |
| **S** | Skip only pure no-PR throwaway; may ship → issue or `spc-` | Sibling worktree if may ship | 0–1 |
| **M** | One issue (skippable) | Sibling worktree | 1–2 |
| **C** | Required (+ split) | Sibling worktree (+ DAG pack) | 2–3 (cap 5) |

## 1.5 Resume-by-id (INVARIANT: no full re-grill)

Load binder + Spec → rebuild COMMITTED from **files** → skip product BATCH_CONFIRM unless re-align requested or Acceptance empty → `ensure-workspace --bind tkt|spc` → EXECUTE unless setup-only.

```text
resume: tkt-N — loaded binder + spc-…; confirm=skip (locked); workspace=ensure
```

## 1.6 ADOPT_CHECK (existing issue, incomplete L0)

```text
adopt: #M — read-only issue body; binder tkt-M-… (adopted: true); optional Spec/comment; soft edges
```

1. `gh issue view M` (fail closed if missing; if CLOSED ask reopen vs new work).  
2. **Append-only:** do not edit issue title/body; optional one adopt comment.  
3. Write binder extracting Why/Scope/Acceptance; `adopted: true`.  
4. Optional: create Spec / link parent (soft-fail); soft-fail labels/project.  
5. COMMITTED → `ensure-workspace --bind tkt --id M` → EXECUTE or setup-only.  

Do **not** invent ticket fiction; fuzzy product scope still → create-spec for new Spec, not body rewrite of `#M`.

## 2. PREP (HINT)

Silent: facts from tools; PCA-reduce; fill secondary defaults.

## 3. BATCH_CONFIRM host

| Situation | Action |
| --- | --- |
| Resume locked `tkt`/`spc` | Skip full product batch |
| Existing issue, incomplete L0 | **ADOPT_CHECK** (append-only) |
| Greenfield / fuzzy | **Delegate `create-spec`** (same PCA dialect) |
| S/light-M session only | COMMITTED may suffice without Spec file |
| Mid-EXECUTE new principal | Must batch-confirm |

When batching: 2–5 principals + recommendation + trade-off; secondary self-decide; cap 5 rounds. No implement/tickets/branches until COMMITTED (S may be implicit).

## 4. COMMITTED card

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

**Ship (INVARIANT when split):** multi-ticket ≠ multi-PR. Path-overlap → **one-PR**. Independent concurrent EXECUTE → **multi-PR** + one worktree per concurrent tkt.

## 4.5 Spec + binder init (DEFAULT: M optional, C required)

**DEFAULT:** no shippable Spec/ticket binder write on team base — WORKSPACE first. **Review-only** is exempt. An explicit clean, user-authorized base-direct escape recorded by `assert-shippable-cwd` is also permitted.
Committed L0 home = current checkout `.lattice` (feature worktree). Claims (`.ids`) may use MAIN via claim home.

**Team Spec id (INVARIANT):** `gh issue create` → N → write `spc-N-*.md` (never guess max+1).  
Template: co-installed `../create-spec/references/templates/spec.md`.  
Reviews: `next-artifact-id --kind rev --claim` → create-review template.

After successful `gh issue create` (Spec tracker or ticket), optional Project add:

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")
bash "$LIB/github-project-add.sh" "$ISSUE_URL" || true
```

## 5. Ticket

| Mode | Action |
| --- | --- |
| S | Issue or `spc-` if may ship; skip only throwaway no-PR |
| M | One issue unless user skips |
| C | Tracking; multi-slice → **`create-tickets`** |

After issue N: binder `tkt-N-slug/README.md`, Spec `tickets: += tkt-N`, acceptance in issue body. Labels: kind + priority on M/C. Run `github-project-add.sh` on the issue URL (soft-fail; opt-in via env / `.env`).

## 6. WORKSPACE (INVARIANT before first shippable write)

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")
bash "$LIB/ensure-workspace.sh" --mode worktree --bind tkt --id N --slug <slug>
# Escapes: user-explicit/profile=light branch; or semantic unbound branch + --reason
```

| DEFAULT | Escape |
| --- | --- |
| Sibling worktree for shippable (`strict`) | User `--mode branch`; `profile: light` allows branch |
| Degree ≥ 2 independent → one tree per concurrent tkt | Path-overlap → one tree / one PR |
| Bind `tkt` or `spc` | `--allow-unbound --reason …` with semantic ownership evidence |

After ensure: all shippable Write/Edit/`git`/`gh` target returned **path**.

## 7. EXECUTE handoff

| Intent | Action |
| --- | --- |
| Default / implement / resume | Implement against COMMITTED under one accountable owner; bounded delegation allowed |
| Setup-only | Stop; print `/start-work tkt-N` |
| PR only after EXECUTE | Point to `create-pr` |

No `/implement` skill. The host owns integration and verification; read/write fan-out is allowed with disjoint ownership.

When done: VERIFY → **`create-pr`**.

## Response style (HINT)

Classification + COMMITTED visible and short. PREP silent. Principal batches only for user confirms.

## Anti-patterns (INVARIANT failures)

- Silent shippable write on team base without explicit clean base-direct authorization
- Unreasoned unbound worktree / `tkt-0` / `spc-0`
- Full re-grill on locked resume
- Ticket fiction without Spec
- Split or ambiguous ownership of classification, workspace evidence, or merge authority
- Multi-ticket assumed multi-PR without ship plan
- Rewrite hand-created issue body on adopt
- Close issue during ADOPT_CHECK

## Relationship

`create-spec` first-pass · `create-tickets` meta+POST_SPLIT · `create-review` · `create-pr` · `finish-work`
