# Reproduction evidence — tkt-293

## Environment

- Local gh: 2.92.0 (2026-04-28, macOS) — `baseRefOid` IS a valid `gh pr view --json` field
- Reporter gh: 2.45.0 (Ubuntu) — `baseRefOid` is NOT a valid `gh pr view --json` field

## Pre-fix observation

The bug is **version-dependent**: `baseRefOid` was added to the gh CLI `gh pr view --json`
field set at some point after July 2022 (GitHub discussion #5902 from 2022-07 lists available
fields without `baseRefOid`; the current Arch Linux manual page and gh 2.92.0 both list it).

On gh 2.92.0, the field works:

```
$ gh pr view 292 --json id,number,baseRefName,baseRefOid,headRefOid
{"baseRefName":"dev","baseRefOid":"fc498a5...","headRefOid":"f404f3...","id":"PR_...","number":292}
```

On gh ≤ 2.45.0 (reporter's environment), the same command fails:

```
$ gh pr view 355 --json id,number,baseRefName,baseRefOid,headRefOid
Unknown JSON field: "baseRefOid"
```

## The two defects the fix addresses

1. **Version-dependent field rejection**: on older gh, requesting `baseRefOid` causes the
   entire `gh pr view --json` call to fail (exit 1), so the script never reaches the parse
   step. The base-update step is broken for every PR on those environments.

2. **Masked stderr** (reproducible on all versions): `update-pr-base.sh:75` uses
   `2>/dev/null` on the `gh pr view` call, then prints a generic `Error: cannot view PR #N`.
   On ANY version, if `gh pr view` fails (auth, network, field rejection), the real
   diagnostic is discarded. This is reproducible by simulating a failure:

   ```bash
   # Simulated: gh returns error, stderr is masked
   $ gh pr view 999999 --json baseRefOid 2>/dev/null || echo "exit $? → script prints: Error: cannot view PR #999999"
   ```

   The operator sees `Error: cannot view PR #N` and cannot tell whether it's an auth issue,
   a visibility issue, or a field-name bug.

## Fix approach

Use REST `gh api repos/{owner}/{repo}/pulls/{n} --jq '.base.sha'` for the base OID — this
channel works across ALL gh versions (REST endpoint is stable). Drop `baseRefOid` from the
`gh pr view --json` field list. Unmask stderr so the real gh diagnostic is visible on failure.
