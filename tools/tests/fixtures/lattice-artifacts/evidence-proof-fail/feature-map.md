# Feature map (evidence-proof fault injection)

| id | feature | entry | oracle (expected — source) | mutations | risk | story | last-verified | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ftr-no-story | No story | /a | lands on /a — spc-1 A1 | none | low | — | — | pass |
| ftr-missing-story | Missing story | /b | lands on /b — spc-2 A2 | none | low | stories/missing.story.md | — | pass |
| ftr-mut-mismatch | Mut mismatch | /c | lands on /c — spc-3 A3 | none | low | stories/mut.story.md | — | pass |
| ftr-oracle-mismatch | Oracle mismatch | /d | does the thing — spc-7 A1 | none | low | stories/oracle.story.md | — | pass |
| ftr-no-result | No result | /e | lands on /e — spc-5 A5 | none | low | stories/noresult.story.md | — | pass |
| ftr-destructive-no-auth | Destructive no auth | /f | destroys a row — spc-6 A6 | destructive | high | stories/destructive.story.md | — | pass |
| ftr-result-not-pass | Result not pass | /g | lands on /g — spc-7 A7 | none | low | stories/notpass.story.md | — | pass |
| ftr-clean | Clean pass | /h | lands on /h — spc-8 A8 | none | low | stories/clean.story.md | 2026-08-30 rev-x | pass |
