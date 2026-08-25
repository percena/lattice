---
name: finish-work
description: "Merge or close a GitHub PR after base update, artifact alignment, and a default-on mini code-review scan, then clean up the feature branch and worktree. Prefer explicit targets: PR number, tkt-N/#N, spc-N, or branch. Use when landing a PR, merge and delete branch, remove worktree after ship, or finish workflow cleanup. Not for opening a PR or starting workspace."
allowed-tools: Bash Read Grep Glob AskUserQuestion
user-invocable: true
argument-hint: "[pr <N> | tkt <N> | spc <N> | #N | --branch <name>] [--close] [--dry-run] [--rebase] [--no-update-branch]"
metadata:
  agents: "claude-code,codex"
---

# Finish work

Close the loop after SHIP: **resolve target → preflight (CI + base update + alignment) → merge|close → cleanup → binder Finish**.

**Scripts:** `update-pr-base.sh`, `alignment-check.sh`, `cleanup-workspace.sh`, `close-fixed-issues.sh`, `finish-ledger.sh` (+ lattice-lib `check-base-residue.sh`, `resolve-integration-branch.sh`).

**Runtime path:** before executing skill-owned files, set `LATTICE_SKILL_ROOT` to the absolute directory containing this loaded `SKILL.md` (Claude may already provide `CLAUDE_SKILL_DIR`). Never infer it from consumer cwd.

## Load on demand

| When | Read |
| --- | --- |
| Full preflight / alignment dimensions / land-time drift | `references/flow.md` |
| Profile / acceptance / adopted-issue tables | `references/policy.md` |
| Constraint severity labels | `../_lattice-lib/references/constraint-language.md` |
| Claiming shippable / tests green | `../_lattice-lib/references/definition-of-done.md` |
| Delegation and accountable ownership | `../_lattice-lib/references/orchestration-patterns.md` |

## When to use / When NOT

| Use | Not — use instead |
| --- | --- |
| Land / merge a known PR, cleanup worktree after ship | Open PR → `create-pr` |
| Close PR without merge + cleanup | Start implement / ensure workspace → `start-work` |
| Explicit `pr` / `tkt` / `spc` / branch target | File issues → `create-tickets`; PR code review → `review-code` |

## Arguments

| Input (priority) | Resolution |
| --- | --- |
| `pr N` / `pr-N` | `gh pr view N` |
| `tkt N` / `#N` | Open PR head `tkt-N-*` or body Fixes/Refs #N |
| `spc N` / `spc-N` | Open PR head `spc-N-*` or body `Spec: spc-N` |
| `--branch name` / bare branch | PR for head or cleanup only |
| *(none)* | Current branch only if **one** open PR — else stop and ask |

| Flag | Effect |
| --- | --- |
| `--close` | Close without merge |
| `--dry-run` | Plan only; still run alignment + base dry-run |
| `--rebase` | Feature rebase via `update-pr-base.sh --rebase` |
| `--no-update-branch` | Skip base update (user asserts ready) |
| `--keep-worktree` / `--keep-branch` / `--keep-remote` | Cleanup opts (remote delete is **default**) |

Finish **does not invent** which PR to merge.

## Finish cycle (copy)

- [ ] Target resolved (pr|tkt|spc|branch) — no multi-PR guess
- [ ] **BATCH_WORK gate:** if `BATCH_WORK=1` env set → refuse `gh pr merge`; print "BATCH_WORK=1 is set — batch-work agents may only create-pr; human must run finish-work after review"; stop (do not merge). Proceed only when `BATCH_WORK` is unset or `0`.
- [ ] Base updated (unless `--no-update-branch`); not CONFLICTING
- [ ] `alignment-check.sh --json` + human dimensions; retain its approved `closing_ids` through merge; **land-time Spec drift** when `Spec:` / Spec-bound Fixes apply; DoD honesty — drift ⇒ remediate (a) commits (b) tickets (c) Spec, **no merge**
- [ ] **Mini-review scan (default-on):** load PR diff, 5-axis light scan, present material findings, `AskUserQuestion` on material items (high → default Hold); advice, **not** a gate — HARD gate stays alignment-check
- [ ] merge|close
- [ ] After **merge**: `close-fixed-issues.sh --pr N --expected-closing-ids <approved-set>` — fail if the PR closing set changed; otherwise actionable local delivery issues CLOSED
- [ ] branch + worktree cleanup; remote head gone by default
- [ ] binder `## Finish` ledger written on merge base with mergedAt (finish-ledger.sh); fails closed if a binder exists for a merged PR but lacks mergedAt
- [ ] **Spec primary:** workstream **complete** → closed + Spec `done` (or explicit operator hold); **incomplete** → still OPEN + residual work named (commits/tickets/Spec)

