#!/usr/bin/env python3
r"""Best-effort detector for raw git branch-create / branch-switch ops.

Input is the command string already stripped of quoted spans and heredoc bodies
by `strip-quoted-and-heredocs.py`. This is a lightweight git-CLI classifier,
not a shell security sandbox — it fails OPEN (op="none") on ambiguity so the
hook never false-blocks a legitimate op.

Purpose: the L1 PreToolUse hook blocks agents from drifting to a plain feature
branch in the main clone. The blessed entry (`ensure-workspace.sh`) is invoked
as `bash …/ensure-workspace.sh …` — its *internal* git branch/checkout are
subprocess calls inside that script, NOT a separate Bash tool call, so they
never pass through this hook. Only a raw `git checkout -b …` typed directly
as the Bash command is matched.

Output (JSON on stdout):
  {"op": "create" | "switch" | "none", "target": str | null, "cwd_override": str | null}

op semantics:
  create  — creates a new branch (git checkout -b/-B X, git switch -c/-C X,
            git branch X)  → block in main clone
  switch  — checks out an existing branch (git switch X, git checkout X) where
            X is a non-flag token  → the hook decides block vs allow by whether
            X is a base branch / a real local branch
  none    — not a branch op (file restore, list, delete, etc.)

Compound commands (`;`, `&&`, `|`, newline, backtick, parens) are scanned per
region; the FIRST branch op found is reported. A bare-branch create hidden
inside a quoted/heredoc body was already removed by the normalizer, so it will
not match — an accepted limitation (this is drift control, not a sandbox).
"""
from __future__ import annotations

import json
import re
import sys

# Operators that separate command regions. Backtick and parens are preserved
# by the normalizer as boundaries.
BOUNDARIES = {";", "&", "|", "(", ")", "`", "\n"}

# Wrappers that run their argument as a command; value_opts consume the next
# token so a wrapper flag value is not mistaken for the command word.
WRAPPERS = {
    "sudo":  {"value_opts": {"-u", "-g", "-C", "-p", "-r", "-t", "-U",
                            "--user", "--group", "--prompt", "--role", "--type"}},
    "env":   {"value_opts": {"-u", "--unset", "-C", "--chdir", "-S", "--split-string"}},
    "doas":  {"value_opts": {"-u", "-C"}},
    "time":  {"value_opts": {"-f", "--format", "-o", "--output"}},
    "timeout": {"value_opts": {"-s", "--signal", "-k", "--kill-after"}, "positionals": 1},
    "nice":  {"value_opts": {"-n", "--adjustment"}},
    "nohup": {"value_opts": set()},
    "exec":  {"value_opts": {"-a"}},
    "command": {"value_opts": set()},
    "builtin": {"value_opts": set()},
}
# Shell keywords that may legitimately precede a command without being one.
PREFIX_WORDS = {"!", "{", "}", "if", "then", "else", "elif", "while", "until",
                "do", "for", "in"}


def _tokenize(s):
    """Split on whitespace. Input is already normalized (quotes collapsed),
    so whitespace splitting is safe."""
    return s.split()


def _skip_wrapper(toks, i):
    """If toks[i] is a wrapper (sudo/env/...), advance past it and its flags.
    Returns new index pointing at the real command word (or past end)."""
    n = len(toks)
    while i < n:
        t = toks[i]
        if t not in WRAPPERS:
            return i
        spec = WRAPPERS[t]
        i += 1
        # skip wrapper flags; value_opts consume the next token
        while i < n:
            tk = toks[i]
            if tk in spec["value_opts"]:
                i += 2
                continue
            if tk.startswith("--") and "=" in tk:
                i += 1
                continue
            if tk.startswith("-") and len(tk) > 1:
                # combined short flags like -u me handled above; a bare -x
                # wrapper flag (e.g. sudo -E) is skipped singly
                i += 1
                continue
            break
        # wrappers with positional args (timeout DURATION) — eat them
        if "positionals" in spec and spec["positionals"]:
            eaten = 0
            while i < n and eaten < spec["positionals"] and not toks[i].startswith("-"):
                i += 1
                eaten += 1
    return i


