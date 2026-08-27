#!/usr/bin/env bats
# Tests for finish-ledger.sh: idempotent binder ## Finish ledger stamping.
# Uses --merged-at/--closed-at overrides so no gh/network is required.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export FL="$REPO_ROOT/skills/_lattice-lib/scripts/finish-ledger.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fl.XXXXXX")"
  # Real layout: the binder lives under <repo>/.lattice/tickets/<bind>/README.md.
  # finish-ledger rewrites this file in place, so it refuses paths outside a
  # repo's .lattice/ tree — stage it exactly where the workflow puts it.
  REPO="$TEST_DIR/repo"
  BINDER_DIR="$REPO/.lattice/tickets/tkt-7-demo"
  mkdir -p "$BINDER_DIR"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email lattice-test@example.invalid
  git -C "$REPO" config user.name 'Lattice Test'
  BINDER="$BINDER_DIR/README.md"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Minimal binder template for tests.
write_fresh_binder() {
  cat >"$BINDER" <<'MD'
# tkt-N-demo

| Field | Value |
| --- | --- |
| status | open |
| prs | (none yet) |

## Acceptance

- [ ] **A1** thing

## Finish

- (none yet)
MD
}

@test "fresh binder: stamps pr line + status closed when issue closed" {
  write_fresh_binder
  run bash "$FL" --pr 12 --issue 7 --binder "$BINDER" --repo percena/lattice \
    --merged-at 2026-07-31T10:00:00Z --closed-at 2026-07-31T10:01:00Z
  [ "$status" -eq 0 ]
  [[ "$output" == *"stamped"* ]]
  grep -q "pr-12 merged: 2026-07-31T10:00:00Z" "$BINDER"
  grep -q "pr-12 merged: 2026-07-31T10:00:00Z — https://github.com/percena/lattice/pull/12" "$BINDER"
  grep -q "issue #7 closed: 2026-07-31T10:01:00Z — https://github.com/percena/lattice/issues/7" "$BINDER"
  # issue URL must not be doubled
  ! grep -q "github.com/https://github.com" "$BINDER"
  grep -qE '\| status \| closed \|' "$BINDER"
  [ "$(grep -c '^## Finish' "$BINDER")" -eq 1 ]
  ! grep -q '(none yet)' "$BINDER"
}

@test "idempotent: re-run does not duplicate the pr line" {
  write_fresh_binder
  bash "$FL" --pr 12 --issue 7 --binder "$BINDER" \
    --merged-at 2026-07-31T10:00:00Z --closed-at 2026-07-31T10:01:00Z >/dev/null
  run bash "$FL" --pr 12 --issue 7 --binder "$BINDER" \
    --merged-at 2026-07-31T10:00:00Z --closed-at 2026-07-31T10:01:00Z
  [ "$status" -eq 0 ]
  [ "$(grep -c 'pr-12 merged' "$BINDER")" -eq 1 ]
  [ "$(grep -c '^## Finish' "$BINDER")" -eq 1 ]
}

@test "idempotent: re-run updates mergedAt to a new value" {
  write_fresh_binder
  bash "$FL" --pr 12 --issue 7 --binder "$BINDER" \
    --merged-at 2026-07-31T10:00:00Z --closed-at 2026-07-31T10:01:00Z >/dev/null
  bash "$FL" --pr 12 --issue 7 --binder "$BINDER" \
    --merged-at 2026-07-31T11:00:00Z --closed-at 2026-07-31T10:01:00Z >/dev/null
  grep -q "pr-12 merged: 2026-07-31T11:00:00Z" "$BINDER"
  ! grep -q "pr-12 merged: 2026-07-31T10:00:00Z" "$BINDER"
}

@test "no binder file: skip with note, exit 0 (not a failure)" {
  run bash "$FL" --pr 12 --binder "$BINDER_DIR/nonexistent.md" \
    --merged-at 2026-07-31T10:00:00Z
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip"* ]]
}