## Core rules

### INVARIANT (fail closed)

1. **User rejection** — "don't merge / hold off / not ready" → STOP until re-confirm.
2. **Explicit target** when ambiguous — never guess among open PRs.
3. **No silent force-delete** dirty worktree without user OK.
4. **Alignment before merge** when binders/Spec/Fixes apply — `alignment-check.sh` + dimensions in `flow.md` / `policy.md` (includes **land-time Spec drift**, distinct from create-tickets POST_SPLIT); chat is not durable L0.
5. **No invent bloodline** — update binders only when paths exist and PR # known.
6. **Merge/cleanup accountability** — authority and exact target stay explicit; bounded delegation is allowed, but the host verifies alignment, merge state, issue closure, and cleanup.
7. **Never** `git push --force` to default branch.
8. **BATCH_WORK gate** — `BATCH_WORK=1` env → refuse `gh pr merge`; print guidance: "BATCH_WORK=1 is set — batch-work agents may only create-pr; human must run finish-work after review". The operator must unset `BATCH_WORK` (or set `0`) before this skill may merge.

### DEFAULT

8. Prefer `gh pr merge --squash --delete-branch` over raw `git merge` on main — **not sufficient alone** when a sibling worktree still checks out the head (`gh` cannot delete a checked-out branch; many repos set `delete_branch_on_merge: false`).
9. **After every merge|close (mandatory):** run `cleanup-workspace.sh --branch <HEAD_BRANCH> --pr <PR_N>` after a merge (and `--worktree-path` when known). A close-without-merge preserves unmerged branches unless the user explicitly authorizes `--force`. The helper observes local and remote tips separately before destructive work, removes the worktree, compare-and-deletes the exact proven local OID, then deletes the exact proven remote OID with a lease. Do **not** stop at the merge step.
10. Base update via `update-pr-base.sh` unless `--no-update-branch` / `--close`.
11. Report must include cleanup JSON: `deleted_remote_branch` / `remote_residual` / `ok`. If `ok:false` or remote head still listed → treat finish as **failed**, fix residual, re-run cleanup.
12. **After every successful merge (mandatory):** run `close-fixed-issues.sh --pr <N> --expected-closing-ids <pre-merge alignment set>`. A changed set fails closed before issue operations. Do not trust GitHub auto-close when PR base ≠ repo default branch.

### HINT

12. `--dry-run` when unsure; report remote residual if delete fails.
13. CI empty-step flake heuristic — see `flow.md` preflight.
14. Squash tips are often not ancestors of base — `--pr <PR_N>` verifies the matching same-repository PR, then binds local and remote authorization independently to refs that still equal `headRefOid`. Local ancestry proof can carry to the remote only when both observed refs are the same exact OID. Compare-and-delete / remote lease failures preserve a ref that changed after proof, and an initially absent remote is re-probed before success. Protected names (`main`/`dev`/…) are never deleted locally or remotely. Dirty non-force `--dry-run` reports blocked without claiming removal; remote dry-run stays explicitly unprobed.

## Short path