def _scan_region(region):
    """Classify a single command region. Returns the result dict or None."""
    toks = _tokenize(region)
    if not toks:
        return None
    i = 0
    # skip leading env assignments (FOO=bar)
    while i < len(toks) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", toks[i]):
        i += 1
    if i < len(toks) and toks[i] in PREFIX_WORDS:
        i += 1
    i = _skip_wrapper(toks, i)
    if i >= len(toks) or toks[i] != "git":
        return None
    i += 1
    cwd_override = None
    # consume git global flags; capture -C <path> for the location check
    while i < len(toks):
        t = toks[i]
        if t == "-C":
            if i + 1 < len(toks):
                cwd_override = toks[i + 1]
            i += 2
            continue
        if t.startswith("-C") and len(t) > 2:
            cwd_override = t[2:]
            i += 1
            continue
        if t in ("--git-dir", "--work-tree", "--namespace", "--git-path"):
            i += 2  # value flag
            continue
        if t.startswith("--") and "=" in t:
            i += 1
            continue
        if t == "-c":
            i += 2  # -c key=value (config) — consume value
            continue
        if t.startswith("-") and len(t) > 1:
            i += 1
            continue
        break
    if i >= len(toks):
        return {"op": "none", "target": None, "cwd_override": cwd_override}
    sub = toks[i]
    i += 1
    rest = toks[i:]

    if sub == "checkout":
        # checkout -b/-B <name> → create; checkout <name> → switch (existing)
        # checkout -- <file> / checkout <path> → none (file restore)
        j = 0
        # skip leading flags except -b/-B (which mark create)
        while j < len(rest):
            t = rest[j]
            if t in ("-b", "-B"):
                if j + 1 < len(rest) and not rest[j + 1].startswith("-"):
                    return {"op": "create", "target": rest[j + 1], "cwd_override": cwd_override}
                return {"op": "none", "target": None, "cwd_override": cwd_override}
            if t == "--":
                # everything after -- is a path, not a branch
                return {"op": "none", "target": None, "cwd_override": cwd_override}
            if t.startswith("-"):
                j += 1
                continue
            # first non-flag positional = branch (switch) or path. But a later
            # `--` means this is a file restore from <treeish>, not a switch
            # (tkt-324: `git checkout <treeish> -- <path>` was misclassified
            # as a switch → blocked legitimate file restores).
            if "--" in rest[j + 1:]:
                return {"op": "none", "target": None, "cwd_override": cwd_override}
            return {"op": "switch", "target": t, "cwd_override": cwd_override}
        return {"op": "none", "target": None, "cwd_override": cwd_override}

    if sub == "switch":
        j = 0
        while j < len(rest):
            t = rest[j]
            if t in ("-c", "-C"):
                if j + 1 < len(rest) and not rest[j + 1].startswith("-"):
                    return {"op": "create", "target": rest[j + 1], "cwd_override": cwd_override}
                return {"op": "none", "target": None, "cwd_override": cwd_override}
            if t == "--detach":
                return {"op": "none", "target": None, "cwd_override": cwd_override}
            if t.startswith("-"):
                j += 1
                continue
            return {"op": "switch", "target": t, "cwd_override": cwd_override}
        return {"op": "none", "target": None, "cwd_override": cwd_override}

    if sub == "branch":
        # git branch <name> → create. git branch (no arg) / -a / -d <name> /
        # --list → none. -m/-M <old> <new> is a rename, not drift-create; none.
        # tkt-324: -f/--force is NOT in the none-set — `git branch -f <name>`
        # force-creates a branch (drift); skip it as a regular flag so the
        # name is reached → op=create. (-f before -d still hits -d → none.)
        j = 0
        while j < len(rest):
            t = rest[j]
            if t in ("-d", "-D", "--delete", "-m", "-M", "--move",
                     "-r", "--remotes", "-a", "--all", "--list",
                     "-v", "-vv", "--verbose", "--no-color", "--column",
                     "--sort", "-t", "--track", "--set-upstream",
                     "--unset-upstream", "--contains", "--merged",
                     "--no-merged", "--points-at"):
                return {"op": "none", "target": None, "cwd_override": cwd_override}
            if t.startswith("-"):
                j += 1
                continue
            # first non-flag positional = new branch name → create
            return {"op": "create", "target": t, "cwd_override": cwd_override}
        return {"op": "none", "target": None, "cwd_override": cwd_override}

    return {"op": "none", "target": None, "cwd_override": cwd_override}


def main():
    cmd = sys.stdin.read()
    # Split into command regions on BOUNDARIES. A simple char-by-char scan.
    regions = []
    cur = []
    for ch in cmd:
        if ch in BOUNDARIES:
            regions.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    regions.append("".join(cur))
    for region in regions:
        res = _scan_region(region)
        if res and res["op"] != "none":
            print(json.dumps(res))
            return
    print(json.dumps({"op": "none", "target": None, "cwd_override": None}))


if __name__ == "__main__":
    main()
