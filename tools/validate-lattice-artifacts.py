#!/usr/bin/env python3
"""Read-only Lattice L0 contract checks.

Detects selected current-law drift over distributed Spec/ticket/Review files
without introducing a lineage database or rewriting artifacts.

Checks (selected, not exhaustive):
  - ticket binder ``status`` FSM vocabulary: working
    queued|in-progress|parked|stuck|pr-open|rework|deferred, terminal closed
    (requires a real ``## Finish`` ledger), legacy open (warning, lazy migration)
  - header ``**Status:**`` copy (TL;DR blockquote) contradicting the field-table
    status (warning; legacy-coarse ``open`` headers are exempt — lazy migration)
  - binder ``prs`` row format: a filled row must be canonical ``pr-N — <URL>``
    entries, comma-separated for multi-PR tickets; ``(none…)`` placeholders are
    exempt (warning permanently — adopt flows may reintroduce legacy rows)
  - Spec/ticket id shape for current files (spc-N / tkt-N bare decimal)
  - ``covers`` A* ids that do not exist on the parent Spec Acceptance
  - one-sided local edges: ticket lists Spec but Spec.tickets omits the ticket
    (when both files exist under the scanned homes)

Exit 0 = clean, 1 = findings, 2 = usage/io error.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

# Binder status FSM (ADR-004 §6 / spc-42 A4). `open` is legacy-coarse: accepted
# with a warning (lazy migration). `closed` is finish-ledger's terminal stamp;
# merged vs closed-without-merge is read from the ## Finish ledger's mergedAt.
STATUS_WORKING_ORDER = ("queued", "in-progress", "parked", "stuck", "pr-open", "rework", "deferred")
STATUS_WORKING = set(STATUS_WORKING_ORDER)
STATUS_TERMINAL = {"closed"}
STATUS_LEGACY = {"open"}
STATUS_OK = STATUS_WORKING | STATUS_TERMINAL | STATUS_LEGACY
SPEC_ID_RE = re.compile(r"^spc-([1-9][0-9]*)$")
TKT_ID_RE = re.compile(r"^tkt-([1-9][0-9]*)$")
REV_ID_RE = re.compile(
    r"^rev-(?:[1-9][0-9]*|[0-9]{8}-[0-9]{6}Z(?:-[a-z0-9]{2,4})?)$"
)
COVERS_RE = re.compile(r"\bA([1-9][0-9]*)\b")
A_HEADING_RE = re.compile(r"\*\*A([1-9][0-9]*)\*\*")
FM_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.S)
STATUS_TABLE_RE = re.compile(r"^\|\s*status\s*\|\s*([^|]+?)\s*\|", re.I | re.M)
STATUS_TLDR_RE = re.compile(r"\*\*Status:\*\*\s*([a-zA-Z0-9_-]+)", re.I)
SPEC_REF_RE = re.compile(r"\|\s*spec\s*\|\s*(spc-[1-9][0-9]*)\b", re.I)
PRS_TABLE_RE = re.compile(r"^\|\s*prs\s*\|\s*([^|]+?)\s*\|", re.I | re.M)
# A row that is entirely a `(none…)` parenthetical is a placeholder, not a
# filled ledger entry (e.g. `(none)`, `(none yet)`, `(none — rides tkt-5 PR)`).
PRS_PLACEHOLDER_RE = re.compile(r"^\(none.*\)$", re.I)
# Canonical filled row: `pr-N — <URL>` (single spaces around the em dash),
# comma-separated for multi-PR tickets (`pr-52 — <URL>, pr-53 — <URL>`).
_PRS_ENTRY = r"pr-[1-9][0-9]* — https?://[^\s,]+"
PRS_ROW_CANON_RE = re.compile(rf"^{_PRS_ENTRY}(?:,\s*{_PRS_ENTRY})*$")
TICKETS_LIST_RE = re.compile(r"^tickets:\s*\[(.*?)\]\s*$", re.M)


def parse_front_matter(text: str) -> dict[str, Any]:
    m = FM_RE.match(text)
    if not m:
        return {}
    data: dict[str, Any] = {}
    for line in m.group(1).splitlines():
        if ":" not in line:
            continue
        key, val = line.split(":", 1)
        data[key.strip()] = val.strip()
    return data


def load_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def first_table_block(text: str) -> str:
    """Return the first markdown table block (consecutive ``|``-prefixed lines).

    Binder field rows (``| status | … |``, ``| covers | … |``, ``| spec | … |``)
    are read only from the binder card, which is always the first table in the
    file; a later docs/example table must not shadow it.
    """
    lines = text.splitlines()
    start = None
    for index, line in enumerate(lines):
        if line.lstrip().startswith("|"):
            start = index
            break
    if start is None:
        return ""
    end = start
    while end < len(lines) and lines[end].lstrip().startswith("|"):
        end += 1
    return "\n".join(lines[start:end])


def tldr_header_status(text: str) -> str | None:
    """Header ``**Status:**`` from TL;DR blockquote lines before the binder card.

    Scoped to ``>`` lines above the first table so prose that merely mentions
    the literal ``**Status:**`` marker (e.g. an acceptance criterion about it)
    can never masquerade as a header status. The template dropped this copy
    (field table is SoT); legacy binders may still carry it.
    """
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("|"):
            break
        if stripped.startswith(">"):
            m = STATUS_TLDR_RE.search(line)
            if m:
                return m.group(1).strip().lower()
    return None


def ticket_status(text: str) -> str | None:
    m = STATUS_TABLE_RE.search(first_table_block(text))
    if m:
        return m.group(1).strip().lower()
    m = STATUS_TLDR_RE.search(text)
    if m:
        return m.group(1).strip().lower()
    fm = parse_front_matter(text)
    if "status" in fm:
        return str(fm["status"]).strip().lower().strip("'\"")
    return None


ACCEPT_HEADING_RE = re.compile(r"^(#{2,6})\s+.*acceptance", re.I)
HEADING_RE = re.compile(r"^(#{2,6})\s")
FINISH_SECTION_RE = re.compile(r"^##\s+Finish\b.*?\n(.*?)(?=^##\s|\Z)", re.S | re.M)
HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.S)


def has_finish_ledger(text: str) -> bool:
    """True when a ``## Finish`` section carries real ledger content.

    Placeholder bodies — ``(none yet)``, bullets of it, HTML comments, blank
    lines — do not count. finish-ledger.sh replaces the placeholder with dated
    ``pr-P merged: …`` / ``issue #N closed: …`` lines, which do.
    """
    m = FINISH_SECTION_RE.search(text)
    if not m:
        return False
    body = HTML_COMMENT_RE.sub("", m.group(1))
    for line in body.splitlines():
        content = line.strip().lstrip("-").strip()
        if content and content != "(none yet)":
            return True
    return False


def finish_ledger_merged(text: str) -> bool:
    """True when the ``## Finish`` ledger records at least one PR merge.

    finish-ledger.sh writes ``pr-P merged: <ISO date> — <URL>`` lines; a
    closed-without-merge ledger (cancel path) has no ``merged:`` line and is
    exempt from the terminal-status requirement.
    """
    m = FINISH_SECTION_RE.search(text)
    if not m:
        return False
    body = HTML_COMMENT_RE.sub("", m.group(1))
    return re.search(r"\bmerged:\s", body) is not None


def spec_acceptance_ids(text: str) -> set[str]:
    """Collect **A-N** ids only from Acceptance section(s).

    A bold A-id in prose outside an Acceptance section must not count as
    coverable. A section runs from a heading matching /^##+ .*Acceptance/i to
    the next heading at the same or a higher level.
    """
    ids: set[str] = set()
    in_section = False
    level = 0
    for line in text.splitlines():
        hm = HEADING_RE.match(line)
        if hm:
            if ACCEPT_HEADING_RE.match(line):
                in_section = True
                level = len(hm.group(1))
                continue
            if in_section and len(hm.group(1)) <= level:
                in_section = False
                continue
        if in_section:
            ids.update(f"A{n}" for n in A_HEADING_RE.findall(line))
    return ids


def binder_covers(text: str) -> set[str]:
    # Prefer table covers row (binder card only — first table block)
    m = re.search(r"^\|\s*covers\s*\|\s*([^|]+)\|", first_table_block(text), re.I | re.M)
    blob = m.group(1) if m else ""
    # Also acceptance headings owned by the ticket
    blob += "\n" + "\n".join(
        line for line in text.splitlines() if line.strip().startswith("- [")
    )
    return {f"A{n}" for n in COVERS_RE.findall(blob)}


def spec_ticket_ids(text: str) -> set[str]:
    """Tickets declared in the **authoritative** tickets: front-matter / list row.

    Prose backtick mentions (`` `tkt-N` ``) are intentionally excluded. A one-sided
    ticket↔spec edge is a real drift only when the authoritative list omits the
    ticket; a casual prose reference must not mask that.
    """
    fm = parse_front_matter(text)
    raw = fm.get("tickets", "")
    ids = set(re.findall(r"tkt-([1-9][0-9]*)", raw))
    m = TICKETS_LIST_RE.search(text)
    if m:
        ids.update(re.findall(r"tkt-([1-9][0-9]*)", m.group(1)))
    return {f"tkt-{n}" for n in ids}


def iter_specs(home: Path) -> list[Path]:
    d = home / "specs"
    if not d.is_dir():
        return []
    return sorted(p for p in d.glob("spc-*.md") if p.is_file())


def iter_tickets(home: Path) -> list[Path]:
    out: list[Path] = []
    for base in (home / "tickets", home / "tickets" / "archive"):
        if not base.is_dir():
            continue
        for readme in base.glob("tkt-*/README.md"):
            out.append(readme)
    return sorted(out)


def iter_reviews(home: Path) -> list[Path]:
    d = home / "reviews"
    if not d.is_dir():
        return []
    return sorted(p for p in d.glob("rev-*.md") if p.is_file())


def validate_home(home: Path) -> list[dict[str, str]]:
    findings: list[dict[str, str]] = []
    specs: dict[str, Path] = {}
    spec_tickets: dict[str, set[str]] = {}
    spec_accept: dict[str, set[str]] = {}

    for path in iter_specs(home):
        text = load_text(path)
        fm = parse_front_matter(text)
        # Slugless fallback derives from the stem so `spc-12.md` yields
        # `spc-12`, not `spc-12.md`.
        sid = str(fm.get("id", "")).strip() or path.stem.split("-", 2)[0] + "-" + path.stem.split("-")[1]
        # id from filename spc-N-slug
        m = re.match(r"(spc-[1-9][0-9]*)-", path.name)
        file_id = m.group(1) if m else ""
        check_id = sid if sid.startswith("spc-") else file_id
        if check_id and not SPEC_ID_RE.fullmatch(check_id):
            findings.append(
                {
                    "code": "malformed_spec_id",
                    "path": str(path.relative_to(home.parent)) if home.parent in path.parents else str(path),
                    "detail": f"id {check_id!r} is not spc-N bare decimal",
                }
            )
        if check_id:
            specs[check_id] = path
            spec_tickets[check_id] = spec_ticket_ids(text)
            spec_accept[check_id] = spec_acceptance_ids(text)

    for path in iter_reviews(home):
        text = load_text(path)
        fm = parse_front_matter(text)
        rid = str(fm.get("id", "")).strip()
        if rid and not REV_ID_RE.fullmatch(rid):
            findings.append(
                {
                    "code": "malformed_review_id",
                    "path": str(path),
                    "detail": f"id {rid!r} is not a valid R1/legacy Review id",
                }
            )

    ticket_dirs_by_id: dict[str, list[Path]] = {}
    for path in iter_tickets(home):
        text = load_text(path)
        # id from directory tkt-N-slug
        m = re.match(r"(tkt-[1-9][0-9]*)-", path.parent.name)
        tid = m.group(1) if m else ""
        if tid:
            ticket_dirs_by_id.setdefault(tid, []).append(path)
        if not tid or not TKT_ID_RE.fullmatch(tid):
            findings.append(
                {
                    "code": "malformed_ticket_id",
                    "path": str(path),
                    "detail": f"directory {path.parent.name!r} is not tkt-N-…",
                }
            )

        st = ticket_status(text)
        if st is not None and st not in STATUS_OK:
            findings.append(
                {
                    "code": "invalid_ticket_status",
                    "path": str(path),
                    "detail": f"status {st!r} not in {sorted(STATUS_OK)}",
                }
            )
        if st in STATUS_LEGACY:
            findings.append(
                {
                    "code": "legacy_open_status",
                    "level": "warning",
                    "path": str(path),
                    "detail": f"status {st!r} is legacy-coarse; migrate to the FSM enum ({' | '.join(STATUS_WORKING_ORDER)} | closed)",
                }
            )
        # Header **Status:** copy vs field-table status. The template dropped
        # the header copy (field table is SoT); a stale survivor that
        # contradicts the table is dual-maintenance drift. Legacy-coarse
        # `open` headers predate the FSM migration and stay exempt (the
        # lazy-migration path owns those).
        table_status_m = STATUS_TABLE_RE.search(first_table_block(text))
        header_st = tldr_header_status(text)
        if (
            table_status_m
            and header_st is not None
            and header_st not in STATUS_LEGACY
            and header_st != table_status_m.group(1).strip().lower()
        ):
            findings.append(
                {
                    "code": "header_status_mismatch",
                    "level": "warning",
                    "path": str(path),
                    "detail": (
                        f"TL;DR header status {header_st!r} contradicts field-table "
                        f"status {table_status_m.group(1).strip().lower()!r} "
                        "(field table is SoT; drop the header copy)"
                    ),
                }
            )
        # Binder prs row: canonical filled format is `pr-N — <URL>` (em dash),
        # comma-separated for multi-PR tickets; `(none…)` placeholders are
        # exempt. Warning-level PERMANENTLY: the historical ledger migrates
        # lazily and adopt flows may reintroduce legacy rows, so this must
        # never fail a run regardless of merge order.
        prs_m = PRS_TABLE_RE.search(first_table_block(text))
        if prs_m:
            prs_val = prs_m.group(1).strip()
            if (
                prs_val
                and not PRS_PLACEHOLDER_RE.fullmatch(prs_val)
                and not PRS_ROW_CANON_RE.fullmatch(prs_val)
            ):
                findings.append(
                    {
                        "code": "prs_row_format",
                        "level": "warning",
                        "path": str(path),
                        "detail": (
                            f"prs row {prs_val!r} is not canonical "
                            "`pr-N — <URL>` (em dash; comma-separated for "
                            "multiples; `(none…)` placeholders exempt)"
                        ),
                    }
                )
        if st in STATUS_TERMINAL and not has_finish_ledger(text):
            findings.append(
                {
                    "code": "closed_without_finish",
                    "path": str(path),
                    "detail": f"status {st!r} but ## Finish ledger is missing or placeholder-only",
                }
            )
        # Inverse of closed_without_finish: a merged ## Finish ledger is
        # terminal evidence, so a working/legacy status contradicts the
        # binder's own single source of truth (spc-42:76). Error-level — this
        # is exactly the breach that stranded 19 binders at `pr-open`
        # (tkt-90; audit rev-20260827-033352Z F1/F2).
        if st is not None and st not in STATUS_TERMINAL and finish_ledger_merged(text):
            findings.append(
                {
                    "code": "finish_without_terminal_status",
                    "path": str(path),
                    "detail": (
                        f"## Finish records a merge but status is {st!r}; "
                        "a merged ledger requires terminal status "
                        "(finish-ledger stamps `closed`)"
                    ),
                }
            )

        # covers vs Spec Acceptance (spec row from the binder card only)
        sm = SPEC_REF_RE.search(first_table_block(text))
        if sm:
            sid = sm.group(1)
            covers = binder_covers(text)
            accept = spec_accept.get(sid)
            if accept is not None and covers:
                missing = sorted(covers - accept, key=lambda x: int(x[1:]))
                if missing:
                    findings.append(
                        {
                            "code": "covers_not_on_spec",
                            "path": str(path),
                            "detail": f"{tid} covers {missing} but {sid} Acceptance lacks them",
                        }
                    )
            # one-sided: active ticket claims Spec but Spec.tickets omits ticket.
            # Active = legacy open + any working FSM state; terminal binders are
            # historical ledger and stay exempt, as does the archive.
            under_archive = "tickets/archive" in path.as_posix()
            if (
                not under_archive
                and st in (STATUS_LEGACY | STATUS_WORKING)
                and sid in spec_tickets
                and tid
                and tid not in spec_tickets[sid]
            ):
                findings.append(
                    {
                        "code": "onesided_spec_ticket_edge",
                        "path": str(path),
                        "detail": f"{tid} references {sid} but {sid}.tickets does not list {tid}",
                    }
                )

    # One binder directory per ticket id: `tkt-N` is the lineage key, so two
    # dirs sharing it fork the chain (tkt-90; the historical tkt-35 collision
    # went unnoticed for four rounds without this check).
    for dup_tid, dup_paths in sorted(ticket_dirs_by_id.items()):
        if len(dup_paths) > 1:
            dirs = ", ".join(sorted(p.parent.name for p in dup_paths))
            findings.append(
                {
                    "code": "duplicate_ticket_id",
                    "path": str(dup_paths[0]),
                    "detail": f"{dup_tid} is claimed by {len(dup_paths)} binder dirs: {dirs}",
                }
            )

    return findings


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--home",
        action="append",
        dest="homes",
        help="Lattice home (.lattice). Repeatable. Default: <repo>/.lattice",
    )
    parser.add_argument("--json", action="store_true", help="JSON findings on stdout")
    parser.add_argument(
        "--root",
        default=None,
        help="Repo root for default home (default: cwd show-toplevel or .)",
    )
    args = parser.parse_args(argv)

    root = Path(args.root).resolve() if args.root else Path.cwd()
    homes = [Path(h).resolve() for h in (args.homes or [])]
    if not homes:
        homes = [root / ".lattice"]

    all_findings: list[dict[str, str]] = []
    for home in homes:
        if not home.is_dir():
            print(f"Error: lattice home not found: {home}", file=sys.stderr)
            return 2
        all_findings.extend(validate_home(home))

    # Stable order
    all_findings.sort(key=lambda f: (f.get("code", ""), f.get("path", ""), f.get("detail", "")))

    # Warnings surface but never fail the run (lazy migration).
    errors = [f for f in all_findings if f.get("level", "error") != "warning"]
    warnings = [f for f in all_findings if f.get("level", "error") == "warning"]

    if args.json:
        print(
            json.dumps(
                {
                    "ok": not errors,
                    "count": len(errors),
                    "warning_count": len(warnings),
                    "findings": all_findings,
                },
                indent=2,
            )
        )
    else:
        if not errors:
            suffix = f" ({len(warnings)} warning(s))" if warnings else ""
            print(f"validate-lattice-artifacts: OK{suffix}")
        else:
            print(f"validate-lattice-artifacts: FAILED ({len(errors)} finding(s), {len(warnings)} warning(s))")
        for f in all_findings:
            level = f.get("level", "error")
            prefix = "warn " if level == "warning" else ""
            print(f"  [{prefix}{f['code']}] {f['path']}: {f['detail']}")

    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
