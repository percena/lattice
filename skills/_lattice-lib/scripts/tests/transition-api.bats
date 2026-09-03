#!/usr/bin/env bats
# transition-api + validator ledger replay (spc-254 A3): the API records legal
# flips, refuses illegal edges and escape-required edges without an operator
# override, and the validator replays the ledger to reject an illegal edge
# between two legal snapshots.

setup() {
  SCRIPT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  export API="$SCRIPT_DIR/transition-api.py"
  export VALIDATOR="$REPO_ROOT/tools/validate-lattice-artifacts.py"
  export LATTICE_HOME="$BATS_RUN_TMPDIR/lattice"
  mkdir -p "$LATTICE_HOME/.transition-ledger"
  rm -rf "$LATTICE_HOME/.transition-ledger"
  mkdir -p "$LATTICE_HOME/.transition-ledger"
}

@test "legal edge exits 0 (queued -> in-progress)" {
  run python3 "$API" legal queued in-progress
  [ "$status" -eq 0 ]
}

@test "illegal edge exits non-zero (closed -> queued: terminal is not a source)" {
  run python3 "$API" legal closed queued
  [ "$status" -ne 0 ]
}

@test "record appends a legal ledger entry" {
  run python3 "$API" record tkt-1 queued in-progress system spawn
  [ "$status" -eq 0 ]
  grep -q '"from":"queued"' "$LATTICE_HOME/.transition-ledger/tkt-1.jsonl"
  grep -q '"to":"in-progress"' "$LATTICE_HOME/.transition-ledger/tkt-1.jsonl"
}

@test "record refuses an illegal edge (no ledger entry written)" {
  run python3 "$API" record tkt-1 closed queued agent reopen
  [ "$status" -eq 1 ]
  [ ! -s "$LATTICE_HOME/.transition-ledger/tkt-1.jsonl" ]
}

@test "escape-required edge refused without operator override (exit 2)" {
  run python3 "$API" record tkt-1 parked pr-open agent force
  [ "$status" -eq 2 ]
  [ ! -s "$LATTICE_HOME/.transition-ledger/tkt-1.jsonl" ]
}

@test "escape-required edge recorded with operator override" {
  run python3 "$API" record tkt-1 parked pr-open agent force \
    --force-side-state-reason "operator: merge urgency"
  [ "$status" -eq 0 ]
  grep -q '"force_side_state_reason":"operator: merge urgency"' \
    "$LATTICE_HOME/.transition-ledger/tkt-1.jsonl"
}

@test "validator replays ledger: legal entry yields no illegal_transition_edge" {
  python3 "$API" record tkt-1 queued in-progress system spawn >/dev/null
  run python3 "$VALIDATOR" --home "$LATTICE_HOME"
  [ "$status" -eq 0 ]
  run grep -qF "illegal_transition_edge" <<<"$output"
  [ "$status" -ne 0 ]
}

@test "validator replays ledger: illegal edge fails the run" {
  printf '%s\n' '{"ts":"2026-08-31T00:00:00Z","ticket":"tkt-1","from":"closed","to":"queued","owner":"agent","reason":"reopen","force_side_state_reason":null}' \
    > "$LATTICE_HOME/.transition-ledger/tkt-1.jsonl"
  run python3 "$VALIDATOR" --home "$LATTICE_HOME"
  [ "$status" -eq 1 ]
  grep -q "illegal_transition_edge" <<<"$output"
}

@test "validator replays ledger: escape-required without override fails" {
  printf '%s\n' '{"ts":"2026-08-31T00:00:00Z","ticket":"tkt-1","from":"parked","to":"pr-open","owner":"agent","reason":"force","force_side_state_reason":null}' \
    > "$LATTICE_HOME/.transition-ledger/tkt-1.jsonl"
  run python3 "$VALIDATOR" --home "$LATTICE_HOME"
  [ "$status" -eq 1 ]
  grep -q "illegal_transition_edge" <<<"$output"
}

# ---------------------------------------------------------------------------
# spc-270 A1.5: the validator's inline replay enforces the three continuity
# invariants (identity / continuity / snapshot) so CI catches ledger↔binder
# drift — the finish-ledger close-without-ledger-entry class — not just edge
# legality. These mirror transition-api replay-ledger tests 19-22 but exercise
# the validator's own replay path.
# ---------------------------------------------------------------------------

