---
name: create-spec
description: "Lock fuzzy product scope into a durable Lattice Spec (spc-N) via batch confirm / product decision align, then write Acceptance/Decisions under .lattice/specs. Use when clarifying multi-session intent, locking C/M scope, align-only create-spec without implement, or when start-work greenfield needs align-before-tickets. Not for implementing code, splitting tickets, or opening PRs."
allowed-tools: Bash Read Grep Glob AskUserQuestion
metadata:
  agents: "claude-code,codex"
---

# Create Spec

**First-pass align host:** silent PREP + PCA **BATCH_CONFIRM**, then persist a durable Lattice **Spec** (`spc-n`) under `.lattice/specs/`.  
**Does not implement product code, open tickets, or open PRs.**

**IDs:** GitHub issue number is team SoT for `spc-N` — create/choose primary **before** writing the Spec file. `next-artifact-id --kind spc` is offline degrade only (multi-clone unsafe).  
**PCA method:** this skill + co-installed `../start-work/references/align-policy.md` when more dialect detail is needed.

**Runtime path:** before executing skill-owned files, set `LATTICE_SKILL_ROOT` to the absolute directory containing this loaded `SKILL.md` (Claude may already provide `CLAUDE_SKILL_DIR`). Never infer it from consumer cwd.

## Load on demand

| When | Read |
| --- | --- |
| Issue create / adopt / write checklist | `references/issue-and-write.md` |
| Portable policy tables | `references/policy.md` |
| Spec file shape | `references/templates/spec.md` |
| Extra PCA dialect | `../start-work/references/align-policy.md` |
| Delegation and accountable ownership | `../_lattice-lib/references/orchestration-patterns.md` |

## When to use / When NOT

| Use | Not — use instead |
| --- | --- |
| Fuzzy multi-session/C intent; lock durable Spec | Implement product → `start-work` |
| start-work greenfield delegates Create-path align | Split tickets → `create-tickets` |
| Persist `spc-n` with Acceptance/Decisions | Architecture research only → `create-review`; open PR → `create-pr` |
| **Adopt** existing epic/`label:epic` issue as Spec primary (append-only body) | Dual-role delivery issue as Spec without operator intent |

## Core rules

1. **Own first-pass alignment here.** If scope is fuzzy (missing Why / In·Out / Acceptance / principal Decisions), run **embedded PREP + BATCH_CONFIRM (PCA)** — 2–5 principals with recommendation + one-line trade-off; secondary self-decide listed for override. **Do not** only say “go to start-work for grill.”
2. **Already locked** (user brief + acceptance + decisions clear, or COMMITTED card): write Spec without re-grilling.
3. **C multi-session / multi-ticket:** Spec is **required**. **M:** only if multi-session handoff or user asks. **S:** optional; usually skip — session COMMITTED without Spec remains valid when user never invokes this skill.
4. **Self-contained:** readable without chat; cite Review/ADR by **id** (path optional if engine checkout); no “as discussed”.
5. **Bare-decimal ids** in front matter lists (`tkt-N`, not slugful/zero-pad). **`id: spc-N` where N is the primary GitHub issue number.**
6. **Feature decisions** → Spec `## Decisions`. **Cross-feature architecture** → cite or promote `docs/adr/NNN` in the **consumer monorepo** (not a lineage node; never `next-artifact-id --kind adr`).
7. **C Acceptance:** number criteria **`A1`, `A2`, …** so tickets can `covers: A1, A2`.
8. **Keep L0 edges** on the Spec (tickets/prs/reviews lists). Bloodline = L0 + GitHub.
9. **Accountable Spec ownership (INVARIANT)** — one owner controls principal decisions, authority, and final validation; bounded evidence/drafting work may be delegated when ownership is explicit.
10. **No product implementation (INVARIANT)** here.
11. **Team id law (INVARIANT):** obtain GitHub issue **#N** before writing `spc-N-*.md`. Never guess `max+1`. Multi-ticket workstreams keep **primary** N for `spc-N`.

## Flow

### 0. Ensure Lattice ready + shippable cwd (required)

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")
bash "$LIB/ensure-lattice.sh"
bash "$LIB/assert-shippable-cwd.sh"   # Spec write is shippable L0
# shellcheck source=/dev/null
source "$LIB/_lattice-home.sh"
PH=$(lattice_default_home || echo "${LATTICE_HOME:-.lattice}")
mkdir -p "$PH/specs"
```

### 1. PREP + BATCH_CONFIRM (when scope fuzzy)

Silent PREP first (repo facts; never ask diggable facts).

**Optional (C + large blast-radius only):** if intent is rewrite/migrate/overhaul/cross-module architecture change, run a short **codebase reality pass** *before* PCA (read-only fan-out OK). Summarize structure/risks/tests/governance conflicts; ground principals in that reality. Write outputs into Spec/rev — **never** default `docs/analysis/`. **S/M: skip** (see `references/policy.md`).

Then one batch:

```text
### Core intent
…

### Please confirm (principal)
1. … — options; **recommended:** … — trade-off: …
2. …

