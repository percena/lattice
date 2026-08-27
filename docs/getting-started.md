# Getting started with Lattice

Make a **GitHub** consumer repo Lattice-ready after installing the skills once on the machine.

## Engine vs consumer

| | **Engine** (`percena/lattice`) | **Consumer** (your app/service repo) |
| --- | --- | --- |
| Role | Workflow logic + Claude plugins | Place work happens |
| Install | Skills/plugins on the **machine** (global recommended) | No copy of skill bodies required |
| Per-repo setup | — | **None for humans** — skills auto-ensure `.lattice/` |
| Daily | Maintain/release this monorepo | `/start-work` … `/finish-work` |
| Artifacts | Dogfood binders under its own `.lattice/` | Specs, tickets, binders **for that product** |

```text
Machine (once)                         Each consumer repo (daily)
─────────────────                      ─────────────────────────
npx skills add … / plugin install      /start-work …
  → skills + _lattice-lib                → agent runs ensure-lattice
  → optional Claude hooks                → .lattice/ on first use
                                       → Issues/PRs + binders + worktrees
```

**Do not** vendor `skills/` into every app unless you are forking the engine. Prefer global install; consumer repos need no manual init script.

## When to use / not use

| Use Lattice when | Prefer not to when |
| --- | --- |
| Team uses **GitHub Issues + PRs** and agent coding (Claude Code / Codex) | Tracker is Jira/Linear only with no GH issues |
| You want **classify → align → ticket → worktree → PR → finish** discipline | Solo toy repo with one-line fixes only |
| Multi-session work needs **stable ids** (`spc`/`tkt`/`pr`/`rev`) | You refuse worktrees **and** refuse `profile: light` |
| You accept binding shippable branches to `tkt-N` or `spc-N` | Non-Unix environments without bash/`gh` |