@test "validator flags snapshot mismatch: ledger final to != binder status" {
  B=$(make_binder tkt-30)   # binder stays queued
  python3 "$API" record tkt-30 queued in-progress system spawn >/dev/null
  run python3 "$VALIDATOR" --home "$LATTICE_HOME"
  [ "$status" -eq 1 ]
  grep -qF "transition_ledger_snapshot_mismatch" <<<"$output"
}

@test "validator flags discontinuity: entry.from != prior entry.to" {
  printf '%s\n%s\n' \
    '{"ts":"2026-08-31T00:00:00Z","ticket":"tkt-31","from":"queued","to":"in-progress","owner":"system","reason":"spawn","force_side_state_reason":null}' \
    '{"ts":"2026-08-31T00:00:01Z","ticket":"tkt-31","from":"parked","to":"queued","owner":"human","reason":"x","force_side_state_reason":null}' \
    > "$LATTICE_HOME/.transition-ledger/tkt-31.jsonl"
  run python3 "$VALIDATOR" --home "$LATTICE_HOME"
  [ "$status" -eq 1 ]
  grep -qF "transition_ledger_discontinuity" <<<"$output"
}

@test "validator flags identity mismatch: entry ticket != ledger file ticket" {
  printf '%s\n' '{"ts":"2026-08-31T00:00:00Z","ticket":"tkt-999","from":"queued","to":"in-progress","owner":"system","reason":"spawn","force_side_state_reason":null}' \
    > "$LATTICE_HOME/.transition-ledger/tkt-32.jsonl"
  run python3 "$VALIDATOR" --home "$LATTICE_HOME"
  [ "$status" -eq 1 ]
  grep -qF "transition_ledger_identity_mismatch" <<<"$output"
}

@test "validator passes a clean chain whose final snapshot matches the binder" {
  B=$(make_binder tkt-33)
  python3 "$API" commit tkt-33 in-progress system spawn >/dev/null
  run python3 "$VALIDATOR" --home "$LATTICE_HOME"
  [ "$status" -eq 0 ]
}

# --- spc-270 A1.1: atomic binder-bound `commit` ---------------------------

# Minimal binder with the field-table rows the writers ship. Returns the path.
make_binder() {
  local id="$1" slug="${2:-slice}"
  local dir="$LATTICE_HOME/tickets/${id}-${slug}"
  mkdir -p "$dir"
  cat > "$dir/README.md" <<MD
# ${id} — ${slug}

| Field | Value |
| --- | --- |
| status | queued |
| wait_reason | (none) |
| updated | 2026-08-31T00:00:00Z |
MD
  echo "$dir/README.md"
}

@test "commit atomically mutates binder status/wait_reason/updated + ledger" {
  B=$(make_binder tkt-10)
  run python3 "$API" commit tkt-10 in-progress system spawn
  [ "$status" -eq 0 ]
  grep -q '| status | in-progress |' "$B"
  grep -q '| wait_reason | (none) |' "$B"
  # updated stamp bumped off the seed value (any real ISO-8601 UTC stamp
  # that is not the seed 2026-08-31T00:00:00Z).
  grep -qE '\| updated \| 20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \|' "$B"
  if grep -qF '| updated | 2026-08-31T00:00:00Z |' "$B"; then false; fi
  grep -q '"from":"queued"' "$LATTICE_HOME/.transition-ledger/tkt-10.jsonl"
  grep -q '"to":"in-progress"' "$LATTICE_HOME/.transition-ledger/tkt-10.jsonl"
}

@test "commit refuses illegal edge: binder and ledger unchanged (fail-close)" {
  B=$(make_binder tkt-11)
  # queued -> in-progress is legal; in-progress -> queued is NOT an edge
  # (no return-to-queue; the schema intentionally omits it).
  python3 "$API" commit tkt-11 in-progress system spawn >/dev/null
  run python3 "$API" commit tkt-11 queued agent skip
  [ "$status" -eq 1 ]
  grep -q '| status | in-progress |' "$B"
  # The refused flip recorded no second ledger entry.
  [ "$(wc -l < "$LATTICE_HOME/.transition-ledger/tkt-11.jsonl")" -eq 1 ]
}

