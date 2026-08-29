---
id: rev-20260829-140444Z
slug: spc186-dogfood-retrospective
title: "spc-186 dogfood retrospective — output-swallowing incident, recovery, and #196 close evaluation"
kind: dogfood
status: concluded
outcome: inform_only
summary: "Retrospective on the spc-186 hard-limit-closure delivery (9 tickets, all merged). A harness-level output-swallowing anomaly caused a cascade of false-success misreads (artifact loss, spec misnumbering, issue-body jumble), fully recovered. Evaluates whether bug #196 can close."
created: 2026-08-29
updated: 2026-08-29
related_specs:
  - spc-186
related_tickets:
  - tkt-196
related_prs:
  - pr-198
  - pr-202
  - pr-203
---

# spc-186 dogfood retrospective

## Problem audit

spc-186 (hard-limit closure, ADR-007 law) was delivered as a full dogfood of the Lattice loop: create-review → create-adr → create-spec → create-tickets → batch-work (5-layer DAG fan-out of 9 tickets) → finish-work per PR. The run was completed — all 9 tickets merged + closed + ledgered, spec status `done`, ci-local all green. But the run also surfaced a harness-level defect worth recording.

## Findings

### F1 — Output-swallowing anomaly (the incident)

The Claude Code Bash tool intermittently swallowed stdout/stderr for compound Bash commands (pattern: `cd <worktree> && ...` chains, heredocs with executable spans, `&&`-chained gh mutations). Exit codes were sometimes reported ("Command failed") with **zero output**, and sometimes partial output masked a failure as success. The agent (me) treated absent output as ambiguous and proceeded on **assumed success** for sequential dependent steps instead of treating nonzero/absent-output as hard failure.

