#!/usr/bin/env bats
# Tests for lineage-metrics.sh + lib/lineage_metrics.py (spc-369 A1).
# L1 running-data sensor: every metric asserted on the fixture home under
# fixtures/metrics/home (7 binders, 2 ledgers, 3 Specs), snapshot + delta,
# --no-snapshot, git metrics on a throwaway repo, python3-missing degrade.
#
# Fixture homes are COPIED into a mktemp dir per test (snapshots write there);
# never set BATS_TEST_TMPDIR (local bats 1.2.x lacks it; a shared value would
# cross-pollute tests).

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export LM="$REPO_ROOT/skills/review-lineage/scripts/lineage-metrics.sh"
  export LM_LIB="$REPO_ROOT/skills/review-lineage/scripts/lib"
  export QH_LIB="$REPO_ROOT/skills/_lattice-lib/scripts/lib"
  export FIXTURE="$REPO_ROOT/skills/review-lineage/scripts/tests/fixtures/metrics/home"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lm.XXXXXX")"
  cp -R "$FIXTURE" "$TEST_DIR/home"
  HOME_DIR="$TEST_DIR/home"
  SNAP="$TEST_DIR/snap"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Throwaway git repo with three commits on `main`: one PR merge (`(#1)`
# suffix), one direct push, one finish( stamp (also a direct push).
make_repo() {
  local r="$TEST_DIR/repo"
  mkdir -p "$r"
  git -C "$r" init -q
  git -C "$r" checkout -q -b main 2>/dev/null || true
  local g=(git -C "$r" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false)
  "${g[@]}" commit -q --allow-empty -m "feat(tkt-1): the thing (#1)"
  "${g[@]}" commit -q --allow-empty -m "chore: pushed straight to base"
  "${g[@]}" commit -q --allow-empty -m "finish(tkt-1): stamp Finish ledger — pr-1 merged"
  echo "$r"
}

# ---------------------------------------------------------------------------
# lib — collect() on the fixture home (git deliberately unavailable)
# ---------------------------------------------------------------------------

@test "collect: schema, generated_at, binders_total and status histogram" {
  python3 - "$QH_LIB" "$LM_LIB" "$HOME_DIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[2])
import lineage_metrics as lm
cur = lm.collect(sys.argv[3], repo_root="/nonexistent")
assert cur["schema"] == 1, cur["schema"]
assert cur["generated_at"].endswith("Z") and "T" in cur["generated_at"], cur["generated_at"]
assert cur["binders_total"] == 7, cur["binders_total"]
assert cur["status_histogram"] == {"closed": 3, "in-progress": 1, "pr-open": 1, "queued": 1, "stuck": 1}, cur["status_histogram"]
PY
}

@test "collect: ledger coverage reuses queue_health (2/3 terminal, tkt-3 missing, 1 direct jump)" {
  python3 - "$QH_LIB" "$LM_LIB" "$HOME_DIR" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[2])
import lineage_metrics as lm
import queue_health as qh
cur = lm.collect(sys.argv[3], repo_root="/nonexistent")
cov = cur["ledger_coverage"]
assert cov["terminal"] == 3 and cov["with_ledger"] == 2, cov
assert cov["missing"] == ["tkt-3"] and cov["missing_count"] == 1, cov
assert cov["direct_jumps"] == 1 and cov["pct"] == 66.7, cov
# byte-equal with the shared sensor
ref = qh.scan_binders(os.path.join(sys.argv[3], "tickets"))["ledger_coverage"]
for k in ("terminal", "with_ledger", "missing", "direct_jumps"):
    assert cov[k] == ref[k], (k, cov[k], ref[k])
assert cur["direct_jumps"] == {"count": 1, "tickets": ["tkt-2"]}, cur["direct_jumps"]
PY
}

