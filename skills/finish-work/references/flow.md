# finish-work full flow (reference)

**Progressive disclosure:** day-to-day use short `../SKILL.md`. This file holds step narrative.  
**Policy:** `policy.md` · **Constraints:** `../../_lattice-lib/references/constraint-language.md` · **DoD:** `../../_lattice-lib/references/definition-of-done.md`

Labels: **INVARIANT** · **DEFAULT** · **HINT**.

---

## Contents

- [1. Resolve target PR (INVARIANT: no multi-PR guess)](#1-resolve-target-pr-invariant-no-multi-pr-guess)
- [2. Preflight (CI + machine)](#2-preflight-ci-machine)
- [2.4 Base update (DEFAULT unless `--no-update-branch` / `--close`)](#24-base-update-default-unless---no-update-branch---close)
- [2.5 Artifact alignment (INVARIANT before merge)](#25-artifact-alignment-invariant-before-merge)
- [2.6 Land-time Spec drift (INVARIANT when Spec applies)](#26-land-time-spec-drift-invariant-when-spec-applies)
- [2.7 Mini-review scan (DEFAULT-on, advice-only — embedded)](#27-mini-review-scan-default-on-advice-only--embedded)
- [3. Merge or close](#3-merge-or-close)
- [3.5 Close Fixes issues (mandatory after successful **merge**)](#35-close-fixes-issues-mandatory-after-successful-merge)
- [3.6 Spec primary close (completion-causal)](#36-spec-primary-close-completion-causal--after-last-honest-delivery-land)
- [4. Cleanup workspace (mandatory after merge|close)](#4-cleanup-workspace-mandatory-after-mergeclose)
- [5. Lineage bookkeeping (when Lattice exists)](#5-lineage-bookkeeping-when-lattice-exists)
- [6. Report](#6-report)
- [Examples](#examples)

## 1. Resolve target PR (INVARIANT: no multi-PR guess)

```bash
gh pr view <N> --json number,url,state,title,headRefName,baseRefName,mergeable,isDraft,body
# or: gh pr view  # current branch only if unambiguous
# ticket/spec: gh pr list --state open --json number,headRefName,body,url
# match head tkt-N-* | */tkt-N-* | body Fixes/Refs #N | Spec: spc-N
```

No PR → `create-pr`. Multiple matches → batch-list once; do not pick silently.  
Record: `PR_N`, `HEAD_BRANCH`, `BASE`, `URL`, optional `TKT_ID`.

## 2. Preflight (CI + machine)

- Draft → do not merge until ready.
- Checks: report failing/pending; stop unless user overrides.
- CI empty-step ≤~5s + same failure on unrelated main → infra flake; re-run once; local bats/shellcheck OK; never skip real failures with logs.
- Base = PR `baseRefName` (not always `main`).
- CONFLICTING before update → stop (unless about to `--rebase` in feature worktree you control).
- Collect lineage pointers from PR body (do not invent).
- Finish **one PR at a time**.

## 2.4 Base update (DEFAULT unless `--no-update-branch` / `--close`)

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
bash "$SKILL_ROOT/scripts/update-pr-base.sh" --pr "<PR_N>"
# optional linear: … --rebase
# preview: … --dry-run
```

| Result | Action |
| --- | --- |
| ok / already up to date | Continue |
| conflicting / rebase conflict | **Stop**; resolve in feature worktree; never force-push default branch |
| update_failed | Surface `gh` message |
| fork/default-head/OID mismatch/unknown or still-behind state | **Stop**; refresh PR identity/state or use the owning checkout; never infer success from error text |
| `--no-update-branch` | Skip script; still refuse CONFLICTING |

**Record whether the update materially changed the diff** — merge/rebase hit conflicts, or the post-update diff differs from the previously reviewed diff beyond trivial context lines. §2.7 uses this to decide verdict validity (rebase-verdict rule, ADR-004 §4). HINT: `git range-diff <old-base>..<old-head> <new-base>..<new-head>` helps judge triviality.

## 2.5 Artifact alignment (INVARIANT before merge)

Green CI ≠ ready. Cross-check contracts against **actual diff**.

**Load when each exists:** PR (+ `git diff <base>...HEAD --stat`) · `gh issue view` for Fixes/Refs · binder `.lattice/tickets/tkt-N-*/` (flat) · Spec · Review.

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
ALIGNMENT_JSON=$(bash "$SKILL_ROOT/scripts/alignment-check.sh" --pr "<PR_N>" --json)
APPROVED_CLOSING_IDS=$(printf '%s' "$ALIGNMENT_JSON" | jq -r '.closing_ids | join(",")')
# Retain APPROVED_CLOSING_IDS as merge-decision evidence for §3.5.
```

Exit 1 / HARD gaps → fix or stop. Exit 0 → still run human dimensions (Acceptance↔diff not fully automated).

**Dimensions (all must hold or be fixed):**

1. **Outcome / Why** — issue, PR, binder, Spec/Review name the same problem and fix.
2. **Acceptance ↔ diff** — open boxes: satisfied → check off issue+binder before merge when Fixes/Closes **and** issue is Lattice-owned; deferred on the line; or follow-up ticket. Never silent-drop. alignment-check HARD on open non-deferred Fixes boxes.
3. **Adopted tickets** — binder `adopted: true`: **binder-first** Acceptance HARD; do **not** rewrite hand-created issue body; optional settlement **comment**. alignment-check does not HARD-fail issue↔binder checkbox desync for adopted binders.
4. **Paths & homes** — cited paths exist on tip; reviews in-flight under `.lattice/reviews/`.
5. **Lineage edges** — Fixes/Refs match; no contradictory edges (missing OK to fill post-merge).
6. **Status honesty** — do not merge while issue/binder promise a superseded contract.
7. **Titles** — issue / PR / binder identity agree after pivot.
8. **Land-time Spec drift** (when `Spec: spc-N` or Spec-bound Fixes apply) — see §2.6.

| Severity | Action |
| --- | --- |
| Fixable in-session | Edit issue/PR/binder before merge; re-run alignment-check |
| Needs product decision | Stop; batch-ask once |
| `--dry-run` | Still print drift; do not claim ready if misaligned |

Chat-only alignment does not count. Print `alignment: ok (…)` or residual gaps.

## 2.6 Land-time Spec drift (INVARIANT when Spec applies)

**Distinct from** create-tickets **POST_SPLIT_CHECK** (split-time Spec↔tickets before EXECUTE). Land-time asks: did EXECUTE/PR still honor Spec + **this PR’s claimed** tickets/diff?

**When:** PR body has `Spec: spc-N` and/or `Fixes`/`Closes`/`Resolves` delivery tickets under that Spec (binders with `spec:` / `covers`).

**Do:**

1. Load Spec file (`A*`, In/Out, Decisions) when present.
2. Load each closing-keyword issue + binder (`covers`, Acceptance).
3. Cross-check **claimed covers/Acceptance ↔ actual PR diff** (human; machine assists via `alignment-check.sh`).
4. Multi-PR ships: only this PR’s claimed A*/tickets — do **not** re-partition the whole Spec.

**Unresolved drift ⇒ do not merge** and **do not** treat delivery tickets as honestly closable via `Fixes`. Leaving Spec primary (`label:epic`) open is **not** a buffer for half-done land. Prefer **new commits** or **explicit user intervention** over closing/abandoning the PR without honesty.

**Remediation ladder (DEFAULT):**

| Drift | Action |
| --- | --- |
| Small | Edit ticket/binder Acceptance + PR commits; re-run alignment-check. **Adopted:** update binder only (+ optional comment), not issue body |
| Material gap | **Stop merge**; file/adjust delivery tickets (`create-tickets`); do not `Fixes`-close unfinished work; notify user of residual gaps |
| Spec wrong | Amend Spec Decisions/Acceptance (or supersede) **before** claiming land complete |

Report residual gaps to the user. `alignment-check` may HARD on machine-decidable honesty (e.g. missing Spec file when `Spec:` cited) and WARN on covers assist; full AC↔diff remains `human_required`.

## 2.7 Mini-review scan (DEFAULT-on, advice-only — embedded)

A bounded code-review scan at the merge decision point — a **compressed projection** of the standalone `/review-code` finding contract (same stance, same material bar, compressed axes/output). Runs **after** §2.5/§2.6 alignment (the HARD gate) and **before** §3 merge. **Never** a HARD gate; the HARD gate stays `alignment-check.sh`.

**Why embedded:** operators almost always want a quick correctness scan of the diff before merge but rarely invoke `/review-code` at merge time. The embedded mini removes that friction without weakening gate discipline — findings are advice, the operator decides.

### Unit

Reuse the PR diff already resolved in §1 (no separate target resolution): `gh pr diff <PR_N>` (or `git diff <BASE>...HEAD` when no PR yet). Do not widen to whole-repo architecture; minimal related reads only, each with a one-line why.

### Axes (diff-touched only)

| Axis | Look for |
| --- | --- |
| Correctness | Logic errors, off-by-one, broken edge cases in **changed** paths |
| High-cost failure (if touched) | authz/trust · data loss/corruption · retry/idempotency · races · empty/timeout · schema/compat when migrations change — short list only |
| Tests | Clear gaps for **new** behavior; missing regression for a bug fix |
| Dig deeper | empty/null paths · partial failure/idempotency · stale state/ordering · rollback/irreversible writes — only where the diff touches |

Skip deep threat modeling, load testing, full coverage matrices (`review-production`).

### Material finding bar (compressed)

Report only **material** findings. Each row = severity + one-line failure scenario + evidence (`path:line` or symbol). Calibration: prefer one strong finding over several weak; empty material list is OK (print `mini-review: no material findings`); no nits in the material table (style/naming demoted or omitted). Mark **inference** when not direct from the diff.

### Output

```markdown
## mini-review · <pr-N>

**Overall:** proceed | fix-first
| Sev | Finding | Evidence |
| --- | --- | --- |
| high/med/low | <inputs/state → bad outcome, one line> | path:line |
```

`proceed` = no material issues; `fix-first` = material issues surfaced. Sort high first.

### Verdict validity across base updates (rebase-verdict rule)

A prior review verdict — a review-delivery digest triage (`auto-pass` / `ratify-then-pass`) or an earlier mini-review `proceed` — stands **only over the diff it reviewed** (ADR-004 §4):

| §2.4 base update was… | Verdict |
| --- | --- |
| **Material** — conflicts during merge/rebase, or post-update diff differs beyond trivial context lines | **VOID** — re-run this mini-review before §3 merge; do not merge on the stale verdict |
| **Clean** — no conflicts, diff unchanged beyond context lines | Carries unchanged — do not re-review out of ritual |

This is a validity condition on advice, not a new gate — the HARD gate stays `alignment-check.sh`.

### Decision (advice, never auto-block / never auto-fix)

- No material findings → one-line `mini-review: no material findings`; proceed to §3 merge.
- Material findings → print the table, then `AskUserQuestion`:
  - `Merge anyway` — operator accepts the risk
  - `Hold (I'll address)` — stop; operator fixes or defers. When the operator **names findings to return**, stamp the binder `status: rework` and record those findings as the new brief (binder note + PR review threads) — the `pr-open → rework` FSM edge (`docs/workflow-fsm.md`); `start-work` resume loads them as the brief and fixes on the same PR (fix cycle ≤2). The stamp records the operator's decision on a durable artifact — bookkeeping, not a gate.
  - `Invoke full /review-code` — deeper pass before deciding
- Any **high** finding → default recommended option `Hold`; only med/low → default `Merge anyway`.
- **Hard stop on edits:** present findings and stop. Do **not** auto-fix even if "obvious". Edit the tree only when the operator explicitly names which findings to fix (then smallest change in the change set's modules; fresh test output if tests requested).
- The HARD merge gate is unchanged — `alignment-check.sh`. Findings are advice; the operator may still choose `Merge anyway`.

### Boundary (do not cross)

- Findings **never** block merge automatically (advice, not gate).
- Do **not** widen to whole-repo architecture or drive-by refactors.
- Do **not** persist findings (PR comment / `rev`) — that stays in `/review-code` full skill.
- The standalone `/review-code` skill remains the full-function superset (full axes, 4-question bar, Confidence field, persistence, 5-mode target resolution, hard-stop-for-fixes) for pre-`create-pr` or dedicated review passes.

## 3. Merge or close

Prefer not forcing checkout of `main` when another worktree holds it.

```bash
gh pr merge <N> --squash --delete-branch
# if gh non-zero: gh pr view <N> --json state,mergedAt — MERGED → **still run §4 cleanup**
gh pr close <N> --comment "Closing without merge; cleaning workspace."
```

| Local symptom | Action |
| --- | --- |
| main already used by worktree | Ignore if MERGED; `git -C MAIN_ROOT pull --ff-only` |
| truly not merged | Stop |
| `gh --delete-branch` fails (branch in use by worktree) | **Expected** with sibling worktrees — §4 removes worktree then deletes remote |

**INVARIANT:** `gh pr merge --delete-branch` is **not** the cleanup step. Many remotes have `delete_branch_on_merge: false`. Always continue to §4.

## 3.5 Close Fixes issues (mandatory after successful **merge**)

GitHub auto-closes `Fixes`/`Closes`/`Resolves` **only** when the PR merges into the repository **default** branch. Percena often lands on `dev` while default is `main` — auto-close is a no-op. **Refs never closes.**

After merge (not after `--close` without merge), **before or right after §4**:

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
bash "$SKILL_ROOT/scripts/close-fixed-issues.sh" --pr <N> --expected-closing-ids "<approved-csv-from-pre-merge-alignment>"
# dry-run first if unsure:
# bash …/close-fixed-issues.sh --pr <N> --dry-run
```

| Result | Action |
| --- | --- |
| exit 0 | All **actionable local delivery** closing-keyword issues CLOSED, already closed, or none; epic/unsupported exclusions may be listed |
| exit 1 | PR not proven merged, or one or more actionable local delivery closes failed — **finish is not done**; re-run or `gh issue close` manually |
| exit 2 | Cannot load PR / usage / metadata unavailable |

**INVARIANT:** Do not claim finish success while any **actionable local delivery** PR-body `Fixes`/`Closes`/`Resolves` issue remains OPEN (unless the user explicitly opted out). Spec-primary/`epic` and unsupported repository-qualified references are exclusions that must appear in the helper report (`skipped_epic` / `unsupported_references`); they do **not** by themselves fail the helper. Soft report line `issue auto-closed?` alone is **not** sufficient.

Parse source: PR **body**, outside fenced Markdown examples. The live close must receive the exact `closing_ids` approved by the pre-merge alignment JSON; if the set changes after approval, the helper fails closed before loading or closing issues. Squash commit messages may lag if lineage was edited post-create.

**Spec primary / epic:** `close-fixed-issues.sh` does **not** close Spec primary `#N` (`label:epic`) via keyword/heuristic; it skips and reports them. Do not put `Fixes #<primary>` for partial multi-ticket workstreams. Delivery tickets close via `Fixes`; epic close is a **separate completion step** (§3.6).

## 3.6 Spec primary close (completion-causal — after last honest delivery land)

**Criterion is reality, not Lattice habit:**

| Workstream actually complete? | Action |
| --- | --- |
| **Yes** — Spec `A*` done/deferred; in-scope delivery landed; no honest remaining delivery tickets | Set Spec `status: done` if needed; **`gh issue close <primary>`** (unless operator explicitly holds). Do **not** leave OPEN as default “hygiene.” |
| **No** | **Do not close** primary. Add commits / tickets / amend Spec. Open epic is not a buffer for half-done land. |

**Script boundary:** `close-fixed-issues.sh` still must **not** close epic via sub-issue-count heuristic (progress ≠ Acceptance). That prevents **blind** auto-close — it does **not** mean “skip close after you verified completion.”

After Fixes closed + cleanup on the **last** land for this Spec: verify completion in-session → close primary (or state the hold). Parent `k/n` alone is never Spec done.

## 4. Cleanup workspace (mandatory after merge|close)

```bash
# Prefer MAIN_ROOT (team base), not inside the feature worktree about to be removed
cd "<MAIN_ROOT>"
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
bash "$SKILL_ROOT/scripts/cleanup-workspace.sh" \
  --branch "<HEAD_BRANCH>" \
  --pr "<PR_N>" \
  [--worktree-path "<path>"] \
  [--keep-remote] \
  [--dry-run]
```

Observe local and remote tips independently → guard dirty / retained worktrees → **remove worktree first** → delete the local ref with `git update-ref -d <ref> <expected-oid>` after exact local ancestry, PR-head, or force proof → delete the independently proven remote ref with `git push --force-with-lease=<ref>:<expected-oid> origin --delete` → re-probe and prune. Local proof may carry to the remote only when both observed refs are the same exact OID. Ref changes after proof fail closed; divergent same-named refs are preserved independently, and an initially absent remote is re-probed before success. Protected names are preserved locally and remotely. For close-without-merge, omit `--pr`; unmerged work is preserved unless the user explicitly authorized `--force`. Dirty non-force `--dry-run` reports blocked with no false deletion flags, while remote dry-run remains explicitly offline/unprobed.

If JSON `ok` is false, `unsafe_delete_blocked` is true, or `remote_residual` is true → **stop**; do not manually delete until merged identity or explicit destructive authority is established.

If cwd inside removed worktree: `cd` MAIN first.  
Worktrees: sibling `*.worktrees/` / `WORKTREE_ROOT`. Binders: `.lattice/`.

**Verify after cleanup (unless `--keep-remote`):**

```bash
git ls-remote --heads origin "<HEAD_BRANCH>"   # must be empty
```

## 5. Lineage bookkeeping (when Lattice exists)

1. Ticket binder: one `## Finish` ledger (never second heading); firm GH dates (`mergedAt`/`closedAt`); `prs` list; status closed only if issue closed; Acceptance checkoff matches pre-merge; Notes not mid-delivery. **REQUIRED** (not "best-effort"): after merge + cleanup, `cd` to the main checkout on the **merge base**, run `finish-ledger.sh --pr N --issue M --binder <path>` (idempotent; no-binder → skip + note, not a fail; closed-without-merge → no `mergedAt` claim), then commit + push the base.
2. Spec `prs:` / `tickets:` if missing.
3. Review `related_prs` / `related_tickets` if spawned from Review.
4. Keep L0 accurate — bloodline = L0 + GitHub.

## 6. Report

PR URL + state · branch deleted? remote gone? worktree removed? · residual paths · **actionable local delivery issues closed?** + **epic/unsupported exclusions reported?** (`close-fixed-issues.sh` output: `closed` / `skipped_epic` / `unsupported_references`) · land-time Spec alignment · **Spec primary:** complete → closed (or hold); incomplete → open + residual work · alignment summary.

## Examples

```text
/finish-work pr N
/finish-work tkt N
/finish-work #N --dry-run
/finish-work --branch tkt-N-workflow-skills --close
```
