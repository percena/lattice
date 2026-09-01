# lattice (Claude Code plugin)

Percena **Lattice** packaging for Claude Code: full delivery loop in **one** plugin.

| Component | Location | Shared? |
| --- | --- | --- |
| `start-work` | [`skills/start-work`](../../skills/start-work/) (symlinked) | Yes — `npx skills` |
| `create-spec` | [`skills/create-spec`](../../skills/create-spec/) (symlinked) | Yes |
| `create-review` | [`skills/create-review`](../../skills/create-review/) (symlinked) | Yes |
| `create-tickets` | [`skills/create-tickets`](../../skills/create-tickets/) (symlinked) | Yes |
| `batch-work` | [`skills/batch-work`](../../skills/batch-work/) (symlinked) | Yes — parallel fan-out orchestrator |
| `create-pr` | [`skills/create-pr`](../../skills/create-pr/) (symlinked) | Yes |
| `finish-work` | [`skills/finish-work`](../../skills/finish-work/) (symlinked) | Yes |
| `create-adr` | [`skills/create-adr`](../../skills/create-adr/) (symlinked) | Yes — out-of-band ADR companion (not a loop step, not a lineage node) |
| `run-e2e` | [`skills/run-e2e`](../../skills/run-e2e/) (symlinked) | Yes — e2e reference pattern (not a runner) |
| `verify-features` | [`skills/verify-features`](../../skills/verify-features/) (symlinked) | Yes — full-feature runtime verification against the feature map |
| `review-code` | [`skills/review-code`](../../skills/review-code/) (symlinked) | Yes — PR-scoped quality side-path |
| `review-production` | [`skills/review-production`](../../skills/review-production/) (symlinked) | Yes — PR-scoped quality side-path |
| `review-delivery` | [`skills/review-delivery`](../../skills/review-delivery/) (symlinked) | Yes — chain-review side-path |
| `generate-wiki` | [`skills/generate-wiki`](../../skills/generate-wiki/) (symlinked) | Yes — standalone doc tool |
| `_lattice-lib` | [`skills/_lattice-lib`](../../skills/_lattice-lib/) (symlinked; **not** a user slash skill) | Yes — shared scripts |

Part of the [`percena`](../../README.md) marketplace.

## Install

```text
/plugin marketplace add percena/lattice
/plugin install lattice@percena
```

### Skills only (Claude + Codex)

```bash
# every shipped skill (all 15 units: 14 user-facing + _lattice-lib)
npx skills add percena/lattice -a claude-code -a codex -g -y

# or explicit (all 15 units):
npx skills add percena/lattice \
  --skill _lattice-lib \
  --skill start-work --skill create-spec --skill create-review \
  --skill create-tickets --skill batch-work --skill create-pr \
  --skill finish-work --skill create-adr --skill run-e2e --skill verify-features \
  --skill review-code --skill review-production --skill review-delivery \
  --skill generate-wiki \
  -a claude-code -a codex -g -y
```

> **Co-install:** always include **`_lattice-lib`** (required by the lifecycle six plus `batch-work`, `create-adr`, `review-delivery`, and `verify-features`).

## Skills

