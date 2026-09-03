# tkt-175 reproduction evidence (post-merge review of tkt-159..163)

## A1 — `git bisect run` detector bypass (regression introduced by tkt-162)

Verified on dev @ d7e11c5 (pre-tkt-175):

```text
printf '%s' 'git bisect run gh pr create' | python3 detect-gh-pr-command.py create  → exit 1 (放行)
```

`git bisect run <cmd> <args>` executes its arguments as a shell command with bare tokens — visible to the detector and caught by the pre-tkt-162 fail-closed scan. Root cause: `git` was added to `DATA_ARGUMENT_COMMANDS` (dual-natured command misclassified as data-only).

Fix: `git` moved to `EXEC_CAPABLE_COMMANDS` with the multi-token trigger `bisect run`; `has_exec_trigger()` generalizes trigger matching. `git checkout -- …` / `git bisect start …` remain data (safe).

Regression tests: `git bisect run gh pr create` (+ merge verb) fail pre-fix, pass post-fix; `git bisect start …` safe in both.

## A2 — ci-local.bats assertion ergonomics (batch's own pre-#167 file)

Post-merge review found 3 tests with mid-body `[[ ]]` assertions that bash `set -e` never fires on — the shebang-leak and mid-help-truncation behaviors they name were not gated, and the valid-ref test asserted whole-run exit 0 (couples to shellcheck presence / dirty tree). Rewritten to errexit-effective forms (`grep -qF`, terminal `! grep`, guard-specific assertions only).

## A3 — minors

- validators-hardening denylist missed `from tomllib import …` / `from zoneinfo import …` (the idiomatic forms) — added.
- stamp-pr-open dedup: valid-but-wrong-shape JSON (`[]`) raised AttributeError outside the `try` → exit 1 → marker-not-found → blind post. Verified: new "wrong shape" test fails pre-fix, passes with the widened try/except (any eval exception → exit 2 → skip).
- build-review-context temp-ref fetch now uses a forced (`+`) refspec so a leaked per-pid ref can never fail the fetch into a silent `local` fallback.
