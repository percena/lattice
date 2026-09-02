#!/usr/bin/env bats
# Tests for queue-health.sh + lib/queue_health.py (spc-186 A5, ADR-007 §8).
# Advisory water-level sensor — never a HARD block. Covers threshold loading,
# binder scanning, age computation, banner/section formatting, gh fallback.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export QH="$REPO_ROOT/skills/_lattice-lib/scripts/queue-health.sh"
  export QH_LIB="$REPO_ROOT/skills/_lattice-lib/scripts/lib"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/qh.XXXXXX")"
  LATTICE_HOME="$TEST_DIR/.lattice"
  TICKETS="$LATTICE_HOME/tickets"
  mkdir -p "$TICKETS"
  # Minimal config.yaml so the home resolves.
  printf 'profile: strict\n' >"$LATTICE_HOME/config.yaml"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Write a binder with a status + updated + prs row under tkt-N-slug/.
write_binder() {
  local dir="$TICKETS/$1"
  mkdir -p "$dir"
  cat >"$dir/README.md" <<EOF
# $1

| Field | Value |
| --- | --- |
| status | $2 |
| updated | $3 |
| prs | $4 |
| wait_reason | $5 |
EOF
}

# ---------------------------------------------------------------------------
# lib/queue_health.py — threshold loading
# ---------------------------------------------------------------------------

@test "load_thresholds returns defaults when no config" {
  HOME="" python3 - "$QH_LIB" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
import queue_health as qh
t = qh.load_thresholds("")
assert t == {"pr_open_hours": 36, "side_state_total": 5}, t
PY
}

@test "load_thresholds reads overrides from config.yaml queue_health block" {
  cat >>"$LATTICE_HOME/config.yaml" <<'EOF'
queue_health:
  pr_open_hours: 48
  side_state_total: 3
EOF
  HOME="$LATTICE_HOME" python3 - "$QH_LIB" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
import queue_health as qh
t = qh.load_thresholds(os.environ["HOME"])
assert t == {"pr_open_hours": 48, "side_state_total": 3}, t
PY
}

@test "load_thresholds exits block at new top-level key" {
  cat >>"$LATTICE_HOME/config.yaml" <<'EOF'
queue_health:
  pr_open_hours: 72
other_key:
  pr_open_hours: 999
EOF
  HOME="$LATTICE_HOME" python3 - "$QH_LIB" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
import queue_health as qh
t = qh.load_thresholds(os.environ["HOME"])
assert t["pr_open_hours"] == 72, t
assert t["side_state_total"] == 5, t
PY
}

# ---------------------------------------------------------------------------
# lib/queue_health.py — scan_binders
# ---------------------------------------------------------------------------

