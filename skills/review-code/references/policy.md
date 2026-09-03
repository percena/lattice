# review-code policy (portable)

Detail contract — [finding-contract.md](./finding-contract.md).

## Unit of analysis

**One PR change set**, dirty working-tree change set that will become a PR, or clean `base...HEAD` on a feature branch. Minimal related context only.

### Sanctioned exception — release-boundary merge review

A **dev→main release merge** is a sanctioned, larger-than-one-PR unit (ADR-005): it bundles many PRs that the integration branch accumulated since the last release, and `ci-local.sh --release-check` is its canonical version-increment gate. Such a merge is **not** refused as a "portfolio of unrelated PRs" when the operator explicitly opts in via **`--release-merge`** / **`--merge-review`**, or by resolving the change set as `base=<release>` (`origin/main...dev`, or `<last-release>...dev`).

| Accepted as the unit | Still refused |
| --- | --- |
| `origin/main...dev` (or `<last-release>...dev`) **with explicit opt-in** | Default-branch "review everything" with **no** change set / no opt-in |
| A partitioned walk of that diff (subsystem slices) | Unbounded whole-repo architecture review |

**Partition, don't linear-scan.** A release diff is large; partition it into **subsystem slices** (validator / scripts / CI / hooks / routing / skills / docs) and review each slice's logic, rather than one shallow linear pass that skips material findings.

**Tier risk by file class** (do not treat all files uniformly):

| Class | Risk | Treatment |
| --- | --- | --- |
| `.lattice/**` process artifacts (binders/specs/fixtures) + `docs/`/ADRs | low-risk bulk | skim for coherence/privacy only; do not deep-review each binder |
| `tools/`, `skills/**/scripts/`, `plugins/lattice/hooks/`, `.github/workflows/` | high-risk logic | full material review per slice |

**First-class axis:** run `bash tools/ci-local.sh --release-check` as a release-boundary axis (the ADR-005 version-increment gate); its result feeds the overall verdict alongside CI/CD, syntax/lint, docs-sync, and interface-impact.

**Finding bar:** coarser than a single-PR review — classify each finding as **release-blocking** (must fix before dev→main merge) vs **ship-as-is** (document residual and merge). The single-PR `ship-as-is | fix-first | unclear` overall still applies, with `release-blocking` findings forcing `fix-first`.

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
