"""Executable closing-directive extraction for finish-work helpers.

Shared by close-fixed-issues and alignment-check.

- Closing keywords inside fenced Markdown examples and inline code spans are
  not actions.
- The full GitHub keyword grammar is recognized (close/closes/closed,
  fix/fixes/fixed, resolve/resolves/resolved, optional colon); hyphenated
  compounds like ``auto-closes`` are not directives.
- Bare ``Fixes #N`` is the supported local-repository form.
- Repository-qualified ``owner/repo#N`` and full issue URLs are reported as
  unsupported and are never coerced to a local issue id.
"""

from __future__ import annotations

import re
import sys
from typing import List, Sequence, Tuple


def split_quote_container(line: str) -> Tuple[int, str]:
    content = line.expandtabs(4)
    depth = 0
    while True:
        quote = re.match(r"^[ ]{0,3}>[ ]?", content)
        if not quote:
            return depth, content
        depth += 1
        content = content[quote.end() :]


def split_list_container(content: str):
    item = re.match(r"^([ ]{0,3})(?:[-+*]|[0-9]+[.)])([ ]+)(.*)$", content)
    if not item:
        return None, content
    indent = item.start(3)
    return indent, item.group(3)


def opening_fence(content: str):
    opening = re.match(r"^[ ]{0,3}(`{3,}|~{3,})(.*)$", content)
    if not opening:
        return None
    marker, info = opening.groups()
    if marker[0] == "`" and "`" in info:
        return None
    return marker


def closing_fence(content: str, fence_char: str, fence_len: int) -> bool:
    closing = re.match(r"^[ ]{0,3}(`{3,}|~{3,})[ ]*$", content)
    if not closing:
        return False
    marker = closing.group(1)
    return marker[0] == fence_char and len(marker) >= fence_len


def visible_prose_lines(body: str) -> List[str]:
    """Return raw lines that are outside fenced Markdown containers."""
    active = None
    list_context = None
    visible: List[str] = []
    for raw_line in body.splitlines():
        reprocess = True
        while reprocess:
            reprocess = False
            quote_depth, content = split_quote_container(raw_line)

            if active is not None:
                if quote_depth != active["quote_depth"]:
                    active = None
                    list_context = None
                    reprocess = True
                    continue

                list_indent = active["list_indent"]
                if list_indent is not None:
                    if not content.strip():
                        break
                    leading = len(content) - len(content.lstrip(" "))
                    if leading < list_indent:
                        active = None
                        list_context = None
                        reprocess = True
                        continue
                    content = content[list_indent:]

                if closing_fence(content, active["char"], active["length"]):
                    active = None
                break

            if list_context is not None:
                if quote_depth != list_context["quote_depth"]:
                    list_context = None
                    reprocess = True
                    continue
                if not content.strip():
                    visible.append(raw_line)
                    break
                leading = len(content) - len(content.lstrip(" "))
                if leading < list_context["indent"]:
                    list_context = None
                    reprocess = True
                    continue

                candidate = content[list_context["indent"] :]
                nested_indent, nested_candidate = split_list_container(candidate)
                if nested_indent is not None:
                    list_context = {
                        "quote_depth": quote_depth,
                        "indent": list_context["indent"] + nested_indent,
                    }
                    candidate = nested_candidate

                marker = opening_fence(candidate)
                if marker is not None:
                    active = {
                        "quote_depth": quote_depth,
                        "list_indent": list_context["indent"],
                        "char": marker[0],
                        "length": len(marker),
                    }
                    break
                visible.append(raw_line)
                break

            list_indent, candidate = split_list_container(content)
            if list_indent is not None:
                list_context = {"quote_depth": quote_depth, "indent": list_indent}
            marker = opening_fence(candidate)
            if marker is not None:
                active = {
                    "quote_depth": quote_depth,
                    "list_indent": list_indent,
                    "char": marker[0],
                    "length": len(marker),
                }
                break

            visible.append(raw_line)
            break
    return visible


# GitHub's auto-close grammar: nine keyword forms, optional colon. The
# lookbehind excludes ``-`` so hyphen compounds (``auto-closes #N``) are prose,
# matching GitHub, which does not close on them.
_KEYWORD = r"(?<![A-Za-z0-9_-])(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)"
_SEP = r"(?::[ \t]*|[ \t]+)"

_LOCAL_RE = re.compile(_KEYWORD + _SEP + r"#([0-9]+)", re.IGNORECASE)
_QUALIFIED_RE = re.compile(
    _KEYWORD + _SEP + r"([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+)\b",
    re.IGNORECASE,
)
_URL_RE = re.compile(
    _KEYWORD + _SEP
    + r"(https?://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/issues/[0-9]+)",
    re.IGNORECASE,
)
# Inline code spans stay within a line here (no DOTALL): a stray unpaired
# backtick must not swallow later lines that carry real directives.
_CODE_SPAN_RE = re.compile(r"(`+)(?:(?!\1).)+?\1")


def extract_closing_directives(body: str) -> Tuple[List[int], List[str]]:
    """Return ``(local_issue_ids, unsupported_refs)`` from body prose."""
    text = "\n".join(visible_prose_lines(body))
    text = _CODE_SPAN_RE.sub(" ", text)
    ids = sorted({int(value) for value in _LOCAL_RE.findall(text)})
    unsupported = sorted(
        set(_QUALIFIED_RE.findall(text)) | set(_URL_RE.findall(text)),
        key=str.lower,
    )
    return ids, unsupported


def main(argv: Sequence[str] | None = None) -> int:
    del argv  # CLI reads body from stdin only.
    ids, unsupported = extract_closing_directives(sys.stdin.read())
    for issue_id in ids:
        print(f"id\t{issue_id}")
    for reference in unsupported:
        print(f"unsupported\t{reference}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