@test "multiple PRs: appends to the same ## Finish (no second heading)" {
  write_fresh_binder
  bash "$FL" --pr 12 --issue 7 --binder "$BINDER" \
    --merged-at 2026-07-31T10:00:00Z --closed-at 2026-07-31T10:01:00Z >/dev/null
  bash "$FL" --pr 13 --issue 7 --binder "$BINDER" \
    --merged-at 2026-07-31T12:00:00Z --closed-at 2026-07-31T10:01:00Z >/dev/null
  grep -q "pr-12 merged" "$BINDER"
  grep -q "pr-13 merged" "$BINDER"
  [ "$(grep -c '^## Finish' "$BINDER")" -eq 1 ]
}

@test "merged PR with an issue that is not closed notes the open issue" {
  write_fresh_binder
  run bash "$FL" --pr 12 --issue 7 --binder "$BINDER" --pr-state MERGED \
    --merged-at 2026-07-31T10:00:00Z
  [ "$status" -eq 0 ]
  grep -q "pr-12 merged" "$BINDER"
  grep -qi "not closed" "$BINDER"
}

@test "closed-without-merge records status and never claims mergedAt" {
  write_fresh_binder
  run bash "$FL" --pr 12 --binder "$BINDER" --pr-state CLOSED
  [ "$status" -eq 0 ]
  grep -q "pr-12 closed without merge" "$BINDER"
  ! grep -q "pr-12 merged" "$BINDER"
  # no merge happened, so the ticket is not silently marked closed
  grep -qE '\| status \| open \|' "$BINDER"
}

@test "closed-without-merge with a closed issue does close the ticket" {
  write_fresh_binder
  run bash "$FL" --pr 12 --issue 7 --binder "$BINDER" --pr-state CLOSED \
    --closed-at 2026-07-31T10:01:00Z
  [ "$status" -eq 0 ]
  grep -q "pr-12 closed without merge" "$BINDER"
  grep -q "issue #7 closed: 2026-07-31T10:01:00Z" "$BINDER"
  grep -qE '\| status \| closed \|' "$BINDER"
}

@test "an OPEN PR is refused: the ledger records outcomes, not intentions" {
  write_fresh_binder
  run bash "$FL" --pr 12 --binder "$BINDER" --pr-state OPEN
  [ "$status" -eq 1 ]
  [[ "$output" == *"still OPEN"* ]]
  grep -q '(none yet)' "$BINDER"
}

@test "high-contention sibling PR stamps are serialized without lost entries" {
  # Two writers do not expose the sidecar unlink race reliably. With a waiter
  # holding the unlinked inode and later arrivals locking a replacement inode,
  # the old implementation lost roughly half of these entries.
  for round in 1 2 3; do
    write_fresh_binder
    for pr in $(seq 1 20); do
      bash "$FL" --pr "$pr" --binder "$BINDER" --pr-state MERGED \
        --merged-at 2026-07-31T10:00:00Z >/dev/null &
    done
    wait
    [ "$(grep -c '^- pr-' "$BINDER")" -eq 20 ]
    for pr in $(seq 1 20); do
      [ "$(grep -c "^- pr-$pr merged" "$BINDER")" -eq 1 ]
    done
    [ "$(grep -c '^## Finish' "$BINDER")" -eq 1 ]
  done
  # Locking must not leave repository-visible sidecars or atomic-write temps.
  run bash -c "ls -A '$BINDER_DIR' | grep -cE '\.(lock|tmp)$' || true"
  [[ "$output" == "0" ]]
}

@test "refuses a non-numeric --pr (URL from prose would stamp another repo)" {
  write_fresh_binder
  run bash "$FL" --pr "https://github.com/attacker/repo/pull/1" --binder "$BINDER" \
    --merged-at 2026-07-31T10:00:00Z
  [ "$status" -eq 2 ]
  [[ "$output" == *"--pr must be a positive GitHub PR number"* ]]
  grep -q '(none yet)' "$BINDER"
}

