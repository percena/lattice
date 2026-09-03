# Needs-decision triage queue

Reviews with `outcome: needs_decision` — design-level policy decisions awaiting an operator call.
Each entry links the review, the decision needed, and recommended options.

| Review | Decision | Recommended | Status |
| --- | --- | --- | --- |
| `rev-20260827-064527Z` | FSM-2 (fuse-halt SoT) + FSM-4 (parked→queued atomicity) | FSM-2=Option B, FSM-4=Option A | **resolved** (tkt-136, 2026-08-27) |

> **How to drain:** morning triage picks an option per row → the review's `outcome` updates to `spawn_tickets` (or `inform_only` if accepted-as-is) → implementation tickets are filed → row removed.
