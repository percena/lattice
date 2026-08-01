#!/usr/bin/env bats
# Tests for upload-github-asset.sh using stubbed gh/curl on PATH (no network).

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../.." && pwd)"
  export UPLOAD="$REPO_ROOT/skills/_lattice-lib/scripts/upload-github-asset.sh"
}

setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/upload.XXXXXX")"
  git -C "$TEST_DIR" init -q -b main
  git -C "$TEST_DIR" config user.email lattice-test@example.invalid
  git -C "$TEST_DIR" config user.name 'Lattice Test'
  cd "$TEST_DIR"
  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"
  printf 'fake-png' >"$TEST_DIR/shot.png"
  printf 'fake' >"$TEST_DIR/notes.txt"
  export CURL_MODE="ok"
  cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  auth) echo "fake-token" ;;
  api) echo "12345" ;;
esac
EOF
  cat >"$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
case "${CURL_MODE:-ok}" in
  ok)     printf '{"url":"https://github.com/user-attachments/assets/abc"}\n201\n' ;;
  http422) printf '{"message":"Validation Failed"}\n422\n' ;;
  netfail) echo "curl: (6) Could not resolve host" >&2; exit 6 ;;
esac
EOF
  chmod +x "$STUB_BIN/gh" "$STUB_BIN/curl"
  export PATH="$STUB_BIN:$PATH"
}

teardown() {
  cd /
  rm -rf "${OUTSIDE_DIR:-}"
  rm -rf "$TEST_DIR"
}

@test "successful upload prints the asset URL" {
  run bash "$UPLOAD" "$TEST_DIR/shot.png" 12345
  [ "$status" -eq 0 ]
  [ "$output" = "https://github.com/user-attachments/assets/abc" ]
}

@test "unsupported extension is rejected before any upload" {
  run bash "$UPLOAD" "$TEST_DIR/notes.txt" 12345
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported file type"* ]]
}

@test "missing file is a clear error" {
  run bash "$UPLOAD" "$TEST_DIR/nope.png" 12345
  [ "$status" -eq 1 ]
  [[ "$output" == *"File not found"* ]]
}

@test "direct media symlink is rejected before token fetch or upload" {
  printf 'TOP-SECRET' >"$TEST_DIR/secret"
  ln -s secret "$TEST_DIR/release.png"
  export GH_CALLED="$TEST_DIR/gh-called"
  export CURL_CALLED="$TEST_DIR/curl-called"
  cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
touch "$GH_CALLED"
EOF
  cat >"$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
touch "$CURL_CALLED"
EOF
  chmod +x "$STUB_BIN/gh" "$STUB_BIN/curl"

  run bash "$UPLOAD" "$TEST_DIR/release.png" 12345
  [ "$status" -eq 1 ]
  [[ "$output" == *"symlinked upload path component"* ]]
  [ ! -e "$GH_CALLED" ]
  [ ! -e "$CURL_CALLED" ]
}

@test "symlinked parent directory is rejected" {
  OUTSIDE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/upload-outside.XXXXXX")"
  printf 'TOP-SECRET' >"$OUTSIDE_DIR/shot.png"
  ln -s "$OUTSIDE_DIR" "$TEST_DIR/media"

  run bash "$UPLOAD" "$TEST_DIR/media/shot.png" 12345
  [ "$status" -eq 1 ]
  [[ "$output" == *"symlinked upload path component"* ]] || [[ "$output" == *"outside the current Git worktree"* ]]
}

@test "ordinary outside-repo file requires an explicit override" {
  OUTSIDE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/upload-outside.XXXXXX")"
  printf 'image bytes' >"$OUTSIDE_DIR/shot.png"

  run bash "$UPLOAD" "$OUTSIDE_DIR/shot.png" 12345
  [ "$status" -eq 1 ]
  [[ "$output" == *"outside the current Git worktree"* ]]

  run bash "$UPLOAD" --allow-outside-repo "$OUTSIDE_DIR/shot.png" 12345
  [ "$status" -eq 0 ]
  [ "$output" = "https://github.com/user-attachments/assets/abc" ]
}

