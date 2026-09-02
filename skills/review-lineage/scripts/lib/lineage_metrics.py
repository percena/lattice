"""Lineage metrics — L1 running-data sensor for `review-lineage` (spc-369 A1).

Computes, from `.lattice/` + `git` only (no network), the numbers that the
audit `rev-20260902-015425Z` F1 counted by hand: status histogram, ledger
coverage, walked vs never-walked edges, direct jumps, fix-cycle distribution,
side-state / wait_reason occurrences, binder section usage, the `- NOTICED:`
backlog, escape traces by `rule_id`, base-branch commit mix, and Spec bloodline
drift. Every run can be persisted as a schema-versioned JSON snapshot so the
next run reports a delta instead of starting from zero (spc-369 D3).

Reuse over rebuild (spc-369 D5): binder rows are parsed through
`queue_health._parse_field_rows` / `_find_binders`, ledger coverage and
direct-jump counting come from `queue_health.scan_binders` /
`_count_direct_jumps`, and the modelled edge set is `transition_table.
LEGAL_EDGES`. There is no second status parser and no second edge table here.

Import contract: the `_lattice-lib/scripts/lib` directory is put on
`sys.path` by the caller (lineage-metrics.sh does; tests do). As a fallback
the sibling install location relative to THIS file (never the consumer cwd —
skill-anatomy rule 1) and `$LATTICE_LIB_SCRIPTS/lib` are tried.

Stdlib only; python >= 3.8.
"""

from __future__ import annotations

import datetime
import glob
import json
import os
import re
import subprocess
from typing import Any, Dict, List, Optional, Tuple


def _import_lattice_lib():
    """Import queue_health + transition_table from _lattice-lib/scripts/lib.

    Resolution: whatever the caller put on sys.path first; else the explicit
    `LATTICE_LIB_SCRIPTS` override; else the sibling skill install dir
    resolved from THIS file's location (`../../../_lattice-lib/scripts/lib`).
    """
    import sys

    try:
        import queue_health  # type: ignore
        import transition_table  # type: ignore
        return queue_health, transition_table
    except ImportError:
        pass
    here = os.path.dirname(os.path.abspath(__file__))
    candidates: List[str] = []
    env = os.environ.get("LATTICE_LIB_SCRIPTS", "")
    if env and os.path.isabs(env):
        candidates.append(os.path.join(env, "lib"))
    candidates.append(os.path.normpath(os.path.join(here, "..", "..", "..", "_lattice-lib", "scripts", "lib")))
    for cand in candidates:
        if os.path.isfile(os.path.join(cand, "queue_health.py")):
            sys.path.insert(0, cand)
            break
    import queue_health  # type: ignore
    import transition_table  # type: ignore
    return queue_health, transition_table


qh, tt = _import_lattice_lib()

SCHEMA = 1
DEFAULT_SINCE = "30d"
SIDE_STATES: Tuple[str, ...] = ("parked", "stuck", "rework", "deferred")
# Binder sections whose *usage* is a signal (ADR-004 §5 fallback ledger, §2
# park & pivot, spc-42 A3 decision journal). Key → heading text.
SECTIONS: Dict[str, str] = {
    "attempts": "Attempts",
    "pending_decisions": "Pending decisions",
    "decision_journal": "Decision journal",
}
BASE_CANDIDATES: Tuple[str, ...] = ("dev", "develop", "main", "master")

_NOTICED_RE = re.compile(r"^\s*-\s+NOTICED:\s*(?P<rest>.*)$")
# Escape traces are journal bullets carrying `rule_id=<x>` (ADR-007 §8). Only
# bullet lines count — prose that merely mentions `rule_id=ci-gate` in an
# Approach paragraph is not a trace.
_RULE_ID_RE = re.compile(r"\brule_id=(?P<rule>[A-Za-z0-9_.-]+)")
_BULLET_RE = re.compile(r"^\s*-\s+")
_PLACEHOLDER_LINE_RE = re.compile(r"^(<!--.*-->|\(none.*\)|_?\(none.*\)_?)$")
_OPEN_ACCEPTANCE_RE = re.compile(r"^\s*-\s+\[ \]\s+\*\*(?P<ac>A[0-9]+)\*\*")
_PR_TOKEN_RE = re.compile(r"\bpr-([1-9][0-9]*)\b")
_TKT_TOKEN_RE = re.compile(r"\btkt-([1-9][0-9]*)\b")
_PR_SUFFIX_RE = re.compile(r"\(#[1-9][0-9]*\)\s*$")
_SINCE_DAYS_RE = re.compile(r"^([1-9][0-9]*)d$")
_SINCE_DATE_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}")


