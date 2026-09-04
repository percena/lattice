#!/usr/bin/env bats
# Tests for claim-probes.sh + references/probes.md (spc-369 A2, tkt-371).
#
# The registry's built-in probes are executable claims; each one ships with a
# clean-fixture pass and a planted-drift case that fails exactly that probe
# (spc-369 Risks: probe false positives teach agents to ignore the report).
# Runner contract: overlay merge by id, --only filter, malformed rows → skip
# with a reason, exit 3 → skip, timeout → fail, always exit 0.
#
# Fixtures: fixtures/probes/clean/ (fake repo, home = clean/.lattice) and
# fixtures/probes/planted/<probe-id>/ overlays. Each test copies clean/ into
# its own mktemp dir (never BATS_TEST_TMPDIR — local bats 1.2.x lacks it).

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export REPO_ROOT
  export CP="$REPO_ROOT/skills/review-lineage/scripts/claim-probes.sh"
  export REGISTRY="$REPO_ROOT/skills/review-lineage/references/probes.md"
  export FIX="$REPO_ROOT/skills/review-lineage/scripts/tests/fixtures/probes"
  export BUILTINS="skill-scripts-exist hooks-json-files-exist validator-codes-cited-exist retired-paths-absent adr-verification-refs-resolve spec-done-acceptance-cites-evidence fsm-doc-edges-subset-of-schema"
  # tkt-412: spec-done-acceptance-cites-evidence is opt-in in the live digest
  # (evidence lives in binders/PRs by convention); the test suite opts in so the
  # strict audit still runs against the planted/clean fixtures.
  export LATTICE_PROBE_STRICT_EVIDENCE=1
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/claim-probes.XXXXXX")"
  export TEST_DIR
  cp -R "$FIX/clean/." "$TEST_DIR/"
  # The clean fixture's scripts must be executable; re-assert in case the
  # checkout dropped mode bits (core.filemode=false).
  chmod 755 "$TEST_DIR/skills/demo/scripts/demo.sh" \
            "$TEST_DIR/skills/_lattice-lib/scripts/lib-tool.sh" \
            "$TEST_DIR/plugins/lattice/hooks/demo-hook.sh"
  export HOME_DIR="$TEST_DIR/.lattice"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Overlay a planted-drift directory onto the working copy.
plant() {
  cp -R "$FIX/planted/$1/." "$TEST_DIR/"
}

# Run the sensor in JSON mode and print "<id> <status>" lines.
statuses() {
  bash "$CP" --home "$HOME_DIR" --json "$@" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for p in d["probes"]:
    print(p["id"], p["status"])
'
}

# Print the evidence string for one probe id (JSON mode).
evidence_of() {
  local id="$1"; shift
  bash "$CP" --home "$HOME_DIR" --json "$@" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for p in d["probes"]:
    if p["id"] == sys.argv[1]:
        print(p["evidence"])
' "$id"
}

# Assert the failing set is exactly {$1} and every other built-in passes.
assert_only_fails() {
  local want="$1"
  run statuses
  [ "$status" -eq 0 ]
  local fails
  fails=$(awk '$2=="fail"{print $1}' <<<"$output" | sort | tr '\n' ' ' | sed 's/ $//')
  [ "$fails" = "$want" ]
  local skips
  skips=$(awk '$2=="skip"{print $1}' <<<"$output")
  [ -z "$skips" ]
  for id in $BUILTINS; do
    if [ "$id" = "$want" ]; then
      grep -qx "$id fail" <<<"$output"
    else
      grep -qx "$id pass" <<<"$output"
    fi
  done
}

# Write a custom registry with the header + the given rows (already escaped).
write_registry() {
  {
    echo "# custom"
    echo
    echo "| id | claim (where) | probe | expect | severity |"
    echo "| --- | --- | --- | --- | --- |"
    cat
  } >"$TEST_DIR/registry.md"
}

# ---------------------------------------------------------------------------
# clean fixture
# ---------------------------------------------------------------------------

@test "clean fixture: every built-in probe passes, summary line, exit 0" {
  run bash "$CP" --home "$HOME_DIR" --md
  [ "$status" -eq 0 ]
  grep -qx 'claim-probes: 7 pass, 0 fail, 0 skip' <<<"$output"
  grep -q '^| probe | status | severity | evidence |$' <<<"$output"
  for id in $BUILTINS; do
    grep -qE "^\| $id \| pass \| (high|med|low) \|  \|$" <<<"$output"
  done
}

