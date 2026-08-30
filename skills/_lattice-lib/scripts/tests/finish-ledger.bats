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
  printf '%s\n' "$output" | grep -qF "stamped"
  grep -q "pr-12 merged: 2026-07-31T10:00:00Z" "$BINDER"
  grep -q "pr-12 merged: 2026-07-31T10:00:00Z — https://github.com/percena/lattice/pull/12" "$BINDER"
  grep -q "issue #7 closed: 2026-07-31T10:01:00Z — https://github.com/percena/lattice/issues/7" "$BINDER"
  # issue URL must not be doubled
  if grep -q "github.com/https://github.com" "$BINDER"; then false; fi
  grep -qE '\| status \| closed \|' "$BINDER"
  [ "$(grep -c '^## Finish' "$BINDER")" -eq 1 ]
  if grep -q '(none yet)' "$BINDER"; then false; fi
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
  if grep -q "pr-12 merged: 2026-07-31T10:00:00Z" "$BINDER"; then false; fi
}

@test "no binder file: skip with note, exit 0 (not a failure)" {
  run bash "$FL" --pr 12 --binder "$BINDER_DIR/nonexistent.md" \
    --merged-at 2026-07-31T10:00:00Z
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "skip"
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
  if grep -q "pr-12 merged" "$BINDER"; then false; fi
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
  printf '%s\n' "$output" | grep -qF "still OPEN"
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
  [ "$output" = "0" ]
}

@test "refuses a non-numeric --pr (URL from prose would stamp another repo)" {
  write_fresh_binder
  run bash "$FL" --pr "https://github.com/attacker/repo/pull/1" --binder "$BINDER" \
    --merged-at 2026-07-31T10:00:00Z
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF -- "--pr must be a positive GitHub PR number"
  grep -q '(none yet)' "$BINDER"
}

@test "refuses a non-numeric --issue and a malformed --repo" {
  write_fresh_binder
  run bash "$FL" --pr 12 --issue "7 --repo other/repo" --binder "$BINDER" \
    --merged-at 2026-07-31T10:00:00Z
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF -- "--issue must be a positive GitHub issue number"

  run bash "$FL" --pr 12 --binder "$BINDER" --repo "owner/repo/../../x" \
    --merged-at 2026-07-31T10:00:00Z
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF -- "--repo must be owner/name"
}

@test "refuses a symlinked binder pointing outside .lattice" {
  write_fresh_binder
  secret="$TEST_DIR/secret.txt"
  printf 'do not touch\n' >"$secret"
  ln -sf "$secret" "$BINDER_DIR/link.md"
  run bash "$FL" --pr 12 --binder "$BINDER_DIR/link.md" \
    --merged-at 2026-07-31T10:00:00Z
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "symlinked binder path component"
  [ "$(cat "$secret")" = "do not touch" ]
}

@test "refuses a binder inside the repo but outside .lattice" {
  outside="$REPO/README.md"
  printf '# repo readme\n' >"$outside"
  run bash "$FL" --pr 12 --binder "$outside" --merged-at 2026-07-31T10:00:00Z
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "must live under"
  [ "$(cat "$outside")" = "# repo readme" ]
}

@test "refuses a 'null' mergedAt instead of stamping it as a date" {
  write_fresh_binder
  run bash "$FL" --pr 12 --binder "$BINDER" --merged-at null
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "not an ISO-8601 timestamp"
  grep -q '(none yet)' "$BINDER"
}

@test "an OPEN issue's 'null' closedAt records not-closed, not a bogus date" {
  write_fresh_binder
  run bash "$FL" --pr 12 --issue 7 --binder "$BINDER" \
    --merged-at 2026-07-31T10:00:00Z --closed-at null
  [ "$status" -eq 0 ]
  grep -q "pr-12 merged: 2026-07-31T10:00:00Z" "$BINDER"
  grep -qi "not closed" "$BINDER"
  if grep -q "closed: null" "$BINDER"; then false; fi
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
  [ "$output" = "0" ]
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
  printf '%s\n' "$output" | grep -qF "different repository"
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
  printf '%s\n' "$output" | grep -qF "different repository"
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
  printf '%s\n' "$output" | grep -qF "different repository"
  printf '%s\n' "$output" | grep -qF "github.com/acme/repo"
  printf '%s\n' "$output" | grep -qF "ghe.example.com/acme/repo"
}