@test "refuses a non-numeric --issue and a malformed --repo" {
  write_fresh_binder
  run bash "$FL" --pr 12 --issue "7 --repo other/repo" --binder "$BINDER" \
    --merged-at 2026-07-31T10:00:00Z
  [ "$status" -eq 2 ]
  [[ "$output" == *"--issue must be a positive GitHub issue number"* ]]

  run bash "$FL" --pr 12 --binder "$BINDER" --repo "owner/repo/../../x" \
    --merged-at 2026-07-31T10:00:00Z
  [ "$status" -eq 2 ]
  [[ "$output" == *"--repo must be owner/name"* ]]
}

@test "refuses a symlinked binder pointing outside .lattice" {
  write_fresh_binder
  secret="$TEST_DIR/secret.txt"
  printf 'do not touch\n' >"$secret"
  ln -sf "$secret" "$BINDER_DIR/link.md"
  run bash "$FL" --pr 12 --binder "$BINDER_DIR/link.md" \
    --merged-at 2026-07-31T10:00:00Z
  [ "$status" -eq 1 ]
  [[ "$output" == *"symlinked binder path component"* ]]
  [ "$(cat "$secret")" = "do not touch" ]
}

@test "refuses a binder inside the repo but outside .lattice" {
  outside="$REPO/README.md"
  printf '# repo readme\n' >"$outside"
  run bash "$FL" --pr 12 --binder "$outside" --merged-at 2026-07-31T10:00:00Z
  [ "$status" -eq 1 ]
  [[ "$output" == *"must live under"* ]]
  [ "$(cat "$outside")" = "# repo readme" ]
}

@test "refuses a 'null' mergedAt instead of stamping it as a date" {
  write_fresh_binder
  run bash "$FL" --pr 12 --binder "$BINDER" --merged-at null
  [ "$status" -eq 1 ]
  [[ "$output" == *"not an ISO-8601 timestamp"* ]]
  grep -q '(none yet)' "$BINDER"
}

@test "an OPEN issue's 'null' closedAt records not-closed, not a bogus date" {
  write_fresh_binder
  run bash "$FL" --pr 12 --issue 7 --binder "$BINDER" \
    --merged-at 2026-07-31T10:00:00Z --closed-at null
  [ "$status" -eq 0 ]
  grep -q "pr-12 merged: 2026-07-31T10:00:00Z" "$BINDER"
  grep -qi "not closed" "$BINDER"
  ! grep -q "closed: null" "$BINDER"
  grep -qE '\| status \| open \|' "$BINDER"
}

@test "binder keeps its mode and leaves no temp residue after an atomic rewrite" {
  write_fresh_binder
  chmod 640 "$BINDER"
  run bash "$FL" --pr 12 --binder "$BINDER" --merged-at 2026-07-31T10:00:00Z
  [ "$status" -eq 0 ]
  perms=$(ls -l "$BINDER" | cut -c1-10)
  [ "$perms" = "-rw-r-----" ]
  run bash -c "ls -A '$BINDER_DIR' | grep -c '^\.finish-ledger\.' || true"
  [[ "$output" == "0" ]]
}

@test "refuses to stamp a PR from a different repository into this binder" {
  write_fresh_binder
  git -C "$REPO" remote add origin https://github.com/owner-a/repo-a.git
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
# whatever is asked, answer as a DIFFERENT repository
if [[ "$1" == "repo" ]]; then printf '%s\n' 'https://github.com/owner-b/repo-b'; exit 0; fi
printf '%s\n' '{"state":"MERGED","mergedAt":"2026-07-31T10:00:00Z","url":"https://github.com/owner-b/repo-b/pull/12"}'
EOF
  chmod +x "$TEST_DIR/bin/gh"

  run env PATH="$TEST_DIR/bin:$PATH" bash "$FL" --pr 12 --binder "$BINDER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"different repository"* ]]
  grep -q '(none yet)' "$BINDER"
}