@test "clean fixture: --json carries schema, summary and per-probe rows" {
  run bash "$CP" --home "$HOME_DIR" --json
  [ "$status" -eq 0 ]
  CP_OUT="$output" python3 - "$HOME_DIR" <<'PY'
import json, os, sys
d = json.loads(os.environ["CP_OUT"])
assert d["schema"] == 1, d
assert d["summary"] == {"pass": 7, "fail": 0, "skip": 0}, d["summary"]
assert d["summary_line"] == "claim-probes: 7 pass, 0 fail, 0 skip"
# tkt-463: compare realpaths — macOS $TMPDIR is /var/… but the script reports
# the resolved /private/var/… (macOS bats job, PR #466).
assert os.path.realpath(d["lattice_home"]) == os.path.realpath(sys.argv[1]), d["lattice_home"]
assert d["overlay"] is None
assert d["degraded"] == [], d["degraded"]
ids = [p["id"] for p in d["probes"]]
assert len(ids) == 7 and len(set(ids)) == 7, ids
for p in d["probes"]:
    assert p["status"] == "pass" and p["exit"] == 0 and p["evidence"] == "", p
    assert p["severity"] in ("high", "med", "low"), p
    assert p["source"].startswith("registry:"), p
PY
}

# ---------------------------------------------------------------------------
# planted drift — one per built-in, each fails exactly its own probe
# ---------------------------------------------------------------------------

@test "planted: SKILL.md naming a missing script fails only skill-scripts-exist" {
  plant skill-scripts-exist
  assert_only_fails skill-scripts-exist
  run evidence_of skill-scripts-exist
  grep -q 'skills/demo/SKILL.md names SKILL_ROOT/scripts/ghost.sh -> skills/demo/scripts/ghost.sh' <<<"$output"
}

@test "planted: a non-executable named script also fails skill-scripts-exist" {
  chmod 644 "$TEST_DIR/skills/_lattice-lib/scripts/lib-tool.sh"
  assert_only_fails skill-scripts-exist
  run evidence_of skill-scripts-exist
  grep -q '_lattice-lib/scripts/lib-tool.sh -> skills/_lattice-lib/scripts/lib-tool.sh (missing or not executable)' <<<"$output"
}

@test "planted: hooks.json naming a missing hook fails only hooks-json-files-exist" {
  plant hooks-json-files-exist
  assert_only_fails hooks-json-files-exist
  run evidence_of hooks-json-files-exist
  grep -q 'hooks/ghost-hook.sh (missing or not executable)' <<<"$output"
}

@test "planted: a doc citing an unknown validator code fails only validator-codes-cited-exist" {
  plant validator-codes-cited-exist
  assert_only_fails validator-codes-cited-exist
  run evidence_of validator-codes-cited-exist
  grep -q 'cited code demo_code_ghost is not emitted' <<<"$output"
}

@test "planted: a doc with a retired phrase fails only retired-paths-absent" {
  plant retired-paths-absent
  assert_only_fails retired-paths-absent
  run evidence_of retired-paths-absent
  grep -q 'docs/marker.md:3:' <<<"$output"
}

@test "planted: an ADR Verification bullet citing a missing file fails only adr-verification-refs-resolve" {
  plant adr-verification-refs-resolve
  assert_only_fails adr-verification-refs-resolve
  run evidence_of adr-verification-refs-resolve
  grep -q 'docs/adr/002-ghost.md cites tools/ghost-check.py (unresolved)' <<<"$output"
}

@test "planted: a done Spec whose checked A* cites no evidence fails only spec-done-acceptance-cites-evidence" {
  plant spec-done-acceptance-cites-evidence
  assert_only_fails spec-done-acceptance-cites-evidence
  run evidence_of spec-done-acceptance-cites-evidence
  # A1 is listed; A2 (cites a .bats) is not
  grep -q 'spc-2-ghost.md: A1 — no test/PR/ticket evidence cited' <<<"$output"
  if grep -q 'A2' <<<"$output"; then false; fi
}

@test "planted: an FSM doc M2 edge outside the schema fails only fsm-doc-edges-subset-of-schema" {
  plant fsm-doc-edges-subset-of-schema
  assert_only_fails fsm-doc-edges-subset-of-schema
  run evidence_of fsm-doc-edges-subset-of-schema
  grep -q 'docs M2 edge closed -> queued is not in transition_table.LEGAL_EDGES' <<<"$output"
}