@test "commit refuses escape-required edge without override (exit 2, no write)" {
  B=$(make_binder tkt-12)
  # First move queued -> in-progress -> parked so a parked->pr-open force is reachable.
  python3 "$API" commit tkt-12 in-progress system spawn >/dev/null
  python3 "$API" commit tkt-12 parked agent park >/dev/null
  run python3 "$API" commit tkt-12 pr-open agent force
  [ "$status" -eq 2 ]
  grep -q '| status | parked |' "$B"
}

@test "commit enforces coupled wait_reason for stuck (fail-close)" {
  B=$(make_binder tkt-13)
  python3 "$API" commit tkt-13 in-progress system spawn >/dev/null
  run python3 "$API" commit tkt-13 stuck agent block
  [ "$status" -eq 1 ]
  grep -q '| status | in-progress |' "$B"
  # No ledger entry recorded for the refused flip.
  if grep -q '"to":"stuck"' "$LATTICE_HOME/.transition-ledger/tkt-13.jsonl"; then false; fi
}

@test "commit accepts stuck with --wait-reason unblock" {
  B=$(make_binder tkt-14)
  python3 "$API" commit tkt-14 in-progress system spawn >/dev/null
  run python3 "$API" commit tkt-14 stuck agent block --wait-reason unblock
  [ "$status" -eq 0 ]
  grep -q '| status | stuck |' "$B"
  grep -q '| wait_reason | unblock |' "$B"
}

@test "commit --from continuity guard rejects a stale expected prior" {
  B=$(make_binder tkt-15)
  # Binder is queued; caller asserts from=in-progress (wrong) -> refused.
  run python3 "$API" commit tkt-15 pr-open agent open --from in-progress
  [ "$status" -eq 1 ]
  grep -q '| status | queued |' "$B"
  [ ! -s "$LATTICE_HOME/.transition-ledger/tkt-15.jsonl" ]
}

@test "commit --dry-run writes neither binder nor ledger" {
  B=$(make_binder tkt-16)
  run python3 "$API" commit tkt-16 in-progress system spawn --dry-run
  [ "$status" -eq 0 ]
  grep -q '| status | queued |' "$B"
  [ ! -s "$LATTICE_HOME/.transition-ledger/tkt-16.jsonl" ]
}

@test "commit records the legal pr-open -> pr-open rebase-void self-edge" {
  B=$(make_binder tkt-17)
  python3 "$API" commit tkt-17 in-progress system spawn >/dev/null
  python3 "$API" commit tkt-17 pr-open agent open >/dev/null
  run python3 "$API" commit tkt-17 pr-open system rebase-void
  [ "$status" -eq 0 ]
  grep -q '"from":"pr-open"' "$LATTICE_HOME/.transition-ledger/tkt-17.jsonl"
  grep -q '"to":"pr-open"' "$LATTICE_HOME/.transition-ledger/tkt-17.jsonl"
}

# --- spc-270 A1.2: fault injection (no partial state on write failure) ------

@test "commit aborts on ledger-write failure: binder unchanged, no temp residue" {
  B=$(make_binder tkt-20)
  # One clean transition first so the binder is in-progress and a further
  # flip is legal (in-progress -> parked).
  python3 "$API" commit tkt-20 in-progress system spawn >/dev/null
  ledger="$LATTICE_HOME/.transition-ledger/tkt-20.jsonl"
  before_path="$LATTICE_HOME/.binder-before-20"
  ledger_backup="$LATTICE_HOME/.ledger-before-20"
  cp "$B" "$before_path"
  cp "$ledger" "$ledger_backup"
  before_lines=$(wc -l < "$ledger")
  # tkt-353: make the ledger append fail in a uid-independent way. Root
  # ignores mode bits (chmod 000 is a no-op for uid 0), so replace the
  # ledger FILE with a directory: lp.open("a") raises IsADirectoryError
  # (OSError) inside commit_transaction's try block for every uid, aborting
  # the transaction before the binder rename (fail-close, exit 3).
  rm -f "$ledger"
  mkdir "$ledger"
  run python3 "$API" commit tkt-20 parked agent park
  # Restore the ledger file so the line-count assertion can read it.
  rmdir "$ledger" 2>/dev/null || true
  cp "$ledger_backup" "$ledger"
  [ "$status" -eq 3 ]
  # Binder byte-identical to pre-attempt snapshot (fail-close left it unchanged).
  diff "$before_path" "$B"
  # Ledger line count unchanged (no misleading record).
  [ "$(wc -l < "$ledger")" -eq "$before_lines" ]
  # No stray temp file left in the binder directory.
  [ -z "$(find "$LATTICE_HOME/tickets/tkt-20-slice" -name '*.tmp' -print)" ]
}