@test "repository identity comparison is case-insensitive" {
  write_fresh_binder
  git -C "$REPO" remote add origin https://github.com/Acme/Repo.git
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "repo" ]]; then
  printf '%s\n' 'https://github.com/acme/repo'
  exit 0
fi
printf '%s\n' '{"state":"MERGED","mergedAt":"2026-07-31T10:00:00Z","url":"https://github.com/acme/repo/pull/12"}'
EOF
  chmod +x "$TEST_DIR/bin/gh"

  run env PATH="$TEST_DIR/bin:$PATH" bash "$FL" --pr 12 --binder "$BINDER"
  [ "$status" -eq 0 ]
  grep -q 'https://github.com/acme/repo/pull/12' "$BINDER"
}

@test "GitHub Enterprise origin is resolved through gh instead of github.com parsing" {
  write_fresh_binder
  git -C "$REPO" remote add origin https://ghe.example.com/acme/repo.git
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "repo" ]]; then
  printf '%s\n' 'https://ghe.example.com/acme/repo'
  exit 0
fi
printf '%s\n' '{"state":"MERGED","mergedAt":"2026-07-31T10:00:00Z","url":"https://ghe.example.com/acme/repo/pull/12"}'
EOF
  chmod +x "$TEST_DIR/bin/gh"

  run env PATH="$TEST_DIR/bin:$PATH" bash "$FL" --pr 12 --binder "$BINDER"
  [ "$status" -eq 0 ]
  grep -q 'https://ghe.example.com/acme/repo/pull/12' "$BINDER"
}

@test "online PR and issue JSON are parsed and stamped together" {
  write_fresh_binder
  git -C "$REPO" remote add origin https://github.com/acme/repo.git
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  repo) printf '%s\n' 'https://github.com/acme/repo' ;;
  pr) printf '%s\n' '{"state":"MERGED","mergedAt":"2026-07-31T10:00:00Z","url":"https://github.com/acme/repo/pull/12"}' ;;
  issue) printf '%s\n' '{"state":"CLOSED","closedAt":"2026-07-31T10:01:00Z"}' ;;
esac
EOF
  chmod +x "$TEST_DIR/bin/gh"

  run env PATH="$TEST_DIR/bin:$PATH" bash "$FL" --pr 12 --issue 7 --binder "$BINDER"
  [ "$status" -eq 0 ]
  grep -q 'pr-12 merged: 2026-07-31T10:00:00Z' "$BINDER"
  grep -q 'issue #7 closed: 2026-07-31T10:01:00Z' "$BINDER"
  grep -qE '\| status \| closed \|' "$BINDER"
}

@test "offline GitHub Enterprise override keeps the binder origin host in URLs" {
  write_fresh_binder
  git -C "$REPO" remote add origin git@ghe.example.com:acme/repo.git
  run bash "$FL" --pr 12 --binder "$BINDER" --repo acme/repo \
    --pr-state MERGED --merged-at 2026-07-31T10:00:00Z
  [ "$status" -eq 0 ]
  grep -q 'https://ghe.example.com/acme/repo/pull/12' "$BINDER"
}

@test "explicit GitHub Enterprise repo pins the host in gh queries" {
  write_fresh_binder
  git -C "$REPO" remote add origin https://ghe.example.com/acme/repo.git
  mkdir -p "$TEST_DIR/bin"
  GH_LOG="$TEST_DIR/gh.log"
  cat >"$TEST_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_LOG"
printf '%s\n' '{"state":"MERGED","mergedAt":"2026-07-31T10:00:00Z","url":"https://ghe.example.com/acme/repo/pull/12"}'
EOF
  chmod +x "$TEST_DIR/bin/gh"

  run env GH_LOG="$GH_LOG" PATH="$TEST_DIR/bin:$PATH" \
    bash "$FL" --pr 12 --binder "$BINDER" --repo acme/repo
  [ "$status" -eq 0 ]
  grep -Fq -- 'pr view 12 --repo ghe.example.com/acme/repo' "$GH_LOG"
}