Concrete misreads caused by this:
- `gh issue create` for #196: failed silently; the number was believed created.
- `gh pr create` for the spec PR (#197): failed silently — the PR never existed; a "197" token from a pre-existing commit message was mistaken for the created PR.
- `gh pr merge 197` against a non-existent PR: the reported "✓ merged" was phantom.
- `git commit`/`git push` in the spc-187 worktree: failed silently — commit objects `b8d2b65c`/`59dcfea9a` never existed in the object DB.
- `cleanup-workspace.sh` then removed the worktree, stranding the uncommitted artifacts.

### F2 — The cascade (artifacts lost + misnumbered)

- The spec's epic issue was actually **#186** (a prior-session "test-probe-delete-me" issue occupied #187). The spec was authored as `spc-187` (phantom number) — a team-id-law violation that cascaded to all 9 binders' `spec:` field, the spec file name, ADR-007 + rev references, and the L1 PR bodies.
- Issue bodies for #188–#195 were systematically jumbled (each ticket's body mis-paired to the wrong issue number) — the same output-swallowing class.
- tkt-195 and tkt-196 binders referenced issue numbers (#195, #196) that were occupied by a PR and the bug ticket respectively — requiring renumber to tkt-201/tkt-200.

### F3 — Recovery (verified clean)

| Action | PR |
|---|---|
| Recover spec/ADR-007/rev from the orphan worktree dir; place at repo-root paths | #198 |
| Renumber spc-187 → spc-186 across dev + 3 L1 branches + ADR + rev + epic title; close junk #187 | #202 |
| Rename binder dirs tkt-195→tkt-201, tkt-196→tkt-200 (dir N = issue N) | #203 |
| Fix L1 regression: bats assertion ergonomics (bare `! cmd`/`[[ ]]`) | #204 |

Final verified state (post-review, this rev):
- dev tree: **0** `spc-187` references; **0** nested `.lattice-worktrees` tracked; ci-local all green.
- 9 binders: all `status: closed`, `## Finish` ledger present, `prs` + `github` fields correct.
- Issues #186 (epic), #188–#194, #200, #201 all CLOSED; #187 (junk probe) CLOSED.
- All PRs #195–#210 MERGED.

### F4 — What held up (positive confirmations)

- **ADR-007 five-piece contract** — every shipped hard rule (marker gate, CI gate, fix_cycles cap, supersede sweep, stamp-pr-open guard) carried check/message/escape/trace/metric. The law proved implementable across 9 tickets without contradiction.
- **The review-before-continue checkpoint pattern** — the user's "先做 Review 操作" instruction caught the bats-assertion regression (PR #204) and the spc-187 workflow-fsm residual that late-merging tickets reintroduced. Independent `ci-local` + `git grep` verification (not trusting agent self-reports) was the decisive tool.
- **The marker gate** — once tkt-188 merged, the `.batch-work-active` marker machine-enforcement was live and correctly blocked merges during the batch.
- **`-X theirs` rebase** — resolved L1 binder add/add conflicts cleanly when dev and a branch both held a binder.

### F5 — What didn't hold up (the failures)

- **Trusting swallowed/absent output as success.** The single highest-leverage process lesson: any Bash command with nonzero exit OR absent output must be treated as HARD failure, never "ambiguous, proceed." Every gh mutation should be followed in-turn by a `gh ... view` verification.
- **Compound Bash commands** (cd + heredoc + `&&`) are the failure-prone shape in this harness. Single-purpose commands or `--body-file` for multi-line content are materially safer.
- **Late-merging tickets reintroducing stale references.** A renumber sweep that runs before a dependent PR merges can be undone by that PR's content. A post-merge re-scan (e.g., `git grep spc-187`) is needed after each layer, not just once.

## Evaluation: can bug #196 close?

**Verdict: YES — #196 can close.**

Rationale:
1. **Impact fully resolved.** All artifacts the bug described as "lost" (spc-186 spec, ADR-007, rev-20260829-160834Z, 9 binders) are landed correctly on dev at the right paths, verified by ci-local + cross-check (this rev's F3).
2. **Root cause is harness-level, not Lattice code.** The output-swallowing is a Claude Code Bash-tool environment behavior, not a defect in any Lattice script/skill. There is no Lattice code change that "fixes" it; the fix is operational (the process lesson in F5).
3. **Process lesson recorded.** F5 captures the verification discipline; ADR-007 §8 (escape metrics) + the new staleness sensor (tkt-192) already provide the surfacing infrastructure for "silent failure" detection.
4. **No remaining open issue.** The re-scan (F3) confirms 0 residual spc-187, 0 nested junk, all binders closed+ledgered.

The bug ticket's purpose — track the incident + ensure recovery — is fulfilled. Closing #196 is honest: the impact is gone, the lesson stays.

## Follow-up consideration (NOT spawned — for operator decision)

A potential hardening ticket (not filed here, awaiting operator direction): **batch-work / finish-work "verify-after-mutate" discipline** — after every `gh pr create`/`gh pr merge`/`git push`, the orchestrator should run a confirming `gh pr view`/`git ls-remote` in the same turn and treat absence as failure. This would mechanize the F5 lesson at the batch-work layer (currently the spawn briefs advise it but don't enforce it). This is a defense-in-depth improvement, not a bug fix. If the operator wants it, it becomes a new ticket; otherwise it lives as the recorded lesson.

## Decision

- Close #196 (impact resolved; root cause out of Lattice scope; lesson recorded here).
- spc-186 program is COMPLETE (spec `done`, #186 closed, 9 tickets delivered, ADR-007 operationalized).

## Evidence

- `tools/ci-local.sh` → all steps green (on dev `a10bd81`).
- `git grep spc-187 HEAD` → 0.
- 9 binders cross-checked (status/ledger/prs/github) — all aligned.
- GitHub issues #186–#201 cross-checked — all expected CLOSED.

## Log

- 2026-08-29: retrospective authored after spc-186 completion + final review. Residual spc-187 in workflow-fsm.md (reintroduced by tkt-189 post-renumber) found and fixed in the same review pass.
