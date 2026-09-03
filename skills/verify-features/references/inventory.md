# Inventory — building and refreshing the feature map

The map answers "what can this application do, and what should each thing do?" from four sources, strongest oracle first. Refresh is a **diff**, never a rewrite (INVARIANT 5; history is the value).

## Source 1 — lineage mining (strong oracles)

```bash
grep -n '^- \[.\] \*\*A' .lattice/specs/*.md            # Spec acceptance criteria
grep -rn '^- \[.\] \*\*A' .lattice/tickets/*/README.md  # ticket acceptance
```

Each user-facing `A*` criterion is a feature candidate whose text IS the expected behavior. Record `source: spc-N A3` (or `tkt-N A2`). Internal/tooling criteria (validators, CI) are not runtime features — skip them, do not force rows.

## Source 2 — docs mining (medium oracles)

README feature tables, `docs/`, user guides, route-level docstrings. `source: README §…`. A doc claim is an oracle the product must honor; a doc claim with no reachable feature is a **finding** (stale doc or missing feature).

## Source 3 — surface scan (entry points, no oracles)

Route tables, navigation components, sitemap, CLI `--help` for hybrid apps — grep the codebase for router/nav registration idioms. Yields `entry` values and features the docs forgot.

## Source 4 — bounded crawl (weak oracles, discovery only)

One ego-browser story: from the app root, breadth-first over same-origin links/nav items, **≤ 20 pages** (INVARIANT 4), read-only — record URL, title, visible primary actions per page. Never click actions during the crawl (a link is navigation; a button is a mutation until classified). Output feeds new rows with `oracle: generic invariants` and a lineage-gap note: an undocumented feature is itself a finding for the report.

## Classifying `mutations`

| Class | Meaning | Examples |
| --- | --- | --- |
| `none` | Read-only surface | dashboards, lists, search |
| `safe` | Reversible, self-contained writes | create/edit a record you can delete, toggle a preference |
| `destructive` | Irreversible or external side-effects | delete, payment, send email/notification, permission grants |

Unknown → `destructive` until an operator or a doc proves otherwise (INVARIANT 2). The operator authorizes destructive testing per row, in the map, in writing (`mutations: destructive (authorized 2026-08-27 by operator)`).

## Diff + write

1. Read the existing map; index by `id`.
2. New candidates → new rows (`status: untested`); changed oracles → update oracle + source, reset `status` to `untested` (the old pass verified the old expectation); vanished features → keep the row, mark `status: blocked` with `entry gone` note (deletion is a human edit after review).
3. Feature `id`: `ftr-<kebab-slug>` — stable across runs; renaming an id is a human decision.
4. Write the map (single writer), then run `python3 tools/validate-lattice-artifacts.py` — the `feature_map` checks must be clean before the pass proceeds.