### Self-decided (secondary; object if needed)
- …

Reply by number, free-form, or “accept all recommendations”.
```

Round budget: S 0–1 · M 1–2 · C 2–3 (cap 5). Prefer LOCKED summary before `status: locked`.  
If already COMMITTED / locked axes → **skip** this step and write.

**Align stop:** Can you fill Why / In / Out / Acceptance (C: `A*`) / principal Decisions **without inventing** unconfirmed product choices? If no after one PCA batch → re-batch missing principals only — do not open tickets or implement.

**ASSUMPTIONS (optional emit before batch):** list silent fills; "correct me or I'll encode these in Decisions."

**HINT — optional depth mode (user-explicit only):** "grill me" / "one at a time" / "deep interview". One principal per turn + recommended answer; still evidence-first; still no implementation. Exit when user returns to batch or locks. **DEFAULT remains PCA batch** — never auto-enter for S/M speed paths.

### 2. Issue number (team SoT) + write

**Load `references/issue-and-write.md`** for adopt recipe, `gh issue create`, offline degrade, and field checklist. Summary:

1. Adopt existing epic `#N` when present (append-only) **or** create primary issue → parse `#N`.
2. Optional Project add (soft-fail).
3. Write `$PH/specs/spc-${N}-<slug>.md` from `references/templates/spec.md` with `id: spc-${N}`.

### 3. Hand off

Report: Spec path, `spc-N`, mode, status, Acceptance ids (`A*`).  
Next: `create-tickets` (C/M) or `start-work` workspace bind (`--bind spc` transitional only until first ticket).

## Promote COMMITTED → Spec

When `start-work` already has a COMMITTED card and mode is C (or M multi-session):

1. Map Why / scope / acceptance / principals into the template.  
2. Do **not** invent tickets or PRs.  
3. Prefer one Spec per locked product intent; supersede with a new `spc-n` rather than silent rewrite of id.

## Anti-patterns

Structural Don’ts (pressure excuses → **Common Rationalizations**):

| Don’t | Why |
| --- | --- |
| Write Spec without acceptance | Cannot slice tickets or RTM |
| Put system-shape ADR body only in Spec forever | Promote to consumer `docs/adr/` when cross-feature |
| Zero-pad / date-as-id | Breaks bare-decimal contract |
| Invent a global index / BOARD | Bloodline is L0 + GitHub only |

## Relationship

- **`start-work`** — may call this step inline; still honor this contract when writing Specs.  
- **first-pass batch align hosts here**; `start-work` routes here before write.  
- **`create-tickets`** — slices; binders `covers` Spec `A*`.  
- **`create-review`** — research/decision support; may `spawn_spec`. **Same-pass Review+Spec** → open one shippable worktree first and write both there (do not land Review on base then Spec in a second tree).  
- **ADR** — consumer `docs/adr/` only; never `spc` substitute for long-lived system law. New ADR with Spec/Review in the same pass shares the shippable worktree.

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| "Scope is fuzzy — tickets first, Spec later" | First-pass align hosts **here**; tickets require locked Why/In/Out/Acceptance |
| "Local next-artifact-id is fine for team Spec ids" | Team SoT is primary GH issue number — create issue before `spc-N` file |
| "Write Spec on main, worktree later" | Shippable L0 (Spec) requires shippable cwd / worktree first |
| "Write Review on base first, then open worktree for Spec" | Same-pass co-create → one worktree first; write Review + Spec together |
| "Acceptance can be prose without A* ids" | C multi-ticket needs stable `A1…` for `covers` / light RTM |
| "Implement a spike while drafting Spec" | This skill does not implement product code |
| "Boss needs a Spec file in 2 minutes — skip batch" | Fuzzy → PREP+BATCH still; already-locked COMMITTED may write without re-align |
| "User said LGTM on a vague summary — lock Spec" | Hollow yes. Restate Why/In/Out/Acceptance/Decisions; require explicit principal confirm |
| "max(issue)+1 is fine under time pressure" | Never guess; create/choose GH issue first |

## Red Flags

- Spec file without Acceptance on C
- Guessing `max(issue)+1` instead of `gh issue create`
- Re-opening product grill as one-question-per-turn by default
- Treating Review as a substitute for Spec
- Silent `status: locked` without principal coverage
- Two PCA batches of only "agent-decided" with hollow user "sure" → not locked
- Claiming team Spec id via local next-artifact-id under multi-clone

## Verification

- [ ] `ensure-lattice` + `assert-shippable-cwd` ran before write
- [ ] Primary issue URL/# printed; `id: spc-N` matches **#N** (team path)
- [ ] Primary issue labeled **`epic`** (+ kind + priority)
- [ ] Spec path written under `.lattice/specs/`
- [ ] Why / In / Out / Acceptance present; C has `A*` ids
- [ ] Decisions capture user-confirmed principals
- [ ] L0 lists (`tickets`/`prs`/`reviews`) accurate (often empty at create)
- [ ] No product implementation performed; primary not dual-roled as sole delivery ticket
