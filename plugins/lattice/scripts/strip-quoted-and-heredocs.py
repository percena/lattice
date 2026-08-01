#!/usr/bin/env python3
r"""Normalize a shell command read on stdin so callers can check whether a
command phrase appears as a real invocation rather than as text inside a
quoted flag value or heredoc body. Writes the normalized result to stdout.

Pragmatic — not a full bash parser. One left-to-right scan tracking quote
and heredoc state (sequential regex passes interacted: a double-quote pass
running before the single-quote pass let `echo '"'; gh pr create; echo '"'`
hide the real invocation, and heredoc matching inside quoted strings
swallowed genuinely executed code).

Normalization rules:
- Quoted spans ('...', "...", $'...', $"..."): a span whose content has no
  whitespace is replaced by its literal content — `gh "pr" create` really
  executes gh pr create and must stay matchable. A span containing
  whitespace (message bodies, prose) collapses to a single placeholder
  char, so it can neither match nor splice its neighbours together into a
  false match (`echo gh "a" pr "b" create`).
- Backslash outside quotes: `\\x` -> `x` (bash: literal next char, so
  `gh p\\r create` is `gh pr create`); backslash-newline (line
  continuation) -> single space, so a continued `gh pr \\<newline>create`
  stays matchable. An escaped backtick becomes a placeholder so literal
  ``\`gh pr ...\``` text cannot create command-substitution boundaries.
- Legacy backtick command substitution remains visible, including inside
  double quotes; single-quoted or escaped backticks remain literal text.
  `$()` command substitution is treated the same way: its interior is
  normalized (so a nested literal `"..."` inside it still collapses) and
  kept visible, including inside double quotes where bash still executes it.
- Heredoc bodies (<<WORD, <<-WORD, quoted/hyphenated WORD) are removed;
  openers are only recognized OUTSIDE quotes. `<<<` here-strings are an
  operator, not a heredoc. Bash still executes `$(...)` and backtick
  substitutions inside an **unquoted** heredoc body, but this normalizer
  discards the whole body, so a real invocation hidden there is not visible
  to phrase matching. The intercept hook is advisory and fail-open by design
  (not a security sandbox), so this is an accepted limitation; strict mode
  does not claim to block such hidden invocations.
- Comments (`#` at a word start, outside quotes) are removed to end of line.
- Unterminated quote: bash rejects the whole command, nothing executes —
  the remainder collapses to a placeholder. Unterminated heredoc: bash
  reads the body to EOF and still runs the command — the body is removed.
"""
import os
import subprocess
import sys
import time

PLACEHOLDER = "Q"

# Resolve bash from known absolute locations rather than PATH, so a poisoned
# PATH (e.g. a malicious directory prepended to PATH) cannot swap in a fake
# `bash` that would receive the substitution body on stdin. Falls back to PATH
# lookup only when none of the known locations exist.
_BASH_BIN = next(
    (
        p for p in ("/bin/bash", "/usr/bin/bash", "/usr/local/bin/bash")
        if os.path.isfile(p) and os.access(p, os.X_OK)
    ),
    "bash",
)

# Per-`_find_paren_end` wall-clock budget. A normal `$()` returns on its first
# valid `)` candidate (a single bash -n, ~milliseconds), so this ceiling only
# bites adversarial inputs that pile up many false `)` candidates (case
# patterns, heredoc bodies, comments) before the real close. Override via env
# for ops/testing.
_DEFAULT_PAREN_BUDGET_SECONDS = 5.0


class _BoundaryUnknown(Exception):
    """The closing `)` could not be determined within the parse budget.

    Distinct from a legitimately unterminated `$(...)` (which bash rejects, so
    nothing executes): here there are more candidates we did not get to test,
    so we cannot claim the substitution is safe to collapse.
    """
_DELIM_FIRST = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_.-")
_DELIM_REST = _DELIM_FIRST | set("0123456789")
# Chars before `#` that make it start a comment (word start), per bash.
_COMMENT_BREAK = set(" \t\n;&|(")


