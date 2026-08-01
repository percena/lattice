---
name: generate-wiki
description: "Generate a navigable root wiki/ of pure Markdown (structure-first catalogue + evidence-cited pages) and optional root llms.txt. Use when the user wants a wiki, repo docs overview, codebase map, or LLM-friendly project index. Not for Lattice Spec/Ticket/PR/Review workflow or writing .lattice/ artifacts."
allowed-tools: Bash Read Grep Glob
metadata:
  agents: "claude-code,codex"
  domain: doc-tool
---

# Generate Wiki

**Documentation/tool-domain skill**. Synthesizes a browsable `wiki/` of pure Markdown + optional root `llms.txt` from the live repository — **structure-first**, **evidence-cited**, **idempotent**.

- **Not** a Lattice lifecycle skill: produces no Spec/Ticket/PR/Review; does **not** depend on `_lattice-lib`; does **not** write `.lattice/`.
- **Portable:** runs in any consumer repo (engine monorepo dogfood is one eval, not the skill body).
- **No site factory:** no VitePress, no deploy workflow, no multi-audience onboarding, no forced `AGENTS.md` writes.

**Runtime path:** before executing the scan helper, set `LATTICE_SKILL_ROOT` to the absolute directory containing this loaded `SKILL.md` (Claude may already provide `CLAUDE_SKILL_DIR`). Never infer it from consumer cwd.

## Load on demand

| When | Read |
| --- | --- |
| Full step bash (repo context, scan, pages, validate) | `references/flow-detail.md` |
| Evidence / write-boundary policy | `references/policy.md` |
| Catalogue JSON schema | `references/catalogue-schema.md` |
| Page / wiki README shapes | `references/templates/` |
| Optional scan helper | `scripts/scan-repo.sh` |

Inspired by the method of [microsoft/skills deep-wiki](https://github.com/microsoft/skills/tree/main/.github/plugins/deep-wiki) (structure-first, evidence citations, crisp page budget, `llms.txt`) — **not** its site-factory product surface.

## When to use

| Trigger | Action |
| --- | --- |
| “generate wiki”, “document this repo”, “create docs overview”, “map codebase” | Full run (`full` mode) |
| “just the TOC / catalogue” | `catalogue-only` |
| “refresh one page …” | `page <title>` |
| “regenerate pages from existing catalogue” | `refresh` |
| Re-scan structure | `--rebuild-catalogue` |

## Modes and flags

| Mode / flag | Behavior |
| --- | --- |
| `full` (default) | Steps 0–5; 5–8 pages (small repos collapse to 3–4) |
| `catalogue-only` | Steps 0–2 only → `wiki/catalogue.json` |
| `page <title>` | Refresh a single leaf matching title/id |
| `refresh` | Re-write pages from existing catalogue (no re-scan) |
| `--rebuild-catalogue` | Re-scan and re-emit catalogue (then pages if not catalogue-only) |
| `--confirm-toc` | Show TOC before pages (default: auto-accept; **no hard AskUserQuestion** — Codex-safe) |
| `--refresh-stamp` | Update `generated_at` on rewrite (default: preserve) |
| `--branch current` | Cite current branch (default: **default branch**) |
| `--no-llms` | Skip root / wiki `llms.txt` |

## Core rules

1. **Structure-first:** write `wiki/catalogue.json` **before** any page.
2. **Never invent:** every non-trivial claim cites real sources (see policy).
3. **Write boundary:** only `wiki/**` and optional root `llms.txt`. Never touch root `AGENTS.md` / `CLAUDE.md` / `.github/workflows/` / `.lattice/` by default.
4. **Idempotent:** pages with `manual: true` frontmatter are **skipped**; preserve `generated_at` unless `--refresh-stamp`.
5. **Self-contained skill package:** policy + schema + templates ship under `references/` — monorepo `docs/` is optional dogfood context, not a runtime dependency.
6. **No Lattice coupling:** do not call `ensure-lattice` / `assert-shippable-cwd` or write Lattice L0 artifacts.

## Flow (short)

Execute in order. Skip page steps under `catalogue-only`. Under `refresh`, skip re-scan unless catalogue missing. Under `page <title>`, rewrite only the matching leaf.

1. Resolve repo context + citation mode → **`references/flow-detail.md` §0**
2. Single-pass scan (`scripts/scan-repo.sh` or find) → **§1**
3. Write `wiki/catalogue.json` first → **§2** (+ schema)
4. Write pages per leaf from templates → **§3**
5. Assemble `wiki/README.md` + optional `llms.txt` → **§4**
6. Validate + report → **§5**

Default page-set heuristics and install notes live in `references/flow-detail.md` / package README — not required on every activation.

## Relationship

| Skill / surface | Relation |
| --- | --- |
| Lattice six (`start-work` … `finish-work`) | Parallel domain — lifecycle vs documentation |
| `_lattice-lib` | **No dependency** |
| Consumer / monorepo `docs/adr/` | Link targets for architecture pages; never paste ADR bodies |

## Anti-patterns

Unique structural Don’ts (pressure excuses live in **Common Rationalizations** — do not duplicate):

| Don’t | Why |
| --- | --- |
| Force-write root `AGENTS.md` / `CLAUDE.md` | Write-boundary; user-owned |
| Hard-require `AskUserQuestion` | Breaks Codex; use `--confirm-toc` opt-in only |
| Pad small repos to 8 empty pages | Violates budget |

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| "Scaffold VitePress for a real wiki" | Out of scope — pure Markdown wiki/ only |
| "Call ensure-lattice / write .lattice" | Doc/tool domain — no lattice-lib, no Lattice artifacts |
| "Invent APIs that must exist" | Evidence discipline — cite only what the scan finds |
| "Paste full ADR bodies into pages" | Link-not-paste; docs/ remains SoT |
| "Skip catalogue.json — pages first" | Structure-first: catalogue before pages |

## Red Flags

- Writing root AGENTS.md/CLAUDE.md unsolicited
- Depending on AskUserQuestion as hard requirement (breaks Codex)
- Empty padded pages to hit a count budget
- Claiming Lattice lifecycle side effects

## Verification

- [ ] Mode/scope respected (full / catalogue-only / page / refresh)
- [ ] `catalogue.json` (when applicable) before page writes
- [ ] Pages evidence-cited; no invented paths/APIs
- [ ] No `.lattice/` writes; no lattice-lib dependency
- [ ] Optional `llms.txt` only when requested/configured
