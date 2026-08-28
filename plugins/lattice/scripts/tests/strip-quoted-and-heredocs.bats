#!/usr/bin/env bats
# Tests for strip-quoted-and-heredocs.py
#
# Verifies the helper normalizes shell commands so callers can match
# command-phrase patterns against the cleaned text: whitespace-free quoted
# spans inline to their content (a quoted token is still a real invocation),
# whitespace-bearing spans collapse to a placeholder, heredoc bodies and
# comments are removed.

setup() {
  SCRIPTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HELPER="$SCRIPTS_DIR/strip-quoted-and-heredocs.py"
  DETECT_HELPER="$SCRIPTS_DIR/detect-gh-pr-command.py"
}

# Pipe stdin into the helper, capture stdout
run_helper() {
  printf '%s' "$1" | python3 "$HELPER"
}

detect_create() {
  printf '%s' "$1" | python3 "$DETECT_HELPER" create
}

PHRASE_RE='gh[[:space:]]+pr[[:space:]]+(create|merge)'

# ============================================================
# Unquoted content passes through unchanged
# ============================================================

@test "passes through a bare command unchanged" {
  result=$(run_helper "foo bar baz")
  [ "$result" = "foo bar baz" ]
}

@test "passes through multi-line unquoted content unchanged" {
  input=$'cd /tmp\nls -la\necho done'
  result=$(run_helper "$input")
  [ "$result" = "$input" ]
}

# ============================================================
# Quoted spans: whitespace content -> placeholder, single word -> inlined
# ============================================================

@test "collapses single-quoted phrase to placeholder" {
  result=$(run_helper "echo 'hidden phrase'")
  [ "$result" = "echo Q" ]
}

@test "inlines whitespace-free single-quoted words" {
  result=$(run_helper "foo 'a' bar 'b'")
  [ "$result" = "foo a bar b" ]
}

@test "collapses double-quoted phrase to placeholder" {
  result=$(run_helper 'echo "hidden phrase"')
  [ "$result" = "echo Q" ]
}

@test "collapses double-quoted span containing escaped quotes" {
  result=$(run_helper 'echo "he said \"hi\""')
  [ "$result" = "echo Q" ]
}

@test "placeholder cannot splice neighbours into a false phrase match" {
  result=$(run_helper 'echo gh "1" pr "2" create')
  [ "$result" = "echo gh 1 pr 2 create" ]
  [ -z "$(printf '%s\n' "$result" | grep -E "$PHRASE_RE")" ]
}

# ============================================================
# Quoted-token invocations stay matchable (real executions)
# ============================================================

@test "quoted command token still matches (gh \"pr\" merge)" {
  result=$(run_helper 'gh "pr" merge 5')
  [ "$result" = "gh pr merge 5" ]
}

@test "ansi-c quoted token still matches (gh \$'pr' create)" {
  result=$(run_helper "gh \$'pr' create")
  [ "$result" = "gh pr create" ]
}

@test "quoted first token still matches (\"gh\" pr create)" {
  result=$(run_helper '"gh" pr create')
  [ "$result" = "gh pr create" ]
}

@test "mid-word quotes still match (gh pr crea\"te\")" {
  result=$(run_helper 'gh pr crea"te"')
  [ "$result" = "gh pr create" ]
}

@test "backslash-escaped letters still match (gh p\\r create)" {
  result=$(run_helper 'gh p\r create')
  [ "$result" = "gh pr create" ]
}

@test "line continuation still matches (gh pr \\<newline>create)" {
  input=$'gh pr \\\ncreate --fill'
  result=$(run_helper "$input")
  printf '%s\n' "$result" | grep -qE "$PHRASE_RE"
}

@test "single-quoted double-quote chars cannot hide a real invocation" {
  input=$'echo \'"\'; gh pr create; echo \'"\''
  result=$(run_helper "$input")
  printf '%s\n' "$result" | grep -qE "$PHRASE_RE"
}

# ============================================================
# Command substitution (backtick and $()) stays visible, including
# inside double quotes where bash still executes it; escaped forms stay literal
# ============================================================

@test "bare \$(gh pr create) is preserved for matching" {
  result=$(run_helper 'x=$(gh pr create)')
  printf '%s\n' "$result" | grep -qF "gh pr create"
}

@test "\$(gh pr create) inside double quotes is surfaced, not collapsed" {
  result=$(run_helper 'echo "see $(gh pr create) done"')
  printf '%s\n' "$result" | grep -qF "gh pr create"
}

@test "literal double-quoted text inside \$(...) still collapses" {
  # Interior of a substitution is itself normalized, so a literal quoted span
  # inside it cannot masquerade as a phrase.
  result=$(run_helper 'echo "$(echo "gh pr create")"')
  [ -z "$(printf '%s\n' "$result" | grep -F "gh pr create")" ]
}

@test "quoted opening paren inside \$(...) does not hide a later command" {
  result=$(run_helper 'echo "$(printf "("; gh pr create)"')
  run detect_create "$result"
  [ "$status" -eq 0 ]
}