@test "an explicit --repo that disagrees with the binder's origin is refused" {
  write_fresh_binder
  git -C "$REPO" remote add origin https://github.com/owner-a/repo-a.git
  run bash "$FL" --pr 12 --binder "$BINDER" --repo owner-b/repo-b
  [ "$status" -eq 1 ]
  [[ "$output" == *"different repository"* ]]
}

@test "same owner/repo on a different GitHub host is still refused" {
  write_fresh_binder
  git -C "$REPO" remote add origin https://github.com/acme/repo.git
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
exit 99
EOF
  chmod +x "$TEST_DIR/bin/gh"

  run env PATH="$TEST_DIR/bin:$PATH" GH_HOST=ghe.example.com \
    bash "$FL" --pr 12 --binder "$BINDER" --repo acme/repo
  [ "$status" -eq 1 ]
  [[ "$output" == *"different repository"* ]]
  [[ "$output" == *"github.com/acme/repo"* ]]
  [[ "$output" == *"ghe.example.com/acme/repo"* ]]
}

@test "--repo rejects traversal-shaped components" {
  write_fresh_binder
  for bad in "../evil" "owner/.." "./x" "owner/."; do
    run bash "$FL" --pr 12 --binder "$BINDER" --repo "$bad" --pr-state MERGED \
      --merged-at 2026-07-31T10:00:00Z
    [ "$status" -eq 2 ]
    [[ "$output" == *"--repo must be owner/name"* ]]
  done
  # a real name that merely starts with a dot is still accepted
  run bash "$FL" --pr 12 --binder "$BINDER" --repo "owner/.github" --pr-state MERGED \
    --merged-at 2026-07-31T10:00:00Z
  [ "$status" -eq 0 ]
}

@test "a (none) prs placeholder is replaced, never appended beside" {
  # digest rev-20260826-172600Z Findings 4: appending left "(none) · pr-N …"
  for placeholder in '(none)' '(none yet)' '(none — pending)'; do
    write_fresh_binder
    sed -i "s/| prs | (none yet) |/| prs | $placeholder |/" "$BINDER"
    run bash "$FL" --pr 12 --binder "$BINDER" --repo percena/lattice \
      --pr-state MERGED --merged-at 2026-07-31T10:00:00Z
    [ "$status" -eq 0 ]
    grep -q '| prs | pr-12 — https://github.com/percena/lattice/pull/12 |' "$BINDER"
    ! grep -qF "$placeholder ·" "$BINDER"
  done
}

@test "a filled prs row appends once and re-runs stay idempotent" {
  write_fresh_binder
  sed -i 's#| prs | (none yet) |#| prs | pr-11 — https://github.com/percena/lattice/pull/11 |#' "$BINDER"
  bash "$FL" --pr 12 --binder "$BINDER" --repo percena/lattice \
    --pr-state MERGED --merged-at 2026-07-31T10:00:00Z >/dev/null
  grep -q '| prs | pr-11 — https://github.com/percena/lattice/pull/11, pr-12 — https://github.com/percena/lattice/pull/12 |' "$BINDER"
  # idempotent: second run for the same PR leaves a single pr-12 entry
  bash "$FL" --pr 12 --binder "$BINDER" --repo percena/lattice \
    --pr-state MERGED --merged-at 2026-07-31T10:00:00Z >/dev/null
  prs_row="$(grep -m1 '^| prs |' "$BINDER")"
  [ "$(printf '%s' "$prs_row" | grep -o 'pr-12' | wc -l)" -eq 1 ]
  [ "$(printf '%s' "$prs_row" | grep -o 'pr-11' | wc -l)" -eq 1 ]
}