# ---------------------------------------------------------------------------
# skip on absent prerequisite (exit 3 contract)
# ---------------------------------------------------------------------------

@test "built-ins skip (not fail) when their prerequisite path is absent" {
  rm -rf "$TEST_DIR/docs/adr" "$TEST_DIR/plugins" "$TEST_DIR/tools"
  run statuses
  [ "$status" -eq 0 ]
  grep -qx 'adr-verification-refs-resolve skip' <<<"$output"
  grep -qx 'hooks-json-files-exist skip' <<<"$output"
  grep -qx 'validator-codes-cited-exist skip' <<<"$output"
  grep -qx 'skill-scripts-exist pass' <<<"$output"
  run evidence_of adr-verification-refs-resolve
  grep -q 'skip: no docs/adr' <<<"$output"
}

# ---------------------------------------------------------------------------
# overlay
# ---------------------------------------------------------------------------

@test "--overlay replaces a probe's expect by id (overlay wins) and appends new ids" {
  plant skill-scripts-exist
  printf '# demo overlay\n\nskill-scripts-exist\tdemoted: ghost is known\techo ghost-known\tregex:ghost\tlow\ncustom-probe\tfixture has a README\ttest -f docs/validator.md\texit0\tmed\n' \
    >"$TEST_DIR/overlay.tsv"
  run bash "$CP" --home "$HOME_DIR" --overlay "$TEST_DIR/overlay.tsv" --json
  [ "$status" -eq 0 ]
  CP_OUT="$output" python3 - <<'PY'
import json, os, sys
d = json.loads(os.environ["CP_OUT"])
by = {p["id"]: p for p in d["probes"]}
assert by["skill-scripts-exist"]["status"] == "pass", by["skill-scripts-exist"]
assert by["skill-scripts-exist"]["severity"] == "low"
assert by["skill-scripts-exist"]["source"].startswith("overlay:"), by["skill-scripts-exist"]["source"]
assert by["custom-probe"]["status"] == "pass", by["custom-probe"]
assert [p["id"] for p in d["probes"]][-1] == "custom-probe", "new ids are appended"
assert len(d["probes"]) == 8, len(d["probes"])
assert d["overlay"].endswith("/overlay.tsv")
PY
}

@test "default overlay <home>/lineage-probes.tsv is picked up without --overlay" {
  printf 'home-probe\tfrom the home overlay\techo hi\tregex:^hi$\tlow\n' >"$HOME_DIR/lineage-probes.tsv"
  run statuses
  [ "$status" -eq 0 ]
  grep -qx 'home-probe pass' <<<"$output"
}

@test "a malformed overlay row is reported as skip with its line" {
  printf 'only\tfour\tfields\there\n' >"$HOME_DIR/lineage-probes.tsv"
  run bash "$CP" --home "$HOME_DIR" --md
  [ "$status" -eq 0 ]
  grep -q '^| overlay-row-1 | skip | low | malformed overlay row (line 1): 4 fields, expected 5 |$' <<<"$output"
  grep -qx 'claim-probes: 7 pass, 0 fail, 1 skip' <<<"$output"
}

# ---------------------------------------------------------------------------
# --only
# ---------------------------------------------------------------------------

@test "--only runs just the named ids; unknown ids are skip 'not in registry'" {
  run statuses --only hooks-json-files-exist,fsm-doc-edges-subset-of-schema,no-such-probe
  [ "$status" -eq 0 ]
  [ "$(wc -l <<<"$output")" -eq 3 ]
  grep -qx 'hooks-json-files-exist pass' <<<"$output"
  grep -qx 'fsm-doc-edges-subset-of-schema pass' <<<"$output"
  grep -qx 'no-such-probe skip' <<<"$output"
  run evidence_of no-such-probe --only no-such-probe
  [ "$output" = "not in registry" ]
}

# ---------------------------------------------------------------------------
# registry parsing + expectation semantics
# ---------------------------------------------------------------------------