@test "--repo rejects traversal-shaped components" {
  write_fresh_binder
  for bad in "../evil" "owner/.." "./x" "owner/."; do
    run bash "$FL" --pr 12 --binder "$BINDER" --repo "$bad" --pr-state MERGED \
      --merged-at 2026-07-31T10:00:00Z
    [ "$status" -eq 2 ]
    printf '%s\n' "$output" | grep -qF -- "--repo must be owner/name"
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
    sed -i.bak "s/| prs | (none yet) |/| prs | $placeholder |/" "$BINDER"
    rm -f "$BINDER.bak"
    run bash "$FL" --pr 12 --binder "$BINDER" --repo percena/lattice \
      --pr-state MERGED --merged-at 2026-07-31T10:00:00Z
    [ "$status" -eq 0 ]
    grep -q '| prs | pr-12 — https://github.com/percena/lattice/pull/12 |' "$BINDER"
    if grep -qF "$placeholder ·" "$BINDER"; then false; fi
  done
}

@test "a filled prs row appends once and re-runs stay idempotent" {
  write_fresh_binder
  sed -i.bak 's#| prs | (none yet) |#| prs | pr-11 — https://github.com/percena/lattice/pull/11 |#' "$BINDER"
  rm -f "$BINDER.bak"
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
  sed -i.bak 's#| status | open |#| status | pr-open |#' "$BINDER"
  rm -f "$BINDER.bak"
  run bash "$FL" --pr 12 --issue 7 --binder "$BINDER" --repo percena/lattice \
    --merged-at 2026-07-31T10:00:00Z --closed-at 2026-07-31T10:01:00Z
  [ "$status" -eq 0 ]
  grep -qE '\| status \| closed \|' "$BINDER"
}

@test "in-progress and rework binders: status flips to closed" {
  for st in in-progress rework; do
    write_fresh_binder
    sed -i.bak "s#| status | open |#| status | $st |#" "$BINDER"
    rm -f "$BINDER.bak"
    bash "$FL" --pr 12 --issue 7 --binder "$BINDER" --repo percena/lattice \
      --merged-at 2026-07-31T10:00:00Z --closed-at 2026-07-31T10:01:00Z >/dev/null
    grep -qE '\| status \| closed \|' "$BINDER"
  done
}

@test "parked binder with a closed issue flips to closed (tkt-150: parked no longer stranded)" {
  write_fresh_binder
  sed -i.bak 's#| status | open |#| status | parked |#' "$BINDER"
  rm -f "$BINDER.bak"
  run bash "$FL" --pr 12 --issue 7 --binder "$BINDER" --repo percena/lattice \
    --merged-at 2026-07-31T10:00:00Z --closed-at 2026-07-31T10:01:00Z
  [ "$status" -eq 0 ]
  grep -qE '\| status \| closed \|' "$BINDER"
}

# tkt-150: the cancel path and the full working-state vocabulary. The prior
# parked-preservation regression codified the contradiction (a closed issue left
# the binder working); it is replaced by a cancel-from-any-state matrix and the
# negative open/unknown cases.

@test "cancel-from-any-state matrix: --cancel closes every working state" {
  for st in open queued in-progress parked stuck pr-open rework deferred; do
    write_fresh_binder
    sed -i.bak "s#| status | open |#| status | $st |#" "$BINDER"
    rm -f "$BINDER.bak"
    run bash "$FL" --cancel --reason "human cancel: wontfix" \
      --closed-at 2026-07-31T10:01:00Z --binder "$BINDER"
    [ "$status" -eq 0 ]
    grep -qE '\| status \| closed \|' "$BINDER"
    grep -q '^- cancelled: human cancel: wontfix — 2026-07-31T10:01:00Z' "$BINDER"
    # no fabricated PR evidence
    if grep -qE '^- pr-' "$BINDER"; then false; fi
    if grep -q 'merged' "$BINDER"; then false; fi
    # prs row untouched (no PR URL, no warning fabricated into a row)
    grep -q '| prs | (none yet) |' "$BINDER"
  done
}

@test "cancel with a gh-verified CLOSED issue closes the ticket and stamps issue line" {
  write_fresh_binder
  git -C "$REPO" remote add origin https://github.com/acme/repo.git
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  repo) printf '%s\n' 'https://github.com/acme/repo' ;;
  issue) printf '%s\n' '{"state":"CLOSED","closedAt":"2026-07-31T10:01:00Z"}' ;;
esac
EOF
  chmod +x "$TEST_DIR/bin/gh"
  run env PATH="$TEST_DIR/bin:$PATH" bash "$FL" --cancel --reason "dup of #9" \
    --issue 7 --binder "$BINDER"
  [ "$status" -eq 0 ]
  grep -qE '\| status \| closed \|' "$BINDER"
  grep -q '^- cancelled: dup of #9' "$BINDER"
  grep -q '^- issue #7 closed: 2026-07-31T10:01:00Z — https://github.com/acme/repo/issues/7' "$BINDER"
  if grep -qE '^- pr-' "$BINDER"; then false; fi
}

