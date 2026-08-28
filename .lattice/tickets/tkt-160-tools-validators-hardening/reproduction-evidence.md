# tkt-160 reproduction evidence

## Bug A — `str.removeprefix` breaks the documented Python 3.8 floor

`tools/validate-plugin-versions.py:236` (pre-fix): `origin_head.removeprefix("refs/remotes/")`. `str.removeprefix` is Python 3.9+; README Requirements declare `python3` ≥ 3.8. On 3.8 the base-discovery path dies with an uncaught `AttributeError`, violating the file's "clean errors, never tracebacks" contract. Same class as tkt-143 (`binder_rows.py`); this occurrence was missed because the shipped skills' Python was audited but `tools/` was not.

Fix: slice equivalent (`origin_head[len("refs/remotes/"):]`) — byte-identical behavior on all supported versions.

## Bug B — routing evals pass vacuously for a zero-positive skill

Pre-fix `run-routing-evals.py` aggregated positives into a global 80% rank-1 floor with no per-skill minimum: emptying one case file's `trigger.positive` list silently removed that skill from the gate (verified by monkeypatched-corpus run: pre-fix main() returned 0 with an emptied `start-work.json`; post-fix returns 1 with `ERROR: start-work.json has zero trigger.positive prompts`).

## Regression tests (tools/tests/validators-hardening.bats, 3 tests)

| Test | Pre-fix | Post-fix |
| --- | --- | --- |
| 3.9+ API denylist grep over tools/skills/plugins `*.py` | FAIL (removeprefix present) | pass |
| zero-positive case file ⇒ exit 1 + loud ERROR | FAIL (exit 0) | pass |
| per-skill `positives=/rank1=` stats printed for all 14 skills | FAIL (absent) | pass |

All assertions errexit-effective (`[ ]`, `grep -q`) — no mid-body `[[ ]]` (#167).
