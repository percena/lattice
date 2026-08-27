#!/usr/bin/env bats
# Registration-surface parity (rev-20260827-033352Z F6): the routing catalog in
# tools/run-routing-evals.py must stay set-equal to the USER_FACING list in
# tools/validate-skills.sh. Both lists are extracted from source so neither can
# drift silently — adding a skill to one without the other fails this suite.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export VALIDATE="$REPO_ROOT/tools/validate-skills.sh"
  export RUNNER="$REPO_ROOT/tools/run-routing-evals.py"
  export ROUTING_DIR="$REPO_ROOT/evals/routing"
}

user_facing_list() {
  sed -n '/^USER_FACING=(/,/^)/p' "$VALIDATE" | sed '1d;$d;s/[[:space:]"]//g' | grep -v '^$'
}

catalog_list() {
  sed -n '/^CATALOG = \[/,/^\]/p' "$RUNNER" | sed '1d;$d;s/[[:space:]",]//g' | grep -v '^$'
}

@test "extraction finds both lists (non-empty)" {
  [ "$(user_facing_list | wc -l)" -gt 0 ]
  [ "$(catalog_list | wc -l)" -gt 0 ]
}

@test "routing CATALOG is set-equal to validate-skills USER_FACING" {
  diff <(user_facing_list | sort) <(catalog_list | sort)
}

@test "every CATALOG skill has a routing case file" {
  while IFS= read -r name; do
    [ -f "$ROUTING_DIR/$name.json" ] || {
      echo "missing routing case: evals/routing/$name.json" >&2
      return 1
    }
  done < <(catalog_list)
}
