# tkt-162 reproduction evidence (pre-fix, on dev @ 1ddba53)

Direct detector calls (`detect-gh-pr-command.py <verb>`; exit 0 = treated as invocation = blocked in strict mode):

| Input | Pre-fix | Correct | Post-fix |
| --- | --- | --- | --- |
| `touch gh pr create` | 0 (**false positive**) | 1 | 1 |
| `mv gh pr create` | 0 (**FP**) | 1 | 1 |
| `git checkout -- gh pr create` | 0 (**FP**) | 1 | 1 |
| `find . -name gh -o -name pr -o -name create` | 0 (**FP**; `-o`/`-name` consumed as gh flags) | 1 | 1 |
| `cat gh pr create` | 0 (**FP**) | 1 | 1 |
| `find . -exec gh pr create {} +` | 0 | 0 (exec ⇒ fail-closed, kept) | 0 |
| `frobnicate gh pr create` | 0 | 0 (unknown prefix ⇒ fail-closed, kept) | 0 |
| `sudo -u gh pr create` | 1 (`gh` is `-u`'s value — runs `pr` as user gh) | 1 | 1 |
| `gh pr create --help` | 1 (docs lookup) | 1 | 1 |
| `bash -c 'gh pr create'` / `eval "gh pr create"` / `sh -c "gh pr merge 1"` | 1 (not detected) | accepted limitation — now documented in detector docstring + `intercept-gh-pr-common.sh` call-site comment, pinned by tests | 1 |

Mechanism of the false positives: `contains()`'s unknown-prefix fallback scan treated any argument sequence spelling `gh [flags] pr [flags] <verb>` as executable; the fix adds `DATA_ARGUMENT_COMMANDS` (words-as-data commands) and `EXEC_CAPABLE_COMMANDS` (find stays fail-closed only when `-exec`/`-execdir`/`-ok`/`-okdir` appears in the same region).

Test suite: new `plugins/lattice/scripts/tests/detect-gh-pr-command.bats` (24 tests). All assertions are errexit-effective plain `[ "$status" -eq N ]` — no mid-body `[[ ]]` (#167). Old detector fails exactly the 5 false-positive tests; fixed detector passes all 24; full plugin suite (278 tests) green.
