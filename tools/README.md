# Monorepo maintainer tools

These scripts are **not** part of the portable `_lattice-lib` install unit.
Consumers who install Lattice skills do not need them.

| Tool | Role |
| --- | --- |
| `ci-local.sh` | One-command local CI parity: every workflow verdict, summary table, nonzero exit on failure |
| `validate-skills.sh` | Tier-1 skill anatomy / eval presence lint |
| `validate-lattice-artifacts.py` | L0 contract checks over Spec/ticket/Review artifacts |
| `validate-plugin-versions.py` | Plugin/marketplace SemVer + bundle change gate (release-boundary enforced via `--release-check`; dev landings lenient per ADR-005) |
| `run-routing-evals.py` | Tier-2 routing catalog ranking |
| `run-behavioral-evals.py` | Behavioral eval runner / corpus validate |
| `hooks/pretooluse-bats-check.py` | Optional Claude Code PreToolUse hook: refuses a `Write`/`Edit` that would introduce a banned bats assertion form (same rules as `check-bats-assertions.py`); exit 2 = block |

Runtime shared scripts live in `skills/_lattice-lib/scripts/`.

## `ci-local.sh`

Run `bash tools/ci-local.sh` before pushing — and always before opening a PR:
the batch-work evidence contract requires its fresh output. It reproduces every
CI verdict locally, one step per check: `validate-skills.sh`,
`validate-lattice-artifacts.py`, `validate-plugin-versions.py` (default base
ref is the fork point vs `origin/dev`; override with `--base-ref REF`;
auto-skips with a note when nothing under lint-heavy's path filter changed,
mirroring CI), routing evals, behavioral corpus validate + fake-provider smoke,
`claude plugin validate` (skipped with a note when the CLI is absent),
shellcheck over the same file set and severity as CI, the broken-symlink check,
and every bats suite CI discovers (each run with the `BATS_TEST_TMPDIR` shim
for older local bats). Steps never abort the run: each records pass/FAIL/skip,
a summary table prints at the end, and the exit code is nonzero if any step
failed. `--fast` skips the bats suites (the slow step).

## `hooks/pretooluse-bats-check.py` (optional, maintainer-only)

Not part of the `lattice` plugin (`plugins/lattice/hooks/hooks.json`) — it is a
repo-maintainer convenience that runs `check-bats-assertions.py` at write time
so a banned assertion form is refused before CI sees it. Register it yourself in
`.claude/settings.json` (gitignored here) or `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Write|Edit",
        "hooks": [ { "type": "command",
                     "command": "python3 /absolute/path/to/lattice/tools/hooks/pretooluse-bats-check.py" } ] }
    ]
  }
}
```

Exit contract: `2` blocks the write and feeds the findings to the model; `0`
allows. Non-`.bats` paths and unparseable payloads always allow (fail-open).
Tests: `tools/tests/pretooluse-bats-check.bats`.
