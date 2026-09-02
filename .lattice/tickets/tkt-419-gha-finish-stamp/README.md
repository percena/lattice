| field | value |
| status | queued |
| priority | P1 |
| labels | feat, P1 |
| github | https://github.com/percena/lattice/issues/419 |
| spec | spc-416 |
| covers | A6 |
| prs | (none) |
| updated | 2026-09-02T19:30:00Z |
| wait_reason | (none) |

## Summary

GHA on pull_request:closed — verifies local stamp landed, repairs Mode C (ledger continuity), catches local stamp failures. CI-dependent safety net (local stamp is primary, CI-independent).

## Scope

- .github/workflows/finish-stamp.yml — pull_request: closed (merged) trigger
- Verifies binder + ledger consistency on merged dev branch
- Invokes finish-stamp.py in CI if stamp missing (idempotent)
- Mode C repair: insert missing intermediate ledger edges
- Commits as github-actions[bot] with contents:write
- Race with local stamp: benign (both idempotent)

## Acceptance

- [ ] A6: GHA verifies local stamp + repairs missing ledger entries (Mode C safety net)

## Notes

- Blocked by #418 (finish-stamp.py must exist)
- CI billing risk: local stamp is primary; GHA is safety net. If billing exhausted, local stamp still works.
- Layer 3 (daily sweep) deferred to follow-up if needed.