def _parse_heredoc_opener(text, i):
    """Parse `<<`/`<<-` + delimiter at text[i:]. Returns (delim, strip_tabs,
    next_index) or None when this is not a heredoc opener."""
    j = i + 2
    n = len(text)
    strip_tabs = False
    if j < n and text[j] == "-":
        strip_tabs = True
        j += 1
    while j < n and text[j] in " \t":
        j += 1
    quote = ""
    if j < n and text[j] in "'\"":
        quote = text[j]
        j += 1
    elif j < n and text[j] == "\\":
        j += 1  # \WORD also quotes the delimiter
    start = j
    if quote:
        while j < n and text[j] != quote:
            j += 1
        if j >= n or j == start:
            return None
        delim = text[start:j]
        j += 1
    else:
        # First char may not be a digit: `1<<2` and `x << y` inside
        # arithmetic would otherwise register a bogus heredoc and swallow
        # the following lines.
        if j >= n or text[j] not in _DELIM_FIRST:
            return None
        j += 1
        while j < n and text[j] in _DELIM_REST:
            j += 1
        delim = text[start:j]
    return delim, strip_tabs, j


def _emit_span(out, content):
    """Inline whitespace-free quoted content; collapse the rest to a
    placeholder (see module docstring)."""
    if any(ch.isspace() for ch in content):
        out.append(PLACEHOLDER)
    elif content:
        out.append(content)


def _find_backtick_end(text, start):
    """Return the next unescaped backtick index, or -1."""
    i = start
    while i < len(text):
        if text[i] == "\\" and i + 1 < len(text):
            i += 2
            continue
        if text[i] == "`":
            return i
        i += 1
    return -1


def _find_paren_end(text, open_idx):
    """Return the index of the `)` matching the `(` at open_idx.

    Returns -1 when the `$(...)` is legitimately unterminated (no candidate
    closes it; bash would reject the whole command, so nothing inside it
    executes) or when the bash parser itself is unavailable. Raises
    `_BoundaryUnknown` when the parse budget is exhausted before every
    candidate could be tested — in that case the substitution may still
    contain a real invocation we cannot afford to hide, so callers must
    surface the remaining content rather than collapse it to a placeholder.

    Ask bash's no-exec parser which candidate closes the substitution instead
    of growing another partial shell grammar here. Parsing the candidate body
    as a parenthesized command handles quotes, nested substitutions, parameter
    expansion, case patterns, comments, and heredocs according to the installed
    bash itself. The body is parsed only (`bash -n`), never executed.
    """
    parser_env = {
        "LC_ALL": "C",
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
    }
    try:
        budget = float(os.environ.get("LATTICE_STRIP_PAREN_BUDGET_SECONDS", "")
                       or _DEFAULT_PAREN_BUDGET_SECONDS)
    except ValueError:
        budget = _DEFAULT_PAREN_BUDGET_SECONDS
    deadline = time.monotonic() + max(budget, 0.0)
    for i in range(open_idx + 1, len(text)):
        if text[i] != ")":
            continue
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            # Budget spent while candidates remain untested: we cannot claim
            # the substitution is unterminated, so do NOT collapse it.
            raise _BoundaryUnknown()
        body = text[open_idx + 1:i]
        try:
            parsed = subprocess.run(
                [_BASH_BIN, "--noprofile", "--norc", "-n"],
                input=f"({body})",
                text=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                timeout=min(0.25, remaining),
                check=False,
                env=parser_env,
            )
        except subprocess.TimeoutExpired as exc:
            # A timed-out candidate is still a possible false `)` (for
            # example, one inside a long quoted span). Treating it like a
            # definitively unterminated substitution would collapse the rest
            # of the double-quoted command and could hide a real invocation.
            raise _BoundaryUnknown() from exc
        except OSError:
            return -1
        # Unterminated heredocs are warnings with exit 0 in bash -n; requiring
        # quiet stderr prevents a `)` in their body from becoming a false end.
        if parsed.returncode == 0 and not parsed.stderr:
            return i
    return -1


