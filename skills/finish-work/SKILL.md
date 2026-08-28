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
| Full preflight / alignment dimensions / land-time drift / **mini-review full text (§2.7)** / **sequential merge queue (§3.4)** | `references/flow.md` |
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
- [ ] **Batch-work marker gate:** if `.lattice/.batch-work-active` marker file exists in the worktree → refuse `gh pr merge`; print "batch-work marker is present — batch-work agents may only create-pr; human must run finish-work after review"; stop (do not merge). Proceed only when the marker is absent. After a successful human-driven merge, remove the marker.
- [ ] Base updated (unless `--no-update-branch`); not CONFLICTING
- [ ] **Rebase-verdict rule (machine signal):** `update-pr-base.sh` JSON `diff_changed:true` **or** `conflict:true` → any prior review verdict (review-delivery digest triage or an earlier mini-review result) is **VOID** — re-run the mini-review before merge. Both `false` (clean/noop update) → the verdict carries unchanged (ADR-004 §4; flow.md §2.7)
- [ ] `alignment-check.sh --json` + human dimensions; retain its approved `closing_ids` through merge; **land-time Spec drift** when `Spec:` / Spec-bound Fixes apply; DoD honesty — drift ⇒ remediate (a) commits (b) tickets (c) Spec, **no merge**
- [ ] **Mini-review scan (default-on):** load PR diff, 5-axis light scan, present material findings, `AskUserQuestion` on material items (high → default Hold); advice, **not** a gate — HARD gate stays alignment-check
- [ ] **Sequential merge queue (multi-PR landing):** before **each** merge in the queue, `gh pr checks <N>` rollup — fail/pending surfaced to the operator (distinguish transient CI reds from real failures), never merge on `mergeable` alone; conflicts resolved **file-explicit only** (`git checkout --ours`/`--theirs` per named path — `git add -A` forbidden); post-merge `grep -rn '<<<<<<<'` over touched paths; in-flight head-branch runs waited-for or `gh run cancel`-ed before `--delete-branch` (flow.md §3.4)
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
8. **Batch-work marker gate** — `.lattice/.batch-work-active` marker file present → refuse `gh pr merge`; print guidance: "batch-work marker is present — batch-work agents may only create-pr; human must run finish-work after review". The operator must remove the marker (or confirm it was not set by batch-work) before this skill may merge. After a successful human-driven merge, the marker is removed.

### DEFAULT

9. Prefer `gh pr merge --squash --delete-branch` over raw `git merge` on main — **not sufficient alone** when a sibling worktree still checks out the head (`gh` cannot delete a checked-out branch; many repos set `delete_branch_on_merge: false`).
10. **After every merge|close (mandatory):** run `cleanup-workspace.sh --branch <HEAD_BRANCH> --pr <PR_N>` after a merge (and `--worktree-path` when known). A close-without-merge preserves unmerged branches unless the user explicitly authorizes `--force`. The helper observes local and remote tips separately before destructive work, removes the worktree, compare-and-deletes the exact proven local OID, then deletes the exact proven remote OID with a lease. Do **not** stop at the merge step.
11. Base update via `update-pr-base.sh` unless `--no-update-branch` / `--close`.
12. Report must include cleanup JSON: `deleted_remote_branch` / `remote_residual` / `ok`. If `ok:false` or remote head still listed → treat finish as **failed**, fix residual, re-run cleanup.
13. **After every successful merge (mandatory):** run `close-fixed-issues.sh --pr <N> --expected-closing-ids <pre-merge alignment set>`. A changed set fails closed before issue operations. Do not trust GitHub auto-close when PR base ≠ repo default branch.
14. Operator states a durable work preference during merge/hold decisions → write it to `.lattice/preferences.md` at utterance time + one-line confirm (`../_lattice-lib/references/decision-policy.md` §Capture duty).
15. **Red-run disposition before merge:** every failed/errored CI run on the PR branch (not just the latest rollup) gets one disposition line in the binder — `transient` (platform outage, version race, superseded push — say which) or `real` (what fixed it). A later green does not retire a red unexamined; pairs with the CI smart-retry DEFAULT in `.lattice/preferences.md`.
16. Defect noticed outside the ticket's `paths` during finish → write `- NOTICED: <path> — <one line> (out-of-paths, <date>)` to the active binder `## Notes` at notice time, then move on — never expand the merge (`../_lattice-lib/references/decision-policy.md` §Observation duty).

### HINT

17. `--dry-run` when unsure; report remote residual if delete fails.
18. CI empty-step flake heuristic — see `flow.md` preflight.
19. Squash tips are often not ancestors of base — `--pr <PR_N>` verifies the matching same-repository PR, then binds local and remote authorization independently to refs that still equal `headRefOid`. Local ancestry proof can carry to the remote only when both observed refs are the same exact OID. Compare-and-delete / remote lease failures preserve a ref that changed after proof, and an initially absent remote is re-probed before success. Protected names (`main`/`dev`/…) are never deleted locally or remotely. Dirty non-force `--dry-run` reports blocked without claiming removal; remote dry-run stays explicitly unprobed.

