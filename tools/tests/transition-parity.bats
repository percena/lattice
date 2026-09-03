#!/usr/bin/env bats
# Transition schema parity (spc-254 A4 / D2): the lib transition table is the
# SoT; the validator's vendored copy must stay set-equal, and every status
# edge documented in docs/workflow-fsm.md §2 M2 must be legal per the schema.
# Editing one without the other fails this suite.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export REPO_ROOT
  export LIB="$REPO_ROOT/skills/_lattice-lib/scripts/lib/transition_table.py"
  export VALIDATOR="$REPO_ROOT/tools/validate-lattice-artifacts.py"
  export FSM_DOC="$REPO_ROOT/docs/workflow-fsm.md"
}

# (from,to) pairs from the lib LEGAL_EDGES, as "from to" lines.
lib_pairs() {
  PYTHONPATH="$REPO_ROOT/skills/_lattice-lib/scripts/lib" python3 - <<'PY'
import transition_table as t
for e in t.LEGAL_EDGES:
    print(f"{e.from_} {e.to}")
PY
}

# (from,to) pairs from the validator's vendored LEGAL_TRANSITIONS, as "from to".
# Scope to the LEGAL_TRANSITIONS block so .get("level", "error") calls elsewhere
# are not mistaken for transition tuples.
validator_pairs() {
  sed -n '/^LEGAL_TRANSITIONS: set/,/^}/p' "$VALIDATOR" \
    | grep -oE '\("[a-z-]+", "[a-z-]+"\)' \
    | sed 's/[("")]//g; s/,/ /' | awk '{print $1" "$2}'
}

# Status words used by the schema (for filtering docs prose edges like -> M1).
status_words() {
  PYTHONPATH="$REPO_ROOT/skills/_lattice-lib/scripts/lib" python3 - <<'PY'
import transition_table as t
words = set()
for e in t.LEGAL_EDGES:
    for w in (e.from_, e.to):
        words.add(w)
words.discard("any"); words.discard("init")
print("\n".join(sorted(words)))
PY
}