1. Resolve target → record PR_N / HEAD / BASE.
2. **BATCH_WORK gate:** if `BATCH_WORK=1` env is set → refuse `gh pr merge`; print "BATCH_WORK=1 is set — batch-work agents may only create-pr; human must run finish-work after review" and stop (do not merge, do not proceed to base update). Proceed only when `BATCH_WORK` is unset or `0`.
3. Preflight (draft, checks, mergeable). **Base-mismatch advice:** if `BASE` (PR base) ≠ the user's current integration branch (long-lived, e.g. on `dev` but PR targets `main`), surface a one-line warning **before** `gh pr merge` and let the operator confirm or switch. Advice only — HARD gate stays `alignment-check.sh`.
4. `update-pr-base.sh --pr N` (unless skipped).
5. `alignment-check.sh --pr N` + dimension fix/stop; **land-time Spec drift** when applicable; print `alignment:` line.
6. **Mini-review scan (default-on):** load PR diff (`gh pr diff N` or `git diff <BASE>...HEAD`), 5-axis light scan, present material findings, `AskUserQuestion` on material items (any high → default recommended `Hold`; only med/low → default `Merge anyway`); advice, **not** a gate — HARD gate stays alignment-check. See **§ Mini-review (embedded)**. Proceed on no findings or operator `Merge anyway`.
7. `gh pr merge` or `gh pr close`.
8. **After merge:** `close-fixed-issues.sh --pr N --expected-closing-ids <approved-set>` (required) — refuse a changed closing set, then close OPEN actionable local delivery issues only; skip and report Spec-primary/`epic` plus unsupported repository-qualified references.
9. **`cleanup-workspace.sh --branch HEAD --pr N …` (required after merge)** — not optional after a “successful” merge; close-without-merge does not imply branch deletion authority.
10. **Binder `## Finish` ledger (REQUIRED).** After cleanup (step 9), `cd` to the **main checkout**, switch to the **PR merge base** (`git checkout <base>` + pull), and run `finish-ledger.sh --pr <PR_N> --issue <closing_M> --binder <.lattice/tickets/tkt-M-*/README.md> [--repo owner/repo]`. It stamps firm GH dates (`mergedAt`/`closedAt`) + `prs` + `status: closed` into the binder idempotently (never a second `## Finish`), then commit + push the base branch. **Two-phase:** cleanup removes the worktree, so the ledger is a post-merge commit on the base branch (policy.md:41). **No binder** (ticket-only flow) → `finish-ledger.sh` skips with a note, finish does not fail. **Closed-without-merge** → the helper reads the PR state itself and records `closed without merge` **without** claiming `mergedAt`; `status` flips to `closed` only when a closing issue actually closed. An **OPEN** PR is refused (the ledger records outcomes, not intentions). The helper also refuses to stamp a PR from a repository other than the binder's own origin. Spec primary close (when workstream complete) is separate.
11. Report URL + cleanup + **actionable local delivery issues closed** + **epic/unsupported exclusions reported** + Spec-primary suggestion (if any) + **assert remote gone**.

Full step text: **`references/flow.md`**. Policy tables: **`references/policy.md`**.

## Mini-review (embedded, default-on)

A bounded, **advice-only** code-review scan at the merge decision point — a compressed projection of the standalone `/review-code` finding contract. Runs after alignment-check (HARD gate) and before merge. **Never** a HARD gate; HARD gate stays `alignment-check.sh`.

**Why this and `/review-code` both exist:** this scan is a last-gate sanity pass at merge time (5 axes, no persistence, advice-only). `/review-code` is the full-function skill for pre-`create-pr` or dedicated review passes (full axes, Confidence field, PR comment / `rev` persistence, hard-stop-for-fixes). Overlap is intentional — this is a bounded subset of the same finding contract, not a parallel one.

### Unit (reuse resolved target)

No separate target resolution — reuse the PR diff already in scope: `gh pr diff <PR_N>` (or `git diff <BASE>...HEAD` when no PR yet). Do not widen to whole-repo architecture.

### Axes (diff-touched only)

