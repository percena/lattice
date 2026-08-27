# review-code documentation sync check (portable)

Detect when code changes alter behavior, interface, or config but related documentation was not updated to match.

## When to check

During Step 3 (Auxiliary checks), after syntax/lint. Only when the diff alters **behavior, interface, or config** — not for pure cosmetic/refactor changes. If the diff is whitespace/rename/internal refactor → `docs in sync` by default.

## Doc locations to check

Check **existing** docs only (do not invent missing optional docs):

| Location | When to check |
| --- | --- |
| `README.md` (root) | New commands, changed install/run steps, new features, changed CLI flags |
| `docs/` directory | Any behavior/interface change that has existing docs in `docs/` |
| `wiki/` directory (if exists) | Any feature/behavior change |
| `CLAUDE.md` (project-level) | Changed build commands, test commands, architecture, key conventions |
| `SKILL.md` (if skill files in diff) | Changed skill behavior, axes, process, allowed-tools |
| `docs/adr/` | Architectural decision change |
| API docs (OpenAPI spec, GraphQL schema) | API contract change (new/removed endpoints, changed request/response) |

## Stale detection

Compare the diff's **intent** against the doc's current content:

1. Identify what changed in code: new function signature, changed CLI flag, new config key, changed default, new/removed command, changed file layout.
2. Open the related doc section.
3. If the doc **does not mention** or **contradicts** the new behavior → **stale**.
4. If the doc already reflects the new behavior → **in sync**.
5. **Claim reconciliation:** a doc/comment sentence in the change set that **promises tool or code behavior** ("the validator rejects X", "the flag defaults to Y") is checked against the implementation — read the code at the promise, or execute it when cheap — not just for staleness of names/paths. Doc–code disagreement is a finding regardless of which side is right.

Do not flag docs as stale just because code near them changed — the doc must actually describe the thing that changed.

## Severity

| Signal | Severity |
| --- | --- |
| Stale README/user-facing doc for a behavior change | **med** |
| Stale internal doc (CLAUDE.md, ADR) for an architecture change | **med** |
| Stale internal doc for a minor behavior change | **low** |
| Missing optional doc (no wiki directory, no API spec) | **low** (suggest creating) |
| Doc exists and is accurate | not a finding |

## Output

```
doc-path · what code changed · what doc should say · recommendation
```

If all checked docs are accurate: one line in the Docs sync subsection: `docs in sync`.

## Not a finding

- Docs that don't exist and aren't required (e.g., no `wiki/` directory) → skip silently.
- Comments/inline docs in the code itself → not in scope (that's a code-quality axis, not docs-sync).

## Hard stop

Docs-sync findings are part of the **single batch confirmation** in Step 6 — presented alongside all other findings and confirmed in **one** `AskUserQuestion`. Fix only when the operator picks a fix option (e.g. `Apply all recommended solutions`). Do not auto-edit docs during review.
