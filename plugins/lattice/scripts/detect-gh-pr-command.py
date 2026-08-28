#!/usr/bin/env python3
"""Best-effort detector for direct `gh [global flags] pr [flags] VERB` calls.

Input is already stripped of quoted strings and heredoc bodies by the hook's
normalizer. This is intentionally a lightweight GitHub CLI classifier, not a
shell parser. When a region contains a valid `gh pr` mutation behind an unknown
command prefix, it fails closed instead of assuming the prefix only prints
text. The small safe list below preserves common prose/search commands.

The scan is FORWARD, per command region, because that is the only way to tell
an invocation from a word that merely spells "gh":

    gh pr create                 -> invocation
    sudo -u me gh pr create      -> invocation (wrapper)
    >out.txt gh pr create        -> invocation (leading redirection)
    echo gh pr create            -> argument text, NOT an invocation
    sudo echo gh pr create       -> argument text, NOT an invocation

A backwards scan cannot distinguish `sudo -u me gh` from `echo gh` without
re-deriving where the command word starts, so we derive that directly.

Accepted limitation (pinned by tests): nested-shell payloads are invisible by
design — the hook normalizer strips quoted strings before we run, so
`bash -c 'gh pr create'`, `sh -c …`, and `eval "gh pr merge"` are NOT detected.
Same tradeoff class as the heredoc-body note in strip-quoted-and-heredocs.py:
this hook is a guardrail for direct commands, not a sandbox boundary against
an operator who deliberately wraps a call.
"""

from __future__ import annotations

import os
import re
import sys


VALUE_FLAGS = {"-R", "--repo", "--hostname", "--config-dir"}
TERMINAL_FLAGS = {"-h", "--help", "--version"}
# Backtick is a boundary so executable legacy command-substitution content
# preserved by the normalizer stays matchable; it never appears in a real gh
# global/pr flag. A newline separates commands just like `;` does.
BOUNDARIES = {";", "&", "|", "(", ")", "`", "\n"}

# Shell keywords/operators that may sit in front of a command without being it.
PREFIX_WORDS = {
    "!", "{", "}",
    "if", "then", "else", "elif", "while", "until", "do",
}

# Programs that RUN their argument as a command. After one of these, the real
# command word follows its own options — so keep scanning. `value_opts` are the
# options that consume the next token; `positionals` is how many non-option
# arguments the wrapper itself eats before the command word (timeout's DURATION).
WRAPPERS = {
    "sudo":    {"value_opts": {"-u", "-g", "-C", "-p", "-r", "-t", "-U", "--user", "--group", "--prompt", "--role", "--type", "--close-from"}, "positionals": 0},
    "doas":    {"value_opts": {"-u", "-C"}, "positionals": 0},
    "env":     {"value_opts": {"-u", "--unset", "-C", "--chdir", "-S", "--split-string"}, "positionals": 0},
    "command": {"value_opts": set(), "positionals": 0},
    "builtin": {"value_opts": set(), "positionals": 0},
    "exec":    {"value_opts": {"-a"}, "positionals": 0},
    "nohup":   {"value_opts": set(), "positionals": 0},
    "setsid":  {"value_opts": set(), "positionals": 0},
    "time":    {"value_opts": {"-f", "--format", "-o", "--output"}, "positionals": 0},
    "timeout": {"value_opts": {"-s", "--signal", "-k", "--kill-after"}, "positionals": 1},
    "nice":    {"value_opts": {"-n", "--adjustment"}, "positionals": 0},
    "ionice":  {"value_opts": {"-c", "-n", "-p", "-P", "-u", "--class", "--classdata", "--pid"}, "positionals": 0},
    "stdbuf":  {"value_opts": {"-i", "-o", "-e", "--input", "--output", "--error"}, "positionals": 0},
    "xargs":   {"value_opts": {"-a", "-d", "-E", "-I", "-i", "-L", "-l", "-n", "-P", "-s", "--arg-file", "--delimiter", "--replace", "--max-lines", "--max-args", "--max-procs", "--max-chars"}, "positionals": 0},
    "script":  {"value_opts": {"-c", "--command"}, "positionals": 0},
    "chrt":    {"value_opts": {"-a", "--all-tasks", "-m", "--max", "-p", "--pid", "-r", "--reset-on-fork"}, "positionals": 1},
    "taskset": {"value_opts": {"-p", "--pid"}, "positionals": 1},
}

# These commands consume their remaining words as data and do not dispatch a
# later token as an executable. Unknown prefixes are deliberately not added:
# strict mode must not be bypassable by inventing another wrapper name.
SAFE_ARGUMENT_COMMANDS = {
    "echo", "printf", "grep", "egrep", "fgrep", "rg",
}

# More commands whose words are data, never dispatched as a command —
# `touch gh pr create` creates three files; `git checkout -- gh pr create`
# restores paths. Without this list the fail-closed fallback below treats any
# argument sequence spelling `gh pr create` as an invocation and blocks
# legitimate file work (the worst hook failure mode). Dual-natured commands
# that CAN dispatch (find -exec, xargs) are NOT here: xargs is a WRAPPER,
# find is handled by EXEC_CAPABLE_COMMANDS below.
DATA_ARGUMENT_COMMANDS = {
    "[", "basename", "cat", "cd", "chmod", "chown", "cmp", "comm", "cp",
    "cut", "diff", "dirname", "du", "file", "head", "ln", "ls", "mkdir",
    "mv", "paste", "pwd", "readlink", "realpath", "rm", "rmdir", "sort",
    "stat", "tail", "test", "touch", "tr", "uniq", "wc", "git",
}

