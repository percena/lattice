# Contributing to percena/lattice

Thanks for helping improve **Lattice** — the workflow engine monorepo (portable Agent Skills + optional Claude Code plugin).

## Ground rules

| Rule | Detail |
| --- | --- |
| Skills are the logic SoT | Edit `skills/<name>/` — do not fork skill bodies under `plugins/` |
| Plugins package only | `plugins/lattice/skills/*` symlink to repo-root `skills/`; own `plugin.json` + hooks only |
| One Claude plugin | `lattice@percena` packs **every** shipped skill (lifecycle six, side-paths, optional skills, `_lattice-lib`) via `plugins/lattice/skills/` symlinks — enforced by the registration-integrity check in `tools/validate-skills.sh` |
| Shared scripts | Lattice runtime helpers live in `skills/_lattice-lib/`. Maintainer tools live in `tools/` |
| Doc/tool skills | `generate-*` (e.g. `generate-wiki`) stay optional, standalone, and do **not** depend on `_lattice-lib` (they are still symlinked into the plugin bundle like every shipped skill); `create-adr` is also optional/non-loop but **does** co-install `_lattice-lib` (writes durable `docs/adr/` L0 doc, uses `ensure-lattice` / `assert-shippable-cwd`) |
| Dogfood Lattice | Prefer `/start-work` → … → `/create-pr` → `/finish-work` when changing this repo |

## What to read first

1. [README.md](./README.md) — system map + install
2. [docs/getting-started.md](./docs/getting-started.md) — consumer vs engine
3. [tools/README.md](./tools/README.md) — validation + eval harnesses overview
4. [evals/README.md](./evals/README.md) — routing + behavioral eval corpus

## Local development

```bash
# Skills from this checkout — no --skill flags = every shipped skill
# (lifecycle six + side-paths + _lattice-lib; list stays in tools/validate-skills.sh USER_FACING)
npx skills add . -a claude-code -a codex -y

# Claude plugin from this checkout (note: --plugin-dir does not follow out-of-tree symlinks)
claude --plugin-dir ./plugins/lattice

# Validate
claude plugin validate .
claude plugin validate plugins/lattice
bash tools/validate-skills.sh
python3 tools/validate-plugin-versions.py --base-ref origin/main --release-check

# Tests
bats plugins/lattice/scripts/tests/
# skill script suites:
# bats skills/*/scripts/tests/   (as discovered in CI)
```

## Adding a new skill

"Register a new skill" spans many surfaces; missing any one of them ships a silent gap — every drifted surface in audit rev-20260827-033352Z F6 was exactly a surface this checklist used to omit. Work through the checklist, one surface per line — `bash tools/validate-skills.sh` enforces 1, 2, and 4–7; `tools/tests/routing-catalog-parity.bats` enforces 12:

1. [ ] `skills/<name>/` — `SKILL.md` with frontmatter (`name:`, `description:`, `metadata.agents: "claude-code,codex"`) and anatomy headings (`## Common Rationalizations`, `## Red Flags`, `## Verification`)
2. [ ] `tools/validate-skills.sh` — add the skill to `USER_FACING` (or, for internal install-units only, the documented `EXEMPT` list)
3. [ ] `tools/tests/validate-skills.bats` — add the skill to the `build_green_tree` user-facing fixture list (the suite fails otherwise)
4. [ ] Plugin bundle — `plugins/lattice/skills/<name>` symlink (3-level relative: `../../../skills/<name>`)
5. [ ] `plugins/lattice/.claude-plugin/plugin.json` — description + `keywords` entry
6. [ ] `.claude-plugin/marketplace.json` — plugin description + `keywords` entry (must agree with plugin.json)
7. [ ] `plugins/lattice/README.md` — component table row, Skills bullet, install example
8. [ ] `README.md` — skill table row
9. [ ] `README.zh-CN.md` — mirrored skill table row
10. [ ] `docs/getting-started.md` — skill table
11. [ ] `llms.txt` — skills list one-liner
12. [ ] Routing — `tools/run-routing-evals.py` `CATALOG` entry + `evals/routing/<name>.json` case (catalog parity with `USER_FACING` is bats-enforced)
13. [ ] `skills/_lattice-lib/SKILL.md` — script-table row for any new `_lattice-lib` runtime script the skill ships
14. [ ] Version bump at dev→main merge — `plugins/lattice/CHANGELOG.md` + plugin version (release-boundary enforcement via `--release-check`; dev merges are lenient)

## Testing

The bats suites use `BATS_TEST_TMPDIR`, which requires **bats >= 1.4** (CI installs a compatible version). On an older local bats, work around it with:

```bash
BATS_TEST_TMPDIR=$(mktemp -d) bats <suite-dir>
```

New tests should prefer self-managed temp dirs (`mktemp -d` in `setup`, cleaned up in `teardown`) rather than adding new `BATS_TEST_TMPDIR` dependencies.

## Pull requests

- Prefer a Lattice ticket binder + Spec line when work is multi-session.
- PR body: Why / Scope / How / Verification / Lineage (`Fixes` / `Refs`, Spec, kind).
- Changelog for the Claude plugin: `plugins/lattice/CHANGELOG.md` (SemVer).

## Security reports

See [SECURITY.md](./SECURITY.md). Do not open public issues for undisclosed vulnerabilities.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](./LICENSE).
