# Lattice workflow policy (portable)

Shipped with `start-work`. **Do not require monorepo `docs/`** to run this skill.  

## Contents

- [Self-contained artifacts (hard rule)](#self-contained-artifacts-hard-rule)
- [Consumer ready (every skill entry)](#consumer-ready-every-skill-entry)
- [Shippable isolation default and explicit base-direct escape](#shippable-isolation-default-and-explicit-base-direct-escape)
- [Profiles (`strict` | `light`)](#profiles-strict-light)
- [Modes S / M / C](#modes-s-m-c)
- [Phase ownership](#phase-ownership)
- [Confirmation (batch)](#confirmation-batch)
- [COMMITTED card (session)](#committed-card-session)
- [COMMITTED](#committed)
- [Artifacts](#artifacts)
  - [Review outcomes](#review-outcomes)
- [Kind + priority + labels](#kind-priority-labels)
- [Branch / worktree](#branch-worktree)
  - [Choose isolation (before first shippable write)](#choose-isolation-before-first-shippable-write)
- [Bloodline (L0 + GitHub only)](#bloodline-l0-github-only)
- [Skill map](#skill-map)
- [Anti-patterns](#anti-patterns)

## Self-contained artifacts (hard rule)

Every Spec, Ticket (issue+binder), PR, and Review must be:

1. **Independently intelligible** — a reader with no chat history understands purpose, scope, and status.  
2. **Logically coherent** — Why → Scope → Acceptance/Outcome → Lineage.  
3. **Reference-clear** — when reusing another artifact, name it explicitly (`Spec: spc-N` + path or URL).
4. **Not blindly duplicated** — do not paste full Spec into every ticket/PR; **summarize + link**.

| Bad | Good |
| --- | --- |
| “see chat” / “as discussed” | One-sentence Why in the artifact |
| Copy entire Spec into PR body | `Spec: spc-N` + path + 2-line summary |
| Empty binder that only says “see issue” | Binder has kind, priority, acceptance bullets, links |

Templates: `references/templates/`.

## Consumer ready (every skill entry)

**Agents only** — run the deterministic ensure script (do not hand-roll skeleton; do not ask users to run init):

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")
bash "$LIB/ensure-lattice.sh"
# optional: --sync-labels when gh labels missing (create-tickets path)
```

`ensure-lattice.sh` is idempotent: creates `.lattice/` + `config.yaml` when missing; never overwrites an existing profile. Users never invoke it. See monorepo `docs/getting-started.md` when present.

**After engine release:** reinstall the global pack so agents actually load new scripts (`ensure-lattice`, `assert-shippable-cwd`, …):

```bash
npx skills add percena/lattice -a claude-code -a codex -g -y
```

## Shippable isolation default and explicit base-direct escape

| Rule | Detail |
| --- | --- |
| Default fail | `assert-shippable-cwd.sh` exits 1 when `show-toplevel == MAIN_ROOT` **and** branch is `main`/`master`/`dev` (or live default). Under **strict** it also fails a **non-base branch on the main clone** (`non_base_on_main_clone`) — a bound-name temp branch in the main clone is the recorded drift path and is no longer a pass. |
| Pass | Linked worktree (`show-toplevel != MAIN_ROOT`); **or** non-base branch on main clone under **light** profile (`--mode branch` escape). |
| Base-direct escape | Explicit user authorization + clean starting tree + `--allow-base-write --reason …`; output records the deviation. Under strict it is also the escape for a non-base main-clone branch (`authorized_nonbase_direct`). |
| Order | `gh issue create` may run on base (metadata only) → **ensure-workspace + cd** → then Spec / ticket binder / product Write |
| **Review exempt (Review-only)** | `create-review` may write `.lattice/reviews/` on team base. Same-pass co-create defaults to one worktree; reasoned escapes remain available. Never bind a worktree to `rev-` alone |
| After finish | `check-base-residue.sh` on MAIN; cleanup-workspace warns if residue remains |

**Do not** treat accidental or dirty base writes as a happy path. Base-direct is an explicit user-authorized delivery choice, not a silent model convenience.

## Machine-enforced worktree discipline (strict profile)

The isolation default above was historically **self-enforced** — soft guidance that agents routinely drifted past via a bare `git checkout -b` in the main clone. Under `strict` profile it is now **machine-enforced** by a three-layer PreToolUse stack (see `ADR-006`, `spc-145`):

| Layer | What it blocks | How |
| --- | --- | --- |
| **L1 — git hook** | Raw `git checkout -b`/`-B`, `git switch -c`/`-C`, `git branch <create>`, and switch to an existing non-base branch — when CWD is the main clone | `plugins/lattice/hooks/intercept-git-branch-create.sh`; gates on **location** (main clone vs worktree), not branch name, so a bound name in the main clone is still blocked. The blessed `ensure-workspace.sh` invocation is never matched (its internal git ops are subprocess calls inside the script, not Bash tool calls). |
| **L2 — assert hardening** | Non-base branch on main clone (strict) | `assert-shippable-cwd.sh` now fails `non_base_on_main_clone` under strict; escape via `--allow-base-write --reason`. |
| **L3 — Write/Edit hook** | Shippable writes (`.lattice/specs|tickets|lineage/**`, tracked product code) when the cwd is not a shippable workspace | `plugins/lattice/hooks/intercept-shippable-write.sh`; runs assert before the write and denies (exit 2) on fail. Exempts `.lattice/reviews/**` and `docs/adr/**` (documented base-write policy). Does not trust the L1 sentinel — the spoof backstop. |

**Non-standard flow (interactive-confirmation escape):** the strict default blocks drift. When the user explicitly authorizes a non-standard flow (plain branch or base-direct commit), the agent must **ask the user first and wait for confirmation**, then route through the audited escape so the reason is recorded:

```
ensure-workspace.sh --mode branch --branch <name> --allow-unbound --reason "user-authorized: <why>"
assert-shippable-cwd.sh --allow-base-write --reason "user-authorized: <why>"
```

The "ask the user first" step is a procedure expectation (the hook cannot verify a confirmation happened); the recorded `--reason` is the audit trail, and drift (no authorization) remains blocked at L1/L3. Switching to a base branch and working inside a linked worktree are always allowed.

## Profiles (`strict` | `light`)

| Source | Priority |
| --- | --- |
| `LATTICE_PROFILE` env | highest |
| `.lattice/config.yaml` → `profile:` | |
| default | **strict** |

| Profile | Worktree default | Acceptance alignment (`alignment-check`) | Bind `tkt`/`spc` |
| --- | --- | --- | --- |
| **strict** | Shippable → sibling worktree | Open Acceptance on `Fixes` = **HARD** | Default; reasoned unbound escape allowed |
| **light** | Shippable `--mode branch` **allowed** | Same cases = **WARN** (exit 0) | Default; reasoned unbound escape allowed |

Percena dogfood stays **strict**. Light is opt-in for adopters who accept branch-mode isolation.

## Modes S / M / C

| Mode | When | Ticket | Workspace | Confirm rounds |
| --- | --- | --- | --- | --- |
| **S** | Small, clear, reversible | Skip issue only if no-PR throwaway; may ship → tkt or spc bind | **Sibling worktree** if may ship | 0–1 |
| **M** | Multi-file / real choice / merge | One issue default (skippable) | **Sibling worktree** | 1–2 |
| **C** | Multi-session/module, unclear, parallel | Required (+ split) | **Sibling worktree** (+ pack DAG) | 2–3 (cap 5) |

If unsure → **M**. Never silent-S on ambiguous product work.

**Shippable → sibling worktree by default.** Branch remains the **merge unit** (PR head); worktree is the **default working tree** so the main checkout stays free for parallel work. `--mode branch` only when the user **explicitly** opts in. Pure read-only explore / no-PR throwaways may stay on base without a worktree.

**Main checkout role (DEFAULT):** stay on team base for read-only explore/orchestration and launch workspaces. Direct shippable EXECUTE is allowed only after explicit user authorization and the clean base-direct check.

**Default isolation:** first shippable write uses WORKSPACE (normally a sibling worktree), and subsequent writes use the returned path. **Explicit base-direct:** only when the user authorizes direct base delivery; run `assert-shippable-cwd --allow-base-write --reason …` from a clean tree and record the choice. This escape does not authorize an unrequested push or waive verification.

**Re-entry / upgrade:** demo, review, or dogfood that becomes “fix and open PR” → re-CLASSIFY, refresh COMMITTED, run **WORKSPACE before the first fix edit**. Do not implement on `main` and discover the gap only at `create-pr`. “Edit on main then `git switch -c`” is **rescue only**, not the happy path.

**Setup-only:** user may ask to create Spec/ticket/workspace **without** implementing. After the requested setup steps, **stop** and print how to continue (`/start-work tkt-N` or `spc-N`). There is **no** `/implement` skill — EXECUTE is in-session work after handoff or resume. Setup-only is natural under Create-first phase order (create-spec/tickets may stop without start-work).

**Resume-by-id:** if binders/Spec already exist for `tkt-N` / `spc-N`, load L0 → rebuild COMMITTED from files → **skip full product BATCH_CONFIRM** when scope is locked → `ensure-workspace` → EXECUTE (unless setup-only). Do not re-create Spec/tickets or re-grill unless the user asks or Acceptance is empty/stale.

**ADOPT_CHECK:** when intake is an **existing** GH issue `#M` (or `tkt-M`) and binder/edges are **missing or incomplete**, classify **adopt** — not silent greenfield create and not full product re-grill.

| INVARIANT | Detail |
| --- | --- |
| Append-only issue body | **Never** rewrite operator title/body to Lattice templates. Soft-fail labels/parent/project only. |
| Comments | Optional **one** adopt comment (binder path, Spec id, covers). Prefer no spam. |
| Id SoT | Reuse `#M` as `tkt-M` — **do not** create a second issue for the same delivery intent. |
| Binder | Create/update `.lattice/tickets/tkt-M-*/README.md`; mark `adopted: true` (table field). Extract Acceptance into binder. |
| Gaps | Missing Acceptance → batch into binder/COMMITTED; do not invent product scope into the issue body. |
| Spec | May **create new** Spec primary + file when C/multi-session needs it; soft-fail sub-issue parent. Do not dual-role `#M` as Spec primary + sole delivery on Spec-then-ticket without operator intent. |
| Close | **No** close/reopen during adopt — only later via `Fixes` + finish-work. |

After ADOPT_CHECK: COMMITTED from issue (read-only) + binder + optional Spec → `ensure-workspace --bind tkt --id M` → EXECUTE or setup-only. Finish uses **binder-first** Acceptance for `adopted: true` binders.

## Phase ownership

| Phase | Host |
| --- | --- |
| First-pass product/方案 align | **`create-spec`** (PCA batch) |
| Delivery meta + POST_SPLIT_CHECK | **`create-tickets`** |
| Workspace + EXECUTE / resume | **`start-work`** (this skill) |
| Mid-EXECUTE new principals | **`start-work`** explicit batch (not fully silent) |

Greenfield `/start-work` with no L0: **delegate** create-spec (+ tickets) dialect, then workspace — do not claim “align only lives here.”

## Confirmation (batch)

- Silent PREP first (facts from tools).  
- Batch **2–5 principal** questions with recommendations.  
- Self-decide secondaries; list for override.  
- Not one micro-question per turn. Same PCA rules as `references/align-policy.md` / create-spec.  
- **Prefer** create-spec for first-pass; this skill batches mainly for greenfield delegate + mid-EXECUTE.

## COMMITTED card (session)

Required before EXECUTE on M/C (S may be implicit):

```text
## COMMITTED
- Why / In / Out / Acceptance
- mode: S|M|C
- Spec: none | spc-n
- Ticket: skip | one | split
- Issue: none | #N | pending
- Workspace: worktree | branch | base-direct (explicit user authorization)
- Workspace name: tkt-… | spc-…
- Ship: one-PR | multi-PR
- Primary ticket: none | tkt-N
- Direction confirmed via: ADR-NNN | rev-… | user-stated | assumed
- User-decided / Agent-assumed
```

Promote to Spec file for **C** multi-session work.

**`Direction confirmed via: assumed` → batch-confirm before product EXECUTE** (see `SKILL.md`): a wholly un-confirmed direction (no accepted ADR, no concluded `rev-`, not user-stated) must not silently proceed to implementation.

**Ship:** multi-ticket ≠ multi-PR. Path-overlapping or serial slices → **one-PR** (`Fixes` primary + `Refs` related). **multi-PR** only when independence gates pass and concurrent EXECUTE is planned.

**L0-on-checkout:** default to WORKSPACE first and commit L0 under the active feature checkout. Claim `.ids` may share MAIN_ROOT. Review-only may land on base; explicitly authorized base-direct may co-create L0 there after the clean-start check.

## Artifacts

| Layer | Id | Role | Shippable worktree? |
| --- | --- | --- | --- |
| Review | `rev-YYYYMMDD-HHMMSSZ` | Research / compare; needs `outcome` when concluded | **No** alone |
| Spec | `spc-n` | Locked delivery contract | Transitional `spc-` only |
| Ticket | `tkt-n` = GH `#n` | Delivery slice (GH SoT) | **Yes (default)** |
| PR | `pr-n` = GH PR | Mergeable change set | N/A (has branch) |

IDs: **bare decimal** (`spc-1`, not `spc-001`).

### Review outcomes

`inform_only` | `spawn_spec` | `spawn_tickets` | `spawn_fix` | `needs_grill`  
Path: Review → (optional Spec) → Ticket → worktree. Never Review → worktree only.

## Kind + priority + labels

| kind | GH label | PR/commit type |
| --- | --- | --- |
| feat | `feat` | `feat:` |
| bug | `bug` | `fix:` |
| chore/docs/refactor/perf/test/spike/epic | same name | same (spike/epic rarely ship code) |
| research | *(Review only — no GH label required)* | n/a |

Priority: `P0`–`P3` (default **P2**). Labels on M/C issues: **one kind + one priority**.  
Issue titles: plain language — no required `[Bug]` brackets.  
Bootstrap labels: `create-tickets` → `scripts/sync-github-labels.sh`.

## Branch / worktree

```text
tkt-<n>-<slug>              # preferred when primary issue exists
feat/tkt-<n>-<slug>         # optional type prefix
spc-<n>-<slug>              # legal Spec-first open; rebind optional
```

### Choose isolation (before first shippable write)

**Parallel degree** = how many tickets are in **EXECUTE** at the same time (concurrent writers).  
Branch is the merge unit; **sibling worktree is the default working tree**. **Independence of tickets is decided at split time (`create-tickets`); worktrees only isolate what is already safe to parallelize.**

```text
Shippable write?
  no  → stay on base; read-only / orchestrate only
  yes → sibling worktree first (default)

Default:
  any S/M/C that may PR → --mode worktree --bind tkt|spc …

Parallel packing (after create-tickets DAG):
  dependent / path-overlap / same ship → ONE worktree slot (serial EXECUTE, one PR)
  independence gates pass + parallel_group → ONE worktree per concurrent tkt
  never two agents in one tree

Escape hatch:
  user explicitly asked for branch-only → --mode branch (not skill default)
  profile=light → --mode branch for shippable is allowed without treating as policy violation
  (tkt/spc bind is the default; reasoned unbound escape is available)

Ticket exists?
  yes → prefer --bind tkt --id N --slug …
  no, mode C Spec-first → --bind spc (legal for life of single-PR tree if binder records primary later)
  neither → prefer issue/Spec; or use semantic --branch + --allow-unbound --reason with equivalent ownership/scope evidence
  S no-PR throwaway → may skip workspace entirely
  review-only → no shippable worktree (Never Review → worktree only)
```

| Situation | Action |
| --- | --- |
| Shippable S/M/C (default) | `ensure-workspace.sh --mode worktree …` |
| **Degree ≥ 2** (parallel tickets/agents) | **one sibling worktree per concurrent tkt** — never two agents in one tree |
| Soft cap | prefer ≤3 concurrent agent worktrees unless user overrides |
| Serial multi-ticket same ship | **one** tree / **one** PR; sub-tickets as `Refs` (not N worktrees) |
| User-explicit branch-only | `--mode branch` (escape hatch; script still refuses dirty branch mode) |
| Already edited on base by mistake | **Rescue:** stash → ensure worktree → pop (or `git switch -c` then move to worktree); continue only in bound tree |

**Large demand → parallel-ready (happy path):** align Spec/ADR → `create-tickets` with independence + DAG fields → **pack** dependent tickets into worktree slots → fan out `--mode worktree` only for parallel groups → one PR per tree.

**Ownership:** binder fields `worktree_bind`, `primary_ticket`, `related_tickets` + PR `Fixes`/`Refs` are SoT after open. Rebind `spc` → `tkt` is **optional hygiene**, not required.

Default worktree root: sibling `$(dirname MAIN)/$(basename MAIN).worktrees` (`WORKTREE_ROOT`).  
Not under `.claude/` or `.lattice/`.

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")

# Default (shippable):
bash "$LIB/ensure-workspace.sh" --mode worktree --bind tkt --id N --slug <slug>
# optional: --type feat

# Spec-first C:
bash "$LIB/ensure-workspace.sh" --mode worktree --bind spc --id N --slug <slug>

# Escape hatch only (user-explicit):
bash "$LIB/ensure-workspace.sh" --mode branch --bind tkt --id N --slug <slug>
```

## Bloodline (L0 + GitHub only)

- **SoT:** Spec/binder/Review edges + GitHub `Fixes`/`Refs`.
- **Primary path example:** `spc-N → tkt-N → pr-N, pr-M` (binder / Spec `Path:`).
- **ADR** is architecture history, **not** a bloodline node.
- **Light RTM (C):** Spec Acceptance `A*` + binder `covers`.
- Do not create a derived global index or BOARD; bloodline = L0 + GitHub.

## Skill map

| Skill | Owns |
| --- | --- |
| `start-work` | classify → route first-pass align to `create-spec` → committed → spec? → ticket policy → workspace + EXECUTE/resume |
| `create-spec` | persist `spc-n` |
| `create-review` | persist `rev-YYYYMMDD-HHMMSSZ` + outcome |
| `create-tickets` | issues + binders + labels + `covers` (+ issue media upload) |
| `create-pr` | SHIP + progress comments (+ PR media upload via `upload-github-asset.sh`) |
| `finish-work` | merge/close + cleanup |

## Anti-patterns

- Skip CLASSIFY on ambiguous work  
- Serial micro-questions  
- **Shippable Write/Edit on `main`/`master`** (including “I’ll branch later”)  
- **Default `--mode branch` for shippable work** (use sibling worktree; branch only if user opts in)  
- **Shippable EXECUTE on main checkout** (main = base + orchestrate only)  
- Worktree without `tkt-`/`spc-` for shippable M/C  
- Review-only worktree for ship work  
- Artifact that only says “see conversation”  
- Depending on monorepo `docs/` after skill install  