@test "scan_binders collects parked/stuck/deferred as water-level states" {
  NOW="2026-08-29T12:00:00Z"
  write_binder tkt-1-one parked "2026-08-29T10:00:00Z" "(none)" "unblock"
  write_binder tkt-2-two stuck "2026-08-28T12:00:00Z" "(none)" "re-scope"
  write_binder tkt-3-three deferred "2026-08-27T00:00:00Z" "(none)" "fuse-halt"
  write_binder tkt-4-four queued "2026-08-29T10:00:00Z" "(none)" "(none)"
  HOME="$TICKETS" python3 - "$QH_LIB" "$NOW" <<'PY'
import datetime, os, sys
sys.path.insert(0, sys.argv[1])
import queue_health as qh
now = datetime.datetime.strptime(sys.argv[2], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
data = qh.scan_binders(os.environ["HOME"], now=now)
assert data["side_state_total"] == 3, data["side_state_total"]
statuses = sorted(d["status"] for d in data["side_states"])
assert statuses == ["deferred", "parked", "stuck"], statuses
PY
}

@test "scan_binders excludes rework from water-level states" {
  NOW="2026-08-29T12:00:00Z"
  write_binder tkt-5-five rework "2026-08-29T10:00:00Z" "(none)" "(none)"
  HOME="$TICKETS" python3 - "$QH_LIB" "$NOW" <<'PY'
import datetime, os, sys
sys.path.insert(0, sys.argv[1])
import queue_health as qh
now = datetime.datetime.strptime(sys.argv[2], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
data = qh.scan_binders(os.environ["HOME"], now=now)
assert data["side_state_total"] == 0, data["side_state_total"]
PY
}

@test "scan_binders computes side-state age from binder updated" {
  NOW="2026-08-29T12:00:00Z"
  write_binder tkt-6-six parked "2026-08-29T00:00:00Z" "(none)" "unblock"
  HOME="$TICKETS" python3 - "$QH_LIB" "$NOW" <<'PY'
import datetime, os, sys
sys.path.insert(0, sys.argv[1])
import queue_health as qh
now = datetime.datetime.strptime(sys.argv[2], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
data = qh.scan_binders(os.environ["HOME"], now=now)
assert data["side_state_total"] == 1
s = data["side_states"][0]
assert s["age_hours"] == 12.0, s["age_hours"]
assert s["source"] if "source" in s else True  # side states have no source key
PY
}

@test "scan_binders computes pr-open age from binder updated" {
  NOW="2026-08-29T12:00:00Z"
  write_binder tkt-7-seven pr-open "2026-08-28T12:00:00Z" "pr-42 — https://github.com/acme/repo/pull/42" "(none)"
  HOME="$TICKETS" python3 - "$QH_LIB" "$NOW" <<'PY'
import datetime, os, sys
sys.path.insert(0, sys.argv[1])
import queue_health as qh
now = datetime.datetime.strptime(sys.argv[2], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
data = qh.scan_binders(os.environ["HOME"], now=now)
assert len(data["pr_open"]) == 1
p = data["pr_open"][0]
assert p["age_hours"] == 24.0, p["age_hours"]
assert p["pr_n"] == 42, p["pr_n"]
assert p["source"] == "binder.updated", p["source"]
PY
}

@test "scan_binders uses gh fallback when binder updated missing for pr-open" {
  NOW="2026-08-29T12:00:00Z"
  # No updated row — lazy migration binder.
  mkdir -p "$TICKETS/tkt-8-eight"
  cat >"$TICKETS/tkt-8-eight/README.md" <<'EOF'
| status | pr-open |
| prs | pr-99 — https://github.com/acme/repo/pull/99 |
EOF
  HOME="$TICKETS" python3 - "$QH_LIB" "$NOW" <<'PY'
import datetime, os, sys
sys.path.insert(0, sys.argv[1])
import queue_health as qh
now = datetime.datetime.strptime(sys.argv[2], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
def fake_gh(pr_n):
    return "2026-08-28T00:00:00Z" if pr_n == 99 else None
data = qh.scan_binders(os.environ["HOME"], now=now, gh_fallback=fake_gh)
assert len(data["pr_open"]) == 1
p = data["pr_open"][0]
assert p["age_hours"] == 36.0, p["age_hours"]
assert p["source"] == "gh.pr.createdAt", p["source"]
PY
}

@test "scan_binders reports unknown age when no timestamp and no gh fallback" {
  NOW="2026-08-29T12:00:00Z"
  mkdir -p "$TICKETS/tkt-9-nine"
  cat >"$TICKETS/tkt-9-nine/README.md" <<'EOF'
| status | pr-open |
| prs | pr-7 — https://github.com/acme/repo/pull/7 |
EOF
  HOME="$TICKETS" python3 - "$QH_LIB" "$NOW" <<'PY'
import datetime, os, sys
sys.path.insert(0, sys.argv[1])
import queue_health as qh
now = datetime.datetime.strptime(sys.argv[2], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
data = qh.scan_binders(os.environ["HOME"], now=now, gh_fallback=None)
assert len(data["pr_open"]) == 1
p = data["pr_open"][0]
assert p["age_hours"] is None, p["age_hours"]
assert p["source"] is None, p["source"]
PY
}

# ---------------------------------------------------------------------------
# lib/queue_health.py — format_banner
# ---------------------------------------------------------------------------

@test "banner is empty when no thresholds exceeded" {
  NOW="2026-08-29T12:00:00Z"
  write_binder tkt-10-ten queued "2026-08-29T10:00:00Z" "(none)" "(none)"
  HOME="$TICKETS" python3 - "$QH_LIB" "$NOW" <<'PY'
import datetime, os, sys
sys.path.insert(0, sys.argv[1])
import queue_health as qh
now = datetime.datetime.strptime(sys.argv[2], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
data = qh.scan_binders(os.environ["HOME"], now=now)
t = qh.DEFAULT_THRESHOLDS
banner = qh.format_banner(data, t)
assert banner == "", repr(banner)
PY
}

@test "banner fires when side-state total exceeds threshold" {
  NOW="2026-08-29T12:00:00Z"
  for i in 1 2 3 4 5 6; do
    write_binder "tkt-2${i}-p${i}" parked "2026-08-29T10:00:00Z" "(none)" "unblock"
  done
  HOME="$TICKETS" python3 - "$QH_LIB" "$NOW" <<'PY'
import datetime, os, sys
sys.path.insert(0, sys.argv[1])
import queue_health as qh
now = datetime.datetime.strptime(sys.argv[2], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
data = qh.scan_binders(os.environ["HOME"], now=now)
t = qh.DEFAULT_THRESHOLDS
banner = qh.format_banner(data, t)
assert "6 parked/stuck/deferred" in banner, banner
assert "threshold 5" in banner, banner
PY
}

@test "banner fires when any side-state present (total > 0 per binder AC)" {
  NOW="2026-08-29T12:00:00Z"
  write_binder tkt-21-one parked "2026-08-29T10:00:00Z" "(none)" "unblock"
  HOME="$TICKETS" python3 - "$QH_LIB" "$NOW" <<'PY'
import datetime, os, sys
sys.path.insert(0, sys.argv[1])
import queue_health as qh
now = datetime.datetime.strptime(sys.argv[2], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
data = qh.scan_binders(os.environ["HOME"], now=now)
t = qh.DEFAULT_THRESHOLDS
banner = qh.format_banner(data, t)
# Banner fires for ANY pile-up (> 0), not just over threshold (5).
assert "1 parked/stuck/deferred" in banner, banner
PY
}

@test "banner fires when pr-open age exceeds threshold" {
  NOW="2026-08-29T12:00:00Z"
  # 48h old pr-open (threshold 36h).
  write_binder tkt-30-thirty pr-open "2026-08-27T12:00:00Z" "pr-30 — https://github.com/acme/repo/pull/30" "(none)"
  HOME="$TICKETS" python3 - "$QH_LIB" "$NOW" <<'PY'
import datetime, os, sys
sys.path.insert(0, sys.argv[1])
import queue_health as qh
now = datetime.datetime.strptime(sys.argv[2], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
data = qh.scan_binders(os.environ["HOME"], now=now)
t = qh.DEFAULT_THRESHOLDS
banner = qh.format_banner(data, t)
assert "1 pr-open > 36h" in banner, banner
PY
}

# ---------------------------------------------------------------------------
# lib/queue_health.py — format_section
# ---------------------------------------------------------------------------

@test "section states zero-rows good result instead of skipping" {
  NOW="2026-08-29T12:00:00Z"
  write_binder tkt-40-forty queued "2026-08-29T10:00:00Z" "(none)" "(none)"
  HOME="$TICKETS" python3 - "$QH_LIB" "$NOW" <<'PY'
import datetime, os, sys
sys.path.insert(0, sys.argv[1])
import queue_health as qh
now = datetime.datetime.strptime(sys.argv[2], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
data = qh.scan_binders(os.environ["HOME"], now=now)
t = qh.DEFAULT_THRESHOLDS
section = qh.format_section(data, t)
assert "no pile-up" in section, section
assert "No pr-open binders" in section, section
PY
}

@test "section marks over-threshold side-state pile with flag" {
  NOW="2026-08-29T12:00:00Z"
  for i in 1 2 3 4 5 6 7; do
    write_binder "tkt-5${i}-s${i}" deferred "2026-08-28T12:00:00Z" "(none)" "fuse-halt"
  done
  HOME="$TICKETS" python3 - "$QH_LIB" "$NOW" <<'PY'
import datetime, os, sys
sys.path.insert(0, sys.argv[1])
import queue_health as qh
now = datetime.datetime.strptime(sys.argv[2], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
data = qh.scan_binders(os.environ["HOME"], now=now)
t = qh.DEFAULT_THRESHOLDS
section = qh.format_section(data, t)
assert "OVER" in section, section
assert "7" in section
PY
}

@test "section flags stale pr-open with marker" {
  NOW="2026-08-29T12:00:00Z"
  write_binder tkt-60-sixty pr-open "2026-08-27T00:00:00Z" "pr-60 — https://github.com/acme/repo/pull/60" "(none)"
  HOME="$TICKETS" python3 - "$QH_LIB" "$NOW" <<'PY'
import datetime, os, sys
sys.path.insert(0, sys.argv[1])
import queue_health as qh
now = datetime.datetime.strptime(sys.argv[2], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
data = qh.scan_binders(os.environ["HOME"], now=now)
t = qh.DEFAULT_THRESHOLDS
section = qh.format_section(data, t)
assert "beyond 36h" in section, section
assert "1 beyond" in section, section
PY
}

# ---------------------------------------------------------------------------
# queue-health.sh — end-to-end script
# ---------------------------------------------------------------------------

@test "script --banner prints nothing when clean and exits 0" {
  write_binder tkt-70-seventy queued "2026-08-29T10:00:00Z" "(none)" "(none)"
  run bash "$QH" --banner --home "$LATTICE_HOME" --no-gh
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "script --banner prints one-liner when side-state pile exceeds threshold" {
  for i in 1 2 3 4 5 6; do
    write_binder "tkt-8${i}-q${i}" parked "2026-08-29T10:00:00Z" "(none)" "unblock"
  done
  run bash "$QH" --banner --home "$LATTICE_HOME" --no-gh
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "6 parked/stuck/deferred"
  echo "$output" | grep -q "triage advised"
}

@test "script --banner fires for a single side-state (total > 0)" {
  write_binder tkt-82-solo stuck "2026-08-29T10:00:00Z" "(none)" "unblock"
  run bash "$QH" --banner --home "$LATTICE_HOME" --no-gh
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "1 parked/stuck/deferred"
}

@test "script --section emits the Queue health heading and exits 0" {
  write_binder tkt-90-ninety stuck "2026-08-28T12:00:00Z" "(none)" "unblock"
  run bash "$QH" --section --home "$LATTICE_HOME" --no-gh
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Queue health (staleness water-level"
  echo "$output" | grep -q "tkt-90"
  echo "$output" | grep -q "stuck"
}

@test "script --json emits valid JSON with thresholds and counts" {
  write_binder tkt-100-hundred deferred "2026-08-28T00:00:00Z" "(none)" "spec-superseded"
  run bash "$QH" --json --home "$LATTICE_HOME" --no-gh
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["side_state_total"] == 1, d
assert d["thresholds"] == {"pr_open_hours": 36, "side_state_total": 5}, d["thresholds"]
assert d["side_states"][0]["status"] == "deferred", d["side_states"]
'
}

@test "script honors config.yaml threshold overrides" {
  cat >>"$LATTICE_HOME/config.yaml" <<'EOF'
queue_health:
  pr_open_hours: 12
  side_state_total: 1
EOF
  # 2 parked binders — banner fires (total > 0); digest would flag (2 > 1).
  write_binder tkt-110-one parked "2026-08-29T10:00:00Z" "(none)" "unblock"
  write_binder tkt-111-two parked "2026-08-29T10:00:00Z" "(none)" "unblock"
  run bash "$QH" --banner --home "$LATTICE_HOME" --no-gh
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "2 parked/stuck/deferred"
  echo "$output" | grep -q "threshold 1"
}

@test "script --banner exits 0 when tickets dir empty (no binders)" {
  run bash "$QH" --banner --home "$LATTICE_HOME" --no-gh
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "script never exits non-zero on advisory grounds (sensor not gate)" {
  # Even with stale pr-open + pile-up, exit is 0 (ADR-007 §8 sensor posture).
  write_binder tkt-120-stale pr-open "2026-08-26T12:00:00Z" "pr-120 — https://github.com/acme/repo/pull/120" "(none)"
  for i in 1 2 3 4 5 6 7; do
    write_binder "tkt-13${i}-x${i}" deferred "2026-08-28T12:00:00Z" "(none)" "fuse-halt"
  done
  run bash "$QH" --banner --home "$LATTICE_HOME" --no-gh
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# tkt-381: _FIELD_ROW_RE reads 3-column binder rows correctly
# ---------------------------------------------------------------------------

@test "_parse_field_rows reads 3-column row value as second cell only" {
  python3 - "$QH_LIB" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import queue_health as qh
# A binder with a stray 3rd column (legacy drift — 15 binders carry this).
text = "| status | closed | 2026-09-02T09:20:35Z |"
rows = qh._parse_field_rows(text)
assert rows.get("status") == "closed", repr(rows.get("status"))
PY
}

@test "_parse_field_rows still reads 2-column rows correctly" {
  python3 - "$QH_LIB" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import queue_health as qh
text = "| status | closed |"
rows = qh._parse_field_rows(text)
assert rows.get("status") == "closed", repr(rows.get("status"))
text2 = "| status | queued |"
rows2 = qh._parse_field_rows(text2)
assert rows2.get("status") == "queued", repr(rows2.get("status"))
PY
}

@test "scan_binders counts a 3-column closed binder as terminal" {
  NOW="2026-08-29T12:00:00Z"
  mkdir -p "$TICKETS/tkt-200-three-col"
  cat >"$TICKETS/tkt-200-three-col/README.md" <<'EOF'
# tkt-200-three-col

| Field | Value |
| --- | --- |
| status | closed | 2026-09-02T09:20:35Z |
| updated | 2026-09-02T09:20:35Z |
| prs | (none) |
| wait_reason | (none) |
EOF
  mkdir -p "$LATTICE_HOME/.transition-ledger"
  printf '%s\n' '{"ticket":"tkt-200","from":"queued","to":"closed","reason":"merge","metric":"direct-jump"}' \
    > "$LATTICE_HOME/.transition-ledger/tkt-200.jsonl"
  HOME="$TICKETS" python3 - "$QH_LIB" "$NOW" <<'PY'
import datetime, os, sys
sys.path.insert(0, sys.argv[1])
import queue_health as qh
now = datetime.datetime.strptime(sys.argv[2], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
data = qh.scan_binders(os.environ["HOME"], now=now)
cov = data["ledger_coverage"]
assert cov["terminal"] == 1, cov  # the 3-column binder must be counted
assert cov["with_ledger"] == 1, cov
PY
}

# ---------------------------------------------------------------------------
# spc-337 A1: ledger coverage + direct-jump sensor
# ---------------------------------------------------------------------------

@test "scan_binders reports ledger coverage and direct jumps for terminal binders" {
  NOW="2026-08-29T12:00:00Z"
  write_binder tkt-1-one closed "2026-08-29T10:00:00Z" "(none)" "(none)"
  write_binder tkt-2-two closed "2026-08-29T10:00:00Z" "(none)" "(none)"
  write_binder tkt-3-three queued "2026-08-29T10:00:00Z" "(none)" "(none)"
  mkdir -p "$LATTICE_HOME/.transition-ledger"
  printf '%s\n' '{"ticket":"tkt-1","from":"queued","to":"closed","reason":"merge","metric":"direct-jump"}' \
    > "$LATTICE_HOME/.transition-ledger/tkt-1.jsonl"
  HOME="$TICKETS" python3 - "$QH_LIB" "$NOW" <<'PY'
import datetime, os, sys
sys.path.insert(0, sys.argv[1])
import queue_health as qh
now = datetime.datetime.strptime(sys.argv[2], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
data = qh.scan_binders(os.environ["HOME"], now=now)
cov = data["ledger_coverage"]
assert cov["terminal"] == 2, cov
assert cov["with_ledger"] == 1, cov
assert cov["missing"] == ["tkt-2"], cov
assert cov["direct_jumps"] == 1, cov
sec = qh.format_section(data, qh.load_thresholds())
assert "Ledger coverage — 1/2 terminal binders" in sec, sec
assert "direct jumps: 1" in sec, sec
assert "tkt-2" in sec, sec
PY
}
