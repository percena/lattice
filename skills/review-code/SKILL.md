---
name: review-code
description: "Optional PR-scoped code review of a change set — material correctness/regression findings (failure scenario, evidence, recommendation), not style nits. Use when the user asks to code-review a PR or branch, review the diff, or check for bugs before/after opening a PR. Not Lattice Review reports (create-review), not production ship checklists (review-production), not whole-repo architecture."
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
| PR checks when a PR exists | Portfolio of unrelated PRs |
| Material findings + optional `rev` / PR comment | Expanding into monorepo-wide cleanup |

**Related ≠ unbounded.** Prefer files in the diff. Any related read: one-line why. Cap related exploration.

If the user explicitly requests architecture / whole-repo work: **do not** silently expand; redirect to `create-review` and/or a Spec.

## Inputs (target resolution)

Resolve in order (unless user overrides):

1. Explicit `pr-N` → resolve the absolute active skill root, then prefer `python3 "$SKILL_ROOT/scripts/review-context.py" --pr N` (or `gh pr view/diff`)
2. Open PR for current branch → that PR
3. **Dirty working tree** (staged, unstaged, **untracked**) → `review-context.py` with no args; announce unit clearly
4. Clean feature branch → `review-context.py --branch HEAD --base <base>` or `git merge-base` + `git diff base...HEAD`
5. Optional **date-range** only when user asks (`--since` / `--until`) — not the default unit
6. **Refuse** default-branch “review everything” with no change set — ask for PR/branch/diff

**Shippable cwd:** reading is fine anywhere. Writing tests/fixes defaults to a bound sibling worktree; a reasoned unbound workspace or explicitly authorized clean base-direct path is also allowed.

Large change sets: start with context script / status / `--stat` / file list; self-collect file reads as needed. If context reports `Has changes: no`, stop — no invented findings.

## Process

### 1. Orient (short)

- Run context script when available; else title/body or branch; base or WT state; file list
- Announce: `mode: review-code · unit: pr-N | working-tree | branch-diff | commit-range · files: K · stance: root-cause-light`

### 2. Stance and axes (root-cause light)

**Default stance:** material **correctness / regression** risk in this change set — not full adversarial redesign.

| Axis | Look for |
| --- | --- |
| Correctness | Logic errors, off-by-one, broken edge cases in **changed** paths |
| High-cost failure (if touched) | authz/trust, data loss/corruption, retry/idempotency, races, empty/timeout, contract/schema when migrations change — short list only. Security **high** only with exploit bar (attacker → action → impact); theoretical “potential” stays med/low. Full production security checklist → `review-production` |
| Tests | Clear gaps for **new** behavior; missing regression for a bug fix |
| (demoted) Nits | Style/naming only if truly high confusion — **not** in material table by default |

Skip deep threat modeling, load testing, full coverage matrices (`review-production`).

**Dig deeper:** after the first plausible issue (or before a clean pass), check empty-state, retries/partial failure, stale state/ordering, rollback **where the diff touches**.

### 3. Material finding bar

Report only **material** findings. Each must answer:

1. What can go wrong? (**failure scenario**)
2. Why is this code path vulnerable?
3. Likely impact?
4. Concrete **recommendation** (smallest risk-reducing direction)

**Calibration:** prefer one strong finding over several weak ones; empty material list is OK; no filler; no invented files/lines; mark **inference** when not direct evidence.

### 4. Output findings

```markdown
## review-code · <pr-N | working-tree | branch>

**Unit:** … · **Base/head or WT:** …
**Overall:** ship-as-is | fix-first | unclear

| Sev | Finding | Failure scenario | Evidence | Confidence | Recommendation |
| --- | --- | --- | --- | --- | --- |
| high/med/low | … | inputs/state → bad outcome | path:line or symbol | high/med/low | … |

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
| Sort | Material rows by severity (high first) |

Do **not** use `go|go-with-risks|no-go` here (`review-production`). Advice only — **not** a `finish-work` HARD block.

### 5. Review-only hard stop (INVARIANT)

1. Present findings.
2. **STOP.** Do **not** apply patches or “obvious” fixes.
3. Edit the tree **only** if the user explicitly names which findings to fix and/or asks for tests (e.g. “补单测”, “fix the high ones”).
4. If fixes/tests requested: smallest change in the change set’s modules; run relevant tests; paste **fresh** output; no repo-wide harness rewrite.

### 6. Optional: persist

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
| “No PR yet — audit the entire repo” | Need a change set; refuse unbounded |
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
- Using `go/no-go` vocabulary from `review-production` as this skill’s overall

## Verification

Before claiming done:

- [ ] Target resolved (pr-N, working-tree, or branch change set) — not “whole repo”
- [ ] Orient announced unit + overall `ship-as-is|fix-first|unclear`
- [ ] Material findings (if any) have failure scenario, evidence, confidence, recommendation
- [ ] Sorted by severity; nits not mixed into material table
- [ ] Dig-deeper considered where diff touches
- [ ] Related reads (if any) justified and minimal
- [ ] **Hard stop** — no tree edits unless user explicitly requested tests/fixes
- [ ] Did not gate or run finish-work / create-pr unless user also asked for those skills separately