@test "quoted closing paren inside \$(...) does not expose outer literal text" {
  result=$(run_helper 'echo "$(printf ")") gh pr create "')
  run detect_create "$result"
  [ "$status" -eq 1 ]
}

@test "nested \$(...) inside a quoted substitution keeps matching its own parens" {
  result=$(run_helper 'echo "$(printf "%s" "$(printf "(")"; gh pr create)"')
  run detect_create "$result"
  [ "$status" -eq 0 ]
}

@test "case pattern paren inside \$(...) does not close the substitution" {
  result=$(run_helper 'echo "$(case x in x) gh pr create;; esac)"')
  run detect_create "$result"
  [ "$status" -eq 0 ]
}

@test "parameter-expansion paren inside \$(...) does not close the substitution" {
  result=$(run_helper 'echo "$(echo ${x:-)}; gh pr create)"')
  run detect_create "$result"
  [ "$status" -eq 0 ]
}

@test "comment paren inside \$(...) does not close the substitution" {
  result=$(run_helper $'echo "$(\n# )\ngh pr create\n)"')
  run detect_create "$result"
  [ "$status" -eq 0 ]
}

@test "heredoc-body paren inside \$(...) does not close the substitution" {
  result=$(run_helper $'echo "$(cat <<\'EOF\'\n)\nEOF\ngh pr create\n)"')
  run detect_create "$result"
  [ "$status" -eq 0 ]
}

@test "bash no-exec boundary parsing never executes substitution content" {
  marker="${BATS_TEST_TMPDIR:-$(mktemp -d)}/normalizer-must-not-execute"
  printf -v input 'echo "$(touch %q; gh pr create)"' "$marker"
  result=$(run_helper "$input")
  [ ! -e "$marker" ]
  run detect_create "$result"
  [ "$status" -eq 0 ]
}

@test "parse-budget exhaustion fails closed: surfaces the real invocation" {
  # A zero budget forces _BoundaryUnknown on the first `)` candidate, before
  # any bash -n spawn. The fail-closed path must surface the substitution body
  # (normalized) so a genuine `gh pr create` cannot be hidden by collapsing it.
  LATTICE_STRIP_PAREN_BUDGET_SECONDS=0 run run_helper 'echo "$(case y in y) gh pr create;; esac)"'
  result="$output"
  run detect_create "$result"
  [ "$status" -eq 0 ]
}

@test "parse-budget exhaustion still does not execute substitution content" {
  marker="${BATS_TEST_TMPDIR:-$(mktemp -d)}/fail-closed-must-not-execute"
  printf -v input 'echo "$(touch %q; gh pr create)"' "$marker"
  LATTICE_STRIP_PAREN_BUDGET_SECONDS=0 run run_helper "$input"
  result="$output"
  [ ! -e "$marker" ]
  run detect_create "$result"
  [ "$status" -eq 0 ]
}

@test "single-candidate parser timeout fails closed instead of hiding an invocation" {
  # Import the helper and replace only subprocess.run so this deterministically
  # exercises TimeoutExpired without adding a multi-second test fixture.
  run python3 - "$HELPER" <<'PY'
import importlib.util
import pathlib
import subprocess
import sys

helper = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("strip_quoted_and_heredocs", helper)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def time_out(*args, **kwargs):
    raise subprocess.TimeoutExpired(args[0], kwargs.get("timeout"))

module.subprocess.run = time_out
print(module.strip('echo "$(printf \")"; gh pr create)"'))
PY
  [ "$status" -eq 0 ]
  run detect_create "$output"
  [ "$status" -eq 0 ]
}

@test "escaped \$( does not execute and stays neutralized" {
  result=$(run_helper 'echo "\$(gh pr create)"')
  [ -z "$(printf '%s\n' "$result" | grep -F "gh pr create")" ]
}

@test "backtick substitution inside double quotes is surfaced" {
  result=$(run_helper 'echo "see `gh pr create` done"')
  printf '%s\n' "$result" | grep -qF "gh pr create"
}


@test "legacy backtick command substitution remains matchable" {
  result=$(run_helper 'echo `gh pr create`')
  printf '%s\n' "$result" | grep -qE "$PHRASE_RE"
}

@test "backtick command substitution inside double quotes remains matchable" {
  result=$(run_helper 'x="prefix `gh pr merge 1` suffix"')
  printf '%s\n' "$result" | grep -qE "$PHRASE_RE"
}

@test "escaped backticks remain literal and cannot create a match" {
  result=$(run_helper 'echo \`gh pr create\`')
  run detect_create "$result"
  [ "$status" -eq 1 ]
}

@test "escaped backticks do not hide a real command after a separator" {
  result=$(run_helper 'echo \`note; gh pr create; echo \`')
  run detect_create "$result"
  [ "$status" -eq 0 ]
}

@test "single-quoted backticks remain literal and cannot create a match" {
  result=$(run_helper "echo '\`gh pr create\`'")
  [ -z "$(printf '%s\n' "$result" | grep -E "$PHRASE_RE")" ]
}

# ============================================================
# Heredoc bodies are stripped
# ============================================================

