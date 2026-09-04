#!/usr/bin/env python3
"""PreToolUse hook: catch banned assertion forms in .bats files at write time.

Receives the tool input as JSON on stdin. For Write tool calls targeting
a .bats file, writes the content to a temp file and runs
check-bats-assertions.py on it. If the checker finds banned forms
(bare [[ ]], bare ! cmd, grep -q inside [ -z "$(...)" ]), exits 2 to
block the write and prints the findings to stderr.

Exit contract (Claude Code PreToolUse): exit 2 = block (stderr is fed back to
the model); exit 0 = allow; any other non-zero is a NON-blocking error. The
first version exited 1 while printing "BLOCKED" — the write went through
(tkt-460 A5).

Registration: this is a maintainer tool, not a plugin hook, so it is NOT in
plugins/lattice/hooks/hooks.json. Wire it into your own settings, e.g.
`.claude/settings.json` (gitignored in this repo) — see tools/README.md.

For Edit tool calls, the hook reads the existing file + applies the edit
in-memory, then checks the result. This catches banned forms introduced
by an edit.

tkt-400 / spc-398 A2.
"""
import json
import os
import subprocess
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
        res = subprocess.run([sys.executable, checker, tmp],
                             capture_output=True, text=True)
        if res.returncode != 0:
            # Show findings (suppress "OK" output)
            sys.stderr.write(res.stdout)
            sys.stderr.write(res.stderr)
            print(f"\nPreToolUse: BLOCKED — banned assertion form(s) in {file_path}", file=sys.stderr)
            print("Fix: replace bare [[ ]] with grep -qE, bare ! cmd with [ ... ],", file=sys.stderr)
            print("and grep -q inside [ -z \"$(...)\" ] with grep -qE at terminal position.", file=sys.stderr)
            sys.exit(2)  # block the write (PreToolUse: only exit 2 blocks)
    finally:
        os.unlink(tmp)

    sys.exit(0)  # clean — allow

if __name__ == "__main__":
    main()