@test "malformed registry rows skip with a reason; well-formed rows still run" {
  write_registry <<'ROWS'
| `ok-row` | fine | `echo ok` | `regex:ok` | low |
| `short-row` | only four cells | `echo x` | `exit0` |
| `bad-expect` | unknown expect | `echo x` | `maybe` | low |
| `bad-sev` | unknown severity | `echo x` | `exit0` | urgent |
| `bad-regex` | unbalanced paren | `echo x` | `regex:(` | low |
| `Bad Id` | id with a space | `echo x` | `exit0` | low |
ROWS
  run bash "$CP" --home "$HOME_DIR" --registry "$TEST_DIR/registry.md" --md
  [ "$status" -eq 0 ]
  grep -q '^| ok-row | pass | low |  |$' <<<"$output"
  grep -q '^| row-6 | skip | low | malformed row (line 6): 4 cells, expected 5 |$' <<<"$output"
  grep -q "^| bad-expect | skip | low | malformed row: expect 'maybe' not in exit0|regex:<pattern>|empty |$" <<<"$output" \
    || grep -q "^| bad-expect | skip | low | malformed row: expect 'maybe' not in exit0\\\\|regex:<pattern>\\\\|empty |$" <<<"$output"
  grep -q "^| bad-sev | skip | low | malformed row: severity 'urgent' not in high|med|low |$" <<<"$output" \
    || grep -q "^| bad-sev | skip | low | malformed row: severity 'urgent' not in high\\\\|med\\\\|low |$" <<<"$output"
  grep -q '^| bad-regex | skip | low | malformed row: bad regex' <<<"$output"
  grep -q "^| Bad Id | skip | low | malformed row: id 'Bad Id' is not \[a-z0-9._-\] |$" <<<"$output"
  grep -qx 'claim-probes: 1 pass, 0 fail, 5 skip' <<<"$output"
}

@test "expect semantics: exit0 / regex / empty pass and fail as documented; exit 3 skips; a crash never passes" {
  write_registry <<'ROWS'
| `e0-pass` | exit0 | `true` | `exit0` | low |
| `e0-fail` | exit0 | `echo boom >&2; exit 4` | `exit0` | low |
| `rx-pass` | regex | `printf 'a\nhello world\n'` | `regex:^hello` | low |
| `rx-fail` | regex | `echo goodbye` | `regex:^hello` | low |
| `empty-pass` | empty | `true` | `empty` | low |
| `empty-fail` | empty | `echo drift-1; echo drift-2` | `empty` | low |
| `empty-crash` | empty with nonzero exit | `no-such-command-xyz` | `empty` | low |
| `skip-3` | prerequisite absent | `echo "skip: nothing here"; exit 3` | `empty` | low |
| `pipes` | pipes unescaped in the cell | `printf 'x\ny\n' \| wc -l \| tr -d ' '` | `regex:^2$` | low |
| `env` | REPO_ROOT LATTICE_HOME PROBE_ID REGISTRY_DIR exported, cwd = REPO_ROOT | `[ "$PWD" = "$REPO_ROOT" ] && [ "$LATTICE_HOME" = "$REPO_ROOT/.lattice" ] && [ "$PROBE_ID" = env ] && [ -d "$REGISTRY_DIR" ]` | `exit0` | high |
ROWS
  run bash "$CP" --home "$HOME_DIR" --registry "$TEST_DIR/registry.md" --json
  [ "$status" -eq 0 ]
  CP_OUT="$output" python3 - <<'PY'
import json, os, sys
d = json.loads(os.environ["CP_OUT"])
by = {p["id"]: p for p in d["probes"]}
want = {"e0-pass": "pass", "e0-fail": "fail", "rx-pass": "pass", "rx-fail": "fail",
        "empty-pass": "pass", "empty-fail": "fail", "empty-crash": "fail", "skip-3": "skip",
        "pipes": "pass", "env": "pass"}
for k, v in want.items():
    assert by[k]["status"] == v, (k, by[k])
assert by["e0-fail"]["evidence"] == "exit 4 — boom", by["e0-fail"]["evidence"]
assert by["rx-fail"]["evidence"].startswith("no match for /^hello/ — goodbye"), by["rx-fail"]["evidence"]
assert by["empty-fail"]["evidence"] == "drift-1 ⏎ drift-2", by["empty-fail"]["evidence"]
assert by["empty-crash"]["evidence"].startswith("exit 127"), by["empty-crash"]["evidence"]
assert by["skip-3"]["evidence"] == "skip: nothing here", by["skip-3"]["evidence"]
assert d["summary"] == {"pass": 5, "fail": 4, "skip": 1}, d["summary"]
PY
}

