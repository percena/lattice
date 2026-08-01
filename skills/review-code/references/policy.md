# review-code policy (portable)

Detail contract — [finding-contract.md](./finding-contract.md).

## Unit of analysis

**One PR change set**, dirty working-tree change set that will become a PR, or clean `base...HEAD` on a feature branch. Minimal related context only.

## Context script (optional)

Prefer stable collection via skill-local script (does not judge correctness):

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
python3 "$SKILL_ROOT/scripts/review-context.py"           # dirty WT (default)
python3 "$SKILL_ROOT/scripts/review-context.py" --pr N
python3 "$SKILL_ROOT/scripts/review-context.py" --branch HEAD --base origin/main
python3 "$SKILL_ROOT/scripts/review-context.py" --since "3 days ago"   # optional date-range
```

If `Has changes: no`, stop with no findings — do not invent. Date-range is **optional**; default unit remains PR / WT / branch-diff (this policy).

## Compatibility

Never required by `create-pr` / `finish-work`. Does not replace `create-review`. Findings are advice only (not a merge HARD gate).

## Review-only

Default: do not edit the tree. After findings, **hard stop** — no auto-fix. Tests/fixes only when the user **explicitly** requests them; shippable writes need bound worktree.

## Vocabulary

- This skill overall: `ship-as-is` | `fix-first` | `unclear`
- `review-production`: `go` | `go-with-risks` | `no-go`
- Do not mix the two
