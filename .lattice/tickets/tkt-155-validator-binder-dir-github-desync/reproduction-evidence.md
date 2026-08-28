# Reproduction Evidence — tkt-155

## Phase 0c (Pre-Fix)

**Bug:** `validate-lattice-artifacts.py` never parses the `github` field row from
binder cards. Phantom binders (numeric `tkt-N` dir + placeholder `github` field)
and dir-N vs github-issue-N mismatches go undetected.

### Case 1: Phantom binder (numeric dir + placeholder github)

Fixture binder: dir `tkt-999-phantom-test`, `github` field = `(to be created)`

```
$ python3 tools/validate-lattice-artifacts.py --home <tmp>/.lattice --json
{
  "ok": true,
  "count": 0,
  "warning_count": 0,
  "findings": []
}
exit=0
```

**Expected (post-fix):** `phantom_binder_smell` warning + `binder_github_pending` warning.

### Case 2: Dir-N vs github-issue-N mismatch

Fixture binder: dir `tkt-999-desync-test`, `github` field = `https://github.com/percena/lattice/issues/888`

```
$ python3 tools/validate-lattice-artifacts.py --home <tmp>/.lattice --json
{
  "ok": true,
  "count": 0,
  "warning_count": 0,
  "findings": []
}
exit=0
```

**Expected (post-fix):** `binder_dir_github_mismatch` error (dir tkt-999 vs issue #888).

### Root cause

No `GITHUB_TABLE_RE` or github-field parsing exists in the validator. The ticket
loop (`validate_home`) checks status, fix_cycles, prs, spec/covers, and duplicate
ids — but never reads the `github` row from the binder card.

## Phase 1b (Post-Fix Verification)

### Cross-comparison table

| Case | Input | Pre-fix result | Post-fix result | Verdict |
| --- | --- | --- | --- | --- |
| Phantom binder | dir=tkt-999, github=`(to be created)` | `ok:true, 0 errors, 0 warnings` | `ok:true, 0 errors, 1 warning (phantom_binder_smell)` | ✅ Fixed |
| Dir-URL mismatch | dir=tkt-999, github=#888 | `ok:true, 0 errors, 0 warnings` | `ok:false, 1 error (binder_dir_github_mismatch)` | ✅ Fixed |
| Clean match | dir=tkt-205, github=#205 | (n/a — new check) | `ok:true, 0 errors, 0 warnings` | ✅ Pass |
| Malformed URL | dir=tkt-208, github=`/pull/208` | (n/a — new check) | `ok:true, 0 errors, 1 warning (binder_github_malformed)` | ✅ Pass |

### Full test suite

```
$ bats tools/tests/lattice-artifacts.bats
1..26
ok 1-22 (existing tests — no regression)
ok 23 matching github URL and dir N pass clean
ok 24 dir N vs github issue N mismatch errors
ok 25 numeric dir with placeholder github warns phantom_binder_smell
ok 26 github URL that is not an issues path warns binder_github_malformed
```

```
$ bash tools/ci-local.sh
ci-local: all steps green (no skips)
```

### Notes

- `phantom_binder_smell` subsumes `binder_github_pending` when the dir is numeric
  (the phantom signal is the actionable one; emitting both would be noisy). The
  non-numeric dir (e.g. `tkt-pending-…`) case emits `binder_github_pending`
  alone. Decision recorded in binder Decision journal.
- Absent `github` row is OK (lazy migration — mirrors `fix_cycles` missing-row
  posture). This keeps existing minimal fixtures clean.
