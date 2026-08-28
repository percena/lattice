# tkt-159 reproduction evidence (pre-fix)

Captured 2026-08-28 on worktree `tkt-159-ci-local-fail-loud` (base origin/dev @ 1ddba53).

## Bug A — unresolvable `--base-ref` silently skips the version gate

Command (clean tree):

```bash
bash tools/ci-local.sh --fast --base-ref bogus-ref-zzz
```

Observed:

```text
base ref: bogus-ref-zzz [dev mode: lenient]
==> plugin-versions
plugin-versions                            skip   no bundled paths changed vs bogus-ref-zzz (mirrors lint-heavy path filter)
ci-local: all steps green (skips noted above)
```

Exit code 0. The gate CI enforces (`git rev-parse $PLUGIN_VERSION_BASE_REF` fails hard in lint-heavy.yml) vanished into a clean `skip`.

Mechanism: `plugin_version_paths_changed()` pipes `git diff --name-only "$BASE_REF" --` through process substitution; with a bogus ref the diff prints `fatal:` to stderr and yields no stdout, so on a clean tree the function returns 1 → recorded as skip.

## Bug B — `--help` garbled and truncated

Command: `bash tools/ci-local.sh --help`

Observed:

- Line 1 is `!/usr/bin/env bash` — the shebang leaks through `sed 's/^# \{0,1\}//'` (it strips a leading `#` with zero spaces).
- Output ends mid-sentence: `--release-check … Default is` — the 18-line cap (`sed -n '1,18p'`) cuts the description before "dev-mode (lenient…)". 
- `--fast` has no description line at all (only appears inside the Usage line).

## Post-fix verification (same commands)

| Case | Pre-fix | Post-fix |
| --- | --- | --- |
| `--help` line 1 | `!/usr/bin/env bash` (shebang leak) | `ci-local: run locally, …` |
| `--help` tail | cut mid-sentence at "Default is"; no `--fast` description | full `--release-check` + `--fast` descriptions; ends with complete sentence |
| `--base-ref bogus-ref-zzz` | `plugin-versions skip …` + "all steps green", exit 0 | `plugin-versions FAIL unresolvable --base-ref` + "1 step(s) FAILED", exit 1 |
| `--base-ref HEAD` (guard) | — | no false FAIL, run green |

Tests: `tools/tests/ci-local.bats` (new, 5 tests) — all green.
