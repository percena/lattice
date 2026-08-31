---
name: create-pr
description: "Open or update a GitHub pull request for the current feature branch (Why/How/Fixes body, push, lineage). Use when asked to create a PR, open a pull request, push and PR, submit a PR, or draft the PR body. Not for filing issues, merging, or starting a workspace."
allowed-tools: Bash Read Grep Glob AskUserQuestion
argument-hint: "[optional intent notes]"
metadata:
  agents: "claude-code,codex"
---

# Pull Request Creation

**Runtime path:** before executing skill-owned files, set `LATTICE_SKILL_ROOT` to the absolute directory containing this loaded `SKILL.md` (Claude may already provide `CLAUDE_SKILL_DIR`). Never infer it from consumer cwd.

## Load on demand

| When | Read |
| --- | --- |
| Full create steps, public-repo checklist, default-branch recovery §1.6 | `references/workflow.md` |
| Lineage / body policy tables | `references/policy.md` |
| PR body / progress comment shapes | `references/templates/` |
| Constraint severity labels | `../_lattice-lib/references/constraint-language.md` |
| Claiming tests green / shippable | `../_lattice-lib/references/definition-of-done.md` |
| Sub-agent vs create gate | `../_lattice-lib/references/orchestration-patterns.md` |

Short path below is enough for a normal private-repo PR.

## When to use / When NOT

| Use | Not — use instead |
| --- | --- |
| Open/update PR for current feature branch | File issues → `create-tickets` |
| Draft Why/How/Fixes body + push | Merge/cleanup → `finish-work` |
| PR-side media upload when local paths | Start workspace / implement → `start-work` |
| | PR change-set review only → `review-code` |

## Core rules (result contracts)


### INVARIANT (fail closed)

1. **User rejection** — Session "don't push / don't make a PR / hold off / not ready" → STOP until re-confirm.
2. **No fabricated Why** — Prefer COMMITTED / Spec / user problem statement; if still missing, ASK once.
3. **Structured PR context before `gh pr create`** — Resolve repository, visibility, current head, push state, and live default branch from tools rather than chat. `check-pr-context.sh` is the DEFAULT helper; equivalent structured proof is valid when it preserves the same fields.
4. **No PR on default branch** — Recover via a feature WORKSPACE (`workflow.md` §1.6); bound naming is preferred, with a reasoned unbound escape when no ticket/Spec exists.
5. **Self-contained body** — Cold reader gets Why, Scope, How, Lineage. Prefer `templates/pr-body.md`. Not "as discussed" alone.
6. **Lineage when known** — `Fixes`/`Refs` + Spec line. Delivered tickets: `Fixes #N` per issue (not `Refs`). GitHub auto-close only on **default-branch** merge; non-default base relies on finish-work `close-fixed-issues.sh`. M/C no issue: warn once. S may use a reasoned semantic workspace when no real ticket/Spec exists. After PR #P: update Spec `prs:` / binder L0.
7. **Create/push accountability** — exact repository, branch, intent, and authority must be fixed before mutation. A bounded delegate may execute it, but the host verifies the resulting PR and remains accountable.

### DEFAULT

8. **Body shape** — Why + How required; Scope on M/C; **Verification (commands run)** only when real commands ran. Standing DoD when claiming shippable.
9. **No theater** — No empty Test plan checklist, no Files Updated list, no invented risks / hunk narration. Optional Risks/Decisions only if user stated them. Claims of green tests require Iron Law evidence (`definition-of-done.md`).
10. **Progress comments** — Multi-commit milestones → `templates/pr-progress-comment.md`; skip typo-only pushes.
11. **Post-open binder stamp** — After a **new** PR, when a ticket binder exists for the branch, run `bash "$LIB/stamp-pr-open.sh" --pr <N>` (`../_lattice-lib/scripts/stamp-pr-open.sh`): binder `prs` row + `status: pr-open` + issue acceptance sync, one idempotent call. Marker lifecycle: `.lattice/.batch-work-active` stays untracked-dirty until finish-work removes it at merge — scripts must never `git add -A` it (check-pr-context whitelists it at warning level only). **Before the stamp: mutation-proof the PR** (`../_lattice-lib/scripts/verify-main-chain.sh --stage pr …`, spc-254 A2/D5) — a `FAILED:` proof halts the stamp/binder/L0 write and emits structured recovery JSON. Normal, batch, and delegated paths share this one helper contract.

### HINT

12. **Response style** — Intent question (if needed), public-repo warning (if public), PR URL or errors. No phase narration.

## Short path

1. Intent from session / Spec (ask only if missing).
2. Resolve the active `SKILL.md` directory to absolute `LATTICE_SKILL_ROOT` (Claude may supply `CLAUDE_SKILL_DIR`), then run `bash "$SKILL_ROOT/scripts/check-pr-context.sh"`.
3. If on default branch → WORKSPACE recovery (`workflow.md` §1.6).
4. Commit/push if needed; pick `--base`; confirm diff matches intent.
5. PUBLIC → sanitize + explicit confirm.
6. `gh pr create` / `gh pr edit` with template body; after **new** PR, optional Project add; update L0; print URL.

After a **new** PR URL:

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")
bash "$LIB/github-project-add.sh" "$PR_URL" || true
```

Opt-in via `LATTICE_GITHUB_PROJECT_OWNER` + `LATTICE_GITHUB_PROJECT_NUMBER` (env or gitignored `.env`). Soft-fail always. Do not re-run on description-only `gh pr edit`.

Full step text, public-repo checklist, plan-details, media upload: **`references/workflow.md`**.

## Media (when local paths present)

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")
UP="$LIB/upload-github-asset.sh"
bash "$UP" "<file-path>"
# User explicitly supplied a path outside the current repo:
# bash "$UP" --allow-outside-repo "<approved-file-path>"
```

Embed returned URLs. No local media → skip.

## Anti-Patterns

Contract Don’ts (theater / memory excuses → **Common Rationalizations**):

| Don't | Why |
| --- | --- |
| Mutate before repository/head/authority are fixed | Identity or authorization can target the wrong PR |
| Trust prompt claims for visibility/default branch | Resolve structured context from tools; use the helper or equivalent proof |
| PR after user said "don't" | INVARIANT |
| PR on default branch | §1.6 recovery |
| Base How on chat, not diff | Body must match actual changes |

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| "PR from main is fine for a tiny fix" | Default-branch stop; feature-workspace recovery |
| "Skip context checks — I know the branch" | Tool-derived structured context is mandatory; the helper is the default, not the only implementation |
| "Invent Why from the diff vibe" | Ask if missing; do not fabricate |
| "Dummy Test plan for show" | Theater banned; real Verification only |
| "A delegate opened it, so verification is optional" | Host still verifies the exact PR, body, base/head, and result |
| "DoD is optional fluff" | Standing bar when claiming shippable |
| "Tests pass — I remember from earlier" | Iron Law: re-run this session or do not claim |

## Red Flags

- `gh pr create` on default branch
- Dummy Test plan / Files Updated / invented risks
- Ignoring "don't make a PR" without re-confirm
- Local media left without upload when required

## Verification

- [ ] Structured repo/visibility/head/push/default context was resolved; not on default branch
- [ ] Why from user/session/Spec or asked
- [ ] Body Why+How minimum; lineage when known
- [ ] DoD + Iron Law considered (fresh Verification only if commands ran)
- [ ] PR URL returned; accountable owner verified the exact repository, base/head, body, and resulting state