@test "cancel with an OPEN issue fails closed (no terminal evidence)" {
  write_fresh_binder
  git -C "$REPO" remote add origin https://github.com/acme/repo.git
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  repo) printf '%s\n' 'https://github.com/acme/repo' ;;
  issue) printf '%s\n' '{"state":"OPEN","closedAt":null}' ;;
esac
EOF
  chmod +x "$TEST_DIR/bin/gh"
  run env PATH="$TEST_DIR/bin:$PATH" bash "$FL" --cancel --reason "x" \
    --issue 7 --binder "$BINDER"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "requires terminal evidence"
  printf '%s\n' "$output" | grep -qF "not closed"
  # binder untouched — no cancel line, status still open
  if grep -q '^- cancelled:' "$BINDER"; then false; fi
  grep -qE '\| status \| open \|' "$BINDER"
}

@test "cancel with an unverifiable issue (no gh / foreign repo) fails closed" {
  write_fresh_binder
  # no origin → binder repo unresolved → gh not usable → issue cannot be verified
  run bash "$FL" --cancel --reason "x" --issue 7 --binder "$BINDER"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "requires terminal evidence"
  if grep -q '^- cancelled:' "$BINDER"; then false; fi
}

@test "cancel rejects --pr, missing --reason, and missing terminal evidence" {
  write_fresh_binder
  # --pr is forbidden on the no-PR cancel path
  run bash "$FL" --cancel --reason "x" --pr 5 --closed-at 2026-07-31T10:01:00Z --binder "$BINDER"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "no-PR path"
  # --reason is required
  run bash "$FL" --cancel --closed-at 2026-07-31T10:01:00Z --binder "$BINDER"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF -- "--cancel requires --reason"
  # terminal evidence is required
  run bash "$FL" --cancel --reason "x" --binder "$BINDER"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "requires terminal evidence"
  # --pr-state/--merged-at forbidden on cancel
  run bash "$FL" --cancel --reason "x" --pr-state MERGED --closed-at 2026-07-31T10:01:00Z --binder "$BINDER"
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "no-PR path"
  # binder untouched across all
  grep -q '(none yet)' "$BINDER"
}

@test "cancel is idempotent and atomic: re-run updates reason, leaves no temp residue" {
  write_fresh_binder
  bash "$FL" --cancel --reason "first" --closed-at 2026-07-31T10:01:00Z --binder "$BINDER" >/dev/null
  run bash "$FL" --cancel --reason "second" --closed-at 2026-07-31T10:02:00Z --binder "$BINDER"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^- cancelled:' "$BINDER")" -eq 1 ]
  grep -q '^- cancelled: second — 2026-07-31T10:02:00Z' "$BINDER"
  if grep -q '^- cancelled: first' "$BINDER"; then false; fi
  [ "$(grep -c '^## Finish' "$BINDER")" -eq 1 ]
  run bash -c "ls -A '$BINDER_DIR' | grep -cE '\.(lock|tmp)$' || true"
  [ "$output" = "0" ]
}

@test "merged from parked/stuck/deferred flips to closed and surfaces anomaly (A2)" {
  for st in parked stuck deferred; do
    write_fresh_binder
    sed -i.bak "s#| status | open |#| status | $st |#" "$BINDER"
    rm -f "$BINDER.bak"
    bash "$FL" --pr 12 --binder "$BINDER" --repo percena/lattice --pr-state MERGED \
      --merged-at 2026-07-31T10:00:00Z >/dev/null
    grep -qE '\| status \| closed \|' "$BINDER"
    grep -q "pr-12 merged: 2026-07-31T10:00:00Z" "$BINDER"
    # literal backticks around the prior status — printf avoids command substitution
    anom_pat=$(printf 'anomaly: prior status `%s`' "$st")
    grep -qF "$anom_pat" "$BINDER"
    # anomaly line is not duplicated on re-run
    bash "$FL" --pr 12 --binder "$BINDER" --repo percena/lattice --pr-state MERGED \
      --merged-at 2026-07-31T10:00:00Z >/dev/null
    [ "$(grep -c '^- anomaly:' "$BINDER")" -eq 1 ]
  done
}

