# GitHub surface (labels + optional Project)

Canonical **kind** + **priority** labels, plus optional **Project auto-add** for skill-created issues/PRs.
Cross-check: [getting-started.md](./getting-started.md).
Automation/daemon trigger plane (Ready column, leases) is separate.

---

## 1. Labels (kind + priority)

### Policy

| Rule | Detail |
| --- | --- |
| Issue type SoT | **GitHub labels** (not `[Bug]` in title) |
| Lattice portable field | front matter / binder `kind` + `priority` — keep aligned when filing |
| PR type | Prefer **title** Conventional Commits (`feat:` / `fix:`) + optional PR label |
| Required on M/C issues | **one kind label** + **one priority label** |
| S demos | labels optional |

### Kind labels

Canon follows the **live** label set (`gh label list`) — ratified default (tkt-65): docs track the labels actually on the repo; renaming repo labels is a separate deliberate migration, never a doc side effect.

| Label | Color (live) | Description |
| --- | --- | --- |
| `bug` | `#D73A4A` | Something isn't working |
| `documentation` | `#0075CA` | Improvements or additions to documentation |
| `enhancement` | `#A2EEEF` | New feature or request |
| `chore` | `#C5DEF5` | Maintenance / non-feature work |
| `epic` | `#5319E7` | Spec primary / multi-ticket epic (filter all Spec trackers) |
| `spec` | `#0E8A16` | Lattice Spec (spc-N) |
| `adr` | `#BFD4F2` | Architecture Decision Record |

Map Lattice kinds → labels: `feat` → `enhancement` · `docs` → `documentation` · `bug` → `bug` (PR/commit type becomes **`fix:`**) · `chore` → `chore`. Kinds without a dedicated live label (`refactor`, `perf`, `test`, `spike`) file under `chore`; keep the precise kind in the binder/front-matter `kind` field.

### Priority labels

| Label | Color (live) | Meaning |
| --- | --- | --- |
| `P1` | `#B60BF0` | Priority 1 (high) |
| `P2` | `#BFD4F2` | Priority 2 (medium) |
| `P3` | `#EAEAEA` | Priority 3 (low) |

Default when unspecified: **P2**. There is no live `P0`: urgent work is `P1` with the urgency called out in the issue body.

### Optional process labels (not kind)

| Label | Use |
| --- | --- |
| `good first issue` | Onboarding |
| `help wanted` | Extra attention needed |
| `question` | Further information requested |
| `wontfix` | Closed without work |
| `duplicate` | Closed as dup |
| `invalid` | Doesn't seem right |

Do **not** overload these as substitutes for `kind`.

### Apply with `gh`

```bash
gh issue create --title "…" --label "enhancement,P1" --body "…"
gh issue edit 12 --add-label "bug,P0"
gh label list
```

### Bootstrap script

```bash
# From this monorepo checkout:
bash skills/create-tickets/scripts/sync-github-labels.sh

# After skill install (portable):
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: set LATTICE_SKILL_ROOT to the absolute create-tickets skill directory" >&2; exit 1; }
bash "$SKILL_ROOT/scripts/sync-github-labels.sh"
# (create-tickets skill root)
```

Colors match the tables above. Existing labels with the same name are left unchanged unless `--force-color` is passed.

### Issue templates (optional)

When adding `.github/ISSUE_TEMPLATE/`, set default labels in front matter, e.g.:

```yaml
name: Bug
about: Something is broken
labels: [bug, P2]
```

Templates should still ask for acceptance / repro; **do not** rely only on `[Bug]` in the title.

---

## 2. Optional Project auto-add

Skill-created **issues** and **PRs** can be added to a GitHub Project (org or user) when the consumer repo opts in. Public installs stay **off** until configured.

### Goals

| Goal | Behavior |
| --- | --- |
| Multi-repo → one board | Same `OWNER` + `NUMBER` in each repo’s local config |
| Skill path only | `create-spec` / `create-tickets` / `start-work` issues and `create-pr` new PRs |
| Non-skill creates | Not required (use Project Auto-add in GitHub UI if you want web coverage) |
| Soft-fail | Missing config / missing `project` scope never blocks create |