@test "evidence is truncated to 200 chars and pipes are escaped in --md" {
  write_registry <<'ROWS'
| `long` | long stdout | `head -c 400 /dev/zero \| tr '\0' x` | `empty` | low |
| `pipe-out` | stdout with a pipe | `echo 'a \| b'` | `empty` | low |
ROWS
  run bash "$CP" --home "$HOME_DIR" --registry "$TEST_DIR/registry.md" --json
  [ "$status" -eq 0 ]
  CP_OUT="$output" python3 - <<'PY'
import json, os, sys
d = json.loads(os.environ["CP_OUT"])
by = {p["id"]: p for p in d["probes"]}
assert len(by["long"]["evidence"]) == 201 and by["long"]["evidence"].endswith("…"), len(by["long"]["evidence"])
assert by["pipe-out"]["evidence"] == "a | b", by["pipe-out"]["evidence"]
PY
  run bash "$CP" --home "$HOME_DIR" --registry "$TEST_DIR/registry.md" --md
  [ "$status" -eq 0 ]
  grep -q '^| pipe-out | fail | low | a \\| b |$' <<<"$output"
}

@test "--timeout kills a hung probe and reports fail with 'timeout'; exit stays 0" {
  write_registry <<'ROWS'
| `hang` | hangs | `sleep 30; echo late` | `exit0` | low |
| `after` | still runs after the hang | `echo ok` | `regex:ok` | low |
ROWS
  run bash "$CP" --home "$HOME_DIR" --registry "$TEST_DIR/registry.md" --timeout 1 --md
  [ "$status" -eq 0 ]
  grep -q '^| hang | fail | low | timeout after 1s' <<<"$output"
  grep -q '^| after | pass | low |  |$' <<<"$output"
  grep -qx 'claim-probes: 1 pass, 1 fail, 0 skip' <<<"$output"
}

@test "always exit 0 with failures present; missing registry degrades, not crashes" {
  plant fsm-doc-edges-subset-of-schema
  run bash "$CP" --home "$HOME_DIR" --md
  [ "$status" -eq 0 ]
  grep -qx 'claim-probes: 6 pass, 1 fail, 0 skip' <<<"$output"
  run bash "$CP" --home "$HOME_DIR" --registry "$TEST_DIR/nope.md" --md
  [ "$status" -eq 0 ]
  grep -q '^claim-probes: registry not found: ' <<<"$output"
  run bash "$CP" --home "$HOME_DIR" --registry "$TEST_DIR/nope.md" --json
  [ "$status" -eq 0 ]
  grep -q '"degraded": *"registry not found' <<<"$output"
}

# ---------------------------------------------------------------------------
# review cycle 1 (pr-376): a sensor never tracebacks, never passes vacuously
# ---------------------------------------------------------------------------

@test "M1: an explicit --overlay that does not exist is reported degraded and ignored; exit 0" {
  run bash "$CP" --home "$HOME_DIR" --overlay /nonexistent/lineage-probes.tsv --md
  [ "$status" -eq 0 ]
  grep -q '^claim-probes: overlay unreadable: /nonexistent/lineage-probes.tsv (.*) (ignored)$' <<<"$output"
  grep -qx 'claim-probes: 7 pass, 0 fail, 0 skip' <<<"$output"
  if grep -q 'Traceback' <<<"$output"; then false; fi
  run bash "$CP" --home "$HOME_DIR" --overlay /nonexistent/lineage-probes.tsv --json
  [ "$status" -eq 0 ]
  CP_OUT="$output" python3 - <<'PY'
import json, os
d = json.loads(os.environ["CP_OUT"])
assert len(d["degraded"]) == 1 and d["degraded"][0].startswith("overlay unreadable: /nonexistent/"), d["degraded"]
assert d["summary"] == {"pass": 7, "fail": 0, "skip": 0}, d["summary"]
PY
}

@test "M1: non-UTF-8 bytes in the overlay or registry never traceback; readable rows still run" {
  printf 'bin-ok\tbytes beside it\techo ok\tregex:^ok$\tlow\n\xff\xfe\x00 garbage\n' >"$HOME_DIR/lineage-probes.tsv"
  run bash "$CP" --home "$HOME_DIR" --md
  [ "$status" -eq 0 ]
  grep -q '^| bin-ok | pass | low |  |$' <<<"$output"
  grep -q '^| overlay-row-2 | skip | low | malformed overlay row (line 2): 1 fields, expected 5 |$' <<<"$output"
  if grep -q 'Traceback' <<<"$output"; then false; fi
  rm -f "$HOME_DIR/lineage-probes.tsv"
  { printf '| id | claim (where) | probe | expect | severity |\n| --- | --- | --- | --- | --- |\n'
    printf '| `bin-reg` | \xff\xfe bytes in the claim | `echo ok` | `regex:^ok$` | low |\n'; } >"$TEST_DIR/bin.md"
  run bash "$CP" --home "$HOME_DIR" --registry "$TEST_DIR/bin.md" --md
  [ "$status" -eq 0 ]
  grep -q '^| bin-reg | pass | low |  |$' <<<"$output"
  grep -qx 'claim-probes: 1 pass, 0 fail, 0 skip' <<<"$output"
}

