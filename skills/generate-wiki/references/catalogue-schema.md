# catalogue.json schema

`wiki/catalogue.json` is the **structure SoT**. Write it in step 2 **before** any page. Pages must match leaves 1:1.

## Contents

- [Top-level object](#top-level-object)
- [Page entry (leaf)](#page-entry-leaf)
- [Constraints](#constraints)
- [Example (workflow-engine monorepo style)](#example-workflow-engine-monorepo-style)
- [Modes vs catalogue](#modes-vs-catalogue)

## Top-level object

```json
{
  "repo": "owner/name-or-local",
  "branch": "main",
  "generated_by": "generate-wiki",
  "generated_at": "2026-07-20",
  "citation_mode": "remote",
  "repo_url": "https://github.com/owner/name",
  "pages": []
}
```

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `repo` | string | yes | `owner/name` from remote, or local folder name |
| `branch` | string | yes | Default branch used in blob links (or current if `--branch current`) |
| `generated_by` | string | yes | Always `"generate-wiki"` |
| `generated_at` | string | yes | ISO date `YYYY-MM-DD` |
| `citation_mode` | `"remote"` \| `"local"` | yes | Selects citation format (see policy) |
| `repo_url` | string \| null | yes | HTTPS remote URL without `.git`, or `null` if local |
| `pages` | array | yes | Ordered leaf list (flat preferred; nested via optional `children` for TOC only) |

## Page entry (leaf)

```json
{
  "id": "overview",
  "path": "01-overview.md",
  "title": "Overview",
  "diataxis": "explanation",
  "description": "One-line page summary for llms.txt and wiki README map",
  "prompt": "Write guidance for the page writer: key questions, files to open, non-goals.",
  "sources": ["README.md", "docs/getting-started.md"]
}
```

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `id` | string | yes | Stable kebab id (`overview`, `architecture`, …) |
| `path` | string | yes | Path **relative to `wiki/`** (e.g. `01-overview.md`) |
| `title` | string | yes | Human title |
| `diataxis` | enum | yes | `explanation` \| `tutorial` \| `how-to` \| `reference` |
| `description` | string | yes | One sentence — used in `llms.txt` and doc map |
| `prompt` | string | yes | Writing brief for step 3 (must reference real files) |
| `sources` | string[] | yes | Seed source paths the writer must open |
| `children` | page[] | no | Optional nesting for TOC display only; **leaves still flatten to files** |

## Constraints

1. **Max depth 3** if using `children`; prefer a **flat** `pages` array for v1.
2. **≤8** entries at any sibling level.
3. **Budget:** 5–8 leaf pages for normal repos; 3–4 for small (≤10 source files, excluding prose Markdown). The scan helper reports Markdown separately. Do not pad.
4. `path` must be unique; filename numbering `01-…` is recommended for stable sort.
5. `prompt` and `sources` must be derived from the scan — never generic placeholders like `"Document the system"`.
6. `wiki/README.md` is the entry hub; it may be listed as a synthetic page with `id: "index"` / `path: "README.md"` or assembled outside the leaf loop — either is valid if validation still sees a coherent map.

## Example (workflow-engine monorepo style)

```json
{
  "repo": "percena/lattice",
  "branch": "main",
  "generated_by": "generate-wiki",
  "generated_at": "2026-07-20",
  "citation_mode": "remote",
  "repo_url": "https://github.com/percena/lattice",
  "pages": [
    {
      "id": "overview",
      "path": "01-overview.md",
      "title": "Overview",
      "diataxis": "explanation",
      "description": "What this repo is, who it is for, and system boundaries",
      "prompt": "Summarize product purpose from README; distinguish engine monorepo vs consumer .lattice; cite README and docs/getting-started.md",
      "sources": ["README.md", "docs/getting-started.md"]
    },
    {
      "id": "architecture",
      "path": "02-architecture.md",
      "title": "Architecture",
      "diataxis": "explanation",
      "description": "Portable skills vs Claude plugins, dual-channel packaging",
      "prompt": "Explain skills/ vs plugins/ layers from the root and plugin READMEs; cite the internal library contract",
      "sources": ["README.md", "plugins/lattice/README.md", "skills/_lattice-lib/SKILL.md"]
    }
  ]
}
```

## Modes vs catalogue

| Mode | Catalogue behavior |
| --- | --- |
| `full` | Write or refresh catalogue, then pages |
| `catalogue-only` | Write catalogue only |
| `refresh` | Load existing catalogue; do not re-scan unless missing |
| `--rebuild-catalogue` | Force re-scan and rewrite catalogue |
| `page <title>` | Keep catalogue; rewrite matching leaf only |
