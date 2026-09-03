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

- CI anomalies: retry intelligently before escalating — cheapest probe first (re-check state / wait for platform recovery), then re-trigger (fresh push or close-reopen), and hand to a human only when self-service is exhausted; always record what was tried and why the red was judged transient vs real (added 2026-08-26, operator-stated — direct entry, ×2 promotion not required for explicit operator directives)
- Label taxonomy: docs and sync tooling follow the repo's live label set; renaming repo labels needs an explicit operator decision (added 2026-08-26, ratified-by-default in tkt-65, unobjected)
- Preference capture is proactive: when the operator states a durable work preference mid-session, the active AI writes it here AT UTTERANCE TIME with provenance and confirms in one line — never waits to be reminded (added 2026-08-26, operator-stated; encoded into decision-policy law 2026-08-27, pr-88)

<!-- - New scripts: bash + `set -euo pipefail`, mirror sibling script style (added 2026-08-26) -->
<!-- - HTTP client: stdlib, not a new library (added 2026-08-26) -->

## HINT

Apply silently; never blocks ship.

<!-- - Prefer table-form reference docs over prose lists (added 2026-08-26) -->
<!-- - Error messages: state the actionable next step (added 2026-08-26) -->

<!-- Superseded entries stay in place, e.g.
     - ~~HTTP client: axios~~ superseded 2026-08-26 by "stdlib, not a new library" -->

## Review-findings → tickets (operator-stated, 2026-09-01)
When a code review (review-code / finish-work mini-review) surfaces material findings, prefer **creating follow-up tickets** for each issue (with Why/Acceptance/Approach, linked to the PR) over folding fixes into the in-flight PR — *unless* the fix is small and in-scope. Rationale: keeps the reviewed PR's verdict honest + tracks the refinement work as durable, traceable items rather than ad-hoc patches. The operator wants the workflow (including its details) progressively refined via these tickets. Source: finish-work pr-296 (tkt-271) — chose ship-as-is + filed #297-#300.
