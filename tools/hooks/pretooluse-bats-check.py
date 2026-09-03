#!/usr/bin/env python3
"""PreToolUse hook: catch banned assertion forms in .bats files at write time.

Receives the tool input as JSON on stdin. For Write tool calls targeting
a .bats file, writes the content to a temp file and runs
check-bats-assertions.py on it. If the checker finds banned forms
(bare [[ ]], bare ! cmd, grep -q inside [ -z "$(...)" ]), exits 1 to
block the write and prints the findings.

For Edit tool calls, the hook reads the existing file + applies the edit
in-memory, then checks the result. This catches banned forms introduced
by an edit.

tkt-400 / spc-398 A2.
"""
import json
import os
import sys
import tempfile

CHECKER = os.path.join(os.path.dirname(__file__), "..", "check-bats-assertions.py")

def main():
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)  # not a valid tool input — allow

    tool = payload.get("tool_name", "")
    params = payload.get("tool_input", {})

    file_path = params.get("file_path", "")
    if not file_path.endswith(".bats"):
        sys.exit(0)  # not a .bats file — allow

    # Resolve the checker path relative to repo root
    hook_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(os.path.dirname(hook_dir))
    checker = os.path.join(repo_root, "tools", "check-bats-assertions.py")

    if tool == "Write":
        content = params.get("content", "")
    elif tool == "Edit":
        # Read existing file, apply the edit in-memory
        try:
            with open(file_path, encoding="utf-8") as f:
                content = f.read()
            old_str = params.get("old_string", "")
            new_str = params.get("new_string", "")
            if old_str and old_str in content:
                content = content.replace(old_str, new_str, 1)
            elif new_str:
                content = new_str  # fallback: treat as full content
        except (OSError, FileNotFoundError):
            sys.exit(0)  # can't read existing file — allow (CI will catch)
    else:
        sys.exit(0)  # not Write/Edit — allow

    # Write to temp file and run checker
    fd, tmp = tempfile.mkstemp(suffix=".bats")
    try:
        os.write(fd, content.encode("utf-8"))
        os.close(fd)
        rc = os.system(f"python3 {checker} {tmp} > /dev/null 2>&1")
        if rc != 0:
            # Show findings (suppress "OK" output)
            os.system(f"python3 {checker} {tmp} >&2")
            print(f"\nPreToolUse: BLOCKED — banned assertion form(s) in {file_path}", file=sys.stderr)
            print("Fix: replace bare [[ ]] with grep -qE, bare ! cmd with [ ... ],", file=sys.stderr)
            print("and grep -q inside [ -z \"$(...)\" ] with grep -qE at terminal position.", file=sys.stderr)
            sys.exit(1)  # block the write
    finally:
        os.unlink(tmp)

    sys.exit(0)  # clean — allow

if __name__ == "__main__":
    main()