@test "M2: --home whose parent does not exist fails loud (stderr), exits 0, and skips every probe" {
  run bash "$CP" --home /no/such/parent/.lattice --md
  [ "$status" -eq 0 ]
  grep -qx 'error: --home parent not found: /no/such/parent' <<<"$output"
  grep -qx 'claim-probes: 0 pass, 0 fail, 7 skip' <<<"$output"
  for id in $BUILTINS; do
    grep -qE "^\| $id \| skip \| (high|med|low) \| error: --home parent not found: /no/such/parent \|$" <<<"$output"
  done
  # bats `run` merges stderr; drop the stderr line inside a subshell so $output is JSON only
  run bash -c "bash \"$CP\" --home /no/such/parent/.lattice --json 2>/dev/null"
  [ "$status" -eq 0 ]
  CP_OUT="$output" python3 - <<'PY'
import json, os
d = json.loads(os.environ["CP_OUT"])
assert d["degraded"] == ["error: --home parent not found: /no/such/parent"], d["degraded"]
assert d["summary"] == {"pass": 0, "fail": 0, "skip": 7}, d["summary"]
assert d["repo_root"] != "/", d["repo_root"]
PY
}

@test "M3: overlay cells wrapped in backticks are unwrapped like registry cells" {
  printf '`bt-probe`\tbackticked overlay cells\t`echo ok`\t`regex:^ok$`\t`low`\n' >"$HOME_DIR/lineage-probes.tsv"
  run bash "$CP" --home "$HOME_DIR" --json
  [ "$status" -eq 0 ]
  CP_OUT="$output" python3 - <<'PY'
import json, os
d = json.loads(os.environ["CP_OUT"])
by = {p["id"]: p for p in d["probes"]}
assert by["bt-probe"]["status"] == "pass", by["bt-probe"]
assert by["bt-probe"]["expect"] == "regex:^ok$" and by["bt-probe"]["severity"] == "low", by["bt-probe"]
PY
}

@test "spec-done-acceptance-cites-evidence ships at severity low (stricter than the Spec convention)" {
  run bash "$CP" --home "$HOME_DIR" --only spec-done-acceptance-cites-evidence --md
  [ "$status" -eq 0 ]
  grep -q '^| spec-done-acceptance-cites-evidence | pass | low |  |$' <<<"$output"
}

@test "usage errors exit 2" {
  run bash "$CP" --bogus
  [ "$status" -eq 2 ]
  run bash "$CP" --timeout abc
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# the real registry on this repo (structure only — pass/fail is a finding,
# reported in the PR, not asserted here)
# ---------------------------------------------------------------------------

@test "real registry runs on this repo: 7 built-in rows, no skip, no malformed rows, exit 0" {
  run bash "$CP" --home "$REPO_ROOT/.lattice" --json
  [ "$status" -eq 0 ]
  CP_OUT="$output" python3 - <<'PY'
import json, os, sys
d = json.loads(os.environ["CP_OUT"])
ids = [p["id"] for p in d["probes"]]
assert ids == ["skill-scripts-exist", "hooks-json-files-exist", "validator-codes-cited-exist",
               "retired-paths-absent", "adr-verification-refs-resolve",
               "spec-done-acceptance-cites-evidence", "fsm-doc-edges-subset-of-schema"], ids
assert d["summary"]["skip"] == 0, d["summary"]
for p in d["probes"]:
    assert p["status"] in ("pass", "fail"), p
    assert p["exit"] == 0 or p["status"] == "fail", p
PY
}

@test "registry table: every built-in row has a planted fixture and the deny-list has entries" {
  for id in $BUILTINS; do
    [ -d "$FIX/planted/$id" ]
    grep -qF "| \`$id\` |" "$REGISTRY"
  done
  [ -f "$REPO_ROOT/skills/review-lineage/references/retired-paths.txt" ]
  n=$(grep -cvE '^(#|[[:space:]]*$)' "$REPO_ROOT/skills/review-lineage/references/retired-paths.txt")
  [ "$n" -ge 4 ]
}
