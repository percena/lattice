# Lattice

English | [简体中文](./README.zh-CN.md)

> Ticket-Driven Development for coding agents.

Lattice is an open-source toolkit of Agent Skills and optional Claude Code hooks that gives coding agents a disciplined path from product intent to a merged pull request. It runs locally with your existing Git and GitHub credentials, and is packaged for [Claude Code](https://claude.ai/code) and [Codex](https://openai.com/codex). It is **discipline-first, not heavy** — it constrains the *path* (every shippable branch binds to a `tkt-N`/`spc-N`, every PR carries its Why/How/Spec line) but leaves the model free to think and code inside each step; the guardrails are a floor, not a ceiling.

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
       ↓                         ↘ /batch-work (parallel groups → fan-out)
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

## Philosophy

**Constrain the path, not the model.** Lattice scripts the backbone — Spec → ticket → worktree → PR → merge — so the chain never skips a step and never loses its lineage. It does not script *how* the model reasons, what order to think, or what to output inside each step. Strong models stay creative; the framework keeps the chain resumable. Guardrails (worktree isolation, alignment checks, lineage) are a floor, not a ceiling.

**Local-first retrieval, transparent memory.** Spec, ticket, and review are written as templated local files under `.lattice/` (ADRs under `docs/adr/`) — grep-able, reviewable, and committed with your repo. Most context lookups (acceptance criteria, last review outcome, which tickets a spec split into) resolve with a local `cat`/`grep` in milliseconds; GitHub is queried only for facts that can only come from the remote (issue/PR live state, comments, CI). Memory is not a framework black box — it is an explicit engineering artifact you and your team own.

**Lineage.** Each delivery leaves a traceable chain — a Spec (`spc-N`) splits into tickets (`tkt-N`), each ticket lands in a PR (`pr-N`), every review is a `rev-…`. These IDs are the binder file names, so the whole chain is recoverable with one `grep -r spc-N .lattice/`, across sessions, without a network hop.

## Skills

| Skill | Purpose | Slash |
| --- | --- | --- |
| [`start-work`](./skills/start-work/) | Classify S/M/C, bind ticket + worktree, resume by id | `/start-work` |
| [`create-spec`](./skills/create-spec/) | Persist a Lattice Spec (`spc-n`) with acceptance criteria | `/create-spec` |
| [`create-review`](./skills/create-review/) | Persist a Lattice Review (`rev-YYYYMMDD-HHMMSSZ`) with an explicit outcome | `/create-review` |
| [`create-tickets`](./skills/create-tickets/) | Split locked scope into GitHub issues + binders | `/create-tickets` |
| [`batch-work`](./skills/batch-work/) | DAG-orchestrated fan-out: spawn multiple `start-work` agents on sibling worktrees with layer-barrier sync | `/batch-work` |
| [`create-pr`](./skills/create-pr/) | Open/update a well-formed GitHub PR | `/create-pr` |
| [`finish-work`](./skills/finish-work/) | Update base, alignment-check, merge, cleanup | `/finish-work` |
| [`_lattice-lib`](./skills/_lattice-lib/) | Shared scripts backing the above (co-install, not a slash entry) | — |

Not part of the delivery loop — three tiers, none create lineage nodes:

| Tier | Skill(s) | Notes |
| --- | --- | --- |
| PR-scoped quality side-paths | [`review-code`](./skills/review-code/) · [`review-production`](./skills/review-production/) | Optional, before/after `/create-pr`; no `_lattice-lib` |
| Chain-review side-path | [`review-delivery`](./skills/review-delivery/) | Artifact-only review of a delivered ticket set (Spec A* fidelity, cross-PR coherence, decision queue, per-PR findings) → ranked morning digest with per-axis attestation; co-installs `_lattice-lib`; never merges, never a merge gate |
| E2e reference pattern | [`run-e2e`](./skills/run-e2e/) | Heredoc JS story pattern for ego-browser; one Bash invocation per story, fail-loud auth, structured JSON; not a runner, not a loop entry |
| standalone doc tool | [`generate-wiki`](./skills/generate-wiki/) | `wiki/` + `llms.txt`; anytime; no `_lattice-lib` |
| out-of-band companion (`create-*` family) | [`create-adr`](./skills/create-adr/) | writes `docs/adr/NNN`; co-installs `_lattice-lib`; **not a lineage node** — invoked *alongside* `/create-spec`/`/create-review` (same worktree, promotes cross-feature decisions); never a loop entry or a Spec substitute |

## Documentation

| Doc | Topic |
| --- | --- |
| [getting-started](./docs/getting-started.md) | Install, auto-ensure, profiles, daily path, advanced install |
| [github-surface](./docs/github-surface.md) | Kind + priority labels, optional Project auto-add |
| [workflow-fsm](./docs/workflow-fsm.md) | Three coupled state machines, transition owners, bounded-loop invariant |
| [day-phase](./docs/day-phase.md) | Attended planning recipe: requirement → proposal rev → spec → adr → tickets |
| [CONTRIBUTING](./CONTRIBUTING.md) | Changing skills/plugins in this monorepo |
| [SECURITY](./SECURITY.md) | Vulnerability reporting |
| [CODE OF CONDUCT](./CODE_OF_CONDUCT.md) | Community standards |
| [CHANGELOG](./CHANGELOG.md) | Plugin SemVer |

## Requirements

`git`, `gh`, `jq`, `python3` (≥ 3.8), `curl` — plus an agent that runs [Agent Skills](https://agentskills.io/) or Claude Code plugins. Hook tests need `bats`.

## License

MIT — see [LICENSE](./LICENSE).
