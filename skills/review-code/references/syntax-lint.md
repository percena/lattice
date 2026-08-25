# review-code syntax/lint check (portable)

Run language-appropriate syntax and lint checks on **changed files only** and surface errors as findings.

## Scope

Only files in the change set — from the context script `Changed Files` list, or `git diff --name-only <base>...HEAD`. **Never** whole-repo lint. If `Has changes: no`, skip entirely.

## Tool selection by extension

For each changed file, detect language by extension and run the first available tool:

| Extension | Tool (first available) | Fallback |
| --- | --- | --- |
| `.py` | `ruff check <file>` → `python3 -m py_compile <file>` | skip |
| `.sh` / `.bash` | `shellcheck <file>` | skip |
| `.js` / `.mjs` / `.cjs` | `node --check <file>` | skip |
| `.ts` | `tsc --noEmit` (only if `tsconfig.json` present) | skip |
| `.json` | `jq empty <file>` → `python3 -m json.tool <file>` | skip |
| `.yaml` / `.yml` | `python3 -c "import yaml,sys; list(yaml.safe_load_all(open(sys.argv[1])))" <file>` | skip |

> **YAML availability check:** `command -v` does not apply to Python one-liners. Test PyYAML first with `python3 -c "import yaml"` — if it raises `ModuleNotFoundError`, report `skipped for yaml, PyYAML not installed` (not a finding).
| `.md` | `markdownlint <file>` (if installed) | skip |
| other | skip | skip |

**Tool detection:** check availability with `command -v <tool>` before running. Do not error if a tool is missing.

## Severity

| Signal | Severity | Note |
| --- | --- | --- |
| Syntax error (won't compile/parse) | **med** | Broken file; must fix before relying on the change |
| Lint warning (unused var, undefined name) | **low** | Material but limited blast radius |
| Style/format (line length, quotes) | **Nits** appendix only | Never in material table unless it causes a real bug |
| Lint error that causes a real bug (undefined symbol, shadowing) | **med** or **high** | Upgrade from style to correctness |

Lint/style findings are **never** `high` unless they cause a concrete bug. Do not inflate severity to look useful.

## Output

```
file:line · tool · message · suggestion
```

If all changed files are clean: one line in the Syntax/Lint subsection: `all changed files clean`.

## Tool unavailable

If no tool is installed for a given extension: one line `syntax/lint: skipped for <ext>, <tool> not installed`. This is **not** a finding — just a transparency note.

## Hard stop

Syntax/lint findings are part of the **single batch confirmation** in Step 6 — presented alongside all other findings and confirmed in **one** `AskUserQuestion`. Fix only when the operator picks a fix option (e.g. `Apply all recommended solutions`). Do not auto-format or auto-fix lint errors during review.