@test "closed-without-merge from parked with a closed issue flips to closed (no mergedAt)" {
  write_fresh_binder
  sed -i.bak 's#| status | open |#| status | parked |#' "$BINDER"
  rm -f "$BINDER.bak"
  run bash "$FL" --pr 12 --issue 7 --binder "$BINDER" --pr-state CLOSED \
    --closed-at 2026-07-31T10:01:00Z
  [ "$status" -eq 0 ]
  grep -q "pr-12 closed without merge" "$BINDER"
  if grep -q "pr-12 merged" "$BINDER"; then false; fi
  grep -qE '\| status \| closed \|' "$BINDER"
}

# spc-186 A4 / tkt-191: `updated` bumped atomically with the status flip.
# `created` is never touched. Bump is gated on a real mutation (idempotent
# re-run does not touch `updated`). Lazy migration: a binder with no `updated`
# row stamps cleanly (bump is a no-op when absent).

write_ts_binder() {
  write_fresh_binder
  sed -i.bak 's/| status | open |/| status | open |\n| created | 2026-01-01T00:00:00Z |\n| updated | 2026-01-01T00:00:00Z |/' "$BINDER"
  rm -f "$BINDER.bak"
}

@test "updated row is bumped atomically with the status→closed stamp (created untouched)" {
  write_ts_binder
  run bash "$FL" --pr 12 --issue 7 --binder "$BINDER" --repo percena/lattice \
    --merged-at 2026-07-31T10:00:00Z --closed-at 2026-07-31T10:01:00Z
  [ "$status" -eq 0 ]
  grep -qE '\| status \| closed \|' "$BINDER"
  grep -qE '\| updated \| 20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \|' "$BINDER"
  # old value gone (bumped, not duplicated)
  if grep -q '| updated | 2026-01-01T00:00:00Z |' "$BINDER"; then false; fi
  # created is never bumped
  grep -q '| created | 2026-01-01T00:00:00Z |' "$BINDER"
}

@test "idempotent re-run does not bump updated again (no change)" {
  write_ts_binder
  bash "$FL" --pr 12 --issue 7 --binder "$BINDER" --repo percena/lattice \
    --merged-at 2026-07-31T10:00:00Z --closed-at 2026-07-31T10:01:00Z >/dev/null
  cp "$BINDER" "$TEST_DIR/after-first.md"
  run bash "$FL" --pr 12 --issue 7 --binder "$BINDER" --repo percena/lattice \
    --merged-at 2026-07-31T10:00:00Z --closed-at 2026-07-31T10:01:00Z
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "no change (idempotent)"
  cmp -s "$BINDER" "$TEST_DIR/after-first.md"
}