- **[start-work](../../skills/start-work/)** — Classify S/M/C, ticket + workspace, setup-only or resume-by-id.
- **[create-spec](../../skills/create-spec/)** — First-pass PCA align + persist `spc-n`.
- **[create-review](../../skills/create-review/)** — Persist `rev-YYYYMMDD-HHMMSSZ` with explicit `outcome`.
- **[create-tickets](../../skills/create-tickets/)** — Split locked scope into GitHub issues + binders.
- **[batch-work](../../skills/batch-work/)** — DAG-orchestrated unattended fan-out: parallel `start-work` agents on sibling worktrees with layer-barrier sync.
- **[create-pr](../../skills/create-pr/)** — Open/update PR; media upload via `_lattice-lib` when paths present.
- **[finish-work](../../skills/finish-work/)** — Merge/close PR, delete branch, remove worktree.
- **[create-adr](../../skills/create-adr/)** — Out-of-band ADR companion: writes `docs/adr/NNN`; co-installs `_lattice-lib`; not a lineage node, not a loop step.
- **[run-e2e](../../skills/run-e2e/)** — Reference pattern for ego-browser heredoc JS e2e stories; not a runner, not a loop entry.
- **[verify-features](../../skills/verify-features/)** — Full-feature runtime verification: lineage-mined feature map with cited oracles, bounded e2e waves on run-e2e stories, bugs filed as tickets; co-installs `_lattice-lib`.
- **[review-code](../../skills/review-code/)** — Optional PR-scoped code review: material correctness/regression findings with recommended solutions.
- **[review-production](../../skills/review-production/)** — Optional PR-scoped production-readiness review (security, performance, test coverage, ship/rollback).
- **[review-delivery](../../skills/review-delivery/)** — Artifact-only chain review of a delivered ticket set → ranked morning digest; never merges.
- **[generate-wiki](../../skills/generate-wiki/)** — Navigable root `wiki/` of pure Markdown + optional `llms.txt`; standalone doc tool.
- **[`_lattice-lib`](../../skills/_lattice-lib/)** — Shared scripts only (not a user slash skill).

## Typical path

```text
/start-work → (/create-spec | /create-review) → /create-tickets → implement → /create-pr → /finish-work
```

## Hooks (Claude-only)

Optional guidance — **skills remain correct without hooks** (Codex / `npx skills`).

| Hook | Role |
| --- | --- |
| `track-skill-activation` | Record Skill-tool loads |
| `track-skill-slash-command` | Record `/create-pr` / `/finish-work` (and `/lattice:…`) slash loads |
| `intercept-gh-pr-create` | Block bare `gh pr create` unless `create-pr` skill is active |
| `intercept-gh-pr-merge` | Block bare `gh pr merge` unless `finish-work` skill is active |
| `intercept-gh-issue-create` | Block bare `gh issue create` unless `create-tickets` (or `create-spec`) skill is active |
| `clear-skill-markers-on-compact` | Drop markers after context compact |

Does **not** auto-edit issue/PR/binder bodies. Fail-open on ambiguity.

### Hook configuration: `LATTICE_HOOK_MODE`

Default is **strict** — bare `gh pr create` / `gh pr merge` / `gh issue create`
are **blocked** (`exit 2`) unless the respective skill marker is active in the
session.

To **disable** the block and get a nudge-only advisory (`exit 0`), set:

```bash
# per shell
export LATTICE_HOOK_MODE=advisory
```

or in `~/.claude/settings.json` env (applies to every session):

```json
{ "env": { "LATTICE_HOOK_MODE": "advisory" } }
```

Any value other than `advisory`/`strict` falls back to strict. Advisory mode is
available for sessions that want nudge-only enforcement. The hooks recognize
documented `gh`/`pr`/`issue` repository-flag placements, but are not a shell
security sandbox and remain fail-open when parsing itself is unavailable or
indeterminate (including `python3` missing — see spc-212). In strict mode,
an unquoted `gh pr create` / `merge` / `issue create` mutation behind an
unknown command prefix is conservatively treated as executable unless the
prefix is a known text/search command. The skills themselves remain correct
without hooks (Codex / `npx skills`).

### Marker TTL: `LATTICE_SKILL_MARKER_TTL_HOURS`

The `track-skill-activation` and `track-skill-slash-command` hooks record
authorization markers per session and garbage-collect stale session dirs.
Marker TTL defaults to **72 hours**; override it (e.g. on a long-running
shared host) with:

```bash
export LATTICE_SKILL_MARKER_TTL_HOURS=168   # 7 days
```

Non-numeric, zero, or empty values fall back to 72h. Absurd values are
clamped to a 100000h (~11.4 years) ceiling to avoid `find -mmin` overflow.
Lowering the TTL shortens the window in which a bare `gh pr create` / `gh pr
merge` stays authorized after a skill was last active in that session.

## License

MIT
