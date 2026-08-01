#!/usr/bin/env bash
# Usage: ./upload-github-asset.sh [--allow-outside-repo] <file-path> [repository_id]
# Requires: git, gh, curl, jq, python3
set -euo pipefail

ALLOW_OUTSIDE_REPO=false
if [[ "${1:-}" == "--allow-outside-repo" ]]; then
  ALLOW_OUTSIDE_REPO=true
  shift
fi

FILE_PATH="${1:-}"
REPO_ID="${2:-}"

if [[ -n "$REPO_ID" && ! "$REPO_ID" =~ ^[0-9]+$ ]]; then
  echo "Error: repository_id must be numeric, got: $REPO_ID" >&2
  exit 1
fi

if [[ -z "$FILE_PATH" ]]; then
  echo "Usage: upload-github-asset.sh [--allow-outside-repo] <file-path> [repository_id]" >&2
  exit 1
fi

# Preflight every required tool before fetching the auth token — the header
# promises gh, curl, jq; a missing jq mid-flight would abort after the token
# was already fetched.
for tool in git gh curl jq python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: $tool is required by upload-github-asset.sh" >&2
    exit 1
  fi
done

# Resolve and validate the source before fetching credentials. By default only
# regular files physically inside the current worktree are uploadable. For a
# source inside the repo, every component below the repo root is lstat'd so a
# checkout cannot redirect an innocent media-looking path to a local secret.
# A source outside the repo requires the explicit --allow-outside-repo intent
# flag — the model must never add it for a model-discovered path. Outside-repo
# paths are lstat'd only at the final component (a symlinked file is refused),
# because walking every ancestor would false-reject platform path aliases such
# as /tmp -> /private/tmp and /var -> /private/var on macOS.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "Error: upload-github-asset.sh must run inside a Git worktree" >&2
  exit 1
}
export UPLOAD_SOURCE="$FILE_PATH"
export UPLOAD_REPO_ROOT="$REPO_ROOT"
export UPLOAD_ALLOW_OUTSIDE="$ALLOW_OUTSIDE_REPO"
if ! VALIDATED_PATH=$(python3 - <<'PY'
import os
import stat
import sys

source_input = os.path.abspath(os.environ["UPLOAD_SOURCE"])
repo = os.path.realpath(os.environ["UPLOAD_REPO_ROOT"])
allow_outside = os.environ.get("UPLOAD_ALLOW_OUTSIDE") == "true"

# Find the lexical spelling of the repository root used by the supplied path.
# This tolerates platform aliases such as /var -> /private/var while still
# letting us lstat every consumer-controlled component below the repo root.
anchor = None
candidate = source_input
while True:
    if os.path.realpath(candidate) == repo:
        anchor = candidate
        break
    parent = os.path.dirname(candidate)
    if parent == candidate:
        break
    candidate = parent

components = [source_input]
if anchor is not None:
    components = []
    current = anchor
    for part in os.path.relpath(source_input, anchor).split(os.path.sep):
        current = os.path.join(current, part)
        components.append(current)

for component in components:
    try:
        mode = os.lstat(component).st_mode
    except FileNotFoundError:
        print(f"Error: File not found: {source_input}", file=sys.stderr)
        raise SystemExit(1)
    if stat.S_ISLNK(mode):
        print(f"Error: refusing symlinked upload path component: {component}", file=sys.stderr)
        raise SystemExit(1)

source = os.path.realpath(source_input)
inside = os.path.commonpath([repo, source]) == repo
if not inside and not allow_outside:
    print("Error: upload source is outside the current Git worktree; pass --allow-outside-repo only for a path the user explicitly approved", file=sys.stderr)
    raise SystemExit(1)

if not stat.S_ISREG(os.stat(source).st_mode):
    print(f"Error: upload source is not a regular file: {source}", file=sys.stderr)
    raise SystemExit(1)

print(source)
PY
); then
  exit 1
fi
FILE_PATH="$VALIDATED_PATH"
unset UPLOAD_SOURCE UPLOAD_REPO_ROOT UPLOAD_ALLOW_OUTSIDE

# Get auth token
TOKEN=$(gh auth token 2>/dev/null) || {
  echo "Error: gh auth token failed. Run 'gh auth login' first." >&2
  exit 1
}