@test "strips plain heredoc body" {
  input=$'cat <<EOF\nsecret line\nEOF'
  result=$(run_helper "$input")
  [ "$result" = "cat " ]
}

@test "strips dash-indented heredoc body" {
  input=$'cat <<-EOF\n\tsecret line\n\tEOF'
  result=$(run_helper "$input")
  [ "$result" = "cat " ]
}

@test "strips quoted-delimiter heredoc body" {
  input=$'cat <<\'EOF\'\nsecret line\nEOF'
  result=$(run_helper "$input")
  [ "$result" = "cat " ]
}

@test "strips heredoc with double-quoted delimiter" {
  input=$'cat <<"EOF"\nsecret line\nEOF'
  result=$(run_helper "$input")
  [ "$result" = "cat " ]
}

@test "strips heredoc with hyphenated delimiter" {
  input=$'cat <<\'E-O-F\'\ngh pr create\nE-O-F'
  result=$(run_helper "$input")
  [ -z "$(printf '%s\n' "$result" | grep -E "$PHRASE_RE")" ]
}

@test "heredoc opener inside double quotes does not swallow following code" {
  input=$'echo "docs<<X"\ngh pr create\nX'
  result=$(run_helper "$input")
  printf '%s\n' "$result" | grep -qE "$PHRASE_RE"
}

@test "here-string is an operator, not a heredoc" {
  input=$'grep x <<<foo\ngh pr merge 5'
  result=$(run_helper "$input")
  printf '%s\n' "$result" | grep -qE "$PHRASE_RE"
}

@test "arithmetic shift is not a heredoc opener" {
  input=$'echo $((1<<2))\ngh pr create'
  result=$(run_helper "$input")
  printf '%s\n' "$result" | grep -qE "$PHRASE_RE"
}

# ============================================================
# Comments
# ============================================================

@test "comment content is removed" {
  result=$(run_helper 'git push  # then gh pr create')
  [ -z "$(printf '%s\n' "$result" | grep -E "$PHRASE_RE")" ]
}

@test "hash inside a word is not a comment" {
  result=$(run_helper 'echo foo#bar baz')
  [ "$result" = "echo foo#bar baz" ]
}

# ============================================================
# Mixed cases
# ============================================================

@test "strips quotes and heredocs together, preserves surrounding content" {
  input=$'echo "a"; cat <<EOF\nbody\nEOF\necho \'b\''
  result=$(run_helper "$input")
  [ "$result" = $'echo a; cat \necho b' ]
}

@test "phrase outside any quotes survives stripping" {
  result=$(run_helper "gh pr create 'hidden'")
  printf '%s\n' "$result" | grep -qF "gh pr create"
}

@test "phrase inside single quotes is removed" {
  result=$(run_helper "echo 'gh pr create'")
  [ -z "$(printf '%s\n' "$result" | grep -F "gh pr create")" ]
}

@test "phrase inside double quotes is removed" {
  result=$(run_helper 'echo "gh pr create"')
  [ -z "$(printf '%s\n' "$result" | grep -F "gh pr create")" ]
}

@test "phrase inside heredoc body is removed" {
  input=$'cat <<EOF\ngh pr create\nEOF'
  result=$(run_helper "$input")
  [ -z "$(printf '%s\n' "$result" | grep -F "gh pr create")" ]
}

# ============================================================
# Edge cases
# ============================================================

@test "handles empty input" {
  result=$(run_helper "")
  [ "$result" = "" ]
}

@test "unterminated single quote collapses (bash executes nothing)" {
  result=$(run_helper "echo 'unterminated")
  [ "$result" = "echo Q" ]
}

@test "unterminated heredoc body is removed (bash still runs the command)" {
  input=$'cat <<EOF\nnever closed\ngh pr create'
  result=$(run_helper "$input")
  [ -z "$(printf '%s\n' "$result" | grep -F "gh pr create")" ]
  printf '%s\n' "$result" | grep -qE '^cat '
}

# ============================================================
# Arithmetic `<<` is a shift operator, not a heredoc opener
# ============================================================

@test "arithmetic shift does not swallow the following line" {
  result=$(run_helper 'echo $(( x << y ))
gh pr create')
  printf '%s\n' "$result" | grep -qF "gh pr create"
  run detect_create "$result"
  [ "$status" -eq 0 ]
}

@test "arithmetic command form (( … << … )) does not swallow the following line" {
  result=$(run_helper '(( shifted = x << y ))
gh pr create --title t')
  run detect_create "$result"
  [ "$status" -eq 0 ]
}

@test "digit-first shift operands still do not open a heredoc" {
  result=$(run_helper 'echo $((1<<2))
gh pr create')
  run detect_create "$result"
  [ "$status" -eq 0 ]
}

@test "a real heredoc after arithmetic is still consumed" {
  result=$(run_helper 'echo $(( x << y ))
cat <<EOF
gh pr create
EOF')
  [ -z "$(printf '%s\n' "$result" | grep -F "gh pr create")" ]
  run detect_create "$result"
  [ "$status" -eq 1 ]
}