@test "outside-repo symlinked file is rejected even under --allow-outside-repo" {
  # The final lexical component of an outside-repo path is still lstat'd, so a
  # symlinked file is refused regardless of the intent flag. (Walking every
  # ancestor is intentionally avoided: macOS platform aliases such as
  # /tmp -> /private/tmp would otherwise false-reject real uploads.)
  OUTSIDE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/upload-outside.XXXXXX")"
  printf 'TOP-SECRET' >"$OUTSIDE_DIR/real"
  ln -s "$OUTSIDE_DIR/real" "$OUTSIDE_DIR/link.png"

  run bash "$UPLOAD" --allow-outside-repo "$OUTSIDE_DIR/link.png" 12345
  [ "$status" -eq 1 ]
  [[ "$output" == *"symlinked upload path component"* ]]
}

@test "non-201 HTTP response fails with status and body" {
  export CURL_MODE="http422"
  run bash "$UPLOAD" "$TEST_DIR/shot.png" 12345
  [ "$status" -eq 1 ]
  [[ "$output" == *"HTTP 422"* ]]
  [[ "$output" == *"Validation Failed"* ]]
}

@test "curl network failure gives a friendly error, not a bare abort" {
  export CURL_MODE="netfail"
  run bash "$UPLOAD" "$TEST_DIR/shot.png" 12345
  [ "$status" -eq 1 ]
  [[ "$output" == *"before any HTTP response"* ]]
}

@test "non-numeric repository id is rejected" {
  run bash "$UPLOAD" "$TEST_DIR/shot.png" abc
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be numeric"* ]]
}

@test "missing jq is preflighted before any token fetch" {
  FAKE_BIN="$TEST_DIR/nojq"
  mkdir -p "$FAKE_BIN"
  for tool in bash git sed tr grep cat basename mktemp rm python3; do
    p=$(command -v "$tool" 2>/dev/null) || continue
    ln -s "$p" "$FAKE_BIN/$tool"
  done
  # gh that records any call: preflight must fail before the token is fetched
  cat >"$FAKE_BIN/gh" <<EOF
#!/usr/bin/env bash
echo called >>"$TEST_DIR/gh-called.log"
echo fake-token
EOF
  chmod +x "$FAKE_BIN/gh"
  ln -s "$STUB_BIN/curl" "$FAKE_BIN/curl"
  run env PATH="$FAKE_BIN" bash "$UPLOAD" "$TEST_DIR/shot.png" 12345
  [ "$status" -eq 1 ]
  [[ "$output" == *"jq is required"* ]]
  [ ! -e "$TEST_DIR/gh-called.log" ]
}

@test "missing curl is preflighted before any token fetch" {
  FAKE_BIN="$TEST_DIR/nocurl"
  mkdir -p "$FAKE_BIN"
  for tool in bash git sed tr grep cat basename mktemp rm jq python3; do
    p=$(command -v "$tool" 2>/dev/null) || continue
    ln -s "$p" "$FAKE_BIN/$tool"
  done
  cat >"$FAKE_BIN/gh" <<EOF
#!/usr/bin/env bash
echo called >>"$TEST_DIR/gh-called.log"
echo fake-token
EOF
  chmod +x "$FAKE_BIN/gh"
  run env PATH="$FAKE_BIN" bash "$UPLOAD" "$TEST_DIR/shot.png" 12345
  [ "$status" -eq 1 ]
  [[ "$output" == *"curl is required"* ]]
  [ ! -e "$TEST_DIR/gh-called.log" ]
}

@test "does not put bearer token on curl argv" {
  # Replace curl with a logger that fails if Authorization appears in argv
  cat >"$STUB_BIN/curl" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  if [[ "$a" == *Bearer* || "$a" == *Authorization* ]]; then
    echo "token leaked on argv: $a" >&2
    exit 99
  fi
done
# still honour --config if present (read file for header) — just succeed
printf '{"url":"https://github.com/user-attachments/assets/no-argv"}\n201\n'
EOF
  chmod +x "$STUB_BIN/curl"
  run bash "$UPLOAD" "$TEST_DIR/shot.png" 12345
  [ "$status" -eq 0 ]
  [ "$output" = "https://github.com/user-attachments/assets/no-argv" ]
}
