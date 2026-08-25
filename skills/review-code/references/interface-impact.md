# review-code interface/contract impact check (portable)

Detect whether changes in the diff break **callers, consumers, or contracts** in adjacent code — not just the changed files themselves.

## Principle

A change can be internally correct but still break every consumer of a changed signature, export, endpoint, or config key. This check traces **one hop** from the change to its direct consumers. It is not a full call-graph audit — it is targeted breakage detection.

## When to check

During Step 3 (Auxiliary checks), alongside the other candidate-finding checks. Run automatically — do not skip even if the diff looks clean internally. The only skip condition: the diff touches zero signatures/exports/endpoints/config (pure internal logic or whitespace).

## What counts as an interface change

| Change type | What to trace |
| --- | --- |
| Function/method signature (params, return type, arity) | All call sites of that function/method |
| Removed or renamed export (module-level `export`, `__all__`, `module.exports`, `pub fn`) | All import sites of that name |
| API endpoint (path, method, params, response shape) | All clients that call that endpoint (frontend, tests, docs, other services) |
| Config key (added/removed/renamed/changed default) | All readers of that config key |
| CLI flag (added/removed/renamed/changed type) | All invocations in scripts, docs, CI workflows |
| Type/interface/struct shape (field added/removed/renamed) | All consumers that destructure or access that type |
| DB schema (column added/removed/renamed, index, constraint) | All queries that reference that table/column |

## How to find consumers

```bash
# Function/method callers
git grep -n "function_name\|\.method_name(" -- '*.py' '*.js' '*.ts' '*.go'

# Import consumers
git grep -n "from module import name\|import { name }\|require('module')" -- '*.py' '*.js' '*.ts'

# API endpoint consumers
git grep -n "endpoint_path\|/api/v" -- '*.py' '*.js' '*.ts' '*.go'

# Config key readers
git grep -n "config_key\|CONFIG_KEY\|getenv.*KEY" -- '*.py' '*.js' '*.ts'
```

Cap results — if a function has 50+ callers, sample the first few and note "N callers found, sampled top 5". Do not read all 50.

## Severity

| Signal | Severity |
| --- | --- |
| Breaking change with no caller update (will crash at runtime) | **high** |
| Breaking change with some callers updated, others missed | **high** |
| Non-breaking additive change (new optional param, new field) but consumers might rely on exact shape | **med** |
| Breaking change in internal/private helper (no external callers) | **low** or not a finding |
| Config key removed with no migration path | **high** |

## Output

```
changed-symbol · change type · consumer path:line · breakage description · recommended solution
```

## Solution requirements

Every interface-breakage finding must provide:
1. **Recommended solution** — best-practice fix (e.g., "add backward-compat overload + deprecation notice" / "update all 3 callers + add migration" / "revert the param rename, use a new param name instead").
2. **Alternatives** — e.g., for a removed export: "re-export as deprecated alias" vs "update all importers" vs "revert removal".

## Scope boundary

- **One hop only** — direct callers/consumers of changed symbols. Do not trace callers-of-callers.
- **Not a full dependency audit** — that belongs to `review-production` or architecture review.
- If a changed symbol has zero consumers found via grep → note "no callers found, low risk" and move on.
