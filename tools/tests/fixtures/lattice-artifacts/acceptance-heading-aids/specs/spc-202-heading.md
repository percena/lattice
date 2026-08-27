---
id: spc-202
tickets: [tkt-202]
---
# Spec — Acceptance heading carries inline A-ids (tkt-121 P4)

<!-- The A-ids appear ONLY on the heading line ("## Acceptance — **A1**,
     **A2**"), with no list-item repetition below. This isolates the P4 path:
     before the fix, the heading-line A-ids were skipped (continue), leaving
     spec_acceptance_ids empty → covers_not_on_spec fires; after the fix,
     heading-line A-ids are collected → clean. -->

## Acceptance — **A1**, **A2**

The two criteria are declared inline on the heading above. There are no
separate list items restating them — the heading is the sole source of the
coverable A-ids, which is the shape the P4 bug skipped.
