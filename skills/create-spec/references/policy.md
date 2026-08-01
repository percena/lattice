# create-spec policy (portable)

Shipped with `create-spec`. No monorepo docs required at runtime.

## Role

**First-pass product/方案 alignment host** + durable Spec writer.

| Input | Action |
| --- | --- |
| Fuzzy Why / Acceptance / Decisions | **PREP + BATCH_CONFIRM (PCA)** here, then write Spec |
| Already locked COMMITTED / brief | Write Spec; no re-grill |
| User never invokes create-spec (S/light-M) | Session COMMITTED without Spec file remains valid |

Do **not** defer all grill exclusively to `start-work`. Greenfield `start-work` may **delegate** this dialect.

## What a Spec is

Locked (or draft) **delivery contract**: why, in/out, acceptance, principal decisions.  
Not a ticket list, not a PR, not an ADR dump.

## Spec primary issue

| Rule | Detail |
| --- | --- |
| Role | **Intent tracker / GH parent only** — not the delivery ticket on Spec-then-ticket path |
| Labels | Always include **`epic`** + kind + priority (e.g. `epic,feat,P2`) so operators filter Specs via `label:epic` |
| Children | Delivery tickets are separate issues, linked as GH **sub-issues** of primary (create-tickets; incl. N=1) |
| Dual-role | **Forbidden** when user creates Spec then tickets — always ≥2 issues |
| Second epic | Do **not** invent another umbrella under primary |
| Adopt existing epic `#N` | Reuse as `spc-N` — **append-only** body; soft-add `epic` if missing; write Spec file; still file separate delivery tickets |

## Align method (PCA)

- Silent PREP; never ask diggable facts.  
- Batch **2–5 principal** questions with recommendation + trade-off.  
- Secondary self-decide; list for override.  
- Coupling test: if deciding X alone still probably succeeds core intent → secondary.  
- No one-question-per-turn / salami confirms.  
- Rounds: S 0–1 · M 1–2 · C 2–3 (cap 5).

## Optional codebase reality pass (C + large blast-radius only)

**Not** a default step for S/M. **Not** SPD Phase-1 theater (no per-module SUPER scores, no mandatory three analyzers).

| | |
| --- | --- |
| **When (HINT → treat as DEFAULT if signals fire on C)** | User intent is rewrite / migrate / overhaul / rebuild / multi-module architecture change **and** mode is **C** (or M escalating to C). When unsure on pure M feature work → **skip**. |
| **What** | Short **codebase reality** summary *before* PCA principals: structure/entrypoints, module boundaries that matter, risk hotspots, test/governance baseline, conflicts with stated direction. |
| **How** | Exploration or bounded drafting may fan out; one accountable owner validates the final Spec and principal decisions. |
| **Where output lives** | Spec `## Why` / Notes / Agent-assumed, and/or a Lattice `rev-` — **never** default consumer `docs/analysis|plan|progress/`. |
| **Then** | Design PCA principals **grounded** in that reality (not generic scope questions). |

S/M cheap paths gain **zero** mandatory steps from this section.

## Required shape

1. Real **YAML front matter** at file top (not only a fenced block).  
2. Preview: TL;DR · kind · status · mode · Path.  
3. **Bare ids** in edge lists.  
4. **C mode:** Acceptance lines `**A1**`, `**A2**`, …  
5. After write: keep L0 edge lists accurate; bloodline = L0 + GitHub.

## Status

| status | Meaning |
| --- | --- |
| `draft` | Not ready for multi-ticket execution |
| `locked` | Principals agreed; tickets may be filed |
| `done` | Delivery complete; no new tickets expected |
| `superseded` | Replaced by another `spc-n` |

Do not multi-ticket off silent draft without principal confirmation.

## Scripts

Prefer:

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh")
"$LIB/next-artifact-id.sh"
"$LIB/_lattice-home.sh"
```

If lattice-lib scripts are missing, fail with a clear message (do not invent ids by hand).

## ADR boundary

- Feature-local → Spec Decisions.  
- Cross-feature → `docs/adr/NNN` (cite path/`ADR-NNN`).  
- Never allocate `adr-n` via `next-artifact-id` or lineage nodes.

## Template

`references/templates/spec.md`