# ---------------------------------------------------------------------------
# Small readers
# ---------------------------------------------------------------------------

def _read(path: str) -> Optional[str]:
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return None


def _now_utc() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


def _iso(dt: datetime.datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def snapshot_name(dt: datetime.datetime) -> str:
    """`lineage-<YYYYMMDD-HHMMSSZ>.json` — sortable by name (spc-369 Agent-assumed)."""
    return "lineage-" + dt.strftime("%Y%m%d-%H%M%SZ") + ".json"


def _section_lines(text: str, heading: str) -> List[str]:
    """Lines of the `## <heading>` section (until the next `#`-level heading)."""
    out: List[str] = []
    inside = False
    for line in text.splitlines():
        if line.startswith("## ") or line.startswith("# "):
            if inside:
                break
            inside = line.strip() == "## " + heading
            continue
        if inside:
            out.append(line)
    return out


def _is_placeholder_line(line: str) -> bool:
    s = line.strip()
    return not s or bool(_PLACEHOLDER_LINE_RE.match(s))


def section_nonempty(text: str, heading: str) -> bool:
    """True when the section holds at least one real content line (not blank,
    not an HTML comment, not a `(none…)` placeholder)."""
    return any(not _is_placeholder_line(l) for l in _section_lines(text, heading))


def _binders(tickets_dir: str) -> List[Tuple[str, str, str, Dict[str, str]]]:
    """[(tkt_id, path, text, fields)] via queue_health's finder + row parser."""
    out = []
    for tkt_id, path in qh._find_binders(tickets_dir):
        text = _read(path)
        if text is None:
            continue
        out.append((tkt_id, path, text, qh._parse_field_rows(text)))
    return out


def _ledger_files(ledger_dir: str) -> List[str]:
    if not os.path.isdir(ledger_dir):
        return []
    return sorted(glob.glob(os.path.join(ledger_dir, "*.jsonl")))


def _ledger_entries(path: str) -> List[Dict[str, Any]]:
    entries: List[Dict[str, Any]] = []
    text = _read(path) or ""
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            e = json.loads(line)
        except ValueError:
            continue  # malformed lines are the validator's business
        if isinstance(e, dict):
            entries.append(e)
    return entries


def _front_matter(text: str) -> Dict[str, str]:
    """Flat `key: value` reader for the Spec YAML front matter (no PyYAML)."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    out: Dict[str, str] = {}
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if line.lstrip().startswith("#"):
            continue
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$", line)
        if m:
            out[m.group(1)] = m.group(2).strip()
    return out


def _pr_tokens(value: str) -> List[str]:
    return sorted({"pr-" + n for n in _PR_TOKEN_RE.findall(value or "")}, key=lambda s: int(s[3:]))


def _tkt_tokens(value: str) -> List[str]:
    return sorted({"tkt-" + n for n in _TKT_TOKEN_RE.findall(value or "")}, key=lambda s: int(s[4:]))


def _pct(num: int, den: int) -> float:
    return round(100.0 * num / den, 1) if den else 0.0


# ---------------------------------------------------------------------------
# git
# ---------------------------------------------------------------------------

def _git(repo_root: str, *args: str) -> Optional[str]:
    try:
        return subprocess.check_output(
            ["git", "-C", repo_root, *args], text=True, stderr=subprocess.DEVNULL, timeout=30,
        )
    except (OSError, subprocess.SubprocessError):
        return None


def _ref_exists(repo_root: str, ref: str) -> bool:
    return _git(repo_root, "rev-parse", "--verify", "--quiet", ref + "^{commit}") is not None


def detect_base_branch(repo_root: str) -> str:
    """Integration-branch guess when no resolver answer is given: the first of
    dev/develop/main/master that exists locally (else as origin/<b>), else HEAD."""
    for b in BASE_CANDIDATES:
        if _ref_exists(repo_root, "refs/heads/" + b):
            return b
        if _ref_exists(repo_root, "refs/remotes/origin/" + b):
            return "origin/" + b
    return "HEAD"


def _since_to_args(since: str, base: str) -> List[str]:
    """`Nd` → --since "N days ago"; ISO date → --since; anything else is a ref."""
    m = _SINCE_DAYS_RE.match(since)
    if m:
        return [base, "--since", "%s days ago" % m.group(1)]
    if _SINCE_DATE_RE.match(since):
        return [base, "--since", since]
    return ["%s..%s" % (since, base)]


def git_metrics(repo_root: str, base_branch: Optional[str] = None, since: Optional[str] = None) -> Dict[str, Any]:
    """Commit mix on the integration branch over the window (rev F3 sensor).

    pr_merges: subject ends with `(#N)` (squash-merge suffix); direct_commits:
    everything else (pushed straight to base); finish_stamps: subject starts
    with `finish(` (bookkeeping stamps — a subset of direct commits).
    """
    since = since or DEFAULT_SINCE
    out: Dict[str, Any] = {
        "available": False, "base": base_branch or "", "since": since, "error": None,
        "commits_total": 0, "pr_merges": 0, "direct_commits": 0, "finish_stamps": 0,
        "direct_ratio": 0.0,
    }
    if not repo_root or _git(repo_root, "rev-parse", "--is-inside-work-tree") is None:
        out["error"] = "not a git repository: %s" % repo_root
        return out
    base = base_branch or detect_base_branch(repo_root)
    out["base"] = base
    if not _ref_exists(repo_root, base):
        out["error"] = "base ref not found: %s" % base
        return out
    log = _git(repo_root, "log", "--format=%s", *_since_to_args(since, base), "--")
    if log is None:
        out["error"] = "git log failed (base=%s since=%s)" % (base, since)
        return out
    subjects = [s for s in log.splitlines() if s.strip()]
    pr = sum(1 for s in subjects if _PR_SUFFIX_RE.search(s))
    fin = sum(1 for s in subjects if s.startswith("finish("))
    out.update({
        "available": True,
        "commits_total": len(subjects),
        "pr_merges": pr,
        "direct_commits": len(subjects) - pr,
        "finish_stamps": fin,
        "direct_ratio": round((len(subjects) - pr) / len(subjects), 3) if subjects else 0.0,
    })
    return out


# ---------------------------------------------------------------------------
# collect
# ---------------------------------------------------------------------------

def collect(
    home: str,
    repo_root: Optional[str] = None,
    since: Optional[str] = None,
    base_branch: Optional[str] = None,
    now: Optional[datetime.datetime] = None,
) -> Dict[str, Any]:
    """Compute every A1 metric from `<home>` (+ git at `repo_root`).

    Returns a JSON-serialisable dict with `schema: 1` and `generated_at`. All
    numeric leaves are delta-able (see `delta`); lists carry the evidence.
    """
    now = now or _now_utc()
    home = os.path.abspath(home)
    tickets_dir = os.path.join(home, "tickets")
    ledger_dir = os.path.join(home, ".transition-ledger")
    specs_dir = os.path.join(home, "specs")

    binders = _binders(tickets_dir)
    by_id: Dict[str, Dict[str, str]] = {t: f for t, _, _, f in binders}

    # --- status histogram / fix_cycles / side states / wait reasons ----------
    status_hist: Dict[str, int] = {}
    fix_hist: Dict[str, int] = {}
    fix_gt0 = 0
    side: Dict[str, int] = {s: 0 for s in SIDE_STATES}
    wait_reasons: Dict[str, int] = {}
    sections: Dict[str, int] = {k: 0 for k in SECTIONS}
    noticed_items: List[Dict[str, str]] = []
    escape_by_rule: Dict[str, int] = {}
    escape_items: List[Dict[str, str]] = []

    for tkt_id, _path, text, fields in binders:
        status = fields.get("status", "") or "(none)"
        status_hist[status] = status_hist.get(status, 0) + 1
        fc = fields.get("fix_cycles", "")
        fc_key = fc if fc.isdigit() else "(none)"
        fix_hist[fc_key] = fix_hist.get(fc_key, 0) + 1
        if fc.isdigit() and int(fc) > 0:
            fix_gt0 += 1
        if status in side:
            side[status] += 1
        wr = fields.get("wait_reason", "")
        if wr and not _PLACEHOLDER_LINE_RE.match(wr):
            wait_reasons[wr] = wait_reasons.get(wr, 0) + 1
        for key, heading in SECTIONS.items():
            if section_nonempty(text, heading):
                sections[key] += 1
        for line in text.splitlines():
            m = _NOTICED_RE.match(line)
            if m:
                noticed_items.append({"ticket": tkt_id, "line": "NOTICED: " + m.group("rest").strip()})
            if _BULLET_RE.match(line):
                for rule in _RULE_ID_RE.findall(line):
                    escape_by_rule[rule] = escape_by_rule.get(rule, 0) + 1
                    escape_items.append({"ticket": tkt_id, "rule_id": rule})

    # --- ledger coverage + direct jumps (reuse queue_health) -----------------
    scan = qh.scan_binders(tickets_dir, now=now, gh_fallback=None)
    cov = dict(scan.get("ledger_coverage") or {})
    cov.setdefault("terminal", 0)
    cov.setdefault("with_ledger", 0)
    cov.setdefault("missing", [])
    cov.setdefault("direct_jumps", 0)
    cov["missing_count"] = len(cov["missing"])
    cov["pct"] = _pct(int(cov["with_ledger"]), int(cov["terminal"]))
    # Tickets carrying a direct-jump merge — same file selection as scan_binders
    # (canonical `<tkt>.jsonl`, else the first legacy `<tkt>-*.jsonl`).
    dj_tickets: List[str] = []
    for tkt_id, fields in by_id.items():
        if fields.get("status", "") != "closed":
            continue
        lp = os.path.join(ledger_dir, tkt_id + ".jsonl")
        if not os.path.isfile(lp):
            legacy = sorted(glob.glob(os.path.join(ledger_dir, tkt_id + "-*.jsonl")))
            if not legacy:
                continue
            lp = legacy[0]
        if qh._count_direct_jumps(lp) > 0:
            dj_tickets.append(tkt_id)

    # --- edges: histogram over ALL ledgers vs LEGAL_EDGES --------------------
    legal = sorted({(e.from_, e.to) for e in tt.LEGAL_EDGES if e.from_ != "init"})
    legal_set = set(legal)
    edge_hist: Dict[str, int] = {}
    entries_total = 0
    ledger_files = _ledger_files(ledger_dir)
    for lf in ledger_files:
        for e in _ledger_entries(lf):
            frm, to = str(e.get("from", "")), str(e.get("to", ""))
            if not frm or not to or frm == "init":
                continue
            entries_total += 1
            key = "%s->%s" % (frm, to)
            edge_hist[key] = edge_hist.get(key, 0) + 1
    walked_pairs = {tuple(k.split("->", 1)) for k in edge_hist}
    walked = ["%s->%s" % p for p in legal if p in walked_pairs]
    never_walked = ["%s->%s" % p for p in legal if p not in walked_pairs]
    unmodelled = sorted("%s->%s" % p for p in walked_pairs if p not in legal_set)

    # --- specs: done with open A*; prs vs child binder union ----------------
    spec_status_hist: Dict[str, int] = {}
    open_acc: List[Dict[str, Any]] = []
    prs_mismatch: List[Dict[str, Any]] = []
    spec_files = sorted(glob.glob(os.path.join(specs_dir, "spc-*.md"))) if os.path.isdir(specs_dir) else []
    for sf in spec_files:
        text = _read(sf) or ""
        fm = _front_matter(text)
        sid = fm.get("id") or os.path.basename(sf).split("-", 2)[0] + "-" + os.path.basename(sf).split("-", 2)[1]
        st = fm.get("status", "") or "(none)"
        spec_status_hist[st] = spec_status_hist.get(st, 0) + 1
        if st != "done":
            continue
        opens = [m.group("ac") for m in (_OPEN_ACCEPTANCE_RE.match(l) for l in text.splitlines()) if m]
        if opens:
            open_acc.append({"spec": sid, "open": opens})
        spec_prs = _pr_tokens(fm.get("prs", ""))
        children = _tkt_tokens(fm.get("tickets", ""))
        union: List[str] = []
        for c in children:
            union.extend(_pr_tokens(by_id.get(c, {}).get("prs", "")))
        union = sorted(set(union), key=lambda s: int(s[3:]))
        if union != spec_prs:
            # missing_in_spec = a delivered child PR the Spec bloodline does not
            # cite (real drift); extra_in_spec = PRs only the Spec cites — usually
            # the Spec-creation / planning PR (informational).
            prs_mismatch.append({
                "spec": sid, "spec_prs": spec_prs, "binder_prs": union, "tickets": children,
                "missing_in_spec": [p for p in union if p not in spec_prs],
                "extra_in_spec": [p for p in spec_prs if p not in union],
            })

    root = os.path.abspath(repo_root) if repo_root else os.path.dirname(home)
    git = git_metrics(root, base_branch=base_branch, since=since)
    # Display-only relative home so reports pasted into rev-/PR bodies carry
    # no machine-local absolute path.
    try:
        home_rel = os.path.relpath(home, root)
        if home_rel.startswith(".."):
            home_rel = os.path.basename(home)
    except ValueError:
        home_rel = os.path.basename(home)

    return {
        "schema": SCHEMA,
        "generated_at": _iso(now),
        "home": home_rel,
        "binders_total": len(binders),
        "status_histogram": dict(sorted(status_hist.items())),
        "ledger_coverage": cov,
        "direct_jumps": {"count": int(cov["direct_jumps"]), "tickets": dj_tickets},
        "edges": {
            "ledger_files": len(ledger_files),
            "entries": entries_total,
            "modelled": len(legal),
            "walked_count": len(walked),
            "never_walked_count": len(never_walked),
            "unmodelled_count": len(unmodelled),
            "histogram": dict(sorted(edge_hist.items(), key=lambda kv: (-kv[1], kv[0]))),
            "walked": walked,
            "never_walked": never_walked,
            "unmodelled": unmodelled,
        },
        "fix_cycles_histogram": dict(sorted(fix_hist.items())),
        "fix_cycles_gt0": fix_gt0,
        "side_states": dict(side, total=sum(side.values())),
        "wait_reasons": dict(sorted(wait_reasons.items())),
        "sections": sections,
        "noticed": {"count": len(noticed_items), "items": noticed_items},
        "escape_traces": {"total": len(escape_items), "by_rule": dict(sorted(escape_by_rule.items())), "items": escape_items},
        "git": git,
        "specs": {
            "total": len(spec_files),
            "by_status": dict(sorted(spec_status_hist.items())),
            "done_with_open_acceptance_count": len(open_acc),
            "done_with_open_acceptance": open_acc,
            "prs_mismatch_count": len(prs_mismatch),
            "prs_missing_in_spec_count": sum(1 for x in prs_mismatch if x["missing_in_spec"]),
            "prs_mismatch": prs_mismatch,
        },
    }


# ---------------------------------------------------------------------------
# snapshots + delta
# ---------------------------------------------------------------------------

def load_previous(snapshot_dir: str) -> Optional[Dict[str, Any]]:
    """Newest `lineage-*.json` by name (names sort chronologically), tagged with
    `_file` (basename). None when the dir is absent/empty or the file is unreadable."""
    if not snapshot_dir or not os.path.isdir(snapshot_dir):
        return None
    files = sorted(glob.glob(os.path.join(snapshot_dir, "lineage-*.json")))
    for path in reversed(files):
        text = _read(path)
        if text is None:
            continue
        try:
            data = json.loads(text)
        except ValueError:
            continue
        if isinstance(data, dict):
            data["_file"] = os.path.basename(path)
            return data
    return None


def write_snapshot(snapshot_dir: str, cur: Dict[str, Any]) -> str:
    """Write `cur` as `<snapshot_dir>/lineage-<UTC>.json` (append-only file set)."""
    os.makedirs(snapshot_dir, exist_ok=True)
    ts = cur.get("generated_at") or _iso(_now_utc())
    dt = datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ")
    path = os.path.join(snapshot_dir, snapshot_name(dt))
    payload = {k: v for k, v in cur.items() if not k.startswith("_")}
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2, sort_keys=False, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, path)
    return path


_SKIP_KEYS = frozenset({"schema", "generated_at", "home", "delta", "snapshot_file"})


def numeric_leaves(d: Dict[str, Any], prefix: str = "") -> Dict[str, float]:
    """Flatten nested dicts to {"a.b.c": number}; lists/strings/bools skipped."""
    out: Dict[str, float] = {}
    for k, v in d.items():
        if k.startswith("_") or (not prefix and k in _SKIP_KEYS):
            continue
        key = prefix + k
        if isinstance(v, bool):
            continue
        if isinstance(v, (int, float)):
            out[key] = v
        elif isinstance(v, dict):
            out.update(numeric_leaves(v, key + "."))
    return out


def delta(cur: Dict[str, Any], prev: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    """Numeric-only delta: {"previous": <file|None>, "changes": {path: {prev, cur, diff, arrow}}}.

    arrow ∈ ▲ (up) ▼ (down) = (same) new (no previous value) gone (no current).
    """
    if not prev:
        return {"previous": None, "previous_generated_at": None, "changes": {}}
    a = numeric_leaves(cur)
    b = numeric_leaves(prev)
    changes: Dict[str, Dict[str, Any]] = {}
    for key in sorted(set(a) | set(b)):
        c, p = a.get(key), b.get(key)
        if c is None:
            changes[key] = {"prev": p, "cur": None, "diff": None, "arrow": "gone"}
        elif p is None:
            changes[key] = {"prev": None, "cur": c, "diff": None, "arrow": "new"}
        else:
            diff = round(c - p, 3)
            arrow = "▲" if diff > 0 else ("▼" if diff < 0 else "=")
            changes[key] = {"prev": p, "cur": c, "diff": diff, "arrow": arrow}
    return {
        "previous": prev.get("_file"),
        "previous_generated_at": prev.get("generated_at"),
        "changes": changes,
    }


# ---------------------------------------------------------------------------
# markdown
# ---------------------------------------------------------------------------

def _fmt_num(v: Any) -> str:
    if isinstance(v, float):
        return ("%.3f" % v).rstrip("0").rstrip(".") if v != int(v) else str(int(v))
    return str(v)


def _dcell(d: Dict[str, Any], key: str) -> str:
    """Δ cell for one numeric path. '—' on a first snapshot."""
    if not d or d.get("previous") is None:
        return "—"
    ch = d.get("changes", {}).get(key)
    if not ch:
        return ""
    arrow = ch["arrow"]
    if arrow in ("new", "gone"):
        return arrow
    if arrow == "=":
        return "="
    diff = ch["diff"]
    sign = "+" if diff > 0 else ""
    return "%s %s%s" % (arrow, sign, _fmt_num(diff))


def _clip(s: str, n: int = 110) -> str:
    s = s.replace("|", "\\|")
    return s if len(s) <= n else s[: n - 1] + "…"


def render_md(cur: Dict[str, Any], d: Optional[Dict[str, Any]] = None) -> str:
    """Compact Markdown: headline table with Δ, then per-metric tables."""
    d = d or {"previous": None, "changes": {}}
    L: List[str] = []
    L.append("## Lineage metrics — %s (schema %s)" % (cur.get("generated_at"), cur.get("schema")))
    L.append("")
    if d.get("previous"):
        L.append("_Δ vs `%s` (%s)._" % (d["previous"], d.get("previous_generated_at") or "?"))
    else:
        L.append("_First snapshot — no previous `lineage-*.json` to diff against._")
    L.append("")

    cov = cur["ledger_coverage"]
    e = cur["edges"]
    g = cur["git"]
    sp = cur["specs"]
    sec = cur["sections"]

    L.append("### Headline")
    L.append("")
    L.append("| Metric | Value | Δ |")
    L.append("| --- | --- | --- |")
    rows = [
        ("Binders", str(cur["binders_total"]), "binders_total"),
        ("Ledger coverage (terminal with ledger)", "%s/%s (%s%%)" % (cov["with_ledger"], cov["terminal"], _fmt_num(cov["pct"])), "ledger_coverage.with_ledger"),
        ("Missing ledger", str(cov["missing_count"]), "ledger_coverage.missing_count"),
        ("Direct jumps (merge from queued/in-progress)", str(cur["direct_jumps"]["count"]), "direct_jumps.count"),
        ("Ledger entries / files", "%s / %s" % (e["entries"], e["ledger_files"]), "edges.entries"),
        ("Edges walked / modelled", "%s / %s" % (e["walked_count"], e["modelled"]), "edges.walked_count"),
        ("Edges never walked", str(e["never_walked_count"]), "edges.never_walked_count"),
        ("Edges unmodelled (walked but not in LEGAL_EDGES)", str(e["unmodelled_count"]), "edges.unmodelled_count"),
        ("Side-state binders (parked/stuck/rework/deferred)", str(cur["side_states"]["total"]), "side_states.total"),
        ("Binders with fix_cycles > 0", str(cur["fix_cycles_gt0"]), "fix_cycles_gt0"),
        ("Binders with `## Attempts` entries", str(sec["attempts"]), "sections.attempts"),
        ("Binders with `## Pending decisions` entries", str(sec["pending_decisions"]), "sections.pending_decisions"),
        ("Binders with `## Decision journal` entries", str(sec["decision_journal"]), "sections.decision_journal"),
        ("`- NOTICED:` backlog", str(cur["noticed"]["count"]), "noticed.count"),
        ("Escape traces (`rule_id=`)", str(cur["escape_traces"]["total"]), "escape_traces.total"),
        ("Base commits (`%s`, since %s)" % (g.get("base") or "?", g.get("since")), str(g["commits_total"]), "git.commits_total"),
        ("  PR merges (`(#N)` suffix)", str(g["pr_merges"]), "git.pr_merges"),
        ("  Direct commits (no PR suffix)", "%s (%s%%)" % (g["direct_commits"], _fmt_num(round(100 * g["direct_ratio"], 1))), "git.direct_commits"),
        ("  `finish(` stamps", str(g["finish_stamps"]), "git.finish_stamps"),
        ("Specs done with open A*", str(sp["done_with_open_acceptance_count"]), "specs.done_with_open_acceptance_count"),
        ("Specs with `prs` ≠ child binder PR union", str(sp["prs_mismatch_count"]), "specs.prs_mismatch_count"),
        ("  of which a child PR is missing from the Spec", str(sp["prs_missing_in_spec_count"]), "specs.prs_missing_in_spec_count"),
    ]
    for label, value, key in rows:
        L.append("| %s | %s | %s |" % (label, value, _dcell(d, key)))
    L.append("")
    if not g.get("available"):
        L.append("_git metrics unavailable: %s_" % (g.get("error") or "unknown"))
        L.append("")

    L.append("### Status histogram")
    L.append("")
    L.append("| Status | Binders | Δ |")
    L.append("| --- | --- | --- |")
    for k, v in cur["status_histogram"].items():
        # A key that is not a bare status word is a parser-visible binder
        # defect (e.g. a 3-column field table) — show it, clipped, not hidden.
        L.append("| `%s` | %s | %s |" % (_clip(k, 40), v, _dcell(d, "status_histogram." + k)))
    L.append("")

    L.append("### Edges (ledger) — %s walked / %s modelled · never walked %s" % (e["walked_count"], e["modelled"], e["never_walked_count"]))
    L.append("")
    L.append("| Edge | Entries | Δ |")
    L.append("| --- | --- | --- |")
    for k, v in e["histogram"].items():
        flag = "" if k in e["walked"] else " (unmodelled)"
        L.append("| `%s`%s | %s | %s |" % (k, flag, v, _dcell(d, "edges.histogram." + k)))
    L.append("")
    L.append("Never walked: " + (", ".join("`%s`" % x for x in e["never_walked"]) if e["never_walked"] else "(none)"))
    L.append("")
    if cur["direct_jumps"]["tickets"]:
        L.append("Direct-jump tickets: " + ", ".join(cur["direct_jumps"]["tickets"]))
        L.append("")
    if cov["missing"]:
        shown = cov["missing"][:12]
        more = " … (+%d)" % (len(cov["missing"]) - 12) if len(cov["missing"]) > 12 else ""
        L.append("Missing ledger: " + ", ".join(shown) + more)
        L.append("")

    L.append("### Side states, wait reasons, fix cycles")
    L.append("")
    L.append("| Key | Count | Δ |")
    L.append("| --- | --- | --- |")
    for s in SIDE_STATES:
        L.append("| status `%s` | %s | %s |" % (s, cur["side_states"][s], _dcell(d, "side_states." + s)))
    for k, v in cur["wait_reasons"].items():
        L.append("| wait_reason `%s` | %s | %s |" % (k, v, _dcell(d, "wait_reasons." + k)))
    for k, v in cur["fix_cycles_histogram"].items():
        L.append("| fix_cycles = %s | %s | %s |" % (k, v, _dcell(d, "fix_cycles_histogram." + k)))
    L.append("")

    L.append("### Escape traces by rule")
    L.append("")
    if cur["escape_traces"]["by_rule"]:
        L.append("| rule_id | Count | Δ |")
        L.append("| --- | --- | --- |")
        for k, v in cur["escape_traces"]["by_rule"].items():
            L.append("| `%s` | %s | %s |" % (k, v, _dcell(d, "escape_traces.by_rule." + k)))
    else:
        L.append("(none)")
    L.append("")

    L.append("### `- NOTICED:` backlog — %s" % cur["noticed"]["count"])
    L.append("")
    if cur["noticed"]["items"]:
        L.append("| Ticket | Line |")
        L.append("| --- | --- |")
        for it in cur["noticed"]["items"]:
            L.append("| %s | %s |" % (it["ticket"], _clip(it["line"])))
    else:
        L.append("(none)")
    L.append("")

    L.append("### Specs — %s (%s)" % (sp["total"], ", ".join("%s %s" % (k, v) for k, v in sp["by_status"].items()) or "none"))
    L.append("")
    if sp["done_with_open_acceptance"]:
        L.append("Done with open acceptance boxes: " + "; ".join("%s (%s)" % (x["spec"], ", ".join(x["open"])) for x in sp["done_with_open_acceptance"]))
    else:
        L.append("Done with open acceptance boxes: (none)")
    if sp["prs_mismatch"]:
        L.append("")
        L.append("| Spec | Child PRs missing from Spec `prs` | Spec-only PRs (planning / create PR) |")
        L.append("| --- | --- | --- |")
        for x in sp["prs_mismatch"]:
            L.append("| %s | %s | %s |" % (x["spec"], ", ".join(x["missing_in_spec"]) or "(none)", ", ".join(x["extra_in_spec"]) or "(none)"))
    else:
        L.append("Spec `prs` vs child PR union: all consistent")
    L.append("")
    L.append("_Source: `%s` (binders, `.transition-ledger/*.jsonl`, `specs/`) + `git log %s` — no network. Advisory sensor (ADR-007 §8)._" % (cur.get("home"), g.get("base") or "?"))
    return "\n".join(L)
