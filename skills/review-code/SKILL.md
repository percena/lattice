---
name: review-code
description: "Optional PR-scoped code review of a change set — material correctness/regression findings with recommended solutions + alternatives, plus CI/CD status check, syntax/lint on changed files, documentation sync detection, and interface/contract breakage tracing to adjacent consumers. Not style nits. Use when the user asks to code-review a PR or branch, review the diff, or check for bugs before/after opening a PR. Not Lattice Review reports (create-review), not production ship checklists (review-production), not whole-repo architecture."
allowed-tools: Bash Read Grep Glob AskUserQuestion
metadata:
  agents: "claude-code,codex"
  domain: quality-side-path
---

# Review Code

**Quality side-path**. Light **change-set** review with a **finding quality contract** — **supplement**, not a Lattice lifecycle skill.

**Runtime path:** before executing the optional context helper, set `LATTICE_SKILL_ROOT` to the absolute directory containing this loaded `SKILL.md` (Claude may already provide `CLAUDE_SKILL_DIR`). Never infer it from consumer cwd.

## Load on demand

| When | Read |
| --- | --- |
| Material finding bar / severity calibration | `references/finding-contract.md` |
| Scope / side-path policy | `references/policy.md` |
| CI/CD check procedure | `references/ci-check.md` |
| Syntax/lint check procedure | `references/syntax-lint.md` |
| Documentation sync check | `references/docs-sync.md` |
| Interface/contract impact check | `references/interface-impact.md` |
| Stable git/PR context (optional) | `scripts/review-context.py` |

- **Not** required for `/start-work` → `/create-pr` → `/finish-work`.
- **Not** `create-review` (durable Lattice Review *report* / research / architecture notes).
- **Not** `review-production` (production checklist + `go|go-with-risks|no-go`).
- **Not** GitHub’s social PR review UI (you may still post a comment summary).
- **Not** whole-repo architecture or drive-by refactors unless the user **explicitly** asks (then hand off to `create-review` / Spec — do not silently widen).
- **Not** a Codex CLI wrapper — optional second opinion via external `/codex:review` is fine; this skill runs in-session.

## When to use

| Trigger | Action |
| --- | --- |
| “code review this PR”, “review the diff”, “any obvious bugs?” | Run this skill on the PR, dirty WT, or branch change set |
| Before `create-pr` | Dirty WT or `base...HEAD` on current bound branch/worktree |
| After `create-pr` | Prefer `pr-N` or open PR for current branch |

## When NOT to use

| Situation | Use instead |
| --- | --- |
| Design compare, dogfood note, architecture decision support | `create-review` |
| Production-readiness (security/perf/coverage/ship checklist) | `review-production` |
| Implement a feature / open workspace | `start-work` |
| Open or merge PR | `create-pr` / `finish-work` |
| Whole-repo health, monorepo redesign (no explicit ask) | Decline widen; offer `create-review` + Spec |
| “Challenge the whole design permanently” with `outcome` | `create-review` (not an adversarial skill id) |

## HARD scope (change-set unit of analysis)

