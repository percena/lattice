# Feature map

| id | feature | entry | oracle (expected — source) | mutations | risk | story | last-verified | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ftr-login | Sign in | /login | valid creds land on /dash — spc-7 A1 | none | high | stories/login.story.md | 2026-08-27 rev-x | pass |
| ftr-export | Export CSV | /export | file downloads with rows — README §export | safe | med | stories/export.story.md | — | fail (tkt-9) |
| ftr-billing | Billing | /billing | generic invariants | destructive | high | — | — | blocked (auth) |
