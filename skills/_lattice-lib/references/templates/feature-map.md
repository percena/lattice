# Feature map (template — copied to `.lattice/feature-map.md` by `verify-features`)

Committed inventory of what the application can do and what each feature is expected to do.
**Single writer: the `verify-features` skill** (humans edit like any reviewed artifact; other skills read).
Status vocabulary: `untested | pass | fail | blocked` — `pass`/`fail` cells may carry a parenthetical
(`fail (tkt-N)`, `blocked (auth)`); `last-verified` is `YYYY-MM-DD rev-<id>` or `—`.
Validator: `validate-lattice-artifacts.py` checks row shape + status vocabulary when this file exists.

<!-- One row per feature. id: stable `ftr-<kebab-slug>`. oracle: the expected behavior, with its
     source (spc-N A* > doc § > "generic invariants"). mutations: none | safe | destructive —
     destructive rows need written operator authorization in the cell before any testing. -->

| id | feature | entry | oracle (expected — source) | mutations | risk | story | last-verified | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
<!-- | ftr-login | Sign in with email | /auth/login | valid creds land on /dashboard; invalid show inline error — spc-7 A1 | none | high | .lattice/e2e/stories/login.story.md | — | untested | -->