# --- spc-270 A1.4: replay identity / continuity / snapshot invariants -------

@test "replay flags a ticket-identity mismatch" {
  B=$(make_binder tkt-30)
  printf '%s\n' '{"ticket":"tkt-999","from":"queued","to":"in-progress","owner":"x","reason":"y"}' \
    > "$LATTICE_HOME/.transition-ledger/tkt-30.jsonl"
  run python3 "$API" replay-ledger
  [ "$status" -eq 1 ]
  grep -q 'identity mismatch' <<<"$output"
}

@test "replay flags a discontinuity (entry.from != prior entry.to)" {
  B=$(make_binder tkt-31)
  {
    printf '%s\n' '{"ticket":"tkt-31","from":"queued","to":"in-progress","owner":"x","reason":"y"}'
    printf '%s\n' '{"ticket":"tkt-31","from":"parked","to":"pr-open","owner":"x","reason":"y"}'
  } > "$LATTICE_HOME/.transition-ledger/tkt-31.jsonl"
  run python3 "$API" replay-ledger
  [ "$status" -eq 1 ]
  grep -q 'discontinuity' <<<"$output"
}

@test "replay flags a final-snapshot mismatch vs the binder" {
  B=$(make_binder tkt-32)
  # Ledger claims queued -> in-progress, but the binder is still queued.
  printf '%s\n' '{"ticket":"tkt-32","from":"queued","to":"in-progress","owner":"x","reason":"y"}' \
    > "$LATTICE_HOME/.transition-ledger/tkt-32.jsonl"
  run python3 "$API" replay-ledger
  [ "$status" -eq 1 ]
  grep -q 'snapshot mismatch' <<<"$output"
}

@test "replay passes a clean consistent chain" {
  B=$(make_binder tkt-33)
  python3 "$API" commit tkt-33 in-progress system spawn >/dev/null
  python3 "$API" commit tkt-33 pr-open agent open >/dev/null
  run python3 "$API" replay-ledger
  [ "$status" -eq 0 ]
  grep -q '0 illegal/inconsistent' <<<"$output"
}

# --- spc-337 A1: the ledger lives in the binder's OWN home, never cwd -------

@test "spc-337 A1: commit from a foreign cwd with LATTICE_HOME unset lands the ledger under the binder home" {
  B=$(make_binder tkt-31)
  OTHER="$BATS_RUN_TMPDIR/elsewhere-31"
  mkdir -p "$OTHER"
  # Fault injection: the pre-spc-337 API resolved `.lattice/.transition-ledger`
  # relative to cwd, so this exact call wrote the ledger under $OTHER/.lattice
  # and the writer's `git add <binder home>/.transition-ledger/...` staged
  # nothing (tkt-335). The binder path is the only home that counts.
  run env -u LATTICE_HOME bash -c "cd '$OTHER' && python3 '$API' commit tkt-31 in-progress system spawn --binder '$B'"
  [ "$status" -eq 0 ]
  [ -s "$LATTICE_HOME/.transition-ledger/tkt-31.jsonl" ]
  grep -q '"to":"in-progress"' "$LATTICE_HOME/.transition-ledger/tkt-31.jsonl"
  [ ! -e "$OTHER/.lattice/.transition-ledger/tkt-31.jsonl" ]
}

@test "spc-337 A1: home_for_binder derives <home> from <home>/tickets/<dir>/README.md and None otherwise" {
  run python3 - "$API" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location('ta', sys.argv[1])
ta = importlib.util.module_from_spec(spec); spec.loader.exec_module(ta)
assert str(ta.home_for_binder('/x/.lattice/tickets/tkt-9-s/README.md')) == '/x/.lattice'
assert ta.home_for_binder('/x/other/README.md') is None
assert ta.home_for_binder(None) is None
assert str(ta.ledger_path('tkt-9', '/x/.lattice')) == '/x/.lattice/.transition-ledger/tkt-9.jsonl'
PY
  [ "$status" -eq 0 ]
}

# --- spc-337 A2: explicit terminal edges, no `any -> closed` wildcard --------

