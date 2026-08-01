# create-pr workflow (detail)

**Progressive disclosure:** load when executing ship steps. Day-to-day contracts live in `../SKILL.md` (INVARIANT / DEFAULT / HINT).  
Policy: `policy.md` · body template: `templates/pr-body.md` · progress: `templates/pr-progress-comment.md`.

## Contents

- [1. Intent](#1-intent)
- [1.5. Structured PR context (INVARIANT; helper DEFAULT)](#15-structured-pr-context-invariant-helper-default)
- [1.6. Default branch → WORKSPACE recovery (INVARIANT)](#16-default-branch-workspace-recovery-invariant)
- [2. Ask intent (only if missing)](#2-ask-intent-only-if-missing)
- [2.5. Branch rename (DEFAULT)](#25-branch-rename-default)
- [3. Commit and push](#3-commit-and-push)
- [3.5. Base branch](#35-base-branch)
- [3.55. Diff matches intent (DEFAULT)](#355-diff-matches-intent-default)
- [3.6. Public repo safeguards (INVARIANT when PUBLIC)](#36-public-repo-safeguards-invariant-when-public)
- [4. Create or update](#4-create-or-update)
  - [Progress comments (long-lived PRs)](#progress-comments-long-lived-prs)
  - [Media](#media)
- [Response style (HINT)](#response-style-hint)

## 1. Intent

Prefer session COMMITTED / Spec Why. **"Do X" alone is not Why.** ASK once only if still missing.

## 1.5. Structured PR context (INVARIANT; helper DEFAULT)

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
bash "$SKILL_ROOT/scripts/check-pr-context.sh"
```

JSON fields: `repo`, `visibility` (`PUBLIC`|`PRIVATE`|`INTERNAL`), `branch`, `already_pushed`, `default_branch`.  
Do **not** query `isPrivate` (polarity traps). Never infer visibility/branch from chat. An equivalent native/tool path is acceptable only when it resolves and retains the same fields before mutation; the shipped script remains the normal and best-tested path.

## 1.6. Default branch → WORKSPACE recovery (INVARIANT)

If `branch == default_branch`: **do not** `gh pr create`.

1. Clean tree, nothing to ship → STOP.  
2. Work to ship → prefer a **bound** `tkt-N-slug` or `spc-n-slug` when a real id exists. Otherwise propose a semantic branch plus `--allow-unbound --reason <ownership/scope/evidence>`; never invent a fake id.
3. Prefer sibling worktree:

```bash
git stash push -u -m "create-pr: workspace recovery"
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")
ENSURE="$LIB/ensure-workspace.sh"
OUT=$(bash "$ENSURE" --mode worktree --bind tkt --id <N> --slug <slug>)
WT_PATH=$(printf '%s' "$OUT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["path"])')
git -C "$WT_PATH" stash pop
# continue all git/gh/check-pr-context from WT_PATH
```

Ask once to confirm the exact recovery branch/workspace when it was not already authorized. On decline: STOP. Never open PR while still on default branch.

## 2. Ask intent (only if missing)

```
Before creating this PR, I need to understand the intent behind this change.

What problem does this solve, and why is this change needed?
```

## 2.5. Branch rename (DEFAULT)

If branch name is meaningless and `already_pushed` is false, suggest descriptive rename (optional login prefix via `gh api user -q .login`).  
**PUBLIC:** also sanitize internal IDs / customer / codenames from branch name.

## 3. Commit and push

Commit if needed; `git push -u origin <branch>`.  
**PUBLIC:** review `git log --oneline <base>..HEAD` for internal identifiers in commit messages before push.

## 3.5. Base branch

Prefer `recommended_base` from `check-pr-context.sh` (integration-branch resolution) over the blind `default_branch`. The recommended base follows the user's working branch when long-lived, else fork-point inference from the current branch. Always pass `--base` to `gh pr create`.

- `recommended_source` ∈ {`user_branch`, `fork_point`, `only_choice`} → use `recommended_base` directly.
- `recommended_source` == `ask` (ambiguous fork-point, ≥2 long-lived) → `AskUserQuestion` among `long_lived` (NOT a hardcoded {main,dev}). If `|long_lived| == 1` there is no ask.
- `recommended_base` empty / `recommended_source` == `default` → fall back to `default_branch`.
- Soft-confirm when `recommended_base == default_branch` BUT the user's working branch is a non-default long-lived branch (e.g. on `dev`, recommended `main`): "landing on `main`, ok?".

GitFlow note: a repo with both `main` + `dev` is integration-shaped — feature PRs target `dev`; `dev → main` is a separate operator-authorized release merge. Trunk-shaped (only `main`) → `main`.

## 3.55. Diff matches intent (DEFAULT)

1. `git diff <base>...HEAD --stat`  
2. Unexpected files vs session → STOP and offer proceed / split / exclude.  
3. How from **actual diff**; Why from session/COMMITTED/Spec.

## 3.6. Public repo safeguards (INVARIANT when PUBLIC)

No internal URLs, team/employee IDs, private process links, or customer data in title/body.  
Print PUBLIC warning and wait for explicit confirm before `gh pr create`.

## 4. Create or update

```bash
PR_URL=$(gh pr create --base "<base>" --title "<title>" --body "$(cat <<'EOF'
…
EOF
)")
# Optional GitHub Project after *new* PR only (soft-fail; no-op when unset)
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
[[ -f "$RESOLVE" ]] || { echo "Error: _lattice-lib is not installed beside $SKILL_ROOT" >&2; exit 1; }
LIB=$(bash "$RESOLVE")
bash "$LIB/github-project-add.sh" "$PR_URL" || true
# existing: gh pr edit --body …  (do not re-run project-add on description-only updates)
# exists?: gh pr view --json number
```

**Body spirit** (see `templates/pr-body.md`): Summary · Why · Scope · How · Verification (commands run only if real) · Lineage · References · optional Notes.  
Title: Conventional Commits (`feat:` / `fix:`).  
Issue links: bulleted `Fixes #N` / `Refs #N` only (avoid `#N` in prose).  
**Closing:** use `Fixes`/`Closes`/`Resolves` for every ticket this PR fully delivers. Prefer **one line per issue** (`Fixes #N` … `Fixes #M`), not a single `Refs #N #M #K`. `Refs` never auto-closes.  
**Non-default base:** GitHub auto-close runs **only** on merge into the repository default branch. If `--base` is e.g. `dev` while default is `main`, document Fixes correctly anyway — **finish-work** will run `close-fixed-issues.sh` after merge.  
Optional plan `<details>` only if a plan path is known in session.  
Optional Risks/Decisions only if user stated them.

### Progress comments (long-lived PRs)

After meaningful multi-commit milestones: `gh pr comment` with `templates/pr-progress-comment.md`. Skip typo-only pushes. Update PR body if overall Why/How shifts.

### Media

Local image/video → `lattice-lib/scripts/upload-github-asset.sh` once per file; embed durable URLs. The default requires a non-symlink regular file inside the current repo. A user-explicit outside path requires `--allow-outside-repo`; never add that flag for a model-discovered path. No path → skip.

## Response style (HINT)

Surface: intent question (if needed), PUBLIC warning (if public), PR URL or errors. All other steps silent.