### Configuration (opt-in)

Set **both** of:

| Variable | Example |
| --- | --- |
| `LATTICE_GITHUB_PROJECT_OWNER` | `percena` (org or user login) |
| `LATTICE_GITHUB_PROJECT_NUMBER` | `13` (project number in the URL, not the title) |

Optional:

| Variable | Default | Meaning |
| --- | --- | --- |
| `LATTICE_GITHUB_PROJECT_ADD_ISSUES` | `true` | Add issue URLs |
| `LATTICE_GITHUB_PROJECT_ADD_PRS` | `true` | Add PR URLs |
| `LATTICE_GITHUB_PROJECT_ALLOW_DOTENV` | unset | Trust a repository `.env` to select the board for **writes** |

**Resolution order**

1. **Process environment** — if a variable is **set** (including empty), it wins
2. **Files:** `<MAIN_ROOT>/.env` then `<MAIN_ROOT>/.env.local`  
   (`MAIN_ROOT` = primary checkout / parent of shared `.git`)
3. Incomplete (missing owner or number) → **no-op**

**A repository file cannot authorize an external write.** `.env` lives in the
checked-out repo, so any repo you clone could otherwise redirect every item this
workflow creates onto someone else's board using your token. When the board
target comes from `.env` rather than your environment, `github-project-add.sh`
**skips the add** and says so. Confirm it either by exporting
`LATTICE_GITHUB_PROJECT_OWNER`/`_NUMBER` in your own environment, or by setting
`LATTICE_GITHUB_PROJECT_ALLOW_DOTENV=1` for a repo whose `.env` you trust.
Reads (`list-board-items.sh`) stay softer: they proceed but name the source.

Do **not** commit real `.env` files. Ship only [`.env.example`](../.env.example).

```bash
cp .env.example .env
# edit OWNER + NUMBER (digits)
gh auth refresh -s project   # once per machine/token
```

### Runtime

Canonical script (`_lattice-lib` only):

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: set LATTICE_SKILL_ROOT to the absolute active skill directory" >&2; exit 1; }
LIB=$(bash "$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh")
bash "$LIB/github-project-add.sh" "https://github.com/org/repo/issues/1"
# always exit 0; logs on stderr
```

Skills call this **after** a successful `gh issue create` / `gh pr create` (not on description-only `gh pr edit`).

### Auth

`gh project item-add` needs the **`project`** scope:

```bash
gh auth refresh -s project
```

### Not this feature

| Want | Do |
| --- | --- |
| Web UI issues on the same board | Configure Project **Auto-add** in GitHub settings |
| Hardcoded board in public skills | **Not supported** — use per-repo `.env` |
| Block create when Project fails | **Not supported** — always soft-fail |

---

## 3. Operational helper contracts

Two `_lattice-lib` / finish-work helpers touch the GitHub surface directly and carry contracts worth knowing before scripting against them.

### Board item listing is current-repository scoped

`_lattice-lib/scripts/list-board-items.sh` lists GitHub Project items. The **default** output (`tkt-<N>` per line) is scoped to the **current repository** so the same issue number across two repos cannot collide. If the current repository identity cannot be resolved, the helper fails closed rather than emitting cross-repo `tkt-N` lines. A cross-repository inventory requires `--all-repositories --json` so repository identity is preserved on every item.

### Post-merge issue close requires the approved closing-id set

`finish-work/scripts/close-fixed-issues.sh` closes the OPEN delivery issues named by executable `Fixes`/`Closes`/`Resolves` directives in the PR body. A live close (`--pr <N>` without `--dry-run`) **requires** `--expected-closing-ids <csv>` — the closing-id set approved by the pre-merge `alignment-check.sh --json` (`closing_ids`). If the current PR closing set differs from the approved set, the helper fails closed (`reason: closing_set_changed`) **before** loading or closing any issue. Parsing-only modes (`--body-file` / `--body-stdin`) and `--dry-run` stay offline and do not require the flag.