@test "spc-337 A2: every working state has an explicit -> closed edge; 'any' is not a source" {
  for frm in queued in-progress parked stuck rework deferred pr-open open; do
    run python3 "$API" legal "$frm" closed
    [ "$status" -eq 0 ]
  done
  run python3 "$API" legal any closed
  [ "$status" -ne 0 ]
  run python3 "$API" legal closed closed
  [ "$status" -ne 0 ]
}

@test "spc-337 A2: a merge committed from queued carries metric direct-jump" {
  B=$(make_binder tkt-32)
  run python3 "$API" commit tkt-32 closed human merge --binder "$B"
  [ "$status" -eq 0 ]
  grep -q '"metric":"direct-jump"' "$LATTICE_HOME/.transition-ledger/tkt-32.jsonl"
  grep -q '"from":"queued"' "$LATTICE_HOME/.transition-ledger/tkt-32.jsonl"
}

@test "spc-337 A2 (review cycle 1): a CANCEL committed from queued is metric cancel-count, not direct-jump" {
  B=$(make_binder tkt-33)
  run python3 "$API" commit tkt-33 closed human cancel --binder "$B"
  [ "$status" -eq 0 ]
  grep -q '"metric":"cancel-count"' "$LATTICE_HOME/.transition-ledger/tkt-33.jsonl"
  if grep -q '"metric":"direct-jump"' "$LATTICE_HOME/.transition-ledger/tkt-33.jsonl"; then false; fi
}

# --- tkt-352 / ADR-012 §4: record home resolution + --help (A1/A2) -----------

@test "tkt-352 A2: --help prints usage and exits 0" {
  run python3 "$API" --help
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'Usage:'
  run python3 "$API" -h
  [ "$status" -eq 0 ]
}

@test "tkt-352 A2: record --help and commit --help print usage and exit 0" {
  run python3 "$API" record --help
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'usage:.*record'
  run python3 "$API" commit --help
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'usage:.*commit'
}

@test "tkt-352 A1: --home overrides the ledger home for record" {
  other="$BATS_RUN_TMPDIR/other-home"
  mkdir -p "$other/.transition-ledger"
  run env -u LATTICE_HOME python3 "$API" record tkt-40 queued in-progress system spawn --home "$other"
  [ "$status" -eq 0 ]
  [ -s "$other/.transition-ledger/tkt-40.jsonl" ]
}

@test "tkt-352 A1: record from a non-toplevel cwd lands under the repo .lattice (LATTICE_HOME unset)" {
  # Build a throwaway git repo so `git rev-parse --show-toplevel` resolves.
  repo="$BATS_RUN_TMPDIR/mini-repo"
  mkdir -p "$repo/sub/dir/.lattice/.transition-ledger"
  ( cd "$repo" && git init -q && git add -A >/dev/null 2>&1 && git commit -qm init >/dev/null 2>&1 ) || true
  # Run record from a deep subdir with LATTICE_HOME unset — the entry must land
  # under <repo>/.lattice, not <cwd>/.lattice.
  run env -u LATTICE_HOME bash -c "cd '$repo/sub/dir' && python3 '$API' record tkt-41 queued in-progress system spawn"
  [ "$status" -eq 0 ]
  [ -s "$repo/.lattice/.transition-ledger/tkt-41.jsonl" ]
  # And NOT under the cwd.
  [ ! -s "$repo/sub/dir/.lattice/.transition-ledger/tkt-41.jsonl" ]
}

# --- spc-430 A1: rollback path coverage (rename-failure → _rollback_ledger) --
# spc-427 A1 added a flock to _rollback_ledger so a concurrent recorder's entry
# is not clobbered by write_text. The existing fault test (ledger-write fail)
# never reaches _rollback_ledger (invoked only on rename failure). These two
# tests close that gap: (1) the rename→rollback path runs and preserves a
# concurrent entry; (2) _rollback_ledger acquires the per-ticket flock — a
# deterministic regression guard that fails if the spc-427 A1 lock is removed.