Lattice is **discipline-first**, not a silent IDE theme. Default profile is **strict** (sibling worktree for shippable work, HARD acceptance alignment before merge). Opt into **light** only if your team agrees (see [Profiles](#profiles-strict--light)).

## Prerequisites

| Tool | Why |
| --- | --- |
| `git` | Branches / worktrees |
| `gh` | Issues, PRs, labels, asset upload |
| `jq` | JSON in scripts |
| `python3` | Alignment / plugin transcript helpers |
| `curl` | Asset upload |
| Agent with [Agent Skills](https://agentskills.io/) or Claude Code plugins | Run the user-facing skills |

## Skill + plugin map (what to install)

| Package | Kind | Role |
| --- | --- | --- |
| `_lattice-lib` | skill (internal) | Shared scripts — **not** a slash entry; co-install always |
| `start-work` | skill | Classify, ticket/workspace, setup-only or resume-by-id (EXECUTE) |
| `create-spec` | skill | Persist `spc-n` |
| `create-review` | skill | Persist `rev-YYYYMMDD-HHMMSSZ` (not GitHub PR review) |
| `create-tickets` | skill | Issues + binders |
| `batch-work` | skill (optional) | DAG-orchestrated unattended parallel fan-out of `start-work` agents on sibling worktrees |
| `create-pr` | skill | Open/update PR |
| `finish-work` | skill | Align + merge + cleanup |
| `lattice@percena` | Claude plugin | Packages **every** shipped skill (lifecycle six + side-paths + `_lattice-lib`); gates bare `gh pr create` / `gh pr merge` |

Full path = **`_lattice-lib` + six user skills**, and on Claude **`lattice@percena`** (one plugin). The optional side-paths — `review-code` · `review-production` · `review-delivery` (quality), `run-e2e` (e2e reference), `generate-wiki` · `create-adr` (doc tools) — are mapped in their "Optional" sections below.

## 1. Install the full pack (once per machine)

Lattice skills **share scripts** via **`_lattice-lib`** (`ensure-lattice`, `ensure-workspace`, `upload-github-asset`, `next-artifact-id`, …). Install **`_lattice-lib` + all six** user skills (or the whole package / the single Claude plugin `lattice@percena`).

### A. Portable skills (Claude Code + Codex) — recommended baseline

```bash
npx skills add percena/lattice \
  --skill _lattice-lib \
  --skill start-work --skill create-spec --skill create-review \
  --skill create-tickets --skill create-pr --skill finish-work \
  -a claude-code -a codex \
  -g -y
```

**Partial install** without `_lattice-lib` loses init, workspace, and upload helpers. Thin SHIP (`create-pr` alone) still needs `_lattice-lib` for upload + ensure-workspace recovery.

### Optional: quality side-paths (PR-scoped)

The six lifecycle skills alone are a **complete** demo/universal loop. For **PR-level** code or production checks, install optional side-paths (already bundled in the `lattice@percena` plugin; portable installs add them explicitly):

```bash
npx skills add percena/lattice --skill review-code --skill review-production
```

| Skill | When |
| --- | --- |
| `/review-code` | Light **material** code review of a **PR / dirty WT / branch change set** (before or after `create-pr`) — failure scenario + evidence + recommendation; not style-nit primary |
| `/review-production` | Heavier production-readiness checklist on that **same PR unit** (advice only) |
| `/review-delivery` | Artifact-only **chain review of a delivered ticket set** (`spc-N` \| ids \| batch report) — A*→evidence fidelity, cross-PR coherence + throwaway integration build, decision-ratification queue, per-PR findings → ranked morning digest (`auto-pass \| ratify-then-pass \| deep-review`) with per-axis attestation; co-installs `_lattice-lib`; never merges |

**HARD default:** analysis unit = one PR (or the diff / dirty working tree that will become one PR) — **not** whole-repo architecture. Expand only if the user **explicitly** asks; otherwise redirect to `/create-review` / Spec.

**Do not confuse with `/create-review`:** that skill persists a Lattice Review *report* (`rev` + `outcome`). Side-paths are optional quality passes; the pipeline does **not** require them for `create-pr` / `finish-work`.

### Optional: batch execution + e2e reference

Two additional skills extend the loop for parallel delivery and browser e2e:

| Skill | Needs `_lattice-lib`? | Role |
| --- | --- | --- |
| `/batch-work` | Yes (co-install) | DAG-orchestrated unattended fan-out: reads `parallel_group` + `blocked_by` from ticket binders, spawns one `start-work` agent per ticket in a sibling worktree, layer-barrier sync, failure isolation |
| `/run-e2e` | No (reference pattern) | Heredoc JS story pattern for ego-browser — one Bash invocation per story, fail-loud auth, structured JSON; not a runner, not a loop entry |

```bash
npx skills add percena/lattice --skill batch-work        # co-installs _lattice-lib
npx skills add percena/lattice --skill run-e2e            # standalone reference
```

**batch-work** spawns agents that stop at `create-pr` (human reviews, then `finish-work` per PR). A `.lattice/.batch-work-active` marker in each worktree blocks `finish-work` merge until the human runs it.

### Optional: doc-tool skills (not part of the core loop)

Two doc-tool skills are optional and sit outside the six-skill delivery loop:

| Skill | Needs `_lattice-lib`? | Role |
| --- | --- | --- |
| `/generate-wiki` | No (standalone) | Build a navigable `wiki/` + `llms.txt` from repo docs |
| `/create-adr` | Yes (co-install) | Write out-of-band `docs/adr/NNN` architecture decision records (durable L0 doc; uses `ensure-lattice` / `assert-shippable-cwd`) |

```bash
npx skills add percena/lattice --skill generate-wiki                         # standalone
npx skills add percena/lattice --skill _lattice-lib --skill create-adr       # co-installs _lattice-lib
```

### Optional: external practice packs (not Lattice)

Lattice is a **delivery-graph engine** (Spec / tickets / worktree / PR / finish). Broader senior-engineering *practice* catalogs — e.g. [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) (TDD, doubt-driven review, multi-persona ship, …) — and whole-repo **security audit** skills such as [cloudflare/security-audit-skill](https://github.com/cloudflare/security-audit-skill) — are **optional co-installs**. They are **not** required for Lattice correctness and are **not** absorbed into the six lifecycle skills.

| Want | Do |
| --- | --- |
| Lattice only | Install `_lattice-lib` + six (above) |
| PR-scoped quality side-paths | `review-code` + `review-production` |
| Whole-repo security audit / pen-test depth | Co-install `security-audit` (or equivalent) — **not** silent expand of `/review-production` |
| Extra session discipline (depth) | Co-install an external pack via its own install docs (`npx skills add …`) |

**Suggested co-install subset** (when using [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) or similar — pick what you need; names may drift upstream):

| Need during EXECUTE / VERIFY | Typical skill / persona |
| --- | --- |
| Test-first implementation | `test-driven-development` |
| Adversarial check on a high-stakes claim | `doubt-driven-development` |
| Stuck debugging | `debugging-and-error-recovery` |
| Pre-merge quality pass | `code-review-and-quality` (and/or security persona if risk warrants) |

These stay **optional**. Lattice correctness does not depend on them. Prefer thin `/review-*` for PR scope; use packs for depth. Do **not** vendor a full external catalog into every consumer repo “to make Lattice complete.”

### B. Claude Code plugins (skills + optional hooks)

```text
/plugin marketplace add percena/lattice
/plugin install lattice@percena
```

CLI:

```bash
claude plugin marketplace add percena/lattice
claude plugin install lattice@percena
```

Hooks advise on bare `gh pr create` / `gh pr merge` on Claude only; set `LATTICE_HOOK_MODE=strict` to opt into marker-based blocking. Skills remain correct without hooks (Codex).

### Org roll-out (Claude Code)

Pin the marketplace and enable the plugin team-wide via `.claude/settings.json` (or managed settings):

```json
{
  "extraKnownMarketplaces": {
    "percena": {
      "source": { "source": "github", "repo": "percena/lattice" }
    }
  },
  "enabledPlugins": { "lattice@percena": true }
}
```

Pair with **A** if developers also use Codex, so both agents share the same skill logic.

### Refresh install

Re-run the full pack (section 1A) after skill renames or when global skill text looks stale. On Claude, reinstall `lattice@percena` from the marketplace. Hard cut: no marketplace renames.

**Local dogfood** when GitHub `main` lags your checkout:

```bash
npx skills add /path/to/lattice \
  --skill _lattice-lib \
  --skill start-work --skill create-spec --skill create-review \
  --skill create-tickets --skill create-pr --skill finish-work \
  -a claude-code -a codex -g -y
claude plugin marketplace remove percena 2>/dev/null || true
claude plugin marketplace add /path/to/lattice
claude plugin install lattice@percena
```

## 2. Consumer repo — no manual init

After skills are on the machine, **open the consumer repo and run a Lattice skill** (`/start-work`, `/create-spec`, …). Agents **must** run the deterministic script:

```bash
# Agent-only (skill Step 0) — users never type this
bash …/_lattice-lib/scripts/ensure-lattice.sh
```

What `ensure-lattice` does (idempotent):

| Step | Effect |
| --- | --- |
| Skeleton | `.lattice/{specs,reviews,tickets}` |
| Config | `.lattice/config.yaml` with `profile: strict` if missing (**never** overwrites existing profile) |
| Preferences | `.lattice/preferences.md` scaffolded from the shipped template (minimal heredoc fallback when the references tree is absent) if missing — **never** overwrites an existing file, refuses a symlinked path |
| Gitignore | merges Lattice snippet into `.gitignore` when markers absent (default) |
| Labels | **not** synced by default; agent may pass `--sync-labels` or run `create-tickets` `sync-github-labels.sh` when `gh` fails |

You do **not** run absolute `$HOME/.../lattice-init.sh` paths. Optional: commit `.lattice/` with the first Spec/ticket, or when the agent suggests a skeleton commit.

**Profile at first create only:** set `profile: light` in `.lattice/config.yaml` after auto-init, or have the agent pass `--profile light` on first ensure when your team opts in (see [Profiles](#profiles-strict--light)).

**Maintainer / recovery only** (not the happy path): if an agent cannot resolve `_lattice-lib`, reinstall the full pack (`npx skills add percena/lattice … -g -y`). Low-level writer remains `lattice-init.sh` (called by ensure).

## 3. Thirty-second daily path

```text
/start-work …                 # classify → confirm → ticket/workspace
# setup-only: stop after Spec/tickets
# resume:     /start-work tkt-N  or  spc-N
# adopt:      /start-work #M     # existing GH issue → ADOPT_CHECK (append-only)

# implement in the bound worktree (no /implement skill)

/create-pr                    # Why/How + Fixes/Refs + Spec line
/finish-work pr N             # base update + alignment + merge + cleanup
```

Typical complex path:

```text
/start-work → /create-spec → /create-tickets → implement → /create-pr → /finish-work
```

| Intent | Command |
| --- | --- |
| New work | `/start-work …` |
| Spec only | `/create-spec` (after COMMITTED or with brief) |
| Split issues | `/create-tickets` |
| **Adopt hand-created issue** | `/start-work #M` / `tkt-M` — **ADOPT_CHECK**: binder + optional comment/Spec; **do not rewrite** issue body |
| Broad reconciling note | `/create-review` |
| Open PR | `/create-pr` |
| Land | `/finish-work pr N` · `tkt N` · `spc N` — **one open PR per invocation** |

### Manual / external issues (append-only)

Hand-created GitHub issues are first-class. Lattice **outer-joins** them:

| Do | Don't |
| --- | --- |
| Write `.lattice/tickets/tkt-M-*/` binder (extract Acceptance) | Overwrite the operator issue title/body with a Lattice template |
| Optional one adopt comment (binder path, Spec link) | Spam comments every micro-step |
| Create **new** Spec / follow-up tickets when needed | Dual-role `#M` as Spec primary + sole delivery on Spec-then-ticket path without operator intent |
| Soft-add missing kind/priority labels; soft parent under Spec | Strip operator labels |

At land, adopted binders use **binder-first** Acceptance honesty; Spec/claim drift still **blocks merge**.

## Install tracks (team vs expert)

Two legitimate installs — pick consciously. **Dogfood for this monorepo stays team/strict.**

| Track | Install | Profile | When |
| --- | --- | --- | --- |
| **Team (default)** | Full portable pack **+** Claude plugin `lattice@percena` | `strict` | Shared repos, parallel tickets, advisory intercepts; teams may opt into strict hook blocking |
| **Expert / strong-model solo** | Portable skills only (or plugins disabled); optional quality side-paths | often `light` | Solo speed; trusts model path choice while preserving authority, identity, destructive safety, and verification truth |

**What stays hard on both tracks:** no silent PR from the live default branch, real GH identity for `spc-N`, destructive-action safety, and finish-work honesty when binders apply. Worktree/bind choices are defaults with evidence-bearing escapes.
**What team plugins add:** PreToolUse intercepts advise on bare `gh pr create`/`merge`; `LATTICE_HOOK_MODE=strict` opts into marker-based blocking (fail-open on ambiguity).
**What light relaxes:** shippable `--mode branch` without policy shame; Acceptance open-on-Fixes → WARN not HARD.

See also [Profiles](#profiles-strict--light).

## Profiles (`strict` | `light`)

File: `.lattice/config.yaml`

```yaml
profile: strict   # default
# profile: light
```

Or one shell: `export LATTICE_PROFILE=light`.

| | **strict** (default) | **light** (opt-in) |
| --- | --- | --- |
| Shippable isolation | Sibling **worktree** default | **`--mode branch` allowed** without policy shame |
| Bind `tkt-` / `spc-` | **Default** | **Default**; semantic unbound + reason allowed |
| `alignment-check` open Acceptance on `Fixes` | **HARD** (exit 1) | **WARN** (exit 0) — still fix before merge when you can |
| Percena dogfood | Use this | Do not switch this monorepo to light casually |

## Multi-user / multi-clone

| Rule | Detail |
| --- | --- |
| One clone per human | Prefer sibling worktrees for parallel tickets; do not share one dirty MAIN for concurrent shippable writes |
| Spec id | Create GitHub issue first → `spc-N` with **N = issue number** (primary stays when splitting tickets) |
| Review id | R1 `rev-YYYYMMDD-HHMMSSZ` (UTC); legacy `rev-<digits>` still valid |
| ADR | Manual numbering — not timestamps |
| Local `next-artifact-id --kind spc` | **Not** team SoT; offline degrade only (warns) |
| Never guess issue numbers | GitHub assigns on create; Issue+PR share sequence |
| Workspace base | `ensure-workspace` fetches base when online; optional `base_branch:` in `.lattice/config.yaml` |
| Offline | Explicit degrade + loud warning; multi-clone Spec minting unsafe |

## What gets committed

| Path | Commit? |
| --- | --- |
| `.lattice/specs`, `reviews`, `tickets/*/README.md` | Usually **yes** |
| `.lattice/config.yaml` | **yes** (team profile) |
| `.lattice/preferences.md` | **yes** (team preference SoT) |
| `.lattice/lineage/`, `BOARD.md` | **no** — not product; do not create (gitignored) |
| `.lattice/.ids/`, ticket `assets/*` | **no** (gitignore) |
| Physical worktrees | Outside repo (`../<repo>.worktrees/`) |

## Env (optional)

| Env | Default | Use |
| --- | --- | --- |
| `LATTICE_HOME` | `<main>/.lattice` | Override binders root |
| `WORKTREE_ROOT` | `../<repo-basename>.worktrees` | Override sibling worktree pool |
| `LATTICE_PROFILE` | from `config.yaml` (else strict) | One-shell profile override |
| `LATTICE_LIB_SCRIPTS` | resolved next to skills | Point at shared scripts explicitly |
| `LATTICE_SKILL_ROOT` | host-resolved active skill directory | Portable absolute skill root when the client does not expose `CLAUDE_SKILL_DIR`; never point it at the consumer cwd |
| `LATTICE_GITHUB_PROJECT_OWNER` + `_NUMBER` | unset (off) | Opt-in Project auto-add after skill create — [github-surface.md](./github-surface.md) / `.env.example` |

## Industry notes (short)

Lattice keeps **batch principal confirmation** (not one-question-per-turn like Matt/Trellis defaults), **GitHub as Ticket/PR SoT**, Superpowers-like **finish/worktree discipline**, and Trellis-like **init once** without a heavy multi-platform harness.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `gh label` / issue create fails on `feat,P2` | Agent runs `create-tickets` `sync-github-labels.sh` (or `ensure-lattice.sh --sync-labels`) — **not** a user absolute-path step |
| `ensure-lattice.sh` / `ensure-workspace.sh` not found | Install **`_lattice-lib`** with the six user skills (full pack) |
| `ensure-workspace` unbound error | Prefer issue/Spec; or pass semantic `--branch`, `--allow-unbound`, and a concrete `--reason` |
| Global skill text or plugins look stale | Re-run full pack + reinstall **`lattice@percena`** (section 1 / Refresh install) |
| Forgot to install `lattice@percena` | Install `lattice@percena` for full Claude path; or use portable skills only |
| Want fewer worktrees | Set `profile: light` and use `--mode branch` with bind — or skip Lattice for pure throwaways |
| Agent asks you to run `bash $HOME/.../lattice-init.sh` | **Reject** — reinstall pack or set `LATTICE_LIB_SCRIPTS`; skills must call `ensure-lattice` internally |
| Slash skills look stale / missing `ensure-lattice` or `assert-shippable-cwd` | **Refresh global install** after engine releases: `npx skills add percena/lattice -a claude-code -a codex -g -y` (and reinstall Claude plugins). Machine skill dirs lag monorepo tip until reinstall. |

## Checklist (copy for a new consumer)

```bash
# Machine (if not already)
npx skills add percena/lattice \
  --skill _lattice-lib \
  --skill start-work --skill create-spec --skill create-review \
  --skill create-tickets --skill create-pr --skill finish-work \
  -a claude-code -a codex -g -y
# Claude: /plugin install lattice@percena

# Consumer — no manual init
cd /path/to/your-app
# Daily: /start-work … → implement → /create-pr → /finish-work pr N
# First skill run auto-creates .lattice/ via ensure-lattice
```

## Next docs

| Doc | Topic |
| --- | --- |
| [README](../README.md) | Install matrix + system map |
| [github-surface.md](./github-surface.md) | Label catalog |
| [workflow-fsm.md](./workflow-fsm.md) | Three coupled state machines, transition owners, bounded-loop invariant |
| [day-phase.md](./day-phase.md) | Attended planning recipe: requirement → proposal rev → spec → adr → tickets |