def strip(text):
    out = []
    i = 0
    n = len(text)
    pending = []  # queued heredocs on the current line: (delim, strip_tabs)
    prev = ""     # previous significant source char (comment word-start test)
    arith_depth = 0  # inside $(( … )) / (( … )), `<<` is a shift, not a heredoc

    while i < n:
        ch = text[i]

        if ch == "\\":
            if i + 1 < n:
                nxt = text[i + 1]
                emitted = " " if nxt == "\n" else PLACEHOLDER if nxt == "`" else nxt
                out.append(emitted)
                prev = emitted
                i += 2
            else:
                i += 1
            continue

        if ch == "$" and i + 1 < n and text[i + 1] in "'\"":
            # $'...' / $"..." — drop the $, let the quote handler own it.
            i += 1
            continue

        if ch == "'":
            j = text.find("'", i + 1)
            if j < 0:
                out.append(PLACEHOLDER)
                break
            _emit_span(out, text[i + 1:j])
            prev = PLACEHOLDER
            i = j + 1
            continue

        if ch == '"':
            j = i + 1
            buf = []
            closed = False
            while j < n:
                c = text[j]
                if c == "\\" and j + 1 < n:
                    buf.append(text[j + 1])
                    j += 2
                    continue
                if c == "`":
                    end = _find_backtick_end(text, j + 1)
                    if end < 0:
                        out.append(PLACEHOLDER)
                        return "".join(out)
                    _emit_span(out, "".join(buf))
                    buf = []
                    out.append("`")
                    out.append(strip(text[j + 1:end]))
                    out.append("`")
                    j = end + 1
                    continue
                if c == "$" and j + 1 < n and text[j + 1] == "(":
                    try:
                        end = _find_paren_end(text, j + 1)
                    except _BoundaryUnknown:
                        # Parse budget exhausted before the closing `)` could
                        # be confirmed. The substitution may still contain a
                        # real invocation; fail closed by surfacing the rest of
                        # the line (normalized) instead of collapsing it to a
                        # placeholder that would hide a genuine `gh pr ...`.
                        _emit_span(out, "".join(buf))
                        out.append("$")
                        out.append("(")
                        out.append(strip(text[j + 2:]))
                        return "".join(out)
                    if end < 0:
                        out.append(PLACEHOLDER)
                        return "".join(out)
                    _emit_span(out, "".join(buf))
                    buf = []
                    out.append("$")
                    out.append("(")
                    out.append(strip(text[j + 2:end]))
                    out.append(")")
                    j = end + 1
                    continue
                if c == '"':
                    closed = True
                    break
                buf.append(c)
                j += 1
            if not closed:
                out.append(PLACEHOLDER)
                break
            _emit_span(out, "".join(buf))
            prev = PLACEHOLDER
            i = j + 1
            continue

        if ch == "#" and (not prev or prev in _COMMENT_BREAK):
            j = text.find("\n", i)
            if j < 0:
                break
            i = j  # the newline itself may start queued heredoc bodies
            continue

        # Arithmetic context: `$(( x << y ))` and `(( x << y ))` contain a SHIFT
        # operator. Reading it as a heredoc opener registers a bogus delimiter
        # ("y") and then swallows every following line — including a real
        # `gh pr create` on the next one. Digit-first operands are already
        # excluded by _parse_heredoc_opener; identifiers need this context.
        if text[i:i + 3] == "$((":
            arith_depth += 1
            out.append("$((")
            prev = "("
            i += 3
            continue
        if ch == "(" and text[i:i + 2] == "((" and (not prev or prev in _COMMENT_BREAK):
            arith_depth += 1
            out.append("((")
            prev = "("
            i += 2
            continue
        if arith_depth > 0 and text[i:i + 2] == "))":
            arith_depth -= 1
            out.append("))")
            prev = ")"
            i += 2
            continue

        if ch == "<" and text[i:i + 2] == "<<":
            if arith_depth > 0:
                out.append("<<")
                prev = "<"
                i += 2
                continue
            if text[i:i + 3] == "<<<":
                out.append(" ")
                prev = " "
                i += 3
                continue
            parsed = _parse_heredoc_opener(text, i)
            if parsed:
                delim, strip_tabs, j = parsed
                pending.append((delim, strip_tabs))
                i = j
                continue
            out.append("<<")
            prev = "<"
            i += 2
            continue

        if ch == "\n" and pending:
            # Consume queued heredoc bodies through each delimiter line.
            i += 1
            for delim, strip_tabs in pending:
                while i < n:
                    j = text.find("\n", i)
                    line = text[i:j] if j >= 0 else text[i:]
                    i = (j + 1) if j >= 0 else n
                    if (line.lstrip("\t") if strip_tabs else line) == delim:
                        break
            pending = []
            if i < n:
                out.append("\n")
            prev = "\n"
            continue

        out.append(ch)
        prev = ch
        i += 1

    return "".join(out)


def main() -> None:
    sys.stdout.write(strip(sys.stdin.read()))


if __name__ == "__main__":
    main()