# Dual-natured: words are data UNLESS an exec flag appears in the same region
# (`find . -name gh -o -name pr -o -name create` is a search; `find . -exec
# gh pr create {} +` runs gh). Without an exec flag → treat as data; with one
# → fall through to the fail-closed unknown-prefix scan.
EXEC_CAPABLE_COMMANDS = {
    "find": {"-exec", "-execdir", "-ok", "-okdir"},
}

ASSIGNMENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
LINE_CONTINUATION_RE = re.compile(r"\\\n")
# Bash/POSIX redirection operators, optionally fd-prefixed. Tokenization splits
# the operator from an attached target, so `<>state` and `2>/dev/null` follow
# exactly the same skip path as their whitespace-separated forms.
REDIR_RE = re.compile(r"^(?:&>>|&>|[0-9]*(?:<<<|<<-|<<|<>|>>|>\||>&|<&|>|<))$")

_TOKEN_RE = re.compile(
    r"&>>|&>|[0-9]*(?:<<<|<<-|<<|<>|>>|>\||>&|<&|>|<)|[^\s;&|()<>`]+|[;&|()`\n]"
)


def tokens(command: str) -> list[str]:
    return _TOKEN_RE.findall(LINE_CONTINUATION_RE.sub(" ", command))


def skip_flags(items: list[str], index: int) -> tuple[int, bool]:
    while index < len(items):
        token = items[index]
        if token in BOUNDARIES or token in TERMINAL_FLAGS:
            return index, False
        if token in VALUE_FLAGS:
            if index + 1 >= len(items) or items[index + 1] in BOUNDARIES:
                return index, False
            index += 2
            continue
        if any(token.startswith(flag + "=") for flag in VALUE_FLAGS if flag.startswith("--")):
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        return index, True
    return index, False


def has_terminal_flag(items: list[str], index: int) -> bool:
    """A `gh pr create --help` is a docs lookup, not an attempt to open a PR."""
    while index < len(items):
        token = items[index]
        if token in BOUNDARIES:
            return False
        if token in TERMINAL_FLAGS:
            return True
        index += 1
    return False


def command_word_index(items: list[str], index: int) -> int | None:
    """Index of the command word for the region starting at `index`.

    Consumes leading redirections, environment assignments, shell keywords and
    any number of wrapper programs with their own options. Returns None when the
    region ends before a command word appears.
    """
    while index < len(items):
        token = items[index]
        if token in BOUNDARIES:
            return None
        if token in PREFIX_WORDS or ASSIGNMENT_RE.match(token):
            index += 1
            continue
        if REDIR_RE.match(token):
            index += 2  # operator plus its target
            continue
        name = os.path.basename(token)
        if name in WRAPPERS:
            spec = WRAPPERS[name]
            index += 1
            positionals = spec["positionals"]
            while index < len(items):
                nxt = items[index]
                if nxt in BOUNDARIES:
                    return None
                if nxt in spec["value_opts"]:
                    index += 2
                    continue
                if ASSIGNMENT_RE.match(nxt):  # env FOO=1 cmd
                    index += 1
                    continue
                if nxt.startswith("-") and nxt != "-":
                    if nxt == "--":
                        index += 1
                        break
                    index += 1
                    continue
                if positionals > 0:
                    positionals -= 1
                    index += 1
                    continue
                break
            continue
        return index
    return None


def region_starts(items: list[str]) -> list[int]:
    starts = [0]
    for i, token in enumerate(items):
        if token in BOUNDARIES:
            starts.append(i + 1)
    return starts


def is_gh_pr_verb(items: list[str], index: int, verb: str) -> bool:
    if index >= len(items) or os.path.basename(items[index]) != "gh":
        return False
    cursor, ok = skip_flags(items, index + 1)
    if not ok or cursor >= len(items) or items[cursor] != "pr":
        return False
    cursor, ok = skip_flags(items, cursor + 1)
    if not ok or cursor >= len(items) or items[cursor] != verb:
        return False
    return not has_terminal_flag(items, cursor + 1)


def contains(command: str, verb: str) -> bool:
    items = tokens(command)
    for start in region_starts(items):
        index = command_word_index(items, start)
        if index is None:
            continue
        if is_gh_pr_verb(items, index, verb):
            return True

        command_name = os.path.basename(items[index])
        if command_name in SAFE_ARGUMENT_COMMANDS:
            continue
        if command_name in DATA_ARGUMENT_COMMANDS:
            continue
        if command_name in EXEC_CAPABLE_COMMANDS:
            exec_flags = EXEC_CAPABLE_COMMANDS[command_name]
            cursor = index + 1
            has_exec = False
            while cursor < len(items) and items[cursor] not in BOUNDARIES:
                if items[cursor] in exec_flags:
                    has_exec = True
                    break
                cursor += 1
            if not has_exec:
                continue

        # Unknown command prefixes may be command runners. Treat a later valid
        # gh mutation in the same region as executable instead of maintaining
        # an inevitably incomplete wrapper allowlist.
        cursor = index + 1
        while cursor < len(items) and items[cursor] not in BOUNDARIES:
            if is_gh_pr_verb(items, cursor, verb):
                return True
            cursor += 1
    return False


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in {"create", "merge"}:
        return 2
    return 0 if contains(sys.stdin.read(), sys.argv[1]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