# Extract the M2 execution table from the FSM doc and emit "from to" for rows
# whose target is a status word (drops prose edges like "stuck -> M1").
docs_m2_status_pairs() {
  local statuses
  statuses=$(status_words)
  awk -v s="$statuses" '
    BEGIN { in_m2=0 }
    /^### M2 execution/ { in_m2=1; next }
    /^### / && in_m2 { in_m2=0 }
    in_m2 && /\| .* → .* \|/ {
      row=$0
      sub(/^\| */, "", row); sub(/ *\|.*$/, "", row)
      n=split(row, parts, " → ")
      if (n < 2) next
      frm=parts[1]; to=parts[2]
      # trim trailing annotation on `to` (e.g. "closed (merged)" -> "closed")
      sub(/\(.*$/, "", to); gsub(/[ \t]+$/, "", to)
      # only emit if `to` is a known status word
      is_status=0
      nl=split(s, known, "\n")
      for (k in known) if (known[k]==to) { is_status=1; break }
      if (is_status) print frm" "to
    }
  ' "$FSM_DOC"
}

@test "lib and validator vendored transition sets are set-equal" {
  diff <(lib_pairs | sort -u) <(validator_pairs | sort -u)
}

@test "lib escape-required edges == validator ESCAPE_REQUIRED set" {
  # Review F5: the validator's ESCAPE_REQUIRED is a separate hardcoded set;
  # assert it stays set-equal with the lib's escape_required flag so a new
  # escape edge added to one but not the other cannot desync enforcement.
  lib_escape() {
    PYTHONPATH="$REPO_ROOT/skills/_lattice-lib/scripts/lib" python3 - <<'PY'
import transition_table as t
for e in t.LEGAL_EDGES:
    if e.escape_required:
        print(f"{e.from_} {e.to}")
PY
  }
  validator_escape() {
    sed -n '/^ESCAPE_REQUIRED: set/,/^}/p' "$VALIDATOR" \
      | grep -oE '\("[a-z-]+", "[a-z-]+"\)' \
      | sed 's/[("")]//g; s/,/ /' | awk '{print $1" "$2}'
  }
  diff <(lib_escape | sort -u) <(validator_escape | sort -u)
}

@test "schema has the documented M2 legal edges (queued->in-progress etc.)" {
  run bash -c "$(declare -f lib_pairs); lib_pairs | grep -q '^queued in-progress$'"
  [ "$status" -eq 0 ]
  run bash -c "$(declare -f lib_pairs); lib_pairs | grep -q '^rework in-progress$'"
  [ "$status" -eq 0 ]
  run bash -c "$(declare -f lib_pairs); lib_pairs | grep -q '^pr-open closed$'"
  [ "$status" -eq 0 ]
}

@test "a truly illegal edge is absent (closed -> queued: terminal is not a source)" {
  run bash -c "$(declare -f lib_pairs); lib_pairs | grep -q '^closed queued$'"
  [ "$status" -ne 0 ]
}

@test "every documented M2 status edge is legal per the schema" {
  # Each docs M2 (from,to) status pair must appear in the lib legal set.
  lib_sorted=$(lib_pairs | sort -u)
  while IFS= read -r pair; do
    [ -n "$pair" ] || continue
    echo "$lib_sorted" | grep -qxF "$pair" || {
      echo "docs M2 edge '$pair' not legal per schema" >&2
      false
    }
  done < <(docs_m2_status_pairs)
}

# ---------------------------------------------------------------------------
# spc-270 A1.5: field-level parity (owner/guard/reason/escape/trace/metric).
# lib↔validator: the full ADR-007 five-piece contract stays field-for-field
# equal so the validator's dependency-free vendored copy cannot drift from the
# canonical lib. lib↔docs: the docs M2 table's Owner cell matches the lib
# edge's owner set for every documented status edge (the field the docs
# carries; guard/escape/trace/metric are lib/implementation detail).
# ---------------------------------------------------------------------------

lib_validator_full_equal() {
  PYTHONPATH="$REPO_ROOT/skills/_lattice-lib/scripts/lib" python3 - "$VALIDATOR" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location('validator', sys.argv[1])
v = importlib.util.module_from_spec(spec); spec.loader.exec_module(v)
import transition_table as t
trows = [(e.from_, e.to, e.owner, e.guard, e.reason, e.escape, e.trace,
         e.metric, e.escape_required) for e in t.LEGAL_EDGES]
vrows = list(v.LEGAL_EDGES_FULL)
bad = 0
if len(trows) != len(vrows):
    print(f'LENGTH lib={len(trows)} validator={len(vrows)}'); sys.exit(1)
for i, (a, b) in enumerate(zip(vrows, trows)):
    if a != b:
        print(f'EDGE {i} lib={b}')
        print(f'EDGE {i} val={a}')
        bad += 1
sys.exit(1 if bad else 0)
PY
}

validator_full_projections() {
  PYTHONPATH="$REPO_ROOT/skills/_lattice-lib/scripts/lib" python3 - "$VALIDATOR" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location('validator', sys.argv[1])
v = importlib.util.module_from_spec(spec); spec.loader.exec_module(v)
proj_pairs = {(e[0], e[1]) for e in v.LEGAL_EDGES_FULL}
assert proj_pairs == v.LEGAL_TRANSITIONS, 'LEGAL_TRANSITIONS != projection of LEGAL_EDGES_FULL'
proj_escape = {(e[0], e[1]) for e in v.LEGAL_EDGES_FULL if e[8]}
assert proj_escape == v.ESCAPE_REQUIRED, 'ESCAPE_REQUIRED != escape projection of LEGAL_EDGES_FULL'
PY
}

docs_m2_owner_pairs() {
  PYTHONPATH="$REPO_ROOT/skills/_lattice-lib/scripts/lib" python3 - "$FSM_DOC" <<'PY'
import re, sys, transition_table as t
doc = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'(?ms)^### M2 execution\s*\n(.*?)(?=^### )', doc)
assert m, 'no M2 section'
body = m.group(1)
lib = {(e.from_, e.to): e.owner for e in t.LEGAL_EDGES}
def owners(s):
    # docs uses 'a / b' (and sometimes 'a, b'); lib uses 'a|b'. Split on any
    # of those, strip each token.
    return {x.strip() for x in re.split(r'[|/]', s.replace(',', ''))}
bad = 0
for line in body.splitlines():
    # cell1 (from → to) has no internal pipes; the Trigger cell MAY contain a
    # pipe inside backticks (e.g. `unblock | re-scope`), so take it greedily
    # and anchor the final pipe-delimited Owner cell (which has no pipes).
    rm = re.match(r'\|\s*([^|]+?)\s*→\s*([^|]+?)\s*\|\s*(.*)\|\s*([^|]*?)\s*\|$', line)
    if not rm:
        continue
    frm, to_raw, _trigger, owner = rm.group(1), rm.group(2), rm.group(3), rm.group(4)
    frm = frm.strip()
    to = re.sub(r'\(.*$', '', to_raw).strip()
    if (frm, to) not in lib:
        continue  # prose edge (e.g. stuck -> M1, rework -> deep-review)
    want = owners(lib[(frm, to)])
    got = owners(owner)
    if want != got:
        print(f'{frm} -> {to}: docs owner {sorted(got)} != lib {sorted(want)}')
        bad += 1
sys.exit(1 if bad else 0)
PY
}

@test "lib and validator full edge tables are field-equal (owner/guard/reason/escape/trace/metric)" {
  run lib_validator_full_equal
  [ "$status" -eq 0 ]
}

@test "validator LEGAL_TRANSITIONS + ESCAPE_REQUIRED are projections of LEGAL_EDGES_FULL (internal consistency)" {
  run validator_full_projections
  [ "$status" -eq 0 ]
}

@test "every documented M2 edge's Owner matches the lib schema (lib↔docs owner parity)" {
  run docs_m2_owner_pairs
  [ "$status" -eq 0 ]
}