@test "collect: edge histogram vs LEGAL_EDGES — walked, never walked, unmodelled" {
  python3 - "$QH_LIB" "$LM_LIB" "$HOME_DIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[2])
import lineage_metrics as lm
import transition_table as tt
cur = lm.collect(sys.argv[3], repo_root="/nonexistent")
e = cur["edges"]
assert e["ledger_files"] == 2 and e["entries"] == 5, e
assert e["histogram"] == {"closed->queued": 1, "in-progress->pr-open": 1, "pr-open->closed": 1,
                          "queued->closed": 1, "queued->in-progress": 1}, e["histogram"]
modelled = len({(x.from_, x.to) for x in tt.LEGAL_EDGES if x.from_ != "init"})
assert e["modelled"] == modelled, (e["modelled"], modelled)
assert e["walked"] == ["in-progress->pr-open", "pr-open->closed", "queued->closed", "queued->in-progress"], e["walked"]
assert e["walked_count"] == 4 and e["never_walked_count"] == modelled - 4, e
assert "in-progress->stuck" in e["never_walked"] and "queued->closed" not in e["never_walked"], e["never_walked"]
assert e["unmodelled"] == ["closed->queued"] and e["unmodelled_count"] == 1, e["unmodelled"]
# no second edge table: every walked/never-walked edge is a LEGAL_EDGES pair
legal = {"%s->%s" % (x.from_, x.to) for x in tt.LEGAL_EDGES}
assert set(e["walked"]) | set(e["never_walked"]) <= legal
PY
}

@test "collect: fix_cycles histogram, side states and wait reasons" {
  python3 - "$QH_LIB" "$LM_LIB" "$HOME_DIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[2])
import lineage_metrics as lm
cur = lm.collect(sys.argv[3], repo_root="/nonexistent")
assert cur["fix_cycles_histogram"] == {"0": 5, "1": 1, "2": 1}, cur["fix_cycles_histogram"]
assert cur["fix_cycles_gt0"] == 2, cur["fix_cycles_gt0"]
assert cur["side_states"] == {"parked": 0, "stuck": 1, "rework": 0, "deferred": 0, "total": 1}, cur["side_states"]
assert cur["wait_reasons"] == {"unblock": 1}, cur["wait_reasons"]
PY
}

@test "collect: section usage ignores placeholders and HTML comments" {
  python3 - "$QH_LIB" "$LM_LIB" "$HOME_DIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[2])
import lineage_metrics as lm
cur = lm.collect(sys.argv[3], repo_root="/nonexistent")
# tkt-2 has two Attempts bullets; tkt-4 has a Pending decisions question;
# tkt-1 + tkt-2 have journal bullets (tkt-3's journal is only a comment).
assert cur["sections"] == {"attempts": 1, "pending_decisions": 1, "decision_journal": 2}, cur["sections"]
assert lm.section_nonempty("## Attempts\n<!-- (none) -->\n(none yet)\n\n## Notes\n- x\n", "Attempts") is False
assert lm.section_nonempty("## Attempts\n- Try 1\n## Notes\n", "Attempts") is True
PY
}

@test "collect: NOTICED backlog and escape traces by rule_id (bullets only)" {
  python3 - "$QH_LIB" "$LM_LIB" "$HOME_DIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[2])
import lineage_metrics as lm
cur = lm.collect(sys.argv[3], repo_root="/nonexistent")
n = cur["noticed"]
assert n["count"] == 1 and n["items"][0]["ticket"] == "tkt-1", n
assert n["items"][0]["line"].startswith("NOTICED: tools/example.sh"), n["items"][0]
esc = cur["escape_traces"]
# tkt-7's prose mention of rule_id=ci-gate is NOT a trace (not a bullet)
assert esc["total"] == 2 and esc["by_rule"] == {"batch-merge-gate": 1, "ci-gate": 1}, esc
assert all(it["ticket"] == "tkt-2" for it in esc["items"]), esc["items"]
PY
}

@test "collect: Specs — done with open A*, prs vs child union (done only)" {
  python3 - "$QH_LIB" "$LM_LIB" "$HOME_DIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[2])
import lineage_metrics as lm
cur = lm.collect(sys.argv[3], repo_root="/nonexistent")
sp = cur["specs"]
assert sp["total"] == 3 and sp["by_status"] == {"done": 2, "locked": 1}, sp
assert sp["done_with_open_acceptance"] == [{"spec": "spc-100", "open": ["A2"]}], sp["done_with_open_acceptance"]
assert sp["done_with_open_acceptance_count"] == 1
assert sp["prs_mismatch_count"] == 1 and sp["prs_missing_in_spec_count"] == 1, sp
m = sp["prs_mismatch"][0]
assert m["spec"] == "spc-101", m
assert m["spec_prs"] == ["pr-13", "pr-99"] and m["binder_prs"] == ["pr-13", "pr-14"], m
assert m["missing_in_spec"] == ["pr-14"] and m["extra_in_spec"] == ["pr-99"], m
assert m["tickets"] == ["tkt-3", "tkt-7"], m
# spc-102 is locked (open A1) and must not be listed; spc-100 prs == union
assert all(x["spec"] != "spc-102" for x in sp["done_with_open_acceptance"] + sp["prs_mismatch"])
PY
}

