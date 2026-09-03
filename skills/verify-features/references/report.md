# Report — verification rev + map stamping

## Map stamping (single writer, after triage)

Per executed feature: `status` ∈ `pass | fail (tkt-N) | blocked (<reason>)`; `last-verified: YYYY-MM-DD rev-<id>`; `story:` the story file path. Untouched rows keep their prior stamp — staleness stays visible by date, never overwritten to look fresh.

## Verification rev

Persist under `.lattice/reviews/` with create-review conventions (`next-artifact-id.sh --kind rev --claim`), front matter `kind: verification`, `related_tickets:` the filed bugs, `related_specs:` when the pass was scoped to a spec's delivery.

Body order:

1. **TL;DR** — one line: scope, coverage delta, bug count, bounds hit.
2. **Coverage** — counts: pass / fail / blocked / untested (+ delta vs the previous verification rev); scoped-run statement of what was deliberately out of scope.
3. **Bugs filed** — table: tkt-N · feature id · one-line defect · `found_by` · `escaped_from` (or —).
4. **Findings that are not bugs** — lineage gaps (undocumented features from the crawl), stale doc claims, flaky stories, env/config issues.
5. **Evidence index** — story files + JSON/screenshot paths for every executed story (pass and fail).
6. **Bounds** — which bounds were hit (wave cap, crawl cap, timebox) and what was left unverified because of them.

The rev is the interface to the rest of the loop: `review-delivery` digests may cite it (never run stories themselves); the morning human reads its TL;DR next to the digest.

## Wave accounting

Each invocation appends one rev — never edits a previous one. Consecutive passes over the same scope should show the coverage delta trending (untested ↓, pass ↑); a delta of zero across two passes with bounds hit means the bounds are too tight — a finding, not a silent grind.
