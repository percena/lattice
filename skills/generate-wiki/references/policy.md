# generate-wiki policy

Portable rules for the skill. Ship with the skill package — do not require monorepo `docs/` at runtime.

## 1. Evidence discipline

1. **Trace real sources.** Read the file (or a trustworthy index that points to it). Do not guess from directory names alone.
2. **Every non-trivial architectural claim needs a citation.**
3. **Distinguish fact from inference.** If you did not open the file, mark the claim as inference or drop it.
4. **Never invent** APIs, CLI flags, env vars, file paths, or install lines that are not present in the repo or skill package.

### Citation formats

| Kind | Format | Example |
| --- | --- | --- |
| Remote code | `[path:line](REPO_URL/blob/BRANCH/path#Lline)` | `[skills/create-spec/SKILL.md:12](https://github.com/org/repo/blob/main/skills/create-spec/SKILL.md#L12)` |
| Local code | `(path:line)` | `(src/auth.ts:42)` |
| Line ranges | `#Lstart-Lend` | `…#L42-L58` |
| Docs / prose markdown | Relative from **generated wiki page** (no line anchor) | In wiki: `[docs/getting-started.md](../docs/getting-started.md)`. From this policy file: `[docs/getting-started.md](../../../docs/getting-started.md)` |

- **Default branch** for blob links (stable). Override with `--branch current` only when the user asks.
- Tables that list code artifacts include a **Source** column with citations.
- Mermaid diagrams may be followed by an HTML comment listing sources: `<!-- sources: path:line, … -->`.

## 2. Structure-first

1. Write `wiki/catalogue.json` **before** any page body.
2. Page files match catalogue leaves **1:1** (path + id).
3. Depth ≤3; ≤8 children per section.
4. Page budget: **5–8** pages in `full` mode. Small repos (≤10 source files, excluding prose Markdown) collapse to **3–4** (Getting Started only) — do not pad. The scan helper reports Markdown separately so documentation-heavy repositories are not misclassified as code-heavy.
5. Diátaxis labels on catalogue entries: `explanation` · `tutorial` · `how-to` · `reference`.

## 3. Write boundary

| Allowed | Forbidden (default) |
| --- | --- |
| `wiki/**` | Root `AGENTS.md`, `CLAUDE.md` |
| Root `llms.txt` (skill-generated only) | `.github/workflows/**` |
| | `.lattice/**` |
| | Overwriting a **non-skill** root `llms.txt` |

If a non-skill root `llms.txt` exists, write `wiki/llms.txt` only and report the skip.

Optional future flag `--agents` may create missing `AGENTS.md` — **off by default** and not part of v1 acceptance.

## 4. Idempotency

1. Frontmatter on generated pages:

   ```yaml
   generated_by: generate-wiki
   generated_at: YYYY-MM-DD
   manual: false   # set true by humans to protect the page
   ```

2. On re-run:
   - `manual: true` → **skip** (do not overwrite).
   - Preserve existing `generated_at` unless `--refresh-stamp`.
   - `refresh` mode respects existing catalogue; `--rebuild-catalogue` re-scans.

3. Detect pre-existing `wiki/` that has **no** `generated_by: generate-wiki` pages: warn once, then proceed only under the same skip rules (do not wipe hand-written trees wholesale).

## 5. Relationship to monorepo `docs/`

- `docs/` (ADR, design, adopting guides) is the **authoritative** long-form SoT when present.
- `wiki/` is a **synthesized navigation layer**. Prefer **link-not-paste** for ADR/design bodies.
- Do not duplicate entire ADR text into wiki pages; cite `docs/adr/NNN-….md` with a one-line summary.

## 6. Portability (Codex + Claude)

1. No hard dependency on Claude-only tools (`AskUserQuestion`, etc.).
2. TOC confirmation only when `--confirm-toc` is set; default is auto-accept.
3. Wording in reports must work on multiple agents.

## 7. No Lattice coupling

1. Do **not** call `ensure-lattice.sh` or `assert-shippable-cwd.sh`.
2. Do **not** create Specs, tickets, binders, or other Lattice L0 artifacts.
3. This skill may run on team base branches for documentation output — write boundary is `wiki/` + optional `llms.txt`, not product L0.

## 8. Validation checklist (step 5)

- [ ] Every catalogue leaf has a page file (and vice versa for generated pages)
- [ ] Intra-wiki relative links resolve
- [ ] Citations use the resolved format (remote vs local)
- [ ] `manual: true` pages unchanged
- [ ] No writes outside the write boundary
- [ ] Run report lists created / updated / skipped + a suggested commit message

## 9. Content style

1. Progressive disclosure: TL;DR table → details.
2. Tables over prose for structured lists (components, APIs, commands, configs).
3. 0–2 Mermaid diagrams per page (architecture / sequence / flowchart as needed). GitHub-native theme — no forced dark-mode hex palette.
4. Cross-link related wiki pages; end with a **Related** table when useful.