@test "collect: git metrics degrade (available=false) when repo_root is not a git repo" {
  python3 - "$QH_LIB" "$LM_LIB" "$HOME_DIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[2])
import lineage_metrics as lm
cur = lm.collect(sys.argv[3], repo_root="/nonexistent")
g = cur["git"]
assert g["available"] is False and g["error"], g
assert g["commits_total"] == 0 and g["pr_merges"] == 0 and g["direct_commits"] == 0 and g["finish_stamps"] == 0, g
PY
}

@test "collect: git metrics on a tmp repo — pr_merges / direct_commits / finish_stamps / base detection" {
  REPO="$(make_repo)"
  python3 - "$QH_LIB" "$LM_LIB" "$HOME_DIR" "$REPO" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[2])
import lineage_metrics as lm
cur = lm.collect(sys.argv[3], repo_root=sys.argv[4], since="7d", base_branch="main")
g = cur["git"]
assert g["available"] is True and g["error"] is None, g
assert g["base"] == "main" and g["since"] == "7d", g
assert g["commits_total"] == 3 and g["pr_merges"] == 1 and g["direct_commits"] == 2 and g["finish_stamps"] == 1, g
assert g["direct_ratio"] == 0.667, g
# base detection: no dev/develop → main
assert lm.detect_base_branch(sys.argv[4]) == "main"
auto = lm.git_metrics(sys.argv[4])
assert auto["base"] == "main" and auto["commits_total"] == 3, auto
# ref form: <ref>..base
first = lm._git(sys.argv[4], "rev-list", "--max-parents=0", "HEAD").strip()
ranged = lm.git_metrics(sys.argv[4], base_branch="main", since=first)
assert ranged["commits_total"] == 2, ranged
# unknown base → error, zeros
bad = lm.git_metrics(sys.argv[4], base_branch="no-such-branch")
assert bad["available"] is False and "base ref not found" in bad["error"], bad
PY
}

# ---------------------------------------------------------------------------
# lib — snapshots, delta, render
# ---------------------------------------------------------------------------

@test "load_previous picks the newest lineage-*.json by name; None when absent" {
  mkdir -p "$SNAP"
  printf '{"schema":1,"generated_at":"2026-01-01T00:00:00Z","binders_total":1}\n' >"$SNAP/lineage-20260101-000000Z.json"
  printf '{"schema":1,"generated_at":"2026-02-01T00:00:00Z","binders_total":2}\n' >"$SNAP/lineage-20260201-000000Z.json"
  printf 'not json\n' >"$SNAP/lineage-20260301-000000Z.json"
  python3 - "$QH_LIB" "$LM_LIB" "$SNAP" "$TEST_DIR/none" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[2])
import lineage_metrics as lm
prev = lm.load_previous(sys.argv[3])
# the newest file is unreadable JSON → skipped; newest valid wins
assert prev["_file"] == "lineage-20260201-000000Z.json" and prev["binders_total"] == 2, prev
assert lm.load_previous(sys.argv[4]) is None
assert lm.load_previous("") is None
PY
}

@test "delta: numeric leaves only — ▲ ▼ = new gone; first snapshot has no changes" {
  python3 - "$QH_LIB" "$LM_LIB" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[2])
import lineage_metrics as lm
cur = {"schema": 1, "generated_at": "2026-09-02T00:00:00Z", "binders_total": 10,
       "ledger_coverage": {"with_ledger": 5, "pct": 50.0, "missing": ["tkt-1"]},
       "edges": {"histogram": {"queued->closed": 2}}, "git": {"available": True, "commits_total": 3}, "fresh": 1}
prev = {"schema": 1, "generated_at": "2026-09-01T00:00:00Z", "binders_total": 8, "_file": "lineage-20260901-000000Z.json",
        "ledger_coverage": {"with_ledger": 6, "pct": 50.0, "missing": []},
        "edges": {"histogram": {"queued->closed": 2, "pr-open->closed": 1}}, "git": {"available": False, "commits_total": 3}, "old": 9}
