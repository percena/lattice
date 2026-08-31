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

@test "schema has the documented M2 legal edges (queued->in-progress etc.)" {
  run bash -c "$(declare -f lib_pairs); lib_pairs | grep -q '^queued in-progress$'"
  [ "$status" -eq 0 ]
  run bash -c "$(declare -f lib_pairs); lib_pairs | grep -q '^rework in-progress$'"
  [ "$status" -eq 0 ]
  run bash -c "$(declare -f lib_pairs); lib_pairs | grep -q '^pr-open closed$'"
  [ "$status" -eq 0 ]
}

@test "direct rework->pr-open is absent (illegal; must go via in-progress)" {
  run bash -c "$(declare -f lib_pairs); lib_pairs | grep -q '^rework pr-open$'"
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
