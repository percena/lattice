# Contributing to percena/lattice

Thanks for helping improve **Lattice** — the workflow engine monorepo (portable Agent Skills + optional Claude Code plugin).

## Ground rules

| Rule | Detail |
| --- | --- |
| Skills are the logic SoT | Edit `skills/<name>/` — do not fork skill bodies under `plugins/` |
| Plugins package only | `plugins/lattice/skills/*` symlink to repo-root `skills/`; own `plugin.json` + hooks only |
| One Claude plugin | `lattice@percena` packs all six lifecycle skills + `_lattice-lib` |
| Shared scripts | Lattice runtime helpers live in `skills/_lattice-lib/`. Maintainer tools live in `tools/` |
| Doc/tool skills | `generate-*` (e.g. `generate-wiki`) stay optional, standalone, and do **not** depend on `_lattice-lib` or auto-pack into `lattice@percena`; `create-adr` is also optional/non-loop but **does** co-install `_lattice-lib` (writes durable `docs/adr/` L0 doc, uses `ensure-lattice` / `assert-shippable-cwd`) |
| Dogfood Lattice | Prefer `/start-work` → … → `/create-pr` → `/finish-work` when changing this repo |

## What to read first

1. [README.md](./README.md) — system map + install
2. [docs/getting-started.md](./docs/getting-started.md) — consumer vs engine
3. [tools/README.md](./tools/README.md) — validation + eval harnesses overview
4. [evals/README.md](./evals/README.md) — routing + behavioral eval corpus

## Local development

```bash
# Skills from this checkout
npx skills add . \
  --skill _lattice-lib \
  --skill start-work --skill create-spec --skill create-review \
  --skill create-tickets --skill create-pr --skill finish-work \
  -a claude-code -a codex -y

# Claude plugin from this checkout (note: --plugin-dir does not follow out-of-tree symlinks)
claude --plugin-dir ./plugins/lattice

# Validate
claude plugin validate .
claude plugin validate plugins/lattice
bash tools/validate-skills.sh
python3 tools/validate-plugin-versions.py --base-ref origin/main

# Tests
bats plugins/lattice/scripts/tests/
# skill script suites:
# bats skills/*/scripts/tests/   (as discovered in CI)
```

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
