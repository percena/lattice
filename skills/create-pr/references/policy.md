# create-pr policy (portable)

Shipped with `create-pr`. Self-sufficient without monorepo docs.

## Contents

- [Definition of Done (standing bar)](#definition-of-done-standing-bar)
- [Workspace precondition](#workspace-precondition)
- [Self-contained PR (hard rule)](#self-contained-pr-hard-rule)
  - [References](#references)
- [Title](#title)
- [Body template](#body-template)
  - [Still forbidden](#still-forbidden)
- [Progress comments (long-lived PR audit trail)](#progress-comments-long-lived-pr-audit-trail)
  - [When to comment](#when-to-comment)
  - [How](#how)
  - [<Milestone title>](#milestone-title)
  - [Relation to description](#relation-to-description)
- [After open](#after-open)
- [Detail workflow](#detail-workflow)

## Definition of Done (standing bar)

Before treating a branch as shippable, apply the portable **Definition of Done** shipped with lattice-lib:

`skills/_lattice-lib/references/definition-of-done.md` (or co-installed sibling path).

Spec/ticket **Acceptance `A*`** answers “right thing.” DoD answers “ready.” Both apply when Lattice binders exist. Do not invent empty Test plan sections to fake readiness — only record Verification that actually ran.

## Workspace precondition

SHIP assumes WORKSPACE already ran (`start-work` / `ensure-workspace.sh`).

If structured PR context (normally `check-pr-context.sh`) reports `branch == default_branch`:

1. Do **not** call `gh pr create`.
2. Do **not** invent tickets/Specs here (thin SHIP).
3. If there is work to ship: prefer a bound name (`tkt-N-slug` / `spc-n-slug` when known); otherwise use a semantic name with the `--allow-unbound --reason …` escape. Confirm the exact recovery choice once, run **sibling worktree** recovery by default: stash → `ensure-workspace.sh --mode worktree …` → stash pop **into the worktree path** → **continue all SHIP steps from that cwd** (re-resolve structured PR context there). `--mode branch` remains an explicit user/profile escape.
4. If clean and nothing to ship: stop.

Never leave the user with only “run `git checkout -b` yourself” when session context already has ticket/spec/slug.

## Self-contained PR (hard rule)

A PR description must let a reviewer **without chat history** understand:

1. What problem is being solved (**Why**)  
2. What is in/out of this change set (**Scope**)  
3. Approach at a high level (**How**) — not a file list  
4. How it ties to tickets/specs (**Lineage** + **References**)  
5. What remains / risks **only if the user stated them**

**Do not** paste entire Spec/Issue into the body. **Do** name them clearly:

```markdown
### References
- Issue: #N — Workflow skills above create-pr
- Spec: `spc-N` → `.lattice/specs/spc-N-….md` (in repo)
- Kind: feat · Priority: P1
```

The body stays independently readable via short summaries + explicit refs.

## Title

Conventional Commits style:

```text
feat: short summary
fix: short summary
```

Map Lattice `kind: bug` → `fix:`.

## Body template

Use `references/templates/pr-body.md`. Minimum sections:

| Section | Required? | Content |
| --- | --- | --- |
| **Summary** | recommended | One line |
| **Why** | **yes** | Problem / intent (from user or COMMITTED) |
| **Scope** | recommended on M/C | In / out for **this PR** (or “implements slice X of Spec”) |
| **How** | **yes** | 1–5 approach bullets; **no file list** |
| **Verification** | if known | What was run / how to smoke — only if real; **no empty “Test plan” checklist** |
| **Lineage** | when known | `Fixes`/`Refs`, Spec, Kind, Priority |
| **References** | when anything external is reused | Explicit issue/spec/doc links |
| **Notes for reviewers** | optional | Migrations, flags, follow-ups |

### Still forbidden

- Files Updated / narrating every hunk  
- Invented risks  
- Generic dummy test-plan sections  
- Fabricated intent  

## Progress comments (long-lived PR audit trail)

When a PR receives **multiple meaningful pushes** (milestones), post **issue/PR conversation comments** summarizing the delta — same idea as progressive design notes on PR #N.

### When to comment

| Do post | Skip |
| --- | --- |
| After a coherent batch of commits that changes architecture, policy, or user-visible behavior | After every tiny typo commit |
| After correcting a wrong path/branch/decision mid-PR | Pure rebase/noise |
| When landing a named milestone (“sibling worktrees”, “human lineage”) | Duplicate of the last comment |

Prefer **≥1 comment per major milestone** on multi-day / multi-commit PRs. S-mode one-shot PRs need none.

### How

```bash
gh pr comment <N> --body-file - <<'EOF'
### <Milestone title>

- What changed (3–7 bullets, outcome-focused)
- Why now / decision if any
- Pointers: paths, Spec id, follow-ups

EOF
```

Template: `references/templates/pr-progress-comment.md`.

Comments are **append-only history** for auditors; they do not replace updating the PR **description** when the overall Why/How shifts (edit body or add a short “Description updated” note).

### Relation to description

| Surface | Role |
| --- | --- |
| PR **title + body** | Stable entry point; keep current |
| **Progress comments** | Timeline / decisions as the PR evolves |

## After open

1. Update Spec `prs: [pr-P]` and ticket binder when files exist.  
2. Update Spec.prs / binder prs (L0). Bloodline = L0 + GitHub. 
3. On later milestones → progress comment + push.

## Detail workflow

Step-by-step ship narrative: `workflow.md` (progressive disclosure from SKILL.md).
