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
| `intercept-shippable-write.sh` | PreToolUse `Write\|Edit` | **L3-status-row** (spc-337 A4, ADR-012 §2) — once the location gate allows, an Edit/Write on `.lattice/tickets/<dir>/README.md` whose result **changes the `\| status \|` row value** (Edit: `old_string` vs `new_string` when both carry a full row, otherwise the edit is simulated on the on-disk text — first occurrence, or all with `replace_all` — and the result's first status cell is compared with the file's; Write: new content vs the on-disk row; a removed row or an inserted duplicate status row counts as a change) is denied. Other rows/sections, new-binder creation, unchanged-status writes, and non-`README.md` paths pass. | There is no write-side escape: status is written only by the path-point scripts. Run the transition instead — `python3 <lib>/transition-api.py commit <tkt> <to> <owner> <reason> --binder <path>` (side states add `--wait-reason`). The deny message prints the resolved command for the target binder. |

| `auto-stamp-pr-open.sh` | PostToolUse `Bash` | **pr-open path point** (spc-337 A3, ADR-012 §1) — after a Bash call whose command contains `gh pr create` and whose response carries a PR URL (`https://github.com/<o>/<r>/pull/<N>`), resolves the tree the command ran in (payload `cwd`, or a leading `cd <path> &&` prefix), determines the PR head branch (`--head <branch>` in the command, else `gh pr view N --json headRefName`), and runs `_lattice-lib/scripts/stamp-pr-open.sh --pr N` from that toplevel **only when its current branch equals the PR head** and `<toplevel>/.lattice/tickets` exists. A mismatch (main clone on `dev`, sibling worktree, unknown head) or a no-binder skip is reported as "did NOT stamp" — never as a stamp. Idempotent against create-pr's scripted step (`skills/create-pr/scripts/after-pr-open.sh`, the portable writer). **Always exits 0**: missing `jq`/`git`, malformed JSON, no PR URL, no Lattice home, or a stamp error are advisory only (stderr + `additionalContext`). | n/a (never blocks); re-run `after-pr-open.sh --pr N --expected-oid <HEAD>` when the advisory reports a failure |

`lib/` holds shared helpers (`intercept-gh-pr-common.sh`, `batch-merge-gate.sh`).
Tests live in `../scripts/tests/*.bats` (one file per hook; run plain `bats`).