# tkt-90: the flip must cover the FSM working vocabulary, not just legacy `open`
# — stamp-pr-open stamps `pr-open`, which stranded 19 merged binders.

@test "pr-open binder: status flips to closed when issue closed" {
  write_fresh_binder
  sed -i 's#| status | open |#| status | pr-open |#' "$BINDER"
  run bash "$FL" --pr 12 --issue 7 --binder "$BINDER" --repo percena/lattice \
    --merged-at 2026-07-31T10:00:00Z --closed-at 2026-07-31T10:01:00Z
  [ "$status" -eq 0 ]
  grep -qE '\| status \| closed \|' "$BINDER"
}

@test "in-progress and rework binders: status flips to closed" {
  for st in in-progress rework; do
    write_fresh_binder
    sed -i "s#| status | open |#| status | $st |#" "$BINDER"
    bash "$FL" --pr 12 --issue 7 --binder "$BINDER" --repo percena/lattice \
      --merged-at 2026-07-31T10:00:00Z --closed-at 2026-07-31T10:01:00Z >/dev/null
    grep -qE '\| status \| closed \|' "$BINDER"
  done
}

@test "parked binder: status is NOT auto-flipped (needs human attention)" {
  write_fresh_binder
  sed -i 's#| status | open |#| status | parked |#' "$BINDER"
  run bash "$FL" --pr 12 --issue 7 --binder "$BINDER" --repo percena/lattice \
    --merged-at 2026-07-31T10:00:00Z --closed-at 2026-07-31T10:01:00Z
  [ "$status" -eq 0 ]
  grep -qE '\| status \| parked \|' "$BINDER"
}

# tkt-91: the prs grammar is single-sourced in lib/binder_rows.py — writers
# emit the tkt-74 canon (comma joiner, URL required), and the emitted row must
# satisfy the validator's canonical regex.

@test "multi-PR append emits the comma canon accepted by the validator" {
  write_fresh_binder
  bash "$FL" --pr 11 --binder "$BINDER" --repo percena/lattice \
    --pr-state MERGED --merged-at 2026-07-31T10:00:00Z >/dev/null
  bash "$FL" --pr 12 --binder "$BINDER" --repo percena/lattice \
    --pr-state MERGED --merged-at 2026-07-31T10:00:00Z >/dev/null
  row="$(grep -m1 '^| prs |' "$BINDER" | sed 's/^| prs | //; s/ |$//')"
  ROW="$row" python3 - "$(dirname "$FL")/lib" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
import binder_rows
row = os.environ["ROW"]
assert binder_rows.PRS_ROW_CANON_RE.fullmatch(row), f"off-canon row: {row!r}"
PY
}

@test "prs grammar in lib/binder_rows.py matches the validator's copy byte-for-byte" {
  python3 - "$(dirname "$FL")/lib" "$(cd "$(dirname "$FL")/../../.." && pwd)/tools/validate-lattice-artifacts.py" <<'PY'
import importlib.util, sys
sys.path.insert(0, sys.argv[1])
import binder_rows
spec = importlib.util.spec_from_file_location("val", sys.argv[2])
val = importlib.util.module_from_spec(spec)
spec.loader.exec_module(val)
assert binder_rows.PRS_PLACEHOLDER_RE.pattern == val.PRS_PLACEHOLDER_RE.pattern
assert binder_rows.PRS_ROW_CANON_RE.pattern == val.PRS_ROW_CANON_RE.pattern
PY
}

@test "no URL resolvable: prs row left untouched with a warning (bare pr-N never emitted)" {
  write_fresh_binder
  run bash "$FL" --pr 12 --binder "$BINDER" \
    --pr-state MERGED --merged-at 2026-07-31T10:00:00Z
  [ "$status" -eq 0 ]
  grep -q '| prs | (none yet) |' "$BINDER"
  ! grep -qE '\| prs \| pr-12 \|' "$BINDER"
}
