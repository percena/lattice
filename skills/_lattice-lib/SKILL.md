---
name: _lattice-lib
description: "Internal shared Lattice library install-unit (workspace, init, upload, ids + portable policy). Not a workflow entrypoint — do not invoke as a user skill. Leading underscore marks internal package. Install beside the fourteen user-facing Lattice skills."
user-invocable: false
disable-model-invocation: true
metadata:
  agents: "claude-code,codex"
  lattice: library
---

# `_lattice-lib` (library install-unit)

**Not a navigation skill.** User surface is the fourteen user-facing skills — the lifecycle six:

`start-work` · `create-spec` · `create-review` · `create-tickets` · `create-pr` · `finish-work`

plus the optional companions and side-paths: `batch-work`, `create-adr`, `run-e2e`, `verify-features`, `review-code`, `review-production`, `review-delivery`, `generate-wiki`. Of those, `batch-work`, `create-adr`, `review-delivery`, and `verify-features` also co-install this library (per README); the others do not depend on it.

This package is an **install unit** for shared scripts + portable policy so partial installs and relative `../start-work` paths are unnecessary. Leading **`_`** = internal shared package.

## Scripts (runtime — ships with install)

| Script | Role |
| --- | --- |
| `_lattice-home.sh` | `lattice_default_home`, `lattice_profile`, … |
| `next-artifact-id.sh` | spc local claim (not team SoT); rev R1 UTC token |
| `ensure-workspace.sh` | Bound branch/worktree |
| `ensure-lattice.sh` | **Agent entrypoint** — idempotent consumer ready-check + init-if-needed |
| `assert-shippable-cwd.sh` | Default guard against team-base writes; explicit clean, user-authorized base-direct escape is recorded |
| `check-base-residue.sh` | Detect uncommitted `.lattice` dirt on MAIN (finish-work / pull rescue) |
| `lattice-init.sh` | Low-level skeleton writer (called by ensure; not user-facing) |
| `upload-github-asset.sh` | Durable GH media URLs |
| `github-project-add.sh` | Optional Project item-add after issue/PR create (soft-fail; env / `.env`) |
| `github-issue-parent-add.sh` | Soft-fail link child issue as GH sub-issue of Spec primary |
| `resolve-lattice-lib.sh` | Print this scripts dir (resolve order) |
| `stamp-pr-open.sh` | Stamp binder + GitHub issue right after `gh pr create` (prs row, `pr-open` status, acceptance mirror) |
| `finish-ledger.sh` | Stamp a binder's `## Finish` ledger with firm GitHub dates + prs + status after merge |
| `build-review-context.sh` | Build the artifact-only context manifest for a review-delivery chain review |
| `list-board-items.sh` | List GitHub Project board items as `tkt-N` candidates (automation trigger plane) |
| `find-spec.sh` | Resolve a Lattice Spec file path by number, regardless of slug |
| `check-duplicate-work.sh` | Check open issues / worktrees / open PRs for duplicate work before ticket-create or start |
| `resolve-integration-branch.sh` | Resolve the integration branch a feature worktree should PR into |
| `ratify.sh` | Single-commit ratification of a parked binder decision (journal entry + `parked → queued` in one commit) |
| `bump-fix-cycle.sh` | Scripted owner of `fix_cycles` + the `pr-open → rework` transition (cap ≤2; third rework forces `deep-review`; `--extend-budget` escape) — spc-186 A6/A8 |

**Consumer bootstrap:** skills call `ensure-lattice.sh` at entry. Users never run init scripts.  
**L0 pollution guard (DEFAULT):** before shippable Spec / ticket binder / product code / new ADR writes, agents run `assert-shippable-cwd.sh` (or only write after `ensure-workspace` + `cd` into worktree). A clean base checkout may pass only through `--allow-base-write --reason` after explicit user authorization. **`create-review` Review-only is exempt**; same-pass co-create defaults to one shippable worktree.

**Maintainer tools** (validate-skills, plugin-version gate, eval runners) live in monorepo **`tools/`** — not in this install unit.

## Resolve order (callers)

Prefer:

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve this SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/scripts/resolve-lattice-lib.sh"
LIB=$(bash "$RESOLVE")
```

Order inside `resolve-lattice-lib.sh`:

1. Absolute `LATTICE_LIB_SCRIPTS` operator override
2. The resolver script's own canonical installed directory

`--from` remains accepted for older callers but is not searched. Consumer cwd and Git roots are never executable resolution sources.

Legacy install dir `lattice-lib` is **not** accepted (migration window closed).

## Install

Install **with** the user-facing skills (whole package or explicit `--skill _lattice-lib`). Required by the lifecycle six plus `batch-work`, `create-adr`, `review-delivery`, and `verify-features`.

```bash
npx skills add percena/lattice -a claude-code -a codex -g -y
# or explicit (lifecycle six + this library; add the optional skills you use):
npx skills add percena/lattice \
  --skill _lattice-lib \
  --skill start-work --skill create-spec --skill create-review \
  --skill create-tickets --skill create-pr --skill finish-work
```