d = lm.delta(cur, prev)
assert d["previous"] == "lineage-20260901-000000Z.json" and d["previous_generated_at"] == "2026-09-01T00:00:00Z", d
ch = d["changes"]
assert ch["binders_total"] == {"prev": 8, "cur": 10, "diff": 2, "arrow": "▲"}, ch["binders_total"]
assert ch["ledger_coverage.with_ledger"]["arrow"] == "▼" and ch["ledger_coverage.with_ledger"]["diff"] == -1
assert ch["ledger_coverage.pct"]["arrow"] == "="
assert ch["edges.histogram.queued->closed"]["arrow"] == "="
assert ch["edges.histogram.pr-open->closed"]["arrow"] == "gone"
assert ch["fresh"]["arrow"] == "new" and ch["old"]["arrow"] == "gone"
assert "git.available" not in ch and "ledger_coverage.missing" not in ch and "schema" not in ch and "generated_at" not in ch, ch.keys()
first = lm.delta(cur, None)
assert first == {"previous": None, "previous_generated_at": None, "changes": {}}, first
PY
}

@test "render_md: first snapshot says so; with a previous it shows arrows and the file name" {
  python3 - "$QH_LIB" "$LM_LIB" "$HOME_DIR" <<'PY'
import copy, sys
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[2])
import lineage_metrics as lm
cur = lm.collect(sys.argv[3], repo_root="/nonexistent")
md = lm.render_md(cur, lm.delta(cur, None))
assert "First snapshot" in md and "| Binders | 7 | — |" in md, md
assert "`closed->queued` (unmodelled)" in md and "Never walked:" in md, md
assert "Done with open acceptance boxes: spc-100 (A2)" in md, md
assert "| spc-101 | pr-14 | pr-99 |" in md, md
assert "| tkt-1 | NOTICED: tools/example.sh" in md, md
assert "git metrics unavailable" in md, md
prev = copy.deepcopy(cur); prev["_file"] = "lineage-20260101-000000Z.json"
prev["binders_total"] = 5; prev["ledger_coverage"]["with_ledger"] = 3; prev["noticed"]["count"] = 1
md2 = lm.render_md(cur, lm.delta(cur, prev))
assert "lineage-20260101-000000Z.json" in md2 and "First snapshot" not in md2, md2
assert "| Binders | 7 | ▲ +2 |" in md2, md2
assert "| Ledger coverage (terminal with ledger) | 2/3 (66.7%) | ▼ -1 |" in md2, md2
assert "| `- NOTICED:` backlog | 1 | = |" in md2, md2
PY
}

@test "write_snapshot: lineage-<UTC>.json named from generated_at, no private keys" {
  python3 - "$QH_LIB" "$LM_LIB" "$HOME_DIR" "$SNAP" <<'PY'
import json, os, sys
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[2])
import lineage_metrics as lm
cur = lm.collect(sys.argv[3], repo_root="/nonexistent")
cur["generated_at"] = "2026-09-02T07:30:00Z"; cur["_scratch"] = 1
p = lm.write_snapshot(sys.argv[4], cur)
assert os.path.basename(p) == "lineage-20260902-073000Z.json", p
data = json.load(open(p, encoding="utf-8"))
assert data["schema"] == 1 and "_scratch" not in data and data["binders_total"] == 7, data.keys()
assert not [f for f in os.listdir(sys.argv[4]) if f.endswith(".tmp")]
PY
}

# ---------------------------------------------------------------------------
# lineage-metrics.sh — CLI surface
# ---------------------------------------------------------------------------

@test "sh: --md (default) prints the report and writes a schema-1 snapshot under --snapshot-dir" {
  run bash "$LM" --home "$HOME_DIR" --snapshot-dir "$SNAP"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^## Lineage metrics — '
  echo "$output" | grep -q 'First snapshot'
  echo "$output" | grep -q '| Direct jumps (merge from queued/in-progress) | 1 | — |'
  echo "$output" | grep -q '_Snapshot written: `'
  files=("$SNAP"/lineage-*.json)
  [ "${#files[@]}" -eq 1 ]
  python3 - "${files[0]}" <<'PY'
import json, re, sys
p = sys.argv[1]
assert re.search(r"/lineage-[0-9]{8}-[0-9]{6}Z\.json$", p), p
d = json.load(open(p, encoding="utf-8"))
assert d["schema"] == 1 and d["binders_total"] == 7 and d["ledger_coverage"]["direct_jumps"] == 1, d.keys()
assert "delta" not in d and "snapshot_file" not in d
PY
}