# Auto-detect repo ID if not provided
if [[ -z "$REPO_ID" ]]; then
  # Read-only remote lookup (same approach as check-pr-context.sh).
  REMOTE_URL=$(git config --get remote.origin.url 2>/dev/null || echo "")
  if [[ -n "$REMOTE_URL" ]]; then
    # Extract owner/repo from SSH, HTTPS, or git@github.com: forms
    OWNER_REPO=$(printf '%s' "$REMOTE_URL" | sed -E 's|^.*github\.com[:/]||; s|\.git$||')
    # Pin the charset before it becomes a gh api path segment: a remote URL
    # with extra segments, '?' or '..' would otherwise change the endpoint.
    # owner/repo becomes a path segment in a gh api URL. Each component must
    # contain at least one non-dot character, which is what rejects the traversal
    # forms `..`, `.` and `...` while still allowing real names like `owner/.github`.
    OWNER_REPO_RE='^[A-Za-z0-9._-]*[A-Za-z0-9_-][A-Za-z0-9._-]*/[A-Za-z0-9._-]*[A-Za-z0-9_-][A-Za-z0-9._-]*$'
    if [[ "$OWNER_REPO" =~ $OWNER_REPO_RE ]]; then
      REPO_ID=$(gh api "repos/$OWNER_REPO" --jq '.id' 2>/dev/null || echo "")
    fi
  fi

  if [[ -z "$REPO_ID" ]]; then
    echo "Error: Could not detect repository ID. Pass it as second argument." >&2
    exit 1
  fi
fi

# Determine MIME type from extension
FILENAME=$(basename "$FILE_PATH")
EXT="${FILENAME##*.}"
EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

case "$EXT_LOWER" in
  png)  MIME="image/png" ;;
  jpg|jpeg) MIME="image/jpeg" ;;
  gif)  MIME="image/gif" ;;
  webp) MIME="image/webp" ;;
  svg)  MIME="image/svg+xml" ;;
  mov)  MIME="video/quicktime" ;;
  mp4)  MIME="video/mp4" ;;
  webm) MIME="video/webm" ;;
  *)
    echo "Error: Unsupported file type '.$EXT_LOWER'. Supported: png, jpg, jpeg, gif, webp, svg, mov, mp4, webm" >&2
    exit 1
    ;;
esac

# URL-encode filename and mime type
ENCODED_NAME=$(printf '%s' "$FILENAME" | jq -sRr @uri)
ENCODED_MIME=$(printf '%s' "$MIME" | jq -sRr @uri)

# Upload (-sS: quiet progress but keep curl's own error text on failure).
# Pass Authorization via a temp curl config (not argv) so the bearer token is
# not visible in process listings on shared hosts.
CURL_CFG=$(mktemp "${TMPDIR:-/tmp}/upload-curl.XXXXXX")
# INT/TERM/HUP too: an interrupted upload must not leave a bearer token
# readable on disk until the next reboot.
trap 'rm -f "$CURL_CFG"' EXIT INT TERM HUP
# curl --config: header lines are "header = Value" (no shell expansion later)
{
  printf 'header = "Authorization: Bearer %s"\n' "$TOKEN"
  printf 'header = "Content-Type: application/octet-stream"\n'
  printf 'header = "Accept: application/json"\n'
  printf 'header = "X-GitHub-Api-Version: 2022-11-28"\n'
} >"$CURL_CFG"
# Drop TOKEN from the environment of the curl child (extra belt-and-braces).
unset TOKEN

CURL_RC=0
RESPONSE=$(curl -sS -w "\n%{http_code}" \
  --config "$CURL_CFG" \
  "https://uploads.github.com/user-attachments/assets?name=${ENCODED_NAME}&content_type=${ENCODED_MIME}&repository_id=${REPO_ID}" \
  -X POST \
  --data-binary "@$FILE_PATH") || CURL_RC=$?

if [[ "$CURL_RC" -ne 0 ]]; then
  echo "Error: curl failed (exit $CURL_RC) before any HTTP response — network/DNS/TLS problem?" >&2
  exit 1
fi

# Split response body and HTTP status
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" != "201" ]]; then
  echo "Error: Upload failed with HTTP $HTTP_CODE" >&2
  echo "$BODY" >&2
  exit 1
fi

# Extract URL from response
URL=$(echo "$BODY" | jq -r '.url // empty')
if [[ -z "$URL" ]]; then
  echo "Error: No URL in response: $BODY" >&2
  exit 1
fi

# Output the URL
echo "$URL"