@test "spc-430 A1: rename failure rolls back the failed commit entry; concurrent recorder's entry preserved" {
  B=$(make_binder tkt-44)
  # Prior legal transition queued -> in-progress (so in-progress -> parked legal)
  python3 "$API" commit tkt-44 in-progress system spawn >/dev/null
  ledger="$LATTICE_HOME/.transition-ledger/tkt-44.jsonl"
  # A concurrent recorder appends an entry to the same ledger BEFORE the
  # failed commit's rollback runs (queued -> in-progress is always legal).
  python3 "$API" record tkt-44 queued in-progress bg concurrent >/dev/null
  # Inject a rename failure in-process and call commit_transaction directly so
  # os.replace raises → _rollback_ledger runs (the previously-untested path).
  python3 - "$API" "$B" "$ledger" <<'PY'
import os, sys, json, importlib.util
from pathlib import Path
api_path, binder_path, ledger_path_ = sys.argv[1:4]
spec = importlib.util.spec_from_file_location("ta", api_path)
ta = importlib.util.module_from_spec(spec); spec.loader.exec_module(ta)
binder = Path(binder_path)
lp = Path(ledger_path_)
# The commit's own entry (in-progress -> parked). The exact metric value does
# not matter — append and rollback share the SAME dict so the needle matches.
entry = {
  "ts": "2026-09-03T00:00:05Z", "ticket": "tkt-44", "from": "in-progress",
  "to": "parked", "owner": "fg", "reason": "park", "guard": "none",
  "escape_used": False, "force_side_state_reason": None, "trace": None,
  "metric": "normal",
}
new_text = binder.read_text(encoding="utf-8").replace("| in-progress |", "| parked |")
_real = os.replace
os.replace = lambda *a, **k: (_ for _ in ()).throw(OSError("injected rename failure"))
try:
    rc = ta.commit_transaction(binder, new_text, entry)
finally:
    os.replace = _real
assert rc == 3, f"expected exit 3 (transaction aborted), got {rc}"
lines = lp.read_text(encoding="utf-8").splitlines()
# The concurrent recorder's entry must survive the rollback.
assert any('"reason":"concurrent"' in l for l in lines), f"concurrent entry clobbered: {lines}"
# The failed commit's own entry must have been rolled back (removed).
assert not any('"reason":"park"' in l for l in lines), f"failed commit entry not rolled back: {lines}"
PY
}

@test "spc-430 A1: _rollback_ledger acquires the per-ticket flock (regression guard — fails if spc-427 A1 lock removed)" {
  B=$(make_binder tkt-45)
  # One entry so the ledger exists and _rollback_ledger has something to read.
  python3 "$API" record tkt-45 queued in-progress sys spawn >/dev/null
  ledger="$LATTICE_HOME/.transition-ledger/tkt-45.jsonl"
  # Resolve the exact lock path transition-api uses (state-home sidecar).
  LOCKP=$(python3 - "$API" "$LATTICE_HOME" <<'PY'
import sys, importlib.util
spec = importlib.util.spec_from_file_location("ta", sys.argv[1])
ta = importlib.util.module_from_spec(spec); spec.loader.exec_module(ta)
print(ta.lock_path("tkt-45", sys.argv[2]))
PY
)
  mkdir -p "$(dirname "$LOCKP")"
  # Background: hold the per-ticket flock for ~2s (separate process so the
  # lock is genuinely contended — flock is per-process on BSD/macOS).
  ( python3 - "$LOCKP" <<'PY'
import sys, os, fcntl, time
fd = os.open(sys.argv[1], os.O_CREAT | os.O_WRONLY, 0o644)
fcntl.flock(fd, fcntl.LOCK_EX)
time.sleep(2)
fcntl.flock(fd, fcntl.LOCK_UN)
os.close(fd)
PY
  ) &
  BG=$!
  sleep 0.5  # let the background holder acquire the lock first
  # Foreground: _rollback_ledger must block on the flock (~1.5s) then complete.
  # Without the spc-427 A1 lock (regression) it completes in <0.1s → assert fails.
  python3 - "$API" "$ledger" <<'PY'
import sys, json, time, importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location("ta", sys.argv[1])
ta = importlib.util.module_from_spec(spec); spec.loader.exec_module(ta)
lp = Path(sys.argv[2])
entry = json.loads(lp.read_text(encoding="utf-8").strip())
start = time.time()
ta._rollback_ledger(lp, entry)
elapsed = time.time() - start
assert elapsed > 1.0, f"_rollback_ledger did not block on flock (elapsed={elapsed:.2f}s) — spc-427 A1 lock removed?"
PY
  wait "$BG" 2>/dev/null || true
}
