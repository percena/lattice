# Team preferences (Lattice)

Taste/stack defaults for unattended agents — **chain source #4** in `decision-policy.md`
(after ticket AC/Approach, Spec Decisions, ADR; before default heuristics).
Severity per `constraint-language.md`: **INVARIANT** conflicts park, **DEFAULT** applies + journals, **HINT** just applies.

## Lifecycle — INVARIANT

| Rule | Meaning |
| --- | --- |
| Promotion | A decision-journal entry **ratified ×2** raises a promotion proposal in the morning digest (rendering lands with `review-delivery`); a human ratifies it into an entry here |
| Supersede, never delete | Retire an entry by marking it `superseded YYYY-MM-DD by <new entry>` in place — history stays grep-able |
| Rank | Spec/ADR always outrank preferences — chain order is law |
| Citation | Every use is cited in the consuming agent's binder `## Decision journal` (e.g. `4 — preferences.md DEFAULT: <entry>`) |

## INVARIANT

Conflict with one of these → park (binder `## Pending decisions`); never silently override.

<!-- - No new runtime dependency without an ADR (added 2026-08-26) -->
<!-- - Generated artifacts stay grep-able Markdown — no binary/DB state (added 2026-08-26) -->

## DEFAULT

Apply + journal the use; skip only with a stated equivalent-proof reason.

<!-- - New scripts: bash + `set -euo pipefail`, mirror sibling script style (added 2026-08-26) -->
<!-- - HTTP client: stdlib, not a new library (added 2026-08-26) -->

## HINT

Apply silently; never blocks ship.

<!-- - Prefer table-form reference docs over prose lists (added 2026-08-26) -->
<!-- - Error messages: state the actionable next step (added 2026-08-26) -->

<!-- Superseded entries stay in place, e.g.
     - ~~HTTP client: axios~~ superseded 2026-08-26 by "stdlib, not a new library" -->