**Default unit = one PR’s change set**, or the commits/diff/**working tree** that will become one PR.

| Allowed by default | Forbidden by default |
| --- | --- |
| `gh pr diff` / `base...HEAD` / dirty WT (staged+unstaged+untracked) | Whole-repo architecture review |
| Minimal **related** code to understand the diff | Unrelated “while we’re here” refactors |
| **Interface-adjacent code** — callers, consumers, importers of changed signatures/exports/API endpoints/config keys (to detect breakage) | Portfolio of unrelated PRs |
| PR checks when a PR exists | Expanding into monorepo-wide cleanup |
| Material findings + optional `rev` / PR comment | |

**Related ≠ unbounded.** Prefer files in the diff, plus their direct interface consumers. Any related read: one-line why. Cap related exploration — trace one hop out from the change, not the entire call graph.

**Sanctioned exception — release-boundary merge review** (ADR-010; see `references/policy.md` § Unit of analysis). A dev→main release merge (`origin/main...dev`, or `<last-release>...dev`) is an **allowed** larger-than-one-PR unit when the operator explicitly opts in (`--release-merge` / `--merge-review`, or `base=<release>` change set) — it is **not** refused as a "portfolio of unrelated PRs." Distinguish from unbounded default-branch "review everything" with no change set, which **remains refused** (target-order item #6). When invoked, **partition** the diff into subsystem slices (validator/scripts/CI/hooks/routing/skills/docs), **tier risk by file class** (`.lattice/**` + `docs/`/ADRs = low-risk bulk; `tools/`, `skills/**/scripts/`, `plugins/lattice/hooks/`, `.github/workflows/` = high-risk logic), run `ci-local.sh --release-check` as a first-class axis, and carry a coarser **release-blocking vs ship-as-is** finding bar.

If the user explicitly requests architecture / whole-repo work: **do not** silently expand; redirect to `create-review` and/or a Spec.

## Inputs (target resolution)

Resolve in order (unless user overrides):

1. Explicit `pr-N` → resolve the absolute active skill root, then prefer `python3 "$SKILL_ROOT/scripts/review-context.py" --pr N` (or `gh pr view/diff`)
2. Open PR for current branch → that PR
3. **Dirty working tree** (staged, unstaged, **untracked**) → `review-context.py` with no args; announce unit clearly
4. Clean feature branch → `review-context.py --branch HEAD --base <base>` or `git merge-base` + `git diff base...HEAD`
5. Optional **date-range** only when user asks (`--since` / `--until`) — not the default unit
6. **Release-boundary merge review** (sanctioned exception, ADR-010): `origin/main...dev` (or `<last-release>...dev`) with explicit opt-in (`--release-merge` / `--merge-review`, or `base=<release>`). Partition into subsystem slices; tier risk by file class; run `ci-local.sh --release-check`; coarser **release-blocking vs ship-as-is** bar. See `references/policy.md`.
7. **Refuse** default-branch “review everything” with no change set **and no opt-in** — ask for PR/branch/diff

**Shippable cwd:** reading is fine anywhere. Writing tests/fixes defaults to a bound sibling worktree; a reasoned unbound workspace or explicitly authorized clean base-direct path is also allowed.

Large change sets: start with context script / status / `--stat` / file list; self-collect file reads as needed. If context reports `Has changes: no`, stop — no invented findings.

## Process

### 1. Orient (short)

- Run context script when available; else title/body or branch; base or WT state; file list
- Announce: `mode: review-code · unit: pr-N | working-tree | branch-diff | commit-range | release-merge · files: K · stance: root-cause-light`

### 2. Stance and axes (root-cause light)

**Default stance:** material **correctness / regression** risk in this change set — not full adversarial redesign.

| Axis | Look for |
| --- | --- |
| Correctness | Logic errors, off-by-one, broken edge cases in **changed** paths |
| Interface/contract impact | Changes that break **callers, consumers, or contracts** in adjacent code — changed function signatures, removed/renamed exports, changed API endpoint params/responses, changed config keys, changed CLI flags. Trace **one hop** to consumers; flag breaking changes. See `references/interface-impact.md`. |
| High-cost failure (if touched) | authz/trust, data loss/corruption, retry/idempotency, races, empty/timeout, contract/schema when migrations change — short list only. Security **high** only with exploit bar (attacker → action → impact); theoretical “potential” stays med/low. Full production security checklist → `review-production` |
| Tests | Clear gaps for **new** behavior; missing regression for a bug fix |
| Privacy/Secrets | Scan diff, commit messages, and PR body for: local filesystem paths (`/Users/`, `/home/`, `C:\`, `/root/`); API keys, tokens, passwords, private keys (grep: `api[_-]?key`, `secret`, `password`, `token`, `BEGIN.*PRIVATE`); closed-source project names or internal hostnames in public-repo artifacts; DB schema details of external services (table/column names in non-migration context); personal email/phone in non-standard contexts. **Credentials/secrets → high** (recommend removal + `.env`/secret-manager). Local paths/project names → **med** (recommend generic replacement). If sensitive content is unavoidable (e.g. legitimate config reference), mark **inference** and recommend redaction or externalization. |
| CI/CD | Fetch PR/branch CI run status (`gh pr checks` / `gh run list`); for failures, fetch log excerpt; classify real failure vs flaky/infra. Findings feed into the single batch confirmation (Step 6). See `references/ci-check.md`. |
| Syntax/Lint | Run language-appropriate syntax/lint on **changed** files only (`.py`→ruff/py_compile, `.sh`→shellcheck, `.js`→node --check, `.json`→jq, `.yaml`→yaml.safe_load). Skip silently if tool unavailable. See `references/syntax-lint.md`. |
| Docs sync | Code changes that alter behavior/interface/commands/config but README, `docs/`, `wiki/`, `CLAUDE.md`, `SKILL.md`, or ADRs were not updated to match. See `references/docs-sync.md`. |
| (demoted) Nits | Style/naming only if truly high confusion — **not** in material table by default |

Skip deep threat modeling, load testing, full coverage matrices (`review-production`).

**Dig deeper:** after the first plausible issue (or before a clean pass), check empty-state, retries/partial failure, stale state/ordering, rollback, **interface/contract breakage** **where the diff touches**.

### 3. Auxiliary checks

Run CI/CD, syntax/lint, docs-sync, and interface-impact checks on the change set. These produce **candidate findings** that feed into the material-finding bar (Step 4). Load the relevant reference for each.

**Release-boundary merge review only:** additionally run `bash tools/ci-local.sh --release-check` as a first-class axis (the ADR-005 version-increment gate). Partition the diff into subsystem slices (validator/scripts/CI/hooks/routing/skills/docs) and tier risk by file class (`.lattice/**` + `docs/`/ADRs = low-risk bulk skim; `tools/`, `skills/**/scripts/`, `plugins/lattice/hooks/`, `.github/workflows/` = high-risk logic) — do not deep-review each binder. Carry a coarser **release-blocking vs ship-as-is** finding bar.

**CI/CD** (`references/ci-check.md`):
- PR mode: `gh pr checks <PR_N> --json name,state,link`
- Branch mode: `gh run list --branch <branch> --limit 10 --json databaseId,status,conclusion,name,event`
- For failures: `gh run view <databaseId> --log-failed | head -50` — extract failing step + error
- No `gh` or no workflows → one line "no CI runs available", not a finding

**Syntax/Lint** (`references/syntax-lint.md`):
- For each changed file (from context script `Changed Files` or `git diff --name-only`), detect language by extension and run the first available tool (`command -v <tool>` first)
- `.py`→ruff/py_compile · `.sh`→shellcheck · `.js`→node --check · `.json`→jq · `.yaml`→yaml.safe_load
- Tool unavailable → one line "skipped for <ext>", not a finding

**Docs sync** (`references/docs-sync.md`):
- Only when the diff alters behavior/interface/commands/config (not pure refactor)
- Check existing README, `docs/`, `wiki/`, `CLAUDE.md`, `SKILL.md`, `docs/adr/`, API specs against the diff's intent
- Stale = doc doesn't mention or contradicts the new behavior

**Interface/contract impact** (`references/interface-impact.md`):
- Identify changed signatures, exports, API endpoints, config keys, CLI flags, types, DB schema in the diff
- Trace **one hop** to consumers via `git grep` (callers, importers, clients)
- Flag breaking changes where consumers are not updated
- If a changed symbol has zero consumers → note "no callers found, low risk"

### 4. Material finding bar

Report only **material** findings. Each must answer:

1. What can go wrong? (**failure scenario**)
2. Why is this code path vulnerable?
3. Likely impact?
4. **Recommended solution** — best-practice fix with brief rationale (not just "direction"; give the concrete approach you'd apply).
5. **Alternatives** — 1–2 viable alternative solutions with trade-off notes. If only one sound approach exists, say "no viable alternative" rather than padding.

**Calibration:** prefer one strong finding over several weak ones; empty material list is OK; no filler; no invented files/lines; mark **inference** when not direct evidence.

### 5. Output findings

```markdown
## review-code · <pr-N | working-tree | branch>