| Axis | Look for |
| --- | --- |
| Correctness | Logic errors, off-by-one, broken edge cases in **changed** paths |
| High-cost failure (if touched) | authz/trust · data loss/corruption · retry/idempotency · races · empty/timeout · schema/compat when migrations change — short list only |
| Tests | Clear gaps for **new** behavior; missing regression for a bug fix |
| Dig deeper | empty/null paths · partial failure/idempotency · stale state/ordering · rollback/irreversible writes — only where the diff touches |
| Privacy/Secrets | Scan diff, PR body, ticket binders, and commit messages for: local filesystem paths (`/Users/`, `/home/`, `C:\`, `/root/`); API keys, tokens, passwords, private keys (grep: `api[_-]?key`, `secret`, `password`, `token`, `BEGIN.*PRIVATE`); closed-source project names or internal hostnames in public-repo artifacts; DB schema details of external services (table/column names in non-migration context); personal email/phone in non-standard contexts. **Credentials/secrets → high (default Hold).** Local paths/project names → med (recommend cleanup). If sensitive content is unavoidable → `AskUserQuestion`: "This diff contains `<type>` — clean up first or confirm it is safe to commit?" |

Skip deep threat modeling, load testing, full coverage matrices (those are `/review-production`).

### Material finding bar (compressed)

Report only **material** findings. Each row = severity + one-line failure scenario + evidence (`path:line` or symbol). Calibration: prefer one strong finding over several weak; empty material list is OK (print `mini-review: no material findings`); no nits in the material table (style/naming demoted to an optional appendix or omitted).

### Output

```markdown
## mini-review · <pr-N>

**Overall:** proceed | fix-first
| Sev | Finding | Evidence |
| --- | --- | --- |
| high/med/low | <inputs/state → bad outcome, one line> | path:line |
```

`proceed` = no material issues; `fix-first` = material issues surfaced. Sort high first. Mark **inference** when not direct from the diff.

### Decision (advice, never auto-block / never auto-fix)

- No material findings → one-line `mini-review: no material findings`; proceed to merge.
- Material findings → print the table, then `AskUserQuestion`:
  - `Merge anyway` — operator accepts the risk
  - `Hold (I'll address)` — stop; operator fixes or defers
  - `Invoke full /review-code` — deeper pass before deciding
- Any **high** finding (including credential/secret leak) → default recommended option `Hold`; only med/low → default `Merge anyway`.
- **Privacy/Secrets override:** if the Privacy/Secrets axis surfaces a **high** finding (credentials, API keys, private keys), default to `Hold` regardless of other axes. If the finding is **medium** (local paths, project names), recommend cleanup but allow `Merge anyway` after explicit confirmation.
- **Hard stop on edits:** present findings and stop. Do **not** auto-fix even if "obvious". Edit the tree only when the operator explicitly names which findings to fix (then smallest change in the change set's modules; fresh test output if tests requested).
- The HARD merge gate is unchanged — `alignment-check.sh`. Findings are advice; the operator may still choose `Merge anyway`.

## Anti-patterns

Structural Don’ts (authority / remote / CI excuses → **Common Rationalizations**):

| Don't | Why |
| --- | --- |
| "Aligned in chat" without editing issue/PR/binder | Not durable L0 |
| Merge half-done land because Spec primary still open | Land-time gate; epic is not a buffer |

## Relationship

| Skill | Role |
| --- | --- |
| `start-work` | Workspace / EXECUTE |
| `create-pr` | Open PR |
| `create-tickets` | Issues that Fixes may close |
| `review-code` | Full-function code review (pre-create-pr / dedicated pass); the embedded mini is a bounded projection of its contract |
| `review-production` | Optional advice — **not** a merge gate |

## Common Rationalizations

| Rationalization | Reality |
| --- | --- |
| "CI green — bare gh pr merge" | finish-work adds base + alignment + cleanup; hooks advise by default and block only in strict mode |
| "Boss said ship now — skip alignment" | Alignment HARD gaps block merge; chat is not L0 |
| "Leave remote; repo auto-deletes" | Often false (`delete_branch_on_merge` off); cleanup-workspace must delete remote |
| "gh --delete-branch already ran" | Fails if worktree still checks out head; §4 still required |
| "branch -d failed, so it must be a squash residue" | Preserve the local ref unless its exact OID has local PR proof or the user explicitly passes `--force`; deletion still uses an expected-OID compare |
| "The local ref was safe, so delete origin/name too" | Local proof never authorizes a different remote OID; remote deletion requires remote PR proof, explicit force, or the identical safely deleted local OID, and always uses an OID lease |
| "dry-run said deleted_local_branch true — cleanup is done" | Dry-run is predictive; dirty or unsafe local paths report `ok:false`, while the remote remains explicitly unprobed |
| "No need to re-check worktrees before update-ref" | Expected-OID plumbing bypasses porcelain checkout guards; a branch still checked out by any retained or additional worktree is preserved |
| "Dirty worktree — force remove silently" | Never silent `--force` without user OK |
| "Multiple open PRs — pick one" | Require explicit pr / tkt / spc / branch |
| "Acceptance open on Fixes issue is fine" | Check off or defer before merge |
| "Tests pass / aligned — I remember from earlier" | Iron Law: fresh evidence this session (`definition-of-done.md`) |
| "Fixes in the PR body — GitHub will auto-close" | Only on **default** branch merge; non-default base needs `close-fixed-issues.sh` |
| "Refs is fine for delivered one-PR slices" | Refs never closes; delivered work uses Fixes (or explicit close) |
| "Leave Spec primary open so we can merge incomplete tickets" | Unresolved land-time drift blocks merge; fix tickets/diff/Spec — epic open ≠ permission to half-ship |
| "Sub-issues all closed ⇒ auto-close Spec primary" | Progress ≠ Acceptance; verify A* + real remaining work first |
| "Workstream done but leave epic OPEN — ADR says optional" | Completion-causal: complete → close (unless operator holds); optional was anti-blind-script, not anti-close |
| "POST_SPLIT already passed — skip Spec at finish" | Split-time ≠ land-time; EXECUTE can introduce new drift |
| "Adopted issue has no checkboxes — rewrite body to pass alignment" | Binder-first; settle via comment — never pollute operator prose |
| "spc-N means merge every open PR under the Spec" | One PR per finish; primary close only when **this** workstream is actually complete |
| "mini-review high finding → block merge" | Advice only; `AskUserQuestion` lets operator `Merge anyway`; HARD gate stays `alignment-check.sh` |
| "auto-fix the obvious bug the mini-review found" | Hard stop — only fix when operator explicitly names findings |
| "mini-review makes /review-code redundant" | Containment: `/review-code` is the full superset for pre-`create-pr` / dedicated passes; mini is a bounded merge-time subset |

## Red Flags

- Merge without `alignment-check.sh` when binders/Spec apply
- Treating mini-review `high` findings as merge-blocking (advice; HARD gate is alignment-check)
- Auto-applying fixes after mini-review findings (hard stop)
- Running mini-review on the whole repo instead of the PR diff
- Checking off Acceptance the diff did not implement
- Residual `origin/<head>` after finish without keep-remote
- Force-pushing default branch
- Merge after authority pressure with open `- [ ]` on Fixes #N
- Merging despite **high** Privacy/Secrets findings without explicit user confirmation
- Ignoring local paths, credentials, or closed-source project names in the diff
- Using open Spec primary / `label:epic` as cover for unfinished Fixes land
- Rewriting hand-created issue bodies at land to green the gate

## Verification

**Before merge:**

- [ ] Target resolved unambiguously
- [ ] Base updated (unless skipped); not CONFLICTING
- [ ] `alignment-check.sh` pass (or profile-appropriate); DoD honesty (Iron Law)
- [ ] Mini-review scan ran (default-on): material findings → `AskUserQuestion`; advice not gate; no auto-fix
- [ ] Issue Acceptance checkboxes match binder + diff when Fixes closes (**Lattice-template issues**); **adopted** binders: binder Acceptance checked/deferred — do not rewrite hand-created issue body
- [ ] Land-time Spec drift cleared (or deferred/follow-up explicit) when `Spec:` / Spec-bound tickets apply

**After merge:**

- [ ] PR merged|closed; local branch gone; worktree removed
- [ ] Remote head gone unless `--keep-remote`
- [ ] `close-fixed-issues.sh --pr N --expected-closing-ids <approved-set>` ran; the set matched and all actionable local PR-body delivery issues are CLOSED
- [ ] Binder `## Finish` ledger stamped on merge base (mergedAt + prs + status); idempotent; no-binder skipped not failed
- [ ] Spec primary: if workstream complete → closed (or explicit hold); if not complete → still open **and** residual work tracked
- [ ] Adopted Fixes issues: optional one settlement comment if body left append-only
