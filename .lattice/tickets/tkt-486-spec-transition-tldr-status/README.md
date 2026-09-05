# tkt-486-spec-transition-tldr-status

> **TL;DR:** `spec-transition.py` rewrites the front-matter `status:` on done/superseded but not the TL;DR `**Status:**` display line — sync it so terminal Specs don't trip `spec_header_status_mismatch`.
> **Kind:** bug · **Priority:** P2
> **Path:** ticket-only (follow-up to tkt-473) → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P2 |
| labels | bug, P2 |
| github | https://github.com/percena/lattice/issues/486 |
| status | closed |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-05T06:10:00Z |
| updated | 2026-09-05T07:54:29Z |
| adopted | false |
| summary | spec-transition.py syncs TL;DR **Status:** display on done/superseded |
| spec | none (follow-up to tkt-473 / spc-475; spc-475 is `done`) |
| covers | (n/a — no Spec A*) |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | (none) |
| paths | skills/_lattice-lib/scripts/spec-transition.py, skills/_lattice-lib/scripts/tests/spec-transition.bats |
| solo_merge | yes |
| autonomy | 3 |
| **primary_ticket** | tkt-486 (this issue) |
| **related_tickets** | tkt-473 |
| **worktree_bind** | `tkt-486-spec-transition-tldr-status` |
| worktree | sibling `…/lattice.worktrees/tkt-486-spec-transition-tldr-status/` |
| prs | pr-487 — https://github.com/percena/lattice/pull/487 |

## Acceptance (this slice)

- [x] **A1** After `spec-transition.py done`, the Spec's TL;DR `**Status:**` line reads `done` (matches front-matter `status: done`); validator reports no `spec_header_status_mismatch` for the transitioned Spec. *(spec-transition.bats test 17)*
- [x] **A2** After `spec-transition.py superseded`, the TL;DR `**Status:**` line reads `superseded`. *(spec-transition.bats test 18)*
- [x] **A3** A `spec-transition.bats` case proves the TL;DR display matches post-transition (no bare `[[ ]]` / `! cmd`; portable `sed -i.bak`). *(spec-transition.bats tests 17–18)*
- [x] **A4** Existing suites stay green (transition-parity, lattice-artifacts, transition-api, spec-supersede, spec-transition). *(19/19 + 9 + 71 + 50 + 13; tkt-460 guard clean; validator ok True 0 errors 0 new_warnings)*

## Approach

1. Add a `_rewrite_tldr_status(text, new_status)` helper that `re.sub`s the `**Status:** <word>` segment inside the leading `>` TL;DR line (anchored to the first `>` block so it only touches the display line, not prose `**Status:**` mentions).
2. Call it from `_prepare_done_text` (`done`) and `_prepare_superseded_text` (`superseded`).
3. Add a bats test: run `done` on a fixture Spec whose TL;DR says `locked`; assert the TL;DR now says `done` and `validate-lattice-artifacts.py` is clean (no `spec_header_status_mismatch`).

## Anticipated decisions

- TL;DR line shape (`> **Kind:** … **Status:** <state> …`) — disposition: pre-resolved. The regex targets the `**Status:**` token within the first `>` block, robust to other fields reordering.

## Decision journal

<!-- Append-only during execution. -->

## Notes

- Discovered during the #475 close (2026-09-05): spc-475's TL;DR header was synced manually (`fix(spc-475): sync TL;DR Status display to done`). The manual fix stands; this ticket makes the API do it automatically so the next Spec done/superseded doesn't push a red `dev`.

## Finish

- pr-487 merged: 2026-09-05T07:54:19Z — https://github.com/percena/lattice/pull/487 (base merge)
- issue #486: not closed (closed-without-merge? status recorded without mergedAt claim)