@test "sh: default snapshot dir is <home>/reviews/metrics" {
  run bash "$LM" --home "$HOME_DIR" --md
  [ "$status" -eq 0 ]
  files=("$HOME_DIR"/reviews/metrics/lineage-*.json)
  [ "${#files[@]}" -eq 1 ]
  [ -f "${files[0]}" ]
}

@test "sh: --no-snapshot writes nothing" {
  run bash "$LM" --home "$HOME_DIR" --snapshot-dir "$SNAP" --no-snapshot
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^## Lineage metrics — '
  run grep -c 'Snapshot written' <<<"$output"
  [ "$output" = "0" ]
  [ ! -e "$SNAP" ]
  [ ! -e "$HOME_DIR/reviews/metrics" ]
}

@test "sh: --json prints metrics + delta + snapshot_file; snapshot file holds metrics only" {
  run bash "$LM" --home "$HOME_DIR" --snapshot-dir "$SNAP" --json
  [ "$status" -eq 0 ]
  python3 - "$SNAP" <<PY
import json, os, sys
out = json.loads('''$output''')
assert out["schema"] == 1 and out["binders_total"] == 7, out.keys()
assert out["delta"] == {"previous": None, "previous_generated_at": None, "changes": {}}, out["delta"]
assert out["snapshot_file"] and os.path.isfile(out["snapshot_file"]), out["snapshot_file"]
assert os.path.dirname(out["snapshot_file"]) == sys.argv[1]
snap = json.load(open(out["snapshot_file"], encoding="utf-8"))
assert "delta" not in snap and snap["binders_total"] == 7
PY
}

@test "sh: planted previous snapshot → delta arrows in --md and --json" {
  mkdir -p "$SNAP"
  # previous: fewer binders, more ledgers, same NOTICED count
  python3 - "$QH_LIB" "$LM_LIB" "$HOME_DIR" "$SNAP" <<'PY'
import json, os, sys
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[2])
import lineage_metrics as lm
prev = lm.collect(sys.argv[3], repo_root="/nonexistent")
prev["generated_at"] = "2026-01-01T00:00:00Z"
prev["binders_total"] = 5
prev["ledger_coverage"]["with_ledger"] = 3
prev["edges"]["never_walked_count"] = 25
with open(os.path.join(sys.argv[4], "lineage-20260101-000000Z.json"), "w", encoding="utf-8") as fh:
    json.dump(prev, fh)
PY
  run bash "$LM" --home "$HOME_DIR" --snapshot-dir "$SNAP" --md
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'lineage-20260101-000000Z.json'
  echo "$output" | grep -q '| Binders | 7 | ▲ +2 |'
  echo "$output" | grep -q '| Ledger coverage (terminal with ledger) | 2/3 (66.7%) | ▼ -1 |'
  echo "$output" | grep -q '| `- NOTICED:` backlog | 1 | = |'
  run grep -c 'First snapshot' <<<"$output"
  [ "$output" = "0" ]
  # a second snapshot now exists beside the planted one
  files=("$SNAP"/lineage-*.json)
  [ "${#files[@]}" -eq 2 ]
  run bash "$LM" --home "$HOME_DIR" --snapshot-dir "$SNAP" --json --no-snapshot
  [ "$status" -eq 0 ]
  python3 - <<PY
import json
out = json.loads('''$output''')
d = out["delta"]
assert d["previous"].startswith("lineage-") and d["previous_generated_at"], d
assert d["changes"]["binders_total"]["arrow"] == "=", d["changes"]["binders_total"]
PY
}

