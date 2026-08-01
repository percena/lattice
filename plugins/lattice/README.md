# lattice (Claude Code plugin)

Percena **Lattice** packaging for Claude Code: full delivery loop in **one** plugin.

| Component | Location | Shared? |
| --- | --- | --- |
| `start-work` | [`skills/start-work`](../../skills/start-work/) (symlinked) | Yes — `npx skills` |
| `create-spec` | [`skills/create-spec`](../../skills/create-spec/) (symlinked) | Yes |
| `create-review` | [`skills/create-review`](../../skills/create-review/) (symlinked) | Yes |
| `create-tickets` | [`skills/create-tickets`](../../skills/create-tickets/) (symlinked) | Yes |
| `create-pr` | [`skills/create-pr`](../../skills/create-pr/) (symlinked) | Yes |
| `finish-work` | [`skills/finish-work`](../../skills/finish-work/) (symlinked) | Yes |
| `create-adr` | [`skills/create-adr`](../../skills/create-adr/) (symlinked) | Yes — out-of-band ADR companion (not a loop step, not a lineage node) |
| `_lattice-lib` | [`skills/_lattice-lib`](../../skills/_lattice-lib/) (symlinked; **not** a user slash skill) | Yes — shared scripts |

Part of the [`percena`](../../README.md) marketplace.

## Install

```text
/plugin marketplace add percena/lattice
/plugin install lattice@percena
```

### Skills only (Claude + Codex)

```bash
npx skills add percena/lattice \
  --skill _lattice-lib \
  --skill start-work --skill create-spec --skill create-review \
  --skill create-tickets --skill create-pr --skill finish-work \
  -a claude-code -a codex -g -y
```

> **Co-install:** always include **`_lattice-lib`**.

## Skills

- **[start-work](../../skills/start-work/)** — Classify S/M/C, ticket + workspace, setup-only or resume-by-id.
- **[create-spec](../../skills/create-spec/)** — First-pass PCA align + persist `spc-n`.
- **[create-review](../../skills/create-review/)** — Persist `rev-YYYYMMDD-HHMMSSZ` with explicit `outcome`.
- **[create-tickets](../../skills/create-tickets/)** — Split locked scope into GitHub issues + binders.
- **[create-pr](../../skills/create-pr/)** — Open/update PR; media upload via `_lattice-lib` when paths present.
- **[finish-work](../../skills/finish-work/)** — Merge/close PR, delete branch, remove worktree.
- **[create-adr](../../skills/create-adr/)** — Out-of-band ADR companion: writes `docs/adr/NNN`; co-installs `_lattice-lib`; not a lineage node, not a loop step.
- **[lattice-lib](../../skills/_lattice-lib/)** — Shared scripts only (not a user slash skill).

## Typical path

```text
/start-work → (/create-spec | /create-review) → /create-tickets → implement → /create-pr → /finish-work
```

## Hooks (0.1.x, Claude-only)

Optional guidance — **skills remain correct without hooks** (Codex / `npx skills`).

| Hook | Role |
| --- | --- |
| `track-skill-activation` | Record Skill-tool loads |
| `track-skill-slash-command` | Record `/create-pr` / `/finish-work` (and `/lattice:…`) slash loads |
| `intercept-gh-pr-create` | Advise on bare `gh pr create`; `LATTICE_HOOK_MODE=strict` opts into blocking |
| `intercept-gh-pr-merge` | Advise on bare `gh pr merge`; strict mode same |
| `clear-skill-markers-on-compact` | Drop markers after context compact |

Does **not** auto-edit issue/PR/binder bodies. Fail-open on ambiguity.

### Hook configuration: `LATTICE_HOOK_MODE`

Default is **advisory** — bare `gh pr create` / `gh pr merge` get a stderr nudge
(`exit 0`); the skill is recommended, not mandatory.

To **enforce** the marker gate (block the tool call until `create-pr` /
`finish-work` is active in the session), set:

```bash
# per shell
export LATTICE_HOOK_MODE=strict
```

or in `~/.claude/settings.json` env (applies to every session):

```json
{ "env": { "LATTICE_HOOK_MODE": "strict" } }
```

Any value other than `advisory`/`strict` falls back to advisory. Strict mode is
recommended for the dogfood repo and teams that want a best-effort guard around
direct `gh pr create` / `gh pr merge` calls. It recognizes documented `gh`/`pr`
repository-flag placements, but it is not a shell security sandbox and remains
fail-open when parsing itself is unavailable or indeterminate. In strict mode,
an unquoted `gh pr create` / `merge` mutation behind an unknown command prefix
is conservatively treated as executable unless the prefix is a known text/search
command. The skills themselves remain correct without hooks
(Codex / `npx skills`).

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
