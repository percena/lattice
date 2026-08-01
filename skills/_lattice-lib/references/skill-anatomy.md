# Lattice skill anatomy (portable)

Shared footer contract for **user-facing** Lattice skills (the six lifecycle skills + optional doc/tool skills such as `generate-wiki`).  
`_lattice-lib` is internal and **exempt**.

Inspired by external practice-pack skill anatomy; **not** a second product surface.

## Required sections (user-facing skills)

After the process body, each user-facing `SKILL.md` must include:

| Section | Purpose |
| --- | --- |
| `## Common Rationalizations` | Table of excuses agents use to skip HARD steps + rebuttals |
| `## Red Flags` | Behavioral signs the skill is being violated mid-run |
| `## Verification` | Evidence checklist before claiming the skill’s job is done |

Recommended (lifecycle): body **When to use / When NOT** table; Core rules labeled **INVARIANT / DEFAULT / HINT** (`constraint-language.md`). Standing ship bar: `definition-of-done.md` Iron Law.

Section titles must match **exactly** (Tier-1 lint).

## Writing rules

1. **Short** — prefer tables and bullets; no essay. Prefer **progressive disclosure**: `SKILL.md` overview + invariants; long step scripts in `references/` (one level deep). Industry bar: keep main `SKILL.md` lean (agentskills ≈ under 500 lines).
   - Prefer a **Load on demand** table (when → which file) over unconditional ref lists at the top of `SKILL.md`.
   - Resolve the active `SKILL.md` directory to an absolute `SKILL_ROOT` supplied by the host (`LATTICE_SKILL_ROOT`, or Claude's `CLAUDE_SKILL_DIR`), then invoke the sibling `_lattice-lib` resolver. Missing roots fail closed; never search consumer cwd or use repository-relative executable fallbacks.
2. **Constraint language** — label severity with **INVARIANT** / **DEFAULT** / **HINT** (see `constraint-language.md`). Do not write DEFAULT path order as NEVER.
3. **Skill-specific** — excuses must target *this* skill’s true gates (worktree, locked Spec, POST_SPLIT, bare merge, …).
4. **Rebuttals cite policy** — script names when helpful.
5. **Verification is evidence** — commands run, files written, ids issued — not “looks good.”
6. Anti-patterns tables already in the body may stay; anatomy footers still required (lint looks for the three headings).

## Template (copy into SKILL.md)

```markdown
## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| "…" | … |

## Red Flags

- …

## Verification

Before claiming done:

- [ ] …
```

## Lint

`tools/validate-skills.sh` fails CI when a user-facing skill lacks these sections or (lifecycle six) lacks `evals/evals.json`.