@test "updated bump is a no-op when the row is absent (lazy migration, no insert)" {
  write_fresh_binder
  run bash "$FL" --pr 12 --issue 7 --binder "$BINDER" --repo percena/lattice \
    --merged-at 2026-07-31T10:00:00Z --closed-at 2026-07-31T10:01:00Z
  [ "$status" -eq 0 ]
  grep -qE '\| status \| closed \|' "$BINDER"
  if grep -qE '^\| updated \|' "$BINDER"; then false; fi
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

@test "stamp_updated bumps a present updated row and is a no-op when absent (tkt-191)" {
  python3 - "$(dirname "$FL")/lib" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import binder_rows

# present row → bumped in place; created untouched
text = "| status | queued |\n| created | 2026-01-01T00:00:00Z |\n| updated | 2026-01-01T00:00:00Z |"
out = binder_rows.stamp_updated(text, "2026-08-29T12:00:00Z")
assert "| updated | 2026-08-29T12:00:00Z |" in out, out
assert "| updated | 2026-01-01T00:00:00Z |" not in out, out
assert "| created | 2026-01-01T00:00:00Z |" in out, out

# absent row → no-op (lazy migration; never inserts)
bare = "| status | queued |\n"
assert binder_rows.stamp_updated(bare, "2026-08-29T12:00:00Z") == bare, "must not insert"
PY
}

@test "status vocabulary in lib/status_vocab.py matches the validator's copy (tkt-189)" {
  python3 - "$(dirname "$FL")/lib" "$(cd "$(dirname "$FL")/../../.." && pwd)/tools/validate-lattice-artifacts.py" <<'PY'
import importlib.util, sys
sys.path.insert(0, sys.argv[1])
import status_vocab
spec = importlib.util.spec_from_file_location("val", sys.argv[2])
val = importlib.util.module_from_spec(spec)
spec.loader.exec_module(val)
# Constants parity
assert status_vocab.STATUS_WORKING_ORDER == val.STATUS_WORKING_ORDER
assert status_vocab.STATUS_WORKING == val.STATUS_WORKING
assert status_vocab.STATUS_TERMINAL == val.STATUS_TERMINAL
assert status_vocab.STATUS_LEGACY == val.STATUS_LEGACY
assert status_vocab.STATUS_OK == val.STATUS_OK
assert status_vocab.SIDE_STATES == val.SIDE_STATES
assert status_vocab.DIRECT_JUMP_SOURCES == val.DIRECT_JUMP_SOURCES
# Coupled-field wait_reason vocabulary parity (tkt-190 / spc-186 A3)
assert status_vocab.STUCK_REASONS == val.STUCK_REASONS
assert status_vocab.DEFERRED_REASONS == val.DEFERRED_REASONS
assert "spec-superseded" in status_vocab.DEFERRED_REASONS
# Compiled regex pattern byte-equality (the load-bearing single-source check)
assert status_vocab.NONTERMINAL_RE.pattern == val.NONTERMINAL_RE.pattern
assert status_vocab.NONTERMINAL_ALT == val.NONTERMINAL_ALT
# Helpers agree
for s in ("queued", "in-progress", "parked", "stuck", "pr-open", "rework",
          "deferred", "open", "closed", "bogus"):
    assert status_vocab.is_terminal(s) == val.is_terminal(s), s
    assert status_vocab.is_nonterminal(s) == val.is_nonterminal(s), s
    assert status_vocab.is_side_state(s) == val.is_side_state(s), s
PY
}

@test "no URL resolvable: prs row left untouched with a warning (bare pr-N never emitted)" {
  write_fresh_binder
  run bash "$FL" --pr 12 --binder "$BINDER" \
    --pr-state MERGED --merged-at 2026-07-31T10:00:00Z
  [ "$status" -eq 0 ]
  grep -q '| prs | (none yet) |' "$BINDER"
  if grep -qE '\| prs \| pr-12 \|' "$BINDER"; then false; fi
}

@test "A3: garbage --closed-at on cancel path is rejected (ISO-8601 validation)" {
  write_fresh_binder
  run bash "$FL" --cancel --reason "wontfix" --closed-at "garbage-not-a-timestamp" \
    --binder "$BINDER"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qF "must be an ISO-8601 timestamp"
  # binder untouched
  grep -q '(none yet)' "$BINDER"
  if grep -q '^- cancelled:' "$BINDER"; then false; fi
}

@test "cancel with null closedAt stamps a visible unavailable marker (tkt-242 L4)" {
  write_fresh_binder
  git -C "$REPO" remote add origin https://github.com/acme/repo.git
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  repo) printf '%s\n' 'https://github.com/acme/repo' ;;
  issue) printf '%s\n' '{"state":"CLOSED","closedAt":null}' ;;
esac
EOF
  chmod +x "$TEST_DIR/bin/gh"
  run env PATH="$TEST_DIR/bin:$PATH" bash "$FL" --cancel --reason "dup of #9" \
    --issue 7 --binder "$BINDER"
  [ "$status" -eq 0 ]
  # NOT a silent dateless cancel — a visible closedAt-unavailable marker
  grep -q '^- cancelled: dup of #9 — closedAt: unavailable (issue #7 CLOSED but closedAt null)' "$BINDER"
  # no fabricated ISO date on the cancel line
  if grep -qE '^- cancelled: dup of #9 — 20[0-9]{2}-[0-9]{2}-[0-9]{2}T' "$BINDER"; then false; fi
  # terminal evidence exists (issue closed) so status still flips to closed
  grep -qE '\| status \| closed \|' "$BINDER"
  # no fabricated PR evidence
  if grep -qE '^- pr-' "$BINDER"; then false; fi
}

@test "cancel with null closedAt is idempotent (re-run updates the marker, not a duplicate line) (tkt-242 L4)" {
  write_fresh_binder
  git -C "$REPO" remote add origin https://github.com/acme/repo.git
  mkdir -p "$TEST_DIR/bin"
  cat >"$TEST_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  repo) printf '%s\n' 'https://github.com/acme/repo' ;;
  issue) printf '%s\n' '{"state":"CLOSED","closedAt":null}' ;;
esac
EOF
  chmod +x "$TEST_DIR/bin/gh"
  env PATH="$TEST_DIR/bin:$PATH" bash "$FL" --cancel --reason "first" \
    --issue 7 --binder "$BINDER" >/dev/null
  run env PATH="$TEST_DIR/bin:$PATH" bash "$FL" --cancel --reason "second" \
    --issue 7 --binder "$BINDER"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^- cancelled:' "$BINDER")" -eq 1 ]
  grep -q '^- cancelled: second — closedAt: unavailable' "$BINDER"
  if grep -q '^- cancelled: first' "$BINDER"; then false; fi
}
