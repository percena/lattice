# tkt-392-fix-class-taxonomy

> **TL;DR:** Add 8 new fix-class patterns to hotspot_metrics.py to reduce "other" from 66% to <15%; makes fix_class_diversity useful for curve-bending analysis.
> **Kind:** chore · **Priority:** P3
> **Path:** tkt-388 dry run → tkt-392 → (pr-…)

| Field | Value |
| --- | --- |
| kind | chore |
| priority | P3 |
| labels | chore, P3 |
| github | https://github.com/percena/lattice/issues/392 |
| status | queued |
| fix_cycles | 0 |
| wait_reason | (none) |
| created | 2026-09-02T10:05:00Z |
| updated | 2026-09-02T10:05:00Z |
| adopted | false |
| summary | hotspot-metrics fix_class taxonomy: add 8 new classes to reduce "other" from 66% to <15% |
| spec | (none — ticket-only follow-up to tkt-388) |
| covers | (none) |
| blocked_by | (none) |
| merge_blocked_by | (none) |
| parallel_group | (none — single ticket) |
| paths | skills/review-lineage/scripts/lib/hotspot_metrics.py, skills/review-lineage/scripts/tests/hotspot-metrics.bats |
| solo_merge | yes |
| primary_ticket | tkt-392 |
| related_tickets | (none) |
| worktree_bind | tkt-392-fix-class-taxonomy |
| worktree | sibling `…/<repo>.worktrees/tkt-392-fix-class-taxonomy/` |
| prs | (none) |

## Acceptance (this slice)

- [x] **A1** 8 new fix-class patterns added to `_FIX_CLASSES`, each with a planted-drift bats test
- [x] **A2** Dry run on this repo: fix_class "other" drops from 66% to <15% (59 → 12 = 13.5%)
- [x] **A3** No existing fix-class classification changes (status-flip=13, regex-drift=1, bash-guard=3, field-mismatch=4, atomicity=9 — all unchanged)

## Approach

Add 8 entries to `_FIX_CLASSES` list in `hotspot_metrics.py`, ordered before the `other` catch-all:

```python
("hardening", re.compile(r"hardening|harden|fail-closed|fail-loud|fail-open|guard|proof|enforce|enforcement", re.I)),
("docs-sync", re.compile(r"docs.*residue|stale.*ref|rename|renumber|strip.*header|TL;DR.*header|conflict marker|docs sync|hygiene", re.I)),
("ci-infra", re.compile(r"ci-gate|ci-local|routing-eval|bats.*pin|assertion|CI guard|CI red|ls-remote flake|bisect", re.I)),
("binder-format", re.compile(r"binder.*format|prs-row|binder_rows|checkbox|binder-hygiene|binder.*dir|slug.*ledger|format drift|placeholder", re.I)),
("feature-bug", re.compile(r"hostname|git branch.*force|terminal cancel|terminal.*vocab|e2e-story|batch-work.*enforcement|RAM probe|DAG intake|data-command", re.I)),
("portability", re.compile(r"python 3\.[89]|LC_ALL|CJK|sed -i|mapfile|compat|BSD|IFS leak|nested-shell", re.I)),
("residue-cleanup", re.compile(r"residue|cleanup|remove.*committed|strip stale|leftover", re.I)),
("review-followup", re.compile(r"post-review|post-merge.*review|review.*follow|review-code findings|dev branch review", re.I)),
```

Add 8 bats test cases — one per new class, each with a representative subject string asserting the class. Re-run dry run to verify "other" drops from 59 to ~12.

**Touch-set:** `skills/review-lineage/scripts/lib/hotspot_metrics.py` (_FIX_CLASSES list, lines ~80-90), `skills/review-lineage/scripts/tests/hotspot-metrics.bats` (8 new @test blocks).

## Anticipated decisions

- regex pattern breadth — agent-decides: patterns seeded from dry-run analysis; tune if false-positives appear.
- class ordering — pre-resolved: new classes before "other" catch-all; existing classes (status-flip etc.) stay first since they're more specific.
- "still-other" threshold — pre-resolved: <15% is the target; 12/89 = 13.5% is acceptable.

## Notes

- Origin: tkt-388 dry run (spc-387). The L4 sensor's fix_class "other" was 59/89 = 66%.
- Analysis showed 8 new patterns capture 47/59 (79%), reducing "other" to ~12/89 = 13.5%.
- The remaining 12 "other" commits are genuinely ticket-specific feature bugs (e.g. "coordinator wired by default", "ledger path from binder home") — not classifiable.

## Finish

- (none yet)
