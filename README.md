# Lattice

English | [简体中文](./README.zh-CN.md)

> Ticket-Driven Development for coding agents.

Lattice is an open-source toolkit of Agent Skills and optional Claude Code hooks that gives coding agents a disciplined path from product intent to a merged pull request. It runs locally with your existing Git and GitHub credentials, and is packaged for [Claude Code](https://claude.ai/code) and [Codex](https://openai.com/codex).

## Quick start

Install once per machine, then open any repo and start a ticket.

```bash
# 1) Portable skills (all supported agents: Claude Code, Codex, Cursor, …)
npx skills add percena/lattice -g -y
```

```text
# 2) Claude Code plugin (same skills + optional hooks)
/plugin marketplace add percena/lattice
/plugin install lattice@percena
```

```text
# 3) In your repo
/start-work
```

Advanced install (org roll-out, private forks, local dev, refresh) → [docs/getting-started.md](./docs/getting-started.md).

## The loop

`/start-work` is the universal entry — it classifies scope and routes into this loop (for a new feature it delegates to `/create-spec`; to resume an existing ticket, `/start-work tkt-N`).

```text
  /create-spec  |  /create-review
       ↓
  /create-tickets
       ↓
  /start-work
       ↓
  implement
       ↓
  /create-pr
       ↓
  /finish-work
```

```bash
# 1) Plan — lock scope, split into tickets
/create-spec           # e.g. "Add a payment feature"
/create-tickets

# 2) Execute the ticket
/start-work tkt-N

# 3) Ship
/create-pr
/finish-work pr N
```

## Skills

| Skill | Purpose | Slash |
| --- | --- | --- |
| [`start-work`](./skills/start-work/) | Classify S/M/C, bind ticket + worktree, resume by id | `/start-work` |
| [`create-spec`](./skills/create-spec/) | Persist a Lattice Spec (`spc-n`) with acceptance criteria | `/create-spec` |
| [`create-review`](./skills/create-review/) | Persist a Lattice Review (`rev-YYYYMMDD-HHMMSSZ`) with an explicit outcome | `/create-review` |
| [`create-tickets`](./skills/create-tickets/) | Split locked scope into GitHub issues + binders | `/create-tickets` |
| [`create-pr`](./skills/create-pr/) | Open/update a well-formed GitHub PR | `/create-pr` |
| [`finish-work`](./skills/finish-work/) | Update base, alignment-check, merge, cleanup | `/finish-work` |
| [`_lattice-lib`](./skills/_lattice-lib/) | Shared scripts backing the above (co-install, not a slash entry) | — |

Not part of the delivery loop — three tiers, none create lineage nodes:

| Tier | Skill(s) | Notes |
| --- | --- | --- |
| PR-scoped quality side-paths | [`review-code`](./skills/review-code/) · [`review-production`](./skills/review-production/) | Optional, before/after `/create-pr`; no `_lattice-lib` |
| standalone doc tool | [`generate-wiki`](./skills/generate-wiki/) | `wiki/` + `llms.txt`; anytime; no `_lattice-lib` |
| out-of-band companion (`create-*` family) | [`create-adr`](./skills/create-adr/) | writes `docs/adr/NNN`; co-installs `_lattice-lib`; **not a lineage node** — invoked *alongside* `/create-spec`/`/create-review` (same worktree, promotes cross-feature decisions); never a loop entry or a Spec substitute |

## Documentation

| Doc | Topic |
| --- | --- |
| [getting-started](./docs/getting-started.md) | Install, auto-ensure, profiles, daily path, advanced install |
| [github-surface](./docs/github-surface.md) | Kind + priority labels, optional Project auto-add |
| [CONTRIBUTING](./CONTRIBUTING.md) | Changing skills/plugins in this monorepo |
| [SECURITY](./SECURITY.md) | Vulnerability reporting |
| [CODE OF CONDUCT](./CODE_OF_CONDUCT.md) | Community standards |
| [CHANGELOG](./CHANGELOG.md) | Plugin SemVer |

## Requirements

`git`, `gh`, `jq`, `python3` (≥ 3.8), `curl` — plus an agent that runs [Agent Skills](https://agentskills.io/) or Claude Code plugins. Hook tests need `bats`.

## License

MIT — see [LICENSE](./LICENSE).
