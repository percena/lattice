# review-code CI/CD check (portable)

Fetch CI/CD run status for the current review unit and surface failures as findings.

## When to run

Always during Step 3 (Auxiliary checks), after the change set is resolved. Skip only when there is genuinely no CI (see No CI below).

## Fetch status

### PR mode (preferred when a PR exists)

```bash
gh pr checks <PR_N> --json name,state,link
```

Parse `state` (`SUCCESS` / `FAILURE` / `PENDING` / `NEUTRAL`). A check is a **failure** when `state` is `FAILURE`. (The `conclusion` field was removed in gh ≥ 2.6x; `ci-gate-check.sh` derives the legacy pair from `state` — tkt-349.)

### Branch mode (no PR, or review before create-pr)

```bash
gh run list --branch <branch> --limit 10 --json databaseId,status,conclusion,name,event,headBranch
```

Focus on the most recent run per workflow `name`. A run is a **failure** when `status` is `completed` and `conclusion` is `failure`/`cancelled`/`timed_out`. `status: in_progress` → note "pending", not a finding.

### Log excerpt for failures

```bash
gh run view <databaseId> --log-failed | head -50
```

Extract the failing step name and the error message (compile error, test assertion, lint rule). Keep the excerpt short — one to a few lines that pinpoint the root cause. Include the `link` so the operator can open the full log.

## Classification

| Signal | Severity | Note |
| --- | --- | --- |
| Compile / test / logic failure | **med** (or **high** if it blocks the PR purpose) | Real failure — recommend fix |
| Lint / format failure (CI gate) | **low** | Usually style; recommend fix if it blocks merge |
| Timeout / runner infra / network | **low** | Note "possibly flaky/infra"; recommend re-run |
| Pending / in-progress | not a finding | Note "CI still running" in the CI/CD subsection |

## No CI

If `gh` is unavailable, the repo has no workflow files (`.github/workflows/`, `.gitlab-ci.yml`, etc.), or no runs exist for the branch → one line in the CI/CD subsection: `no CI runs available for this unit`. This is **not** a finding.

## Finding format

```
check-name · FAILURE · <log excerpt or run link> · recommendation
```

## Fix flow (hard-stop preserved)

CI/CD findings are part of the **single batch confirmation** in Step 6 — they are presented alongside all other findings (correctness, interface impact, syntax/lint, docs-sync, privacy/secrets) and confirmed in **one** `AskUserQuestion`. Do **not** issue a separate CI-specific confirmation.

If the operator picks a fix option that includes CI failures, apply the smallest change to the failing files, re-run the failing check locally if possible, and paste fresh output.

Do **not** auto-fix CI failures without the operator confirming. Do **not** re-trigger CI runs on the operator's behalf unless asked.