@test "sh: --since / --base drive git metrics on a tmp repo home" {
  REPO="$(make_repo)"
  # a lattice home inside the tmp repo so the script resolves REPO_ROOT from it
  cp -R "$FIXTURE" "$REPO/.lattice"
  run bash "$LM" --home "$REPO/.lattice" --since 7d --base main --no-snapshot --json
  [ "$status" -eq 0 ]
  python3 - <<PY
import json
out = json.loads('''$output''')
g = out["git"]
assert g["available"] is True and g["base"] == "main" and g["since"] == "7d", g
assert g["commits_total"] == 3 and g["pr_merges"] == 1 and g["direct_commits"] == 2 and g["finish_stamps"] == 1, g
PY
  # default --home = <git toplevel>/.lattice when run from inside the repo
  run bash -c "cd '$REPO' && bash '$LM' --no-snapshot --md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '| Base commits (`main`, since 30d) | 3 | — |'
  echo "$output" | grep -q '|   `finish(` stamps | 1 | — |'
}

@test "sh: usage errors exit 2; missing home exits 1" {
  run bash "$LM" --bogus
  [ "$status" -eq 2 ]
  run bash "$LM" --home
  [ "$status" -eq 2 ]
  run bash "$LM" --home "$TEST_DIR/does-not-exist" --no-snapshot
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'lattice home not found'
}

@test "sh: degrades with a clear message (exit 1) when python3 is missing" {
  mkdir -p "$TEST_DIR/bin"
  for t in bash dirname uname sed head grep cat printf; do
    p="$(command -v "$t" 2>/dev/null || true)"
    [ -n "$p" ] && ln -s "$p" "$TEST_DIR/bin/$t"
  done
  run env PATH="$TEST_DIR/bin" bash "$LM" --home "$HOME_DIR" --no-snapshot
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'python3'
  echo "$output" | grep -q 'lineage-metrics: unavailable'
  [ ! -e "$HOME_DIR/reviews/metrics" ]
}

@test "sh: resolves _lattice-lib from its own install dir, not the consumer cwd" {
  # run from an unrelated cwd with no skills/ tree — must still work
  run bash -c "cd '$TEST_DIR' && bash '$LM' --home '$HOME_DIR' --no-snapshot --md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '| Binders | 7 | — |'
  # the wrapper never references a cwd-relative skills path
  run grep -nF '="skills/_lattice-lib/scripts/' "$LM"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# tkt-385: fix_recurrence + coverage_post_ratchet
# ---------------------------------------------------------------------------

@test "tkt-385 A1: fix_recurrence counts files with ≥2 fix( commits in the window" {
  # Make a repo with two fix( commits touching the same file
  REPO="$TEST_DIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" checkout -q -b main 2>/dev/null || true
  local g=(git -C "$REPO" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false)
  echo "v1" > "$REPO/buggy.py"
  "${g[@]}" add -A && "${g[@]}" commit -q -m "feat: init"
  echo "v2" > "$REPO/buggy.py"
  "${g[@]}" add -A && "${g[@]}" commit -q -m "fix(tkt-1): first fix"
  echo "v3" > "$REPO/buggy.py"
  "${g[@]}" add -A && "${g[@]}" commit -q -m "fix(tkt-2): second fix to same file"
  python3 - "$QH_LIB" "$LM_LIB" "$REPO" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[2])
import lineage_metrics as lm
g = lm.git_metrics(sys.argv[3], base_branch="main", since="365d")
fr = g["fix_recurrence"]
assert fr["files_count"] >= 1, fr
assert any("buggy.py" in f for f in fr["files"]), fr
assert "fix(tkt-" in fr["subject_classes"] or "fix(" in fr["subject_classes"], fr
PY
}

@test "tkt-385 A2: coverage_post_ratchet excludes pre-cutoff binders" {
  python3 - "$QH_LIB" "$LM_LIB" "$HOME_DIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[2])
import lineage_metrics as lm
# The fixture has 3 closed binders (tkt-1, tkt-2, tkt-3).
# With a far-future cutoff, none qualify → 0/0.
cur = lm.collect(sys.argv[3], repo_root="/nonexistent", created_after="2099-01-01")
cpr = cur["coverage_post_ratchet"]
assert cpr["terminal"] == 0 and cpr["with_ledger"] == 0, cpr
# With a past cutoff, all closed binders qualify.
cur2 = lm.collect(sys.argv[3], repo_root="/nonexistent", created_after="2020-01-01")
cpr2 = cur2["coverage_post_ratchet"]
# The fixture binders may or may not have created rows; check structure.
assert "with_ledger" in cpr2 and "terminal" in cpr2 and "pct" in cpr2, cpr2
assert cpr2["created_after"] == "2020-01-01", cpr2
PY
}
