# tkt-<id>-<semantic-slug>

<!-- Binder is a thin recovery card (not a second issue tracker).
     required: kind, priority, github, status, created/updated, acceptance, primary_ticket / worktree_bind when shipping
     recommended: covers, spec, summary/TL;DR, Path, autonomy
     optional (parallel / C): blocked_by, merge_blocked_by, parallel_group, paths, solo_merge, related_tickets -->

> **TL;DR:** <one sentence slice — standalone>
> **Kind:** feat · **Priority:** P2 <!-- status lives in the field table -->
> **Path:** spc-N → tkt-<id> → (pr-…)

| Field | Value |
| --- | --- |
| kind | feat |
| priority | P2 |
| labels | enhancement, P2 |
| github | https://github.com/<org>/<repo>/issues/<id> | issue URL — trailing number must match dir `tkt-N` (validator: mismatch → `binder_dir_github_mismatch` error; placeholder on numeric dir → `phantom_binder_smell` warning). Pre-creation placeholder: `(to be created)` / `pending` / `(none…)`. Use `tkt-pending-<slug>` dir until the issue number exists, then rename to `tkt-N-<slug>` |
| status | queued | working: queued \| in-progress \| parked \| stuck \| pr-open \| rework \| deferred · terminal: closed (finish-ledger stamps it; merged vs closed-without-merge read from ## Finish mergedAt) · legacy: open (coarse — validator warns) |
| fix_cycles | 0 | review-fix cycles on this PR (ADR-004 §5 cap ≤2; validator warns >2). Stamped by `bump-fix-cycle.sh` (`_lattice-lib/scripts/`) on each pr-open → rework → pr-open round — the scripted owner (spc-186 A6); do NOT hand-edit. Third rework holds at 2 and forces `deep-review` (human); `--extend-budget --reason` is the operator-adjudicated escape. Missing row = 0 (lazy migration — never fails) |
| wait_reason | (none) | when status is stuck: unblock (needs an answer/env fix — human) \| re-scope (needs Spec/ticket revision → M1 — planning defect). when status is deferred: fuse-halt (batch fuse tripped; re-schedule later) \| budget-exhausted (budget circuit breaker tripped; re-schedule later — spc-433) \| blocked-by-failure (a blocked_by dependency failed) \| spec-superseded (this ticket's Spec was superseded — spec-supersede.sh stamped it at supersede time; re-plan under the superseding Spec or cancel). Routes morning triage. Missing/`(none)` = the stuck/deferred ticket is unspecified (validator fails — tkt-151 A3) |
| created | <YYYY-MM-DDTHH:MM:SSZ> | ISO-8601 UTC, seconds precision (`YYYY-MM-DDTHH:MM:SSZ`). Stamped once at binder creation (create-tickets); never bumped. Missing row → validator warn (lazy migration — historical binders predate the row); a present-but-malformed value → error (spc-186 A4). Time-in-state baseline for A5 staleness |
| updated | <YYYY-MM-DDTHH:MM:SSZ> | ISO-8601 UTC, seconds precision. Bumped by each status-stamping script (stamp-pr-open, finish-ledger, ratify) atomically with the status flip in the same locked write; equals `created` at creation. Missing row → validator warn (lazy migration); malformed → error (spc-186 A4). In-flight age = now − `updated` (A5 water-level) |
| adopted | false | true — **true** when GH issue body is hand-created / append-only; land uses binder-first Acceptance |
| summary | ≤120 chars |
| spec | spc-N — <one-line> (path: ../../specs/spc-N-<slug>.md) |
| covers | A1, A2 |
| blocked_by | (none \| #N) |
| merge_blocked_by | (none \| #N) | merge-order DAG — #N must MERGE before this ticket's PR lands (distinct from `blocked_by` = work-start order; usually the same but governs landing order for stacked PRs / logical deps). Consumed by `finish-work` multi-PR mode; falls back to `blocked_by` when absent |
| parallel_group | G1 \| (serial) |
| paths | approx globs this slice may touch |
| solo_merge | yes \| no |
| autonomy | 4 | ticket-level autonomy score 0-4 (0-indexed per lattice convention). 0=Day-Interactive (needs human architecture/UI confirmation) \| 1=low (may need 1-2 confirmations) \| 2=medium (mostly self-sufficient) \| 3=high (clear acceptance criteria, good test coverage) \| 4=full (docs/tests/pure functions, auto-mergeable). Set at split time by create-tickets; batch-work uses `--min-autonomy` (default 3) to filter night-executable tickets. Scoring rubric: `../../../_lattice-lib/references/autonomy-rubric.md`. Missing row → default 2 (medium) for backward compat — validator warns if absent on C-mode tickets |
| **primary_ticket** | tkt-<id> (this issue) — owner of the ship when this tree has one PR |
| **related_tickets** | (none \| tkt-… sub/Refs tickets on the same PR) |
| **worktree_bind** | `tkt-<id>-<slug>` \| `spc-<n>-<slug>` \| full branch name (open-time bind; rebind optional) |
| worktree | sibling `…/<repo>.worktrees/<worktree_bind or branch>/` (**default for shippable**) |
| prs | (none) | filled format, one per PR: `pr-N — <URL>` (em dash), e.g. `pr-41 — https://github.com/<org>/<repo>/pull/41` |
<!-- OPTIONAL escaped-defect lineage rows (spc-104 A4) — bug-class binders only; uncomment into the field table when used:
| found_by | verify-features rev-… \| human \| review |
| escaped_from | pr-N — digest rev-… (auto-pass) |
     found_by: who surfaced the bug. escaped_from: ONLY when the verify-features
     triage tracing recipe succeeds (blame/`git log -S` → PR → digest class) —
     never guessed; omit the row when tracing fails. Digests count these rows. -->

## Acceptance (this slice)

<!-- Mirror Spec A* ids this ticket owns (light RTM). Do not re-grill whole Spec here. -->
- [ ] **A1** <slice criterion>
- [ ] **A2** <slice criterion>

## Approach

<!-- Authored at split time: 5–10 line sketch + touch-set (files this slice edits). -->

## Anticipated decisions

<!-- One line each: <item> — disposition: pre-resolved(<source>) | agent-decides | must-ask. -->

## Decision journal

<!-- Append-only during execution. Each entry cites its resolution source per decision-policy:
     <decision> → <choice> (source: pre-resolved | preference | spec/ADR | agent-judgment). -->

## Pending decisions

<!-- Parked must-ask questions for morning ratification: question · context · default-if-unanswered. -->

## Attempts

<!-- Fallback ledger, one entry per attempt: approach · what failed · evidence (path/log) · why next differs.
     For review-fix cycles, prefix the round's entry with `cycle: N` (N starts at 1) so the bound is
     machine-readable; the field-table `fix_cycles` row mirrors the latest N. Retry caps (ADR-004 §5):
     ≤2 tries/path, ≤3 paths/ticket — this ledger is the counter inherited across sessions. -->

## Notes

<!-- Sub-tickets: serial extras on the same PR stay related_tickets + PR Refs.
     Default: one sibling worktree per ship slot. New worktree only when
     parallel degree ≥ 2 and independence gates pass. -->

## References

- GitHub issue body is SoT for long prose
- Spec: `spc-N` (path above) — do not duplicate full Spec here
- ADR: cite only if this slice implements a cross-feature decision (`ADR-NNN`)
- Worktree policy: one tree ↔ one PR; spc\|tkt open binds

## Lineage

- Parent spec: **spc-N**
- Parent issue (GH sub-issue of Spec primary when Spec exists): **#N** | none (ticket-only)
- Primary ticket: **tkt-<id>**
- Related / sub-tickets: …
- Covers: **A1, A2**
- Blocked by: … (dependency DAG — not parent)
- Merge blocked by: … (merge-order DAG — not work-start; consumed by finish-work multi-PR mode)
- Parallel group: …
- Worktree bind: …
- Child PRs: … (GitHub Fixes/Refs is SoT)

## Assets

Local files in `./assets/`. Prefer media upload (`create-pr` / `create-tickets` shared script) for durable GH URLs in the **GitHub issue** body.

## Finish

- (none yet)
- <!-- After merge: keep ONE ## Finish section. Example:
     pr-P merged: YYYY-MM-DD — https://github.com/<org>/<repo>/pull/P
     issue #N closed: YYYY-MM-DD — https://github.com/<org>/<repo>/issues/N
     Use firm GH dates; check off Acceptance; update Notes/status together. -->
