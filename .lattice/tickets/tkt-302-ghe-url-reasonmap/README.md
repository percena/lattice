# tkt-302-ghe-url-reasonmap

> **TL;DR:** GHE path-prefixed URL parsing + reason_map word-splitting in close-reason awareness (tkt-294 followup)
> **Kind:** bug · **Priority:** P2

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P2 |
| labels | bug, P2 |
| github | https://github.com/percena/lattice/issues/302 |
| status | pr-open |
| adopted | true |
| summary | Fix URL regex/sed to match last two segments before /pull/ (handles GHE path-prefix); fix reason_map to validate against known set and handle null |
| spec | none |
| covers | A1–A2 |
| paths | skills/finish-work/scripts/alignment-check.sh, skills/finish-work/scripts/close-fixed-issues.sh |
| solo_merge | no (co-delivered with tkt-301) |
| **primary_ticket** | tkt-302 (this issue) |
| **related_tickets** | tkt-301 (co-delivered — state_reason REST call fix) |
| **worktree_bind** | tkt-301-state-reason-rest-fix |
| prs | pr-303 — https://github.com/percena/lattice/pull/303 |
| created | 2026-09-01T02:40:00Z |
| updated | 2026-09-01T07:26:05Z |

## Acceptance

- [x] **A1** Fix URL parsing in alignment-check.sh (regex) and close-fixed-issues.sh (sed) to match the **last two** path segments before `/pull/` instead of the first two after the host — handles both standard GitHub and GHE path-prefixed URLs
- [x] **A2** Fix reason_map in close-fixed-issues.sh: validate state_reason against known set; handle `null` output from --jq; use a delimiter that doesn't conflict with reason values

## Reproduction

```python
# alignment-check regex (Python):
re.match(r'https?://[^/]+/([^/]+/[^/]+)/pull/\d+', 'https://github.acme.io/org/team/repo/pull/1')
# → None (should be 'team/repo')

# close-fixed-issues sed:
echo 'https://github.acme.io/org/team/repo/pull/1' | sed -E 's#https?://[^/]+/([^/]+/[^/]+)/pull/.*#\1#'
# → full URL unchanged (should be 'team/repo')

# reason_map:
reason_map('354=not planned')  # → {354: 'not'} (truncated)
reason_map('354=null')         # → {354: 'null'} (literal null)
```

## Decision journal

- 2026-09-01T07:26:05Z — direct jump: queued → pr-open (in-progress stamp skipped; PR #303) [WARN — signal logged, not silently lost]