**Unit:** … · **Base/head or WT:** …
**Overall:** ship-as-is | fix-first | unclear

| Sev | Finding | Failure scenario | Evidence | Confidence | Recommended solution |
| --- | --- | --- | --- | --- | --- |
| high/med/low | … | inputs/state → bad outcome | path:line or symbol | high/med/low | … |

### Solutions
#### <Finding 1 short label>
- **Recommended (best practice):** <concrete solution + brief rationale>
- **Alternative A:** <solution + trade-off>
- **Alternative B:** <solution + trade-off>

### Interface impact
- changed symbol · change type · consumer path:line · breakage description (or "no breaking interface changes")

### CI/CD
- check name · state/conclusion · log excerpt or link (or "no CI runs for this unit")

### Syntax/Lint
- file:line · tool · error/suggestion (or "all changed files clean")

### Docs sync
- stale doc path · what code changed · what doc should say (or "docs in sync")

### No material findings
(if empty — one line residual risk optional)

### Nits (optional, non-material)
- …

### Out of scope (not expanded)
- …

### Suggested next (optional)
- …
```

| Field | Rule |
| --- | --- |
| **Overall** | `ship-as-is` = no material issues; `fix-first` = material issues before relying on this change; `unclear` = missing context |
| **Sev** | **high** = likely break in this change, **or** security issue with concrete attack sketch + impact; **med** = should fix before prod reliance / smell without proven impact; **low** = material but limited blast radius — **not** style nits |
| **Confidence** | `high` \| `med` \| `low` only (no 0–1 floats) |
| **Recommended solution** | Best-practice fix with rationale; elaborated in **Solutions** subsection with alternatives |
| Sort | Material rows by severity (high first) |

Do **not** use `go|go-with-risks|no-go` here (`review-production`). Advice only — **not** a `finish-work` HARD block.

### 6. Review-only hard stop (INVARIANT)

1. Present **all** findings (correctness, interface impact, CI/CD, syntax/lint, docs-sync, privacy/secrets) in a single output — material table + **Solutions** subsection + axis subsections together.
2. **STOP.** Do **not** apply patches or “obvious” fixes.
3. **Single batch confirmation (ONE AskUserQuestion):** after presenting the full finding set **with recommended solutions and alternatives**, use **one** `AskUserQuestion` to ask what to fix — never per-finding or per-axis. Suggested options:
   - `Apply all recommended solutions` — apply the best-practice fix for every material finding
   - `Apply high-severity recommended only` — just the high rows’ recommended solutions
   - `Choose per-finding` — operator will specify which findings + which alternative; pause for input
   - `Skip — I’ll address manually` — no edits; operator takes over
   - (The operator may also use “Other” to name a custom subset, e.g. “apply recommended for finding 1, alternative B for finding 2”)
4. If a fix option is chosen: apply smallest changes for the selected findings in the change set’s modules; re-run relevant tests/checks (CI locally if possible, lint, syntax); paste **fresh** output for each; no repo-wide harness rewrite.
5. If `Skip` is chosen: stop. No edits. The operator may re-invoke later or fix manually.

### 7. Optional: persist

| Action | When |
| --- | --- |
| PR comment | PR exists and user wants it on GH |
| Lattice `rev` | User wants durable audit via **create-review** contract (`outcome` e.g. `inform_only` / `spawn_fix`) — one accountable owner validates `rev`; no worktree bind to `rev-` alone |

Do **not** invoke `finish-work` or claim merge is tool-blocked.

## Compatibility

- Uninstalling this skill does not break the six-skill pipeline.
- Never required by `create-pr` / `finish-work`.
- `finish-work` embeds a **bounded mini projection** of this skill's finding contract at the merge-decision point (advice-only, never a merge gate). This full skill stays the superset for pre-`create-pr` and dedicated review passes — full axes, Confidence field, persistence, hard-stop-for-fixes all live here.
- Does not own bind/merge/Spec SoT.
- No Codex runtime dependency.

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| “While reviewing, fix the bugs I found” | **Hard stop** — ask which findings to fix |
| “While reviewing, fix the whole module’s style” | PR-scoped only; nits demoted |
| “Just auto-fix the lint errors while reviewing” | Hard stop — present, then fix only if user confirms |
| “Report the problem, let the user find the fix” | Bad UX — always provide recommended solution + alternatives |
| “Only check the diff files, ignore callers” | One-hop interface-adjacent code is in scope to detect breakage |
| “No PR yet — audit the entire repo” | Need a change set; refuse unbounded **unless** release-boundary opt-in (`--release-merge`) |
| “create-review is the same as code review” | create-review = report/`rev`; this skill = change-set quality |
| “Always add tests” | Only when user explicitly asks |
| “Fail finish-work on findings” | Advice only; lifecycle gates unchanged |
| “Related files mean half the monorepo” | Minimal neighborhood with justification |
| “Need a review-adversarial skill” | No — design durability → `create-review`; focus stays in this skill’s change set |
| “Potential vuln / theoretically injectable = high” | High security needs attack sketch + impact; else med/low |

## Red Flags

- Reviewing files with zero connection to the diff
- Auto-applying fixes after presenting findings
- Opening architecture redesign without explicit ask
- Material table full of style/naming nits
- Findings without failure scenario or evidence path
- Silently writing product code/tests on team base without the explicit clean base-direct escape
- Posting as if this replaces Lattice `create-review` research notes
- Silent scope expand after “quick look at dependencies”
- Ignoring local paths, credentials, or closed-source project names in the diff
- Presenting findings without scanning for Privacy/Secrets axis
- Skipping CI/CD check when a PR or branch CI run exists
- Reporting lint errors as "high" severity when they are style-only
- Flagging stale docs without saying what code change requires the update
- Reporting findings without recommended solutions or alternatives (making the user search for fixes)
- Tracing the entire call graph instead of one hop from changed interfaces
- Issuing per-finding or per-axis AskUserQuestion confirmations instead of one batch confirmation
- Using `go/no-go` vocabulary from `review-production` as this skill’s overall

## Verification

Before claiming done:

- [ ] Target resolved (pr-N, working-tree, or branch change set) — not “whole repo”
- [ ] Orient announced unit + overall `ship-as-is|fix-first|unclear`
- [ ] Material findings (if any) have failure scenario, evidence, confidence, **recommended solution + alternatives**
- [ ] Sorted by severity; nits not mixed into material table
- [ ] Dig-deeper considered where diff touches
- [ ] **Interface/contract impact** checked — callers/consumers/importers of changed signatures traced one hop
- [ ] Related reads (if any) justified and minimal
- [ ] **CI/CD status fetched** (or noted “no CI runs for this unit”)
- [ ] **Syntax/lint run on changed files** (or noted “tool unavailable, skipped”)
- [ ] **Docs sync checked** against README/docs/wiki/CLAUDE.md/SKILL.md for behavior/interface changes
- [ ] **Hard stop** — no tree edits unless user explicitly requested tests/fixes
- [ ] Did not gate or run finish-work / create-pr unless user also asked for those skills separately
- [ ] If release-boundary merge review: `ci-local.sh --release-check` run; diff partitioned into subsystem slices; risk tiered by file class; findings classed release-blocking vs ship-as-is