## Short path

1. Resolve target → record PR_N / HEAD / BASE.
2. **Batch-work marker gate:** if `.lattice/.batch-work-active` marker exists in the worktree → refuse `gh pr merge`; print "batch-work marker is present — batch-work agents may only create-pr; human must run finish-work after review" and stop (do not merge, do not proceed to base update). Proceed only when the marker is absent. After a successful human-driven merge, remove the marker.
3. Preflight (draft, checks, mergeable). **Red-run disposition (DEFAULT 15):** list the branch's failed runs (`gh run list --branch <HEAD>`) and disposition each in the binder — transient vs real, one line each — before relying on the green rollup. **Base-mismatch advice:** if `BASE` (PR base) ≠ the user's current integration branch (long-lived, e.g. on `dev` but PR targets `main`), surface a one-line warning **before** `gh pr merge` and let the operator confirm or switch. Advice only — HARD gate stays `alignment-check.sh`.
4. `update-pr-base.sh --pr N` (unless skipped). Record `diff_changed` + `conflict` from its JSON — they decide verdict validity in step 6.
5. `alignment-check.sh --pr N` + dimension fix/stop; **land-time Spec drift** when applicable; print `alignment:` line.
6. **Mini-review scan (default-on):** load PR diff (`gh pr diff N` or `git diff <BASE>...HEAD`), 5-axis light scan, present material findings, `AskUserQuestion` on material items (any high → default recommended `Hold`; only med/low → default `Merge anyway`); advice, **not** a gate — HARD gate stays alignment-check. See **§ Mini-review (embedded)** summary here + authoritative full text `references/flow.md` §2.7. Proceed on no findings or operator `Merge anyway`. **Verdict validity:** a prior verdict skips the re-scan only when step 4's JSON shows `diff_changed:false` **and** `conflict:false` — either `true` voids it (rebase-verdict rule above). Operator `Hold` naming findings → stamp binder `status: rework` (flow.md §2.7 Decision).
7. `gh pr merge` or `gh pr close`.
8. **After merge:** `close-fixed-issues.sh --pr N --expected-closing-ids <approved-set>` (required) — refuse a changed closing set, then close OPEN actionable local delivery issues only; skip and report Spec-primary/`epic` plus unsupported repository-qualified references.
9. **`cleanup-workspace.sh --branch HEAD --pr N …` (required after merge)** — not optional after a “successful” merge; close-without-merge does not imply branch deletion authority.
10. **Binder `## Finish` ledger (REQUIRED).** After cleanup (step 9), `cd` to the **main checkout**, switch to the **PR merge base** (`git checkout <base>` + pull), and run `finish-ledger.sh --pr <PR_N> --issue <closing_M> --binder <.lattice/tickets/tkt-M-*/README.md> [--repo owner/repo]`. It stamps firm GH dates (`mergedAt`/`closedAt`) + `prs` + `status: closed` into the binder idempotently (never a second `## Finish`), then commit + push the base branch. **Two-phase:** cleanup removes the worktree, so the ledger is a post-merge commit on the base branch (policy.md:41). **No binder** (ticket-only flow) → `finish-ledger.sh` skips with a note, finish does not fail. **Closed-without-merge** → the helper reads the PR state itself and records `closed without merge` **without** claiming `mergedAt`; `status` flips to `closed` only when a closing issue actually closed. **Cancel before any PR** → `finish-ledger.sh --cancel --reason "<text>" (--closed-at <ts> | --issue <M>) --binder <path>` writes a dated cancel ledger line with no PR row and no `mergedAt` claim; requires explicit human-supplied reason and either a firm close time or a gh-verified CLOSED issue (an OPEN/unverifiable issue fails closed). The `status` flip covers the **full working vocabulary** (`queued|in-progress|parked|stuck|pr-open|rework|deferred` + legacy `open`) — terminal evidence must not strand a binder in `parked`/`stuck`/`deferred`. A **MERGED** PR observed from `parked`/`stuck`/`deferred` flips to `closed` (external truth wins) and emits an `anomaly:` ledger line recording the unexpected prior state. An **OPEN** PR is refused (the ledger records outcomes, not intentions). The helper also refuses to stamp a PR from a repository other than the binder's own origin. Spec primary close (when workstream complete) is separate.
11. Report URL + cleanup + **actionable local delivery issues closed** + **epic/unsupported exclusions reported** + Spec-primary suggestion (if any) + **assert remote gone**.

Full step text: **`references/flow.md`**. Policy tables: **`references/policy.md`**.

