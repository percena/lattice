# Lattice plugin hooks

Claude-only enforcement layer registered in `hooks.json`. Every hook is
**fail-open on ambiguity** (missing `jq`/`git`/`python3`, unparseable input,
unknown tool) and prints its reason to stderr; a block is `exit 2`. The skills
stay correct without hooks (Codex / `npx skills`). `LATTICE_HOOK_MODE=advisory`
turns the `gh`/branch blocks into nudges — see `../README.md` § Hooks.

| Hook | Event | Rule | Escape |
| --- | --- | --- | --- |
| `track-skill-activation.sh` | PreToolUse `Skill` | Records which Lattice skill is active for the session (marker file) | n/a |
| `track-skill-slash-command.sh` | UserPromptSubmit | Same marker for `/create-pr`, `/finish-work`, `/lattice:…` slash loads | n/a |
| `clear-skill-markers-on-compact.sh` | PreCompact | Drops the markers when context compacts | n/a |
| `intercept-git-branch-create.sh` | PreToolUse `Bash` | **L1** — blocks `git checkout -b` / `git switch -c` in the main clone under `profile: strict` (ADR-006) | `/start-work`, or `ensure-workspace.sh --mode branch --allow-unbound --reason "user-authorized: …"` |
| `intercept-gh-issue-create.sh` | PreToolUse `Bash` | Blocks bare `gh issue create` unless `create-tickets` (or `create-spec`) is active | `/create-tickets` |
| `intercept-gh-pr-create.sh` | PreToolUse `Bash` | Blocks bare `gh pr create` unless `create-pr` is active | `/create-pr` |
| `intercept-gh-pr-merge.sh` | PreToolUse `Bash` | Blocks bare `gh pr merge` unless `finish-work` is active | `/finish-work` |
| `intercept-shippable-write.sh` | PreToolUse `Write\|Edit\|NotebookEdit` | **L3 location gate** — a write to `.lattice/specs\|tickets\|lineage/**` or tracked product code is denied when the cwd is not a shippable workspace (calls `assert-shippable-cwd.sh` directly; does not trust the L1 sentinel). `.lattice/reviews/**` and `docs/adr/**` are exempt. | `/start-work` (bound worktree), or `assert-shippable-cwd.sh --allow-base-write --reason "user-authorized: …"` after asking the user |
| `intercept-shippable-write.sh` | PreToolUse `Write\|Edit` | **L3-status-row** (spc-337 A4, ADR-012 §2) — once the location gate allows, an Edit/Write on `.lattice/tickets/<dir>/README.md` whose result **changes the `\| status \|` row value** (Edit: `old_string` vs `new_string`, or `new_string` vs the on-disk row; Write: new content vs the on-disk row; a removed row counts as a change) is denied. Other rows/sections, new-binder creation, unchanged-status writes, and non-`README.md` paths pass. | There is no write-side escape: status is written only by the path-point scripts. Run the transition instead — `python3 <lib>/transition-api.py commit <tkt> <to> <owner> <reason> --binder <path>` (side states add `--wait-reason`). The deny message prints the resolved command for the target binder. |

`lib/` holds shared helpers (`intercept-gh-pr-common.sh`, `batch-merge-gate.sh`).
Tests live in `../scripts/tests/*.bats` (one file per hook; run plain `bats`).
