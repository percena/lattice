# tkt-122-shell-portability

<!-- Binder is a thin recovery card (not a second issue tracker). -->

> **TL;DR:** ci-local.sh + bats broken on macOS default bash 3.2 — GNU sed -i, apostrophe parse, mapfile guard
> **Kind:** bug · **Priority:** P2
> **Path:** (no Spec) → tkt-122 → (pr-…)

| Field | Value |
| --- | --- |
| kind | bug |
| priority | P2 |
| labels | bug, P2 |
| github | https://github.com/percena/lattice/issues/122 |
| status | closed |
| adopted | false |
| summary | shell portability — ci-local.sh + bats suites fail on macOS default bash 3.2 (sed -i, apostrophe, mapfile) |
| spec | (none — standalone process-hardening bug) |
| covers | (none) |
| blocked_by | (none) |
| parallel_group | G1 |
| paths | skills/create-tickets/scripts/sync-github-labels.sh, skills/_lattice-lib/scripts/tests/build-review-context.bats, skills/_lattice-lib/scripts/tests/finish-ledger.bats, skills/_lattice-lib/scripts/tests/stamp-pr-open.bats, tools/ci-local.sh, skills/_lattice-lib/scripts/build-review-context.sh, skills/create-tickets/scripts/tests/sync-github-labels.bats |
| solo_merge | yes |
| **primary_ticket** | tkt-122 (this issue) |
| **related_tickets** | (none) |
| **worktree_bind** | `tkt-122-shell-portability` |
| worktree | sibling `…/lattice.worktrees/tkt-122-shell-portability/` (default for shippable) |
| prs | pr-128 — https://github.com/percena/lattice/pull/128 |

## Acceptance (this slice)

- [x] **A1** No `sed -i` (GNU form) remains in any bats file — all use the portable `sed -e 's/...' file > tmp && mv tmp file` (or `perl -pi -e`) form already used in `update-pr-base.bats`.
- [x] **A2** `sync-github-labels.sh` parses clean on bash 3.2 (`bash -n` exit 0) — apostrophe removed or label table built without `$(cat <<'EOF' …)`.
- [x] **A3** `ci-local.sh` + `build-review-context.sh` either avoid `mapfile` (portable `while read` loop) OR fail loud with a clear "requires bash 4+" guard before the first `mapfile`; requirement documented in the script header.
- [x] **A4** `bash tools/ci-local.sh` (full, no `--fast`) runs green on macOS default bash 3.2 (`/bin/bash` 3.2.57); all bats suites pass.

## Reproduction Steps (bug-class)

1. **A1:** `sed -i 's/a/b/' file` on macOS BSD sed → `sed: …: unterminated substitute in regular expression`, file unchanged. Sites: `build-review-context.bats:234,236,308`, `finish-ledger.bats` (5×), `stamp-pr-open.bats` (4×).
2. **A2:** `bash -n skills/create-tickets/scripts/sync-github-labels.sh` → `line 48: unexpected EOF while looking for matching '''` + `line 68: syntax error`. All 5 `sync-github-labels.bats` tests fail. Trigger: apostrophe in `Something isn't working` inside `$(cat <<'EOF' …)`.
3. **A3:** `bash tools/ci-local.sh` (full) on bash 3.2 → `tools/ci-local.sh: line 214: mapfile: command not found`. `which bash` = `/bin/bash` (3.2); no homebrew bash installed.

## Approach

- A1: replace each `sed -i 'expr' file` with `sed -e 'expr' file > "$tmp" && mv "$tmp" file` (temp via `mktemp`). Match the form in `update-pr-base.bats:151,168`.
- A2: change the `bug` description to `Something is not working (Lattice kind: bug)` (drop apostrophe) — minimal, preserves the GitHub-canonical wording minus the parser-breaking char. Alternative: build the LABELS array inline instead of `$(cat <<'EOF' …)`.
- A3: add near the top of `ci-local.sh` and `build-review-context.sh`:
  ```bash
  if [[ ${BASH_VERSINFO[0]:-0} -lt 4 ]]; then
    echo "Error: this script requires bash 4+ (mapfile). macOS default /bin/bash is 3.2 — install via 'brew install bash' or use the portable path." >&2
    exit 1
  fi
  ```
  Preferred if feasible: replace `mapfile -t arr < <(...)` with `arr=(); while IFS= read -r line; do arr+=("$line"); done < <(...)` (portable to bash 3.2) so the headline tool works out-of-the-box on macOS.

## Anticipated decisions

- A3 approach (guard vs portable loop) — disposition: agent-decides (guard is minimal; portable loop removes the platform friction entirely; reversible + local). Prefer the portable loop if it doesn't hurt readability.
- A2 fix shape (drop apostrophe vs restructure heredoc) — disposition: pre-resolved (drop apostrophe — smallest change, preserves meaning).

## Decision journal

<!-- append-only -->

## Pending decisions

<!-- (none) -->

## Attempts

<!-- (none) -->

## Notes

- These are the platform the local-CI-parity tool is most likely run on; `ci-local.sh`'s "green here ≈ green CI" promise is currently false on macOS default bash.
- Independent paths from tkt-121/tkt-123 — parallel-safe.

## References

- GitHub issue body: https://github.com/percena/lattice/issues/122
- No Spec (standalone process-hardening bug).

## Lineage

- Parent spec: (none)
- Parent issue: (none — ticket-only)
- Primary ticket: **tkt-122**
- Related / sub-tickets: (none)
- Covers: (none)
- Blocked by: (none)
- Parallel group: G1
- Worktree bind: `tkt-122-shell-portability`

## Assets

Local files in `./assets/`.

## Finish


- pr-128 merged: 2026-08-27T07:29:18Z — https://github.com/percena/lattice/pull/128 (base merge)
- issue #122 closed: 2026-08-27T07:29:26Z — https://github.com/percena/lattice/issues/122
