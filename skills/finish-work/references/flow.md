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
- [2.8 Cross-system state reconciliation (interrupted recovery)](#28-cross-system-state-reconciliation-interrupted-recovery)
- [3. Merge or close](#3-merge-or-close)
- [3.4 Sequential merge queue (DEFAULT when landing a queue of PRs)](#34-sequential-merge-queue-default-when-landing-a-queue-of-prs)
- [3.5 Close Fixes issues (mandatory after successful **merge**)](#35-close-fixes-issues-mandatory-after-successful-merge)
- [3.6 Spec primary close (completion-causal)](#36-spec-primary-close-completion-causal--after-last-honest-delivery-land)
- [4. Cleanup workspace (mandatory after merge|close)](#4-cleanup-workspace-mandatory-after-mergeclose)
- [5. Lineage bookkeeping (when Lattice exists)](#5-lineage-bookkeeping-when-lattice-exists)
- [6. Report](#6-report)
- [7. Multi-PR DAG-aware merge (batch mode — `--ids`/`--groups`/multi-PR `spc N`)](#7-multi-pr-dag-aware-merge-batch-mode---ids--groupsmulti-pr-spc-n)
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
- **CI merge gate (machine-enforced, spc-186 A6/A8, ADR-007 §5a).** Run `ci-gate-check.sh --pr <N> --evidence "<local test output>" [--binder <path>]`. It fetches `gh pr checks <N> --json name,state,conclusion,link`, classifies each non-green check as infra-class (billing/quota/rate-limit/timeout/empty-step flake/runner-infra) or real via config-tunable patterns (`.lattice/config.yaml` ci_gate:) + log inspection, and:
  - **Infra-only red + local evidence present** → pass with auto-stamped waiver (trace: `rule_id=ci-gate`, `authorizer=human-at-merge-time`). This is a **compiled corner case** (ADR-007 §5a) — the rule defines the legitimate path, NOT an exception requiring human adjudication.
  - **Real/unknown failures** → HARD block (exit 1). This IS the red line.
  - **Pending** → block (wait for CI to finish).
  - **Infra-only red WITHOUT evidence** → HARD block (fail-closed).
  - CI empty-step ≤~5s + same failure on unrelated main → infra flake; re-run once; local bats/shellcheck OK; never skip real failures with logs.
- Base = PR `baseRefName` (not always `main`).
- CONFLICTING before update → stop (unless about to `--rebase` in feature worktree you control).
- Collect lineage pointers from PR body (do not invent).
- Finish **one PR at a time**.

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
bash "$SKILL_ROOT/scripts/ci-gate-check.sh" --pr "<PR_N>" --evidence "$(ci-local + bats green)" --binder ".lattice/tickets/tkt-N-*/README.md"
```

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

**Machine signal (verdict-void wiring):** the script's success JSON carries `diff_changed` (true when the update changed the PR's effective `git diff base...HEAD` content vs before; false on noop or a content-identical clean update; probe failure degrades to true) and `conflict` (true when the merge/rebase hit conflicts — also stamped on the conflict-shaped failure JSONs). **Record both.** §2.7 uses them to decide verdict validity (rebase-verdict rule, ADR-004 §4): `diff_changed:true` **or** `conflict:true` ⇒ any prior review verdict is **VOID** — re-run the mini-review; both false ⇒ the verdict carries. `diff_changed` is an any-change flag — materiality judgment (trivial context shift vs real delta) stays with the operator/mini-review. HINT: `git range-diff <old-base>..<old-head> <new-base>..<new-head>` helps judge triviality when deciding how deep the re-review must go.

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

**This section is the authoritative full text of the embedded mini-review.** `../SKILL.md` carries only the compact contract summary + a pointer here — when running the scan, load this section, not the summary.

A bounded code-review scan at the merge decision point — a **compressed projection** of the standalone `/review-code` finding contract (same stance, same material bar, compressed axes/output). Runs **after** §2.5/§2.6 alignment (the HARD gate) and **before** §3 merge. **Never** a HARD gate; the HARD gate stays `alignment-check.sh`.

**Why embedded:** operators almost always want a quick correctness scan of the diff before merge but rarely invoke `/review-code` at merge time. The embedded mini removes that friction without weakening gate discipline — findings are advice, the operator decides.

**Why this and `/review-code` both exist:** this scan is a last-gate sanity pass at merge time (5 axes, no persistence, advice-only). `/review-code` is the full-function skill for pre-`create-pr` or dedicated review passes (full axes, Confidence field, PR comment / `rev` persistence, hard-stop-for-fixes). Overlap is intentional — this is a bounded subset of the same finding contract, not a parallel one.

### Unit

Reuse the PR diff already resolved in §1 (no separate target resolution): `gh pr diff <PR_N>` (or `git diff <BASE>...HEAD` when no PR yet). Do not widen to whole-repo architecture; minimal related reads only, each with a one-line why.

### Axes (diff-touched only)

| Axis | Look for |
| --- | --- |
| Correctness | Logic errors, off-by-one, broken edge cases in **changed** paths |
| High-cost failure (if touched) | authz/trust · data loss/corruption · retry/idempotency · races · empty/timeout · schema/compat when migrations change — short list only |
| Tests | Clear gaps for **new** behavior; missing regression for a bug fix |
| Dig deeper | empty/null paths · partial failure/idempotency · stale state/ordering · rollback/irreversible writes — only where the diff touches |
| Privacy/Secrets | Scan diff, PR body, ticket binders, and commit messages for: local filesystem paths (`/Users/`, `/home/`, `C:\`, `/root/`); API keys, tokens, passwords, private keys (grep: `api[_-]?key`, `secret`, `password`, `token`, `BEGIN.*PRIVATE`); closed-source project names or internal hostnames in public-repo artifacts; DB schema details of external services (table/column names in non-migration context); personal email/phone in non-standard contexts. **Credentials/secrets → high (default Hold).** Local paths/project names → med (recommend cleanup). If sensitive content is unavoidable → `AskUserQuestion`: "This diff contains `<type>` — clean up first or confirm it is safe to commit?" |

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

A prior review verdict — a review-delivery digest triage (`auto-pass` / `ratify-then-pass`) or an earlier mini-review `proceed` — stands **only over the diff it reviewed** (ADR-004 §4). The trigger is **machine-readable**: read `diff_changed` and `conflict` from the §2.4 `update-pr-base.sh` JSON.

| §2.4 JSON says… | Verdict |
| --- | --- |
| `diff_changed:true` **or** `conflict:true` (or the update failed conflict-shaped) | **VOID** — re-run this mini-review before §3 merge; do not merge on the stale verdict |
| `diff_changed:false` **and** `conflict:false` (clean/noop update) | Carries unchanged — do not re-review out of ritual |
| No JSON (update skipped via `--no-update-branch`, or signal lost) | Treat as unknown → **VOID** unless the operator asserts the diff is unchanged |

`diff_changed` is an any-change flag; how deep the re-review must go (trivial context shift vs real delta) is the operator/mini-review's judgment — HINT: `git range-diff`. This is a validity condition on advice, not a new gate — the HARD gate stays `alignment-check.sh`.

### Decision (advice, never auto-block / never auto-fix)

- No material findings → one-line `mini-review: no material findings`; proceed to §3 merge.
- Material findings → print the table, then `AskUserQuestion`:
  - `Merge anyway` — operator accepts the risk
  - `Hold (I'll address)` — stop; operator fixes or defers. When the operator **names findings to return**, stamp the binder `status: rework` + bump `fix_cycles` via the scripted owner (the procedural stamp point), and record those findings as the new brief (binder note + PR review threads) — the `pr-open → rework` FSM edge (see `_lattice-lib/references/workflow-fsm-reference.md` or monorepo `docs/workflow-fsm.md`). Scripted stamp:
    ```bash
    SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
    bash "$SKILL_ROOT/../_lattice-lib/scripts/bump-fix-cycle.sh" \
      --binder .lattice/tickets/tkt-N-slug/README.md --note "<one-line return brief>"
    ```
    The script stamps `status → rework` AND bumps `fix_cycles` atomically (cap ≤2; on the third rework it holds at 2 and FORCES `deep-review` — no auto-retry; `--extend-budget --reason` is the operator-adjudicated escape, spc-186 A6/A8). `start-work` resume loads the findings as the brief and fixes on the same PR (fix cycle ≤2). The stamp records the operator's decision on a durable artifact — bookkeeping, not a gate.
  - `Invoke full /review-code` — deeper pass before deciding
- Any **high** finding (including credential/secret leak) → default recommended option `Hold`; only med/low → default `Merge anyway`.
- **Privacy/Secrets override:** if the Privacy/Secrets axis surfaces a **high** finding (credentials, API keys, private keys), default to `Hold` regardless of other axes. If the finding is **medium** (local paths, project names), recommend cleanup but allow `Merge anyway` after explicit confirmation.
- **Hard stop on edits:** present findings and stop. Do **not** auto-fix even if "obvious". Edit the tree only when the operator explicitly names which findings to fix (then smallest change in the change set's modules; fresh test output if tests requested).
- The HARD merge gate is unchanged — `alignment-check.sh`. Findings are advice; the operator may still choose `Merge anyway`.

### Boundary (do not cross)

- Findings **never** block merge automatically (advice, not gate).
- Do **not** widen to whole-repo architecture or drive-by refactors.
- Do **not** persist findings (PR comment / `rev`) — that stays in `/review-code` full skill.
- The standalone `/review-code` skill remains the full-function superset (full axes, 4-question bar, Confidence field, persistence, 5-mode target resolution, hard-stop-for-fixes) for pre-`create-pr` or dedicated review passes.

## 2.8 Cross-system state reconciliation (interrupted recovery)

When a batch was interrupted (fuse-halt, crash, manual abort), binder state may drift from what GitHub actually shows — a `pr-open` binder whose PR was already merged, a `closed` issue with a still-working binder, or a `pr-open` with no resolvable PR. The read-only `reconcile-state.sh` helper detects this drift before merge so the operator can recover manually:

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
[[ "$SKILL_ROOT" = /* && -f "$SKILL_ROOT/SKILL.md" ]] || { echo "Error: resolve the active SKILL.md directory to absolute LATTICE_SKILL_ROOT" >&2; exit 1; }
bash "$SKILL_ROOT/../_lattice-lib/scripts/reconcile-state.sh" \
  --binder .lattice/tickets/tkt-N-slug/README.md [--json]
```

| Result | Action |
| --- | --- |
| `ok:true` (exit 0) | No drift — proceed to §3 merge |
| `ok:false` (exit 1) | Drift detected — manually update binder (status/prs/Finish ledger) or GitHub (close issue/merge PR), then re-run |
| `result:unknown` (exit 2) | GitHub unreachable (auth/network) — do not assume clean; fix credentials/network and re-run |

The check is **read-only**: it performs no `gh issue edit/close/create`, no `gh pr edit/close/merge`, and no binder mutation. It is not a merge gate — the HARD gate stays `alignment-check.sh` (§2.5). Use it when an interrupted workflow may have left cross-system state inconsistent.

See `docs/morning-triage.md` (monorepo, when present) Step 5.5 for the full manual recovery route.

## 3. Merge or close

Prefer not forcing checkout of `main` when another worktree holds it.

```bash
# Capture the base branch tip BEFORE the merge (spc-254 A2 base-OID probe).
PRE_MERGE_BASE=$(git ls-remote origin "refs/heads/<base>" 2>/dev/null | awk '{print $1}')
gh pr merge <N> --squash --delete-branch
# if gh non-zero: gh pr view <N> --json state,mergedAt — MERGED → **still run §3.1 + §4 cleanup**
gh pr close <N> --comment "Closing without merge; cleaning workspace."
```

| Local symptom | Action |
| --- | --- |
| main already used by worktree | Ignore if MERGED; `git -C MAIN_ROOT pull --ff-only` |
| truly not merged | Stop |
| `gh --delete-branch` fails (branch in use by worktree) | **Expected** with sibling worktrees — §4 removes worktree then deletes remote |

**INVARIANT:** `gh pr merge --delete-branch` is **not** the cleanup step. Many remotes have `delete_branch_on_merge: false`. Always continue to §4.

### 3.1. Mutation-proof the merge (spc-254 A2/D5 — INVARIANT)

After `gh pr merge`, prove the PR reached MERGED **and** the base branch tip
on origin actually advanced past the pre-merge base OID captured above. A
merge that "reported success" but left the base tip unchanged did not land —
stamping `mergedAt` and running cleanup/ledger on it is the false-success the
dogfood retrospective (`rev-20260829-140444Z` F1/F5) hit for real. Normal,
batch, and delegated paths share ONE `verify-main-chain.sh --stage merge`
contract.

```bash
SKILL_ROOT="${LATTICE_SKILL_ROOT:-${CLAUDE_SKILL_DIR:-}}"
RESOLVE="$SKILL_ROOT/../_lattice-lib/scripts/resolve-lattice-lib.sh"
LIB=$(bash "$RESOLVE")
bash "$LIB/verify-main-chain.sh" --stage merge --pr <N> \
  --expected-oid "$PRE_MERGE_BASE" --repo "<owner/name>"
```

A `FAILED:` proof HALTS §3.5 (`close-fixed-issues.sh`) and §4
(`cleanup-workspace.sh`) and the `finish-ledger.sh` Finish stamp — the
structured recovery JSON's `next_action` (`gh pr view <N>`; verify the merge
landed; do NOT run ledger/cleanup) is the operator's recovery surface. Only
after `verified: merge pr-<N> …` does the flow proceed to issue closure +
cleanup + ledger.

## 3.4 Sequential merge queue (DEFAULT when landing a queue of PRs)

Landing several PRs into the same integration branch in sequence repeats §2–§4 per PR. The merge loop MUST NOT skip per-PR discipline for throughput. Five rules, each grounded in a live incident:

1. **CI-checks gate (per merge, machine-enforced).** Before **each** merge, run `ci-gate-check.sh --pr <N> --evidence "<local test output>" [--binder <path>]` (spc-186 A6/A8, ADR-007 §5a). It fetches `gh pr checks <N> --json` rollup and classifies failures: infra-class (billing/quota/rate-limit/timeout/empty-step flake) → compiled waiver with auto-stamped trace (`rule_id=ci-gate`); real failures → HARD block (exit 1). **Never merge blind on `mergeable`/`MERGEABLE` alone**: mergeability is a git-tree statement, not a CI verdict, and merge automation that polls only `mergeable` merges red PRs (observed live 2026-08-26).

2. **File-explicit conflict law (INVARIANT).** When a merge/base-update hits conflicts, resolution goes **path by path**: identify each conflicted file (`git diff --name-only --diff-filter=U`), decide per file, and take a side only via `git checkout --ours <named path>` / `git checkout --theirs <named path>` (or hand-edit that named file), then `git add <named path>`. **`git add -A` during conflict resolution is FORBIDDEN** — it stages unresolved conflict markers wholesale (live incident: markers reached `dev` via PR #59's merge automation; repair commit `628e4cb`). **Superset rule for shared files:** when successive PRs touch the same file, neither `--ours` nor `--theirs` may drop the earlier PR's landed changes — the resolved content must be the superset carrying both; verify the merged content, do not assume a side wins.

3. **Post-merge marker sweep.** After each merge, on the integration branch: `grep -rn '<<<<<<<'` over the PR's touched paths (`gh pr view <N> --json files`). Any hit → **stop the queue**; repair before the next merge (markers compound across subsequent merges).

4. **Orphaned-run hygiene at branch deletion.** A resolution commit pushed just before merging leaves in-flight CI runs on the head branch; merging with `--delete-branch` kills them as `failure`/`startup_failure` on the deleted ref (observed: runs 32984498741 / 32984662279 — no failing steps, just a vanished checkout — a dishonest red Actions tab). Either **wait for the new head's checks** to finish before merging, or **cancel in-flight runs** (`gh run list --branch <head>` + `gh run cancel <id>`) as part of cleanup before the branch deletion.

5. **`--no-update-branch` when GitHub reports clean.** When the next PR shows `mergeable: MERGEABLE` + clean state, pass `--no-update-branch` rather than forcing an update cycle — an unneeded update only churns the head, spawns new CI runs (see rule 4), and voids review verdicts for nothing. The CONFLICTING refusal still applies.

**Verdict-void wiring:** each base update returns the §2.4 machine signal — `diff_changed:true` **or** `conflict:true` ⇒ that PR's prior review verdict is **VOID** → re-run the §2.7 mini-review before its merge; both false ⇒ the verdict carries. Advice discipline is unchanged: findings never auto-block; the HARD gate stays `alignment-check.sh`.

## 3.4.1 Dev→main release-boundary version-bump check

**When the PR targets `main`** (the release boundary), bundled content changed ⟹ version must increase (ADR-005). Before merging to `main`:

1. Run `python3 tools/validate-plugin-versions.py --base-ref origin/main --release-check` locally (or check the CI `lint-heavy` result).
2. If the validator reports **"bundled content changed without a version increment"** → **stop**: the operator must bump the version (`.claude-plugin/marketplace.json` + `plugins/*/.claude-plugin/plugin.json`) and update the CHANGELOG before merging.
3. If the validator is **OK** (version increased or no bundled change) → proceed with the merge.

The bump itself is a manual file edit; this check is the automated gate. `dev` merges do not require a version bump — only `main` merges do.

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

1. Ticket binder: one `## Finish` ledger (never second heading); firm GH dates (`mergedAt`/`closedAt`); `prs` list; status closed only if issue closed; Acceptance checkoff matches pre-merge; Notes not mid-delivery. **REQUIRED** (not "best-effort"): after merge + cleanup, `cd` to the main checkout on the **merge base**, run `finish-ledger.sh --pr N --issue M --binder <path>` once per closing binder (idempotent; no-binder → skip + note, not a fail; closed-without-merge → no `mergedAt` claim). The helper **writes + stages** the binder README + its `.transition-ledger/<tkt>.jsonl`; it does **not** commit or push itself — after the per-binder loop, the finish-work flow commits + pushes the base once (`git commit` + `git push origin <base>`). **Cancel before any PR:** `finish-ledger.sh --cancel --reason "<text>" (--closed-at <ts> | --issue M) --binder <path>` — a no-PR terminal cancel writes a dated cancel line (no PR row, no `mergedAt`) and requires explicit human reason + either a firm close time or a gh-verified CLOSED issue; an OPEN/unverifiable issue fails closed. The status flip covers the full working vocabulary (`queued|in-progress|parked|stuck|pr-open|rework|deferred` + legacy `open`); a MERGED PR from `parked`/`stuck`/`deferred` flips to closed and emits an `anomaly:` line preserving the unexpected prior state.
2. Spec `prs:` / `tickets:` if missing.
3. Review `related_prs` / `related_tickets` if spawned from Review.
4. Keep L0 accurate — bloodline = L0 + GitHub.

## 6. Report

PR URL + state · branch deleted? remote gone? worktree removed? · residual paths · **actionable local delivery issues closed?** + **epic/unsupported exclusions reported?** (`close-fixed-issues.sh` output: `closed` / `skipped_epic` / `unsupported_references`) · land-time Spec alignment · **Spec primary:** complete → closed (or hold); incomplete → open + residual work · alignment summary.

## 7. Multi-PR DAG-aware merge (batch mode — `--ids`/`--groups`/multi-PR `spc N`)

**Why a separate mode:** PR landing order forms a DAG — stacked PRs (B based on A; A must merge first or B's diff won't clean) and logical deps (B's code calls a symbol A introduces). Single-PR finish ignores order. Multi-PR mode builds a merge-order DAG and lands PRs **base-first**, reusing finish-work's existing per-PR flow (§2–§6) in layer order.

**Why not a separate skill (like batch-work):** merges serialize on the base branch — there is no parallelism, so batch-work's parallel/worktree/RAM/watchdog/fuse machinery does not apply. Multi-PR mode is host-owned prose calling the **same scripts** the single-PR path uses; it adds the DAG build, layer barrier, halt-on-failure, and a report only.

**Entry:** `--ids ID1,ID2,…` | `--groups` | `spc N` resolving ≥2 open PRs. Single target → single-PR path (§1–§6), unchanged.

### Arg parsing

`--ids` and `--groups` are mutually exclusive with each other and with any single positional target (`pr`/`tkt`/`spc`/`#N`/`--branch`). `spc N` enters multi-PR mode **only** when it resolves ≥2 open PRs; one open PR → single path. `--close`/`--dry-run`/`--rebase`/`--no-update-branch`/`--report` apply per-mode (`--dry-run` prints the DAG and exits before marker/merge).

### RESOLVE PRs

For each id (under `--groups`, **every** binder under `.lattice/tickets/` that has an open PR):

1. Locate `.lattice/tickets/tkt-<id>-*/README.md`. No binder → record `no-pr` (skip); do not fail the batch.
2. Resolve the open PR via §1 target resolution (head `tkt-<id>-*` or body `Fixes`/`Refs #<id>`). No open PR → record `no-pr` (skip).
3. Parse the binder for `merge_blocked_by` (fallback `blocked_by` when `merge_blocked_by` absent or `(none)`), `primary_ticket`, `worktree_bind`.
4. Record PR number, head branch, `baseRefName`, binder path.

Fail closed only if **zero** ids resolve to an open PR ("no open PRs in the batch; nothing to finish"). A mixed batch (some `no-pr`) proceeds on the resolved set.

### BUILD DAG

Nodes = tickets-with-open-PRs. Edges = `merge_blocked_by` (fallback `blocked_by`): ticket B `merge_blocked_by A` means **A must MERGE before B**.

Layer assignment (Kahn's algorithm):

- Layer 0: PRs with no within-batch `merge_blocked_by` (or deps only on tickets outside the batch — treated as already-satisfied).
- Layer k: PR whose every `merge_blocked_by` dep is in a layer < k.
- Within a layer, PRs merge in binder-id order (order does not affect correctness — they are merge-independent); the layer barrier ensures all of layer k lands before layer k+1 begins.
- Cross-batch deps (the `merge_blocked_by` target is not in the batch) are treated as already-satisfied preconditions.

Cycle detection: if Kahn's leaves unprocessed nodes → fail closed: "merge-order DAG has a cycle: <ids>". Do not merge.

This is host-owned (no script) — the host performs the topological sort, mirroring `batch-work`'s DAG build.

### DRY-RUN

If `--dry-run`: print

```
finish-work multi-PR dry-run
base: <resolved integration branch>
layers:
  L0: [tkt-213 → pr-214 (head tkt-213-…, base dev), tkt-214 → pr-215 (…)]
  L1: [tkt-215 → pr-216 (merge_blocked_by: tkt-213, tkt-214)]
binders:
  tkt-213 → .lattice/tickets/tkt-213-…/README.md
  ...
```

Exit 0 before the marker gate and any merge.

### MARKER GATE (once)

If the `.batch-work-active` marker is present at the out-of-repo state home — `$(bash "$LIB/lattice-state-home.sh")/.batch-work-active` (ADR-011 / spc-282 A1; single gate point, one directory shared by all sibling worktrees of a clone; `LIB` resolved as in §3.1):

- `AskUserQuestion`: confirm "finish-work will remove the batch-work marker and merge N PRs in DAG order. Proceed?" (batch-id + PR count + layer summary).
- On ack: `bash "$SKILL_ROOT/scripts/batch-merge-gate.sh" --remove --reason "user-authorized: batch-finish <batch-id>"`; paste the emitted trace line into a batch Decision-journal note.
- On reject: stop; do not merge.

If the marker is **absent** (no prior batch-work, or already removed): no-op; proceed. The batch owns the whole merge window — no per-PR marker dance. (Under `--close`, the marker gate is a no-op — it only blocks `gh pr merge`, not `gh pr close`; removal is harmless but unnecessary.)

### LAYER LOOP

For each layer L0..Lk, for each PR in the layer (binder-id order), run the **single-PR short path (SKILL.md steps 3–12) inline**, **minus the marker-gate step** (removed once above). Each merge obeys §3.4's sequential-merge-queue rules (ci-gate before each merge, file-explicit conflict resolution `git checkout --ours`/`--theirs` per named path — `git add -A` forbidden, post-merge `grep -rn '<<<<<<<'` over touched paths). Concretely per PR:

1. **Stacked-PR base retarget** (only when all this PR's `merge_blocked_by` deps have merged):
   - `gh pr view <N> --json baseRefName`. If `baseRefName` ≠ the resolved integration branch → `gh pr edit <N> --base <integration-branch>`.
   - **Never** retarget a PR whose deps have not all merged — that would orphan the stack. The check is "all deps in `merged-ok` set"; if any dep failed/halted, this PR is `blocked-by-failure` (skip, not retargeted).
2. **Preflight** (§2): `ci-gate-check.sh --pr <N>`; red-run disposition; base-mismatch advice. Pending or real-CI-red → **failure** for this PR (halt).
3. `update-pr-base.sh --pr <N>` (unless `--no-update-branch`). After layer 0 merges, layer-1 `update-pr-base` pulls layer-0's landed work → stacked diffs clean. Honor the rebase-verdict rule (`diff_changed`/`conflict` from JSON).
4. `alignment-check.sh --pr <N>` + land-time Spec drift. HARD gap → **failure** (halt).
5. **Mini-review** (§2.7): load PR diff, 5-axis scan. Operator `Hold` with named findings → stamp `rework` + `bump-fix-cycle.sh` → **failure** (halt, not `blocked-by-failure`; the PR needs rework). High finding default `Hold`.
6. **Capture the base tip, merge, prove the merge (§3.1).** Before the merge: `BASE_TIP=$(git ls-remote origin "refs/heads/<base>" | cut -f1)` where `<base>` is the resolved integration branch (= this PR's `baseRefName` after step 1); empty → **failure** (halt). Then `gh pr merge <N> --squash --delete-branch` (or `gh pr close <N>` under `--close`). After a merge: `bash "$LIB/verify-main-chain.sh" --stage merge --pr <N> --expected-oid "$BASE_TIP" --repo <owner/name>` (`LIB` resolved as in §3.1) — proves MERGED **and** that the base tip advanced past `BASE_TIP`. Anything other than `verified: merge pr-<N> …` (a `FAILED:` proof, non-zero exit, or empty output) → **failure** (halt; steps 7–9 do not run for this PR). The pre-tkt-341 probe (`verify-mutation.sh` with its default OPEN expectation) misread a landed merge as failure — rev-20260831 F4; do not reintroduce it. Under `--close`: no base-tip proof applies; confirm `gh pr view <N> --json state` reports `CLOSED`, else **failure** (halt).
7. **After merge:** `close-fixed-issues.sh --pr <N> --expected-closing-ids <approved-set>` (required). Changed set → fail closed → **failure** (halt).
8. `cleanup-workspace.sh --branch <HEAD> --pr <N>` (required). `ok:false` or remote residual → **failure** (halt, fix residual).
9. `finish-ledger.sh --pr <N> --issue <closing_M> --binder <path>` on the merge base, once per closing binder. Stamps `pr-open → closed` + `## Finish` ledger line; the helper writes + stages the binder + its `.transition-ledger/<tkt>.jsonl` (does **not** commit/push itself). After the per-binder loop, the flow commits + pushes the base once (`git commit` + `git push origin <base>`). **Halt-on-failure:** if finish-ledger fails on binder k of N, do **not** commit the partial staged set — resolve and re-run.

**On success:** record `ok` + merged PR URL + mergedAt; add PR to the `merged-ok` set (used by dependents' retarget check).

**On failure (halt-on-failure):**

- Stop the batch immediately. Do **not** merge remaining PRs in this layer or any later layer.
- **Failed PR:** leave at its finish-work disposition (`rework` if mini-review Hold, else `pr-open` + record the failure reason in the report). Do not stamp `closed`.
- **Dependents** (any PR whose `merge_blocked_by` chain includes the failed PR): stamp binder `status: deferred` + `wait_reason: blocked-by-failure` (mirrors batch-work's blocked-by-failure). Record as `blocked-by-failure`.
- **Remaining independents** (same layer or later layers, not depending on the failed PR): leave binder `pr-open`; record as `halted` (re-runnable — re-run resumes at their layer).
- Jump to REPORT.

**Layer barrier (automatic):** the loop is serial — all PRs in layer k finish before layer k+1 begins. No synchronization primitive needed; the for-loop over layers is the barrier. After layer 0 lands, layer-1 PRs' `update-pr-base` (step 3) sees layer-0's work in the integration branch.

### Never-merged reason mapping

| Report status | Binder status | Binder wait_reason | When |
| --- | --- | --- | --- |
| `no-pr` | (unchanged, `pr-open` or `queued`) | (none) | No open PR for this id (skip). |
| `halted` | `pr-open` (unchanged) | (none) | Batch stopped (a peer failed) before this PR's turn; still schedulable on re-run. |
| `blocked-by-failure` | `deferred` | `blocked-by-failure` | A `merge_blocked_by` dep failed; the merge-order dep is unsatisfied. `deferred → queued` is a human transition. |
| `failed` | `rework` (mini-review Hold) or `pr-open` | (none) | This PR's own finish failed (alignment/CI/merge/cleanup). |

No new binder enum values — `deferred`/`blocked-by-failure` already exist (mirrors batch-work). `halted` is report-level, not a binder enum (binder stays `pr-open`).

### REPORT

Markdown table emitted to stdout and `--report <path>`:

```markdown
# finish-work multi-PR report

base: <resolved integration branch>
ran: <UTC timestamp>

| ticket | layer | pr | status | binder | mergedAt |
| --- | --- | --- | --- | --- | --- |
| tkt-213 | L0 | #214 | ok | .lattice/tickets/tkt-213-…/README.md | 2026-08-30 |
| tkt-214 | L0 | #215 | ok | … | 2026-08-30 |
| tkt-215 | L1 | #216 | blocked-by-failure | … | — |
| tkt-216 | L1 | — | halted | … | — |
| tkt-217 | — | — | no-pr | … | — |

## Summary
- merged: 2
- failed: 0
- blocked-by-failure: 1
- halted: 1
- no-pr: 1

## Handoff
Re-run `finish-work --ids …` after fixing the failed PR.
Halted PRs re-enter at their layer; blocked-by-failure PRs need their dep merged first
(`deferred → queued` is a manual transition before re-run).
Marker removed once at batch start (no per-PR marker step on re-run).
```

Report-status vocabulary (`ok | failed | blocked-by-failure | halted | no-pr`) is **report-level**, not the binder enum.

## Examples

```text
/finish-work pr N
/finish-work tkt N
/finish-work #N --dry-run
/finish-work --branch tkt-N-workflow-skills --close
/finish-work --ids 213,214,215
/finish-work --groups --dry-run
/finish-work spc 220
```