## Mini-review (embedded, default-on)

**Authoritative full text: `references/flow.md` §2.7 — load it before running the scan.** This is the compact contract summary; every line below is an invariant preserved verbatim in the full text:

- **Advice-only, never a gate** — findings never auto-block merge; the HARD gate stays `alignment-check.sh`. Alignment remains the only HARD merge gate.
- Runs after alignment-check (HARD gate) and before merge, over the already-resolved PR diff only (`gh pr diff <PR_N>` or `git diff <BASE>...HEAD`) — never widened to whole-repo architecture.
- **5 axes** (diff-touched only): Correctness · High-cost failure · Tests · Dig deeper · Privacy/Secrets. Material findings only — severity + one-line failure scenario + evidence; empty list is OK (`mini-review: no material findings`).
- Material findings → `AskUserQuestion` (`Merge anyway` / `Hold (I'll address)` / `Invoke full /review-code`). Any **high** finding — including credential/secret leak — defaults to `Hold`; only med/low → default `Merge anyway`. **Privacy/Secrets override:** privacy **high** (credentials, API keys, private keys) defaults to `Hold` regardless of other axes; **medium** (local paths, project names) → recommend cleanup, allow `Merge anyway` after explicit confirmation.
- **Hard stop on edits:** never auto-fix, even "obvious" findings — edit only when the operator explicitly names which findings to fix.
- Operator `Hold` **naming findings to return** → stamp binder `status: rework` + record the findings as the new brief (bookkeeping on a durable artifact, not a gate).
- **Rebase-verdict rule (machine signal):** `update-pr-base.sh` JSON `diff_changed:true` **or** `conflict:true` ⇒ any prior review verdict is **VOID** → re-run the mini-review before merge; both `false` ⇒ the verdict carries unchanged. No signal (skipped update) → treat as VOID unless the operator asserts the diff is unchanged.
- **Why this and `/review-code` both exist:** the mini is a bounded merge-time subset of the same finding contract (no persistence); `/review-code` stays the full superset for pre-`create-pr` / dedicated passes. Overlap is intentional, not a parallel contract.

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
| "verdict was from last night — still valid after rebase" | `diff_changed:true` or `conflict:true` from update-pr-base voids any prior verdict; re-run the mini-review. Only both-false (clean/noop update) carries it |
| "mergeable=MERGEABLE means safe to merge" | Mergeable is a git-tree statement, not a CI verdict — the `gh pr checks` rollup is part of preflight; surface fail/pending and distinguish transient CI reds from real failures before any merge |
| "add -A is faster during conflicts" | File-explicit only: `git checkout --ours`/`--theirs` per named conflicted path, then `git add <path>`; `git add -A` staged raw conflict markers into dev (repair 628e4cb) |
| "operator held the PR — state is obvious from the open PR" | State is never inferred from PR existence (ADR-004 §6); Hold with named findings stamps binder `status: rework` so resume finds the brief |

## Red Flags

- Merge without `alignment-check.sh` when binders/Spec apply
- Sequential merge on `mergeable` alone with a red/pending checks rollup
- `git add -A` (or blanket staging) during conflict resolution
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
- [ ] `diff_changed`/`conflict` from the base-update JSON read and honored: either `true` → prior verdict voided and mini-review re-run; both `false` → verdict carried (state which)
- [ ] Sequential merge queue: `gh pr checks <N>` rollup fetched before **each** merge in the queue; fail/pending surfaced (transient CI reds vs real failures distinguished); never merged on `mergeable` alone
- [ ] Operator `Hold` with named findings → binder stamped `status: rework` with the findings as the new brief
- [ ] Issue Acceptance checkboxes match binder + diff when Fixes closes (**Lattice-template issues**); **adopted** binders: binder Acceptance checked/deferred — do not rewrite hand-created issue body
- [ ] Land-time Spec drift cleared (or deferred/follow-up explicit) when `Spec:` / Spec-bound tickets apply

**After merge:**

- [ ] PR merged|closed; local branch gone; worktree removed
- [ ] Sequential merge queue: post-merge `grep -rn '<<<<<<<'` over the PR's touched paths clean; conflicts (if any) were resolved file-explicit; in-flight head runs waited-for or cancelled before branch deletion
- [ ] Remote head gone unless `--keep-remote`
- [ ] `close-fixed-issues.sh --pr N --expected-closing-ids <approved-set>` ran; the set matched and all actionable local PR-body delivery issues are CLOSED
- [ ] Binder `## Finish` ledger stamped on merge base (mergedAt + prs + status); idempotent; no-binder skipped not failed
- [ ] Spec primary: if workstream complete → closed (or explicit hold); if not complete → still open **and** residual work tracked
- [ ] Adopted Fixes issues: optional one settlement comment if body left append-only
