# generate-wiki flow detail

Load when executing a full/refresh/page run after modes are chosen.

## Contents

- [0. Resolve repo context](#0-resolve-repo-context)
- [1. Single-pass scan](#1-single-pass-scan)
- [2. Write catalogue first](#2-write-catalogue-first)
- [3. Write pages per leaf](#3-write-pages-per-leaf)
- [4. Assemble entrypoints](#4-assemble-entrypoints)
- [5. Validate + report](#5-validate-report)
- [generate-wiki report](#generate-wiki-report)
  - [Created / Updated / Skipped](#created-updated-skipped)
  - [Validation](#validation)
  - [Suggested commit](#suggested-commit)
- [Default page set (heuristic — not HARD)](#default-page-set-heuristic-not-hard)

## 0. Resolve repo context

```bash
ORIGIN=$(git remote get-url origin 2>/dev/null || true)
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || true)
if [[ -z "${DEFAULT_BRANCH}" ]]; then
  DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p' || true)
fi
if [[ -z "${DEFAULT_BRANCH}" ]]; then
  DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)
fi
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
CURRENT=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)
BRANCH="$DEFAULT_BRANCH"
# if --branch current → BRANCH=$CURRENT
```

| Case | `citation_mode` | Code cite | Docs cite |
| --- | --- | --- | --- |
| Has `origin` → GitHub/GitLab HTTPS or SSH | `remote` | `[path:line](REPO_URL/blob/BRANCH/path#Lline)` | relative markdown link |
| No remote / local-only | `local` | `(path:line)` | relative markdown link |

Store `REPO_URL` as `https://github.com/owner/repo` form (strip `.git`, convert SSH).

## 1. Single-pass scan

Prefer: resolve the active `SKILL.md` directory to absolute `SKILL_ROOT`, then run `bash "$SKILL_ROOT/scripts/scan-repo.sh"`.
Else one `find` + ≤15 key reads.

| Signal | How |
| --- | --- |
| Tree | Top-level dirs; maxdepth 3 key files |
| Manifests | `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `*.csproj`, … |
| Docs | `README.md`, `docs/`, `CONTRIBUTING.md`, `CHANGELOG*` |
| Skills layout | `skills/*/SKILL.md`, `plugins/*` (if present) |
| Existing wiki | `wiki/catalogue.json`, pages with `generated_by: generate-wiki` |
| Root `llms.txt` | Exists? skill-generated stamp? |

**Project-type heuristics (default page set bias):**

| Detect | Page set bias |
| --- | --- |
| `skills/*/SKILL.md` + workflow docs | overview · architecture · getting-started · skills-reference · artifacts-layout · workflows · contributing |
| `package.json` / library | overview · architecture · getting-started · api/modules · config · contributing |
| Service + Dockerfile/CI | overview · architecture · getting-started · data · deploy/config · contributing |
| ≤10 source files | overview · getting-started · architecture only (3–4 pages) |

## 2. Write catalogue first

1. If `wiki/catalogue.json` exists and mode is `refresh` / `page` and **not** `--rebuild-catalogue` → load it.
2. Else build a flat `pages[]` per `references/catalogue-schema.md`.
3. Each leaf: real `sources[]` from the scan; `prompt` names files to open; Diátaxis label.
4. **Write `wiki/catalogue.json` before any page body.**
5. If `--confirm-toc`: print titles + paths; wait for free-form “go” / edits (plain text — **do not require** `AskUserQuestion`). Default: auto-accept.

## 3. Write pages per leaf

For each leaf (or the single `page <title>` match):

1. **Skip** if `wiki/<path>` exists and frontmatter has `manual: true`.
2. Read every path in `sources`. **Do not invent.**
3. If rewriting and not `--refresh-stamp`, preserve prior `generated_at`.
4. Fill `references/templates/page.md` (frontmatter + TL;DR Source column + Why/How/Details/Related/References).
5. Citations: remote/local from step 0; docs as relative links; cross-link wiki pages; **link-not-paste** for ADR/design bodies.

## 4. Assemble entrypoints

1. **`wiki/README.md`** from `references/templates/wiki-readme.md`.
2. **`llms.txt`** (unless `--no-llms`): write root only if missing or skill-generated; else write `wiki/llms.txt` only.
3. Optional `wiki/llms-full.txt` not required for v1.

## 5. Validate + report

```text
## generate-wiki report
### Created / Updated / Skipped
### Validation
- catalogue↔pages: OK | FAIL
- intra-wiki links: OK | FAIL
- write boundary: OK | FAIL
### Suggested commit
docs: generate wiki for <repo> (generate-wiki)
```

Hard rules: every catalogue leaf path exists; every generated page in catalogue (or README hub); relative `./….md` resolve; no writes outside boundary.

## Default page set (heuristic — not HARD)

| File | Role (Diátaxis) |
| --- | --- |
| `wiki/README.md` | Entry / map |
| `01-overview.md` | explanation |
| `02-architecture.md` | explanation |
| `03-getting-started.md` | tutorial / how-to |
| `04-skills-reference.md` | reference (or APIs/modules) |
| `05-artifacts-layout.md` | reference |
| `06-workflows.md` | how-to / explanation |
| `07-contributing.md` | how-to |
| `changelog.md` | optional — prefer link to existing CHANGELOG |

Counts 3–4 small / 5–8 typical are defaults — never pad empty pages.
