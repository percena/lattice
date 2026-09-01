# tkt-293-finish-work-baserefoid-fix

> **TL;DR:** `update-pr-base.sh` requests the non-existent `baseRefOid` `gh pr view` JSON field, causing silent base-update failure on every PR; fix the field list, obtain the base OID via a real channel, and stop masking stderr
> **Kind:** bug · **Priority:** P1

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P1 |
| labels | bug, P1 |
| github | https://github.com/percena/lattice/issues/293 |
| status | closed |
| adopted | true |
| summary | Drop `baseRefOid` from `gh pr view --json`; fetch base OID via REST `gh api repos/{owner}/{repo}/pulls/{n} --jq .base.sha`; surface real gh errors instead of masking stderr; fix bats fixtures + add regression test |
| spec | none |
| covers | A1–A5 |
| blocked_by | (none) |
| parallel_group | (none — serial with tkt-294, one PR) |
| paths | skills/finish-work/scripts/update-pr-base.sh, skills/finish-work/scripts/tests/update-pr-base.bats, skills/finish-work/scripts/tests/finish-preflight.bats |
| solo_merge | no (co-delivered with tkt-294) |
| **primary_ticket** | tkt-293 (this issue) |
| **related_tickets** | tkt-294 (co-delivered in same PR — close-reason awareness) |
| **worktree_bind** | tkt-293-finish-work-baserefoid-closereason |
| worktree | sibling …/lattice.worktrees/tkt-293-finish-work-baserefoid-closereason/ |
| prs | (pending), pr-295 — https://github.com/percena/lattice/pull/295 |

## Acceptance (this slice)

- [x] **A1** Drop `baseRefOid` from the `gh pr view --json` field list on line 75 of `update-pr-base.sh` (keep `baseRefName`)
- [x] **A2** Obtain the base OID via a channel that actually exposes it — REST `gh api "repos/{owner}/{repo}/pulls/{PR}" --jq '.base.sha'` (preferred — simplest); populate `BASE_OID` from this fetch
- [x] **A3** Stop masking the real gh error behind `2>/dev/null` + generic `cannot view PR` — capture stderr and emit the actual diagnostic so the next field/contract mismatch is diagnosable
- [x] **A4** Fix bats fixtures (`GH_INITIAL_JSON` in `update-pr-base.bats` and `finish-preflight.bats`) to drop `baseRefOid` from the stubbed `gh pr view` output (or stub the replacement REST channel)
- [x] **A5** Add a regression test that runs the script against a real-shape `gh pr view` JSON (without `baseRefOid`) so a future field-name regression is caught

## Reproduction

Pre-fix evidence to capture in `reproduction-evidence.md`:

```bash
$ gh pr view 355 --json id,number,baseRefName,baseRefOid,headRefOid
Unknown JSON field: "baseRefOid"

# What update-pr-base.sh sees (line 75 masks stderr → 2>/dev/null)
$ gh pr view 355 --json id,number,baseRefName,baseRefOid,headRefOid 2>/dev/null || echo "exit $?"
exit 1   # → script prints: "Error: cannot view PR #355"
```

## Approach

Minimal, surgical fix:
1. Line 75: remove `baseRefOid` from the `--json` field list.
2. After the `gh pr view` call (which still fetches `baseRefName`), add a REST call: `gh api "repos/${REPOSITORY}/pulls/${PR}" --jq '.base.sha'` to populate `BASE_OID`. Keep the existing `incomplete_identity` guard.
3. Replace `2>/dev/null` on the `gh pr view` line with a stderr-capture pattern that emits the real error on failure.
4. Bats: update `GH_INITIAL_JSON` fixtures to remove `baseRefOid`; stub the REST `gh api` call; add a test case where `gh pr view` JSON lacks `baseRefOid` and the REST call provides `.base.sha`.

## Anticipated decisions

- REST vs GraphQL vs git-resolve for base OID — pre-resolved: REST `gh api repos/{owner}/{repo}/pulls/{n}` is simplest and already used elsewhere in the skill stack; GraphQL adds query complexity; git-resolve from `origin/<baseRefName>` requires a fetch that may not have happened in the non-rebase path. Source: issue #293 suggested fix list (option 1). Reversible, ticket-local.

## Decision journal

- 2026-09-01T02:54:03Z — direct jump: queued → pr-open (in-progress stamp skipped; PR #295) [WARN — signal logged, not silently lost]

## Pending decisions

## Attempts

## Notes

- Issue body is the SoT (adopted: true) — do not rewrite the GitHub issue body
- Found while finishing M1n9X/StockVise#355 (external repo) — the bug affects all finish-work base-update flows on real gh

## References

- Issue: https://github.com/percena/lattice/issues/293
- Anchor: `skills/finish-work/scripts/update-pr-base.sh:75` (baseRefOid in --json), `:106` (view.get("baseRefOid"))
- Bats fixtures: `skills/finish-work/scripts/tests/update-pr-base.bats`, `skills/finish-work/scripts/tests/finish-preflight.bats`

## Finish

- pr-295 merged: 2026-09-01T05:53:57Z — https://github.com/percena/lattice/pull/295 (base merge)
- issue #293 closed: 2026-09-01T05:54:47Z (reason: completed) — https://github.com/percena/lattice/issues/293
