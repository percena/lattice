# finish-work policy (portable)

Shipped with `finish-work`. No monorepo docs required.

## Contents

- [Target resolution (prefer explicit)](#target-resolution-prefer-explicit)
- [Cleanup](#cleanup)
- [Scripts hygiene](#scripts-hygiene)
- [Base update (before merge)](#base-update-before-merge)
- [Definition of Done (standing bar)](#definition-of-done-standing-bar)
- [Artifact alignment (required before merge)](#artifact-alignment-required-before-merge)
- [Lineage (best-effort, after merge)](#lineage-best-effort-after-merge)
- [Profile](#profile)

## Target resolution (prefer explicit)

| Input | Resolve |
| --- | --- |
| `pr N` / `pr-N` | `gh pr view N` |
| `tkt N` / `#N` | Open PR with head `tkt-N-*` or `*/tkt-N-*` or body Fixes/Refs #N |
| `spc N` / `spc-N` | Open PR with head `spc-N-*` or `*/spc-N-*` or body `Spec: spc-N` |
| `--branch name` | PR for that head or cleanup only |
| none | Current branch PR only if unambiguous |

## Cleanup

- Prefer `gh pr merge --squash --delete-branch`  
- If local `gh` fails while checking out main but `gh pr view` shows **MERGED**, continue cleanup  
- After merge: `git -C MAIN_ROOT pull --ff-only` (do not require feature worktree to switch to main)  
- Worktrees: sibling `*.worktrees/` (`WORKTREE_ROOT`); also discover legacy in-repo `.worktrees`  
- **Ref-specific proof** (`cleanup-workspace.sh`): observe local and remote refs independently. Local ancestry or local merged-PR proof authorizes only that exact local OID. It may authorize the remote only when the observed remote OID is identical; otherwise the remote needs its own matching `headRefOid` proof or explicit `--force`.
- **Atomic deletion:** local deletion uses `git update-ref -d <ref> <expected-oid>`; remote deletion uses `--force-with-lease=<ref>:<expected-oid>`. A local or remote ref that changes after proof is preserved and cleanup returns `ok:false`; an initially absent remote is re-probed so absent→present races are also reported as residual. Name-only MERGED proof is never sufficient after branch reuse.
- **Delayed `--pr` cleanup:** compare each extant local/remote tip with the PR `headRefOid`. One matching ref does not make a divergent same-named ref safe. `--force` remains explicit destructive authority, but deletion is still OID-leased and protected names remain blocked.
- **`--dry-run` honesty:** dry-run stays offline for remotes. Dirty non-force or unsafe local paths report `ok:false` without false worktree/local-delete flags; remote output states that it was not probed. Treat dry-run JSON as conditional planning evidence, not completed cleanup.
- **Checked-out refs:** after intended worktree removal, cleanup re-scans all worktrees before local plumbing deletion. `--keep-worktree`, a wrong explicit path, or an additional forced checkout cannot leave a worktree with an invalid HEAD; the local ref is preserved and cleanup reports the residual. Remote cleanup remains independently governed by its own exact-OID proof.
- After cleanup, confirm remote is gone (`git ls-remote --heads origin <branch>` empty or JSON `deleted_remote_branch` / `remote branch absent`); residual remote is a finish defect unless `--keep-remote`.  
- Never force-delete dirty tree without user OK  
- Never guess among multiple PRs  
- CI empty-step ≤~5s failures: suspect infra; preserve local evidence and require an explicit user decision before any merge override
- **Base residue:** `cleanup-workspace` runs `check-base-residue.sh` on MAIN. If uncommitted `.lattice` dirt remains, warn and surface items — often pre-worktree binder pollution. Discard accidental dirt before pull; only commit intentional finish bookkeeping on base after merge. **The binder `## Finish` ledger is exactly such bookkeeping** — `finish-ledger.sh` stamps it on the merge base post-merge (two-phase: cleanup removed the worktree first); this commit is expected, not residue.  


## Scripts hygiene

New or edited `*.sh` in this skill: run `bash -n` before commit; `shellcheck -S warning` when available.

## Base update (before merge)

- Honor PR **`baseRefName`** (main/dev/…).  
- Default: `scripts/update-pr-base.sh --pr N` → GitHub `updatePullRequestBranch` mutation with the inspected PR `headRefOid` as `expectedHeadOid`.
- Default path only mutates from an explicit `BEHIND` state; command errors are failures, never text-matched noops; refreshed state must be verified up to date.
- Optional: `--rebase` → same-repository heads only; require both fetch and push URLs of Git remote `origin` to resolve to that same repository, reject the live default branch and forks, fetch explicit refs, match fetched head to the PR `headRefOid`, then rebase onto `origin/<base>` + **OID-qualified force-with-lease** on the feature head only.
- `--no-update-branch` skips update; still refuse `CONFLICTING`.  
- Multi-worktree: **one PR per finish**; no batch rebase of all trees.  
- Unknown identity, mergeability, or post-update state fails closed; never force-push the default branch.

## Definition of Done (standing bar)

Green CI and checked Acceptance are necessary but not the whole story. Use the portable **Definition of Done**:

`skills/_lattice-lib/references/definition-of-done.md`

DoD is the standing “ready” bar; Spec `A*` is per-slice “right thing.” Do not merge solely because checks are green when DoD honesty items fail (e.g. claimed tests never run, Acceptance checked without implementing).

## Artifact alignment (required before merge)

Green checks ≠ ready to land. Before `gh pr merge`:

1. Run **`scripts/alignment-check.sh --pr N`** (HARD gaps → fix/stop; portable, no auto-edits).  
2. Cross-check every artifact that claims this land against the **actual PR diff**:

| Check | Must hold |
| --- | --- |
| Outcome / Why | Issue, PR, binder TL;DR, Spec/Review (if any) name the same problem and fix |
| Acceptance ↔ diff | Each open Acceptance item is done by the diff (check off **issue + binder** before merge when `Fixes`/`Closes`/`Resolves` **and** issue is Lattice-template-owned), explicitly deferred/out-of-scope on the box line, or has a follow-up ticket — never silent-drop. `alignment-check.sh` HARD-fails open non-deferred boxes on Fixes-closed issues |
| **Adopted Acceptance SoT** | Binder table field `adopted: true` (or equivalent): **binder** Acceptance is HARD SoT. **Do not** rewrite hand-created issue body to pass the gate. Prefer GH **comment** settlement after checks. `alignment-check` skips issue↔binder stale-sync HARD for adopted binders (still HARD on binder open boxes) |
| Paths & homes | Cited paths exist on the tip (or the rename target); Reviews under `.lattice/reviews/` (flat) |
| Lineage edges | `Fixes`/`Refs` match the issues; no contradictory binder/Spec/Review edges |
| Post-merge issue close | After merge, every OPEN **actionable local delivery** issue named by executable PR-body `Fixes`/`Closes`/`Resolves` is closed via `close-fixed-issues.sh` (GitHub auto-close only on default-branch merge; helper still requires proven `MERGED` + `mergedAt`). `Refs` is never auto-closed. Fenced examples are not executable. HARD fail finish only if an actionable local delivery issue remains OPEN. Spec-primary/`label:epic` and unsupported repository-qualified refs are **exclusions** — report (`skipped_epic` / `unsupported_references`), do not helper-close |
| Land-time Spec drift | When `Spec: spc-N` (or Spec-bound Fixes) apply: load Spec + claimed tickets + diff; unresolved drift blocks merge. Distinct from create-tickets **POST_SPLIT**. Multi-PR: only this PR’s claimed covers. **No merge / no dishonest Fixes close** — remediate commits, tickets, or Spec (not epic-as-buffer) |
| Status honesty | Do not merge while issue/binder still promise a superseded contract |
| Titles | Issue / PR / binder identity agree after any scope pivot |
| Finish target | `tkt` / `spc` / `pr` / branch resolve **one** open PR — never batch-merge all PRs under a Spec |

**On drift:** edit issue/PR/binder (or stop and ask) **before** merge. Chat agreement without durable edits does not count. `--dry-run` still surfaces the drift list.

**Causal rule:** unresolved land-time Spec drift ⇒ **do not merge** and **do not** dishonestly `Fixes`-close delivery tickets. Remediation: update tickets / add tickets / amend Spec — **not** “leave Spec primary open and ship half.”

**Remediation ladder:** small → ticket/binder + commits; material → stop + create-tickets; Spec wrong → amend/supersede Spec first.

Load: `gh issue view` for each linked issue; binder under `.lattice/tickets/tkt-N-*/` (flat; closed binders stay in place); Spec/Review paths cited on PR or issue.

**Hooks (Claude-only):** optional lattice plugin advises on bare `gh pr merge`; `LATTICE_HOOK_MODE=strict` opts into marker-based blocking. Skills remain correct without hooks (Codex).

## Lineage (best-effort, after merge)

When `.lattice` binders exist:

1. **One** `## Finish` ledger on the ticket binder (replace pre-merge text; never stack a second heading)
2. Record firm GH dates: `pr-N merged: YYYY-MM-DD — <url>` (`gh pr view --json mergedAt`); issue closed date when closed
3. Flip binder `status`/TL;DR to `closed` only if the GitHub issue is closed
4. Check off Acceptance land items on binder **only if** pre-merge alignment already verified them against the diff **and** the GitHub issue body was updated the same way before merge; rewrite Notes so they no longer claim “open PRs”
5. Spec `prs:` / Review `related_prs` if missing this land’s ids; fix binder paths after renames
6. After binder edits, keep L0 accurate in the same commit when possible; do not invent ADR graph nodes — ADRs live under `docs/adr/`. Bloodline = L0 + GitHub.
7. **Spec primary close (completion-causal):** if the workstream is **actually complete** (all Spec `A*` done/deferred; no honest open delivery work left), **close** `#<primary>` and set Spec `status: done` (unless operator explicitly holds). If **not** complete → do **not** close; remediate with commits/tickets/Spec amend. Scripts must not blind-close on sub-issue count alone (progress ≠ Acceptance). “Out of `close-fixed-issues` path” ≠ “leave completed epic OPEN.”

## Profile

`alignment-check.sh` reads `LATTICE_PROFILE` or `.lattice/config.yaml` `profile:`.

| Profile | Open Acceptance on Fixes/Closes |
| --- | --- |
| **strict** (default) | **HARD** — exit 1 until checked off / deferred |
| **light** | **WARN** — exit 0; agent should still sync issue/binder when possible |

Draft / CONFLICTING / empty title remain HARD in all profiles.
