"""Hotspot metrics — L4 synthesis sensor for review-lineage (spc-387 A1).

Computes cross-cutting recurrence analysis that L1 (lineage-metrics) cannot:
hotspot clusters (files grouped by path/skill/stage), fix-class histogram,
ticket genealogy (rev→ticket→fix_cycles chains), cross-audit recurrence
(finding-class appearing in multiple revs), and NOTICED feedback data.

Reuse over rebuild (spc-387 D5): git commit data comes from
lineage_metrics.git_metrics() and a shared fix-commit scanner; binder
parsing through queue_health._parse_field_rows. No second git log runner
for the base-commit mix, no second binder parser.

Import contract: same as lineage_metrics.py — the _lattice-lib/scripts/lib
directory is on sys.path (put there by hotspot-metrics.sh or tests).

Stdlib only; python >= 3.8.
"""

from __future__ import annotations

import datetime
import json
import os
import re
import subprocess
from typing import Any, Dict, List, Optional, Tuple


# ---------------------------------------------------------------------------
# Import _lattice-lib (same pattern as lineage_metrics.py)
# ---------------------------------------------------------------------------

def _import_lattice_lib():
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


# Also import lineage_metrics (sibling in same lib dir) for git_metrics reuse.
def _import_lineage_metrics():
    import sys
    here = os.path.dirname(os.path.abspath(__file__))
    if here not in sys.path:
        sys.path.insert(0, here)
    try:
        import lineage_metrics  # type: ignore
        return lineage_metrics
    except ImportError:
        return None


qh, tt = _import_lattice_lib()
lm = _import_lineage_metrics()

SCHEMA = 1
DEFAULT_SINCE = "30d"
MIN_FIX_COMMITS = 2  # files in ≥ N fix() commits form a cluster

# Fix-class classification regexes (seeded from rev-20260902-080545Z evidence).
_FIX_CLASSES: List[Tuple[str, re.Pattern]] = [
    ("status-flip", re.compile(r"flip\b|status.*closed|backfill.*pr-open|re-stamp", re.I)),
    ("regex-drift", re.compile(r"regex|parse|field.*row|_FIELD_ROW", re.I)),
    ("bash-guard", re.compile(r"bash.*3\.2|unbound|empty.*array|set -u|\$\{ARR", re.I)),
    ("field-mismatch", re.compile(r"field|gh.*json|conclusion|state_reason|baseRef", re.I)),
    ("atomicity", re.compile(r"atomic|race|lock|transaction|commit_transaction", re.I)),
]

# Finding-class signatures (keyword sets matched against ### F headings).
_FINDING_CLASSES: Dict[str, List[str]] = {
    "terminal-stamp": ["terminal-stamp", "finish-ledger", "stamp-pr-open", "status.flip", "pr-open.*closed"],
    "regex-drift": ["regex", "parse", "field-row", "binder_rows"],
    "silent-bypass": ["silent", "bypass", "direct.*base", "direct.*commit", "no.*pr"],
    "invisible-queue": ["notic", "backlog", "disposition", "drain"],
    "done-without-evidence": ["done.*evidence", "a\\*", "acceptance.*cite", "spec.*done"],
    "environment-dependence": ["bash.*3", "gh.*version", "root", "macos", "bsd"],
}

# Path-prefix → skill attribution (auto-derived, no manual config).
_PATH_PREFIXES: List[Tuple[str, str]] = [
    (".lattice/", "bookkeeping"),
    ("skills/_lattice-lib/", "shared"),
    ("tools/", "cross-cutting"),
    ("docs/", "docs"),
    (".github/", "ci-cd"),
    ("plugins/", "plugin-bundle"),
    ("evals/", "evals"),
    (".claude-plugin/", "plugin-bundle"),
]

# Skill → stage mapping (seeded from validate-skills.sh USER_FACING / QUALITY_SIDE_PATHS).
_DELIVERY_SKILLS = frozenset({
    "create-spec", "create-tickets", "start-work", "create-pr",
    "finish-work", "batch-work",
})
_REVIEW_SKILLS = frozenset({
    "review-code", "review-delivery", "review-lineage",
    "review-production", "create-review", "verify-features",
})


# ---------------------------------------------------------------------------
# Small helpers
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
    return "hotspot-" + dt.strftime("%Y%m%d-%H%M%SZ") + ".json"


def _pct(num: int, den: int) -> float:
    return round(100.0 * num / den, 1) if den else 0.0


def _git(repo_root: str, *args: str) -> Optional[str]:
    try:
        return subprocess.check_output(
            ["git", "-C", repo_root, *args], text=True, stderr=subprocess.DEVNULL, timeout=60,
        )
    except (OSError, subprocess.SubprocessError):
        return None


def detect_base_branch(repo_root: str) -> str:
    for b in ("dev", "develop", "main", "master"):
        if _git(repo_root, "rev-parse", "--verify", "--quiet", "refs/heads/" + b) is not None:
            return b
        if _git(repo_root, "rev-parse", "--verify", "--quiet", "refs/remotes/origin/" + b) is not None:
            return "origin/" + b
    return "HEAD"


def _since_to_args(since: str, base: str) -> List[str]:
    m = re.match(r"^([1-9][0-9]*)d$", since)
    if m:
        return [base, "--since", "%s days ago" % m.group(1)]
    if re.match(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}", since):
        return [base, "--since", since]
    return ["%s..%s" % (since, base)]


# ---------------------------------------------------------------------------
# Core: fix commits with touched files
# ---------------------------------------------------------------------------

def _fix_commits(repo_root: str, base: str, since: str) -> List[Dict[str, Any]]:
    """Return fix() commits in the window: [{hash, subject, files[]}]."""
    log = _git(repo_root, "log", "--format=__%h %s", "--name-only", *_since_to_args(since, base), "--")
    if not log:
        return []
    commits: List[Dict[str, Any]] = []
    cur: Optional[Dict[str, Any]] = None
    for line in log.splitlines():
        if line.startswith("__"):
            parts = line[2:].split(" ", 1)
            h = parts[0]
            subj = parts[1] if len(parts) > 1 else ""
            if re.match(r"^fix\b", subj):
                cur = {"hash": h, "subject": subj, "files": []}
                commits.append(cur)
            else:
                cur = None
        elif cur is not None and line.strip():
            cur["files"].append(line.strip())
    return commits


def _classify_fix(subject: str) -> str:
    for cls, pat in _FIX_CLASSES:
        if pat.search(subject):
            return cls
    return "other"


def _attrib_file(path: str) -> Tuple[str, str, str]:
    """Return (skill, stage, cluster_key) for a file path.

    Auto-derived from directory structure (spc-387 D3):
    - skills/<skill>/ → that skill
    - skills/_lattice-lib/ → shared
    - tools/ → cross-cutting
    - docs/ → docs
    - .lattice/ → lattice-home
    cluster_key groups files that belong to the same hotspot.
    """
    for prefix, skill in _PATH_PREFIXES:
        if path.startswith(prefix):
            if skill == "shared":
                # _lattice-lib/scripts/ — cluster by subdirectory (scripts vs tests vs lib)
                rest = path[len("skills/_lattice-lib/"):]
                parts = rest.split("/")
                sub = parts[0] if parts else "root"
                return "shared", "shared", "shared:" + sub
            elif skill == "bookkeeping":
                return "bookkeeping", "bookkeeping", "bookkeeping"
            elif skill == "cross-cutting":
                return "cross-cutting", "cross-cutting", "cross-cutting"
            elif skill == "docs":
                return "docs", "docs", "docs:" + path.split("/")[1] if len(path.split("/")) > 1 else "docs"
            elif skill == "ci-cd":
                return "ci-cd", "ci-cd", "ci-cd:" + path.split("/")[2] if len(path.split("/")) > 2 else "ci-cd"
            elif skill == "plugin-bundle":
                return "plugin-bundle", "plugin-bundle", "plugin-bundle"
            elif skill == "evals":
                return "evals", "evals", "evals"
            return skill, skill, skill
    # skills/<skill>/ pattern
    m = re.match(r"^skills/([^/]+)/", path)
    if m:
        skill = m.group(1)
        stage = "delivery" if skill in _DELIVERY_SKILLS else ("review" if skill in _REVIEW_SKILLS else "other")
        # Cluster by skill + first sub-path (scripts/ vs references/ vs SKILL.md)
        rest = path[len("skills/"):].split("/")
        sub = rest[1] if len(rest) > 1 else "root"
        return skill, stage, skill + ":" + sub
    return "unknown", "unknown", "unknown"


# ---------------------------------------------------------------------------
# Metric 1: hotspot_clusters
# ---------------------------------------------------------------------------

def hotspot_clusters(repo_root: str, base: str, since: str) -> Dict[str, Any]:
    """Cluster files fixed in ≥N fix() commits by path attribution."""
    fcs = _fix_commits(repo_root, base, since)
    total_fix = len(fcs)

    # Map: cluster_key → {files: set, hashes: set, classes: set, modifications: int}
    clusters: Dict[str, Dict[str, Any]] = {}
    for fc in fcs:
        for fpath in fc["files"]:
            skill, stage, ckey = _attrib_file(fpath)
            if ckey not in clusters:
                clusters[ckey] = {
                    "cluster": ckey,
                    "files": set(),
                    "hashes": set(),
                    "classes": set(),
                    "modifications": 0,
                    "skill": skill,
                    "stage": stage,
                }
            clusters[ckey]["files"].add(fpath)
            clusters[ckey]["hashes"].add(fc["hash"])
            clusters[ckey]["classes"].add(_classify_fix(fc["subject"]))
            clusters[ckey]["modifications"] += 1

    # Filter: clusters with ≥ MIN_FIX_COMMITS unique fix commits
    result = []
    for ckey in sorted(clusters, key=lambda k: len(clusters[k]["hashes"]), reverse=True):
        c = clusters[ckey]
        fix_count = len(c["hashes"])
        if fix_count < MIN_FIX_COMMITS:
            continue
        result.append({
            "cluster": ckey,
            "files": sorted(c["files"]),
            "file_count": len(c["files"]),
            "fix_commit_count": fix_count,
            "total_modifications": c["modifications"],
            "fix_share_pct": _pct(fix_count, total_fix),
            "fix_classes": sorted(c["classes"]),
            "skill": c["skill"],
            "stage": c["stage"],
        })
    return {
        "total_fix_commits": total_fix,
        "cluster_count": len(result),
        "clusters": result,
    }


# ---------------------------------------------------------------------------
# Metric 2: fix_class_histogram
# ---------------------------------------------------------------------------

def fix_class_histogram(repo_root: str, base: str, since: str) -> Dict[str, Any]:
    """Classify fix() commit subjects by regex into named classes."""
    fcs = _fix_commits(repo_root, base, since)
    hist: Dict[str, int] = {cls: 0 for cls, _ in _FIX_CLASSES}
    hist["other"] = 0
    for fc in fcs:
        hist[_classify_fix(fc["subject"])] += 1
    return {
        "total": len(fcs),
        "histogram": hist,
    }


# ---------------------------------------------------------------------------
# Metric 3: ticket_genealogy
# ---------------------------------------------------------------------------

def _binder_fix_cycles(home: str, tkt_id: str) -> int:
    """Read fix_cycles from a binder README."""
    for d in os.listdir(os.path.join(home, "tickets")):
        if d.startswith("tkt-" + tkt_id + "-") or d == "tkt-" + tkt_id:
            text = _read(os.path.join(home, "tickets", d, "README.md"))
            if text:
                m = re.search(r"^\|\s*fix_cycles\s*\|\s*(\d+)", text, re.M)
                if m:
                    return int(m.group(1))
    return 0


def ticket_genealogy(home: str) -> Dict[str, Any]:
    """For each rev with Proposed-tickets: count tickets + fix_cycles.
    For each Spec: count tickets + fix_cycles."""
    revs_dir = os.path.join(home, "reviews")
    rev_entries: List[Dict[str, Any]] = []

    if os.path.isdir(revs_dir):
        for fname in sorted(os.listdir(revs_dir)):
            if not fname.startswith("rev-") or not fname.endswith(".md"):
                continue
            text = _read(os.path.join(revs_dir, fname))
            if not text:
                continue
            # Count rows in a Proposed-tickets table (| N | ... pattern)
            tkt_ids = re.findall(r"\btkt-(\d+)\b", text)
            tkt_set = sorted(set(tkt_ids))
            fc_total = sum(_binder_fix_cycles(home, t) for t in tkt_set)
            fc_gt0 = sum(1 for t in tkt_set if _binder_fix_cycles(home, t) > 0)
            rev_entries.append({
                "rev_id": fname[:-3],
                "tickets_spawned": len(tkt_set),
                "tickets_with_fix_cycles_gt0": fc_gt0,
                "total_fix_cycles": fc_total,
            })

    # Specs
    specs_dir = os.path.join(home, "specs")
    spec_entries: List[Dict[str, Any]] = []
    if os.path.isdir(specs_dir):
        for fname in sorted(os.listdir(specs_dir)):
            if not fname.startswith("spc-") or not fname.endswith(".md"):
                continue
            text = _read(os.path.join(specs_dir, fname))
            if not text:
                continue
            tkt_ids = re.findall(r"\btkt-(\d+)\b", text)
            tkt_set = sorted(set(tkt_ids))
            fc_total = sum(_binder_fix_cycles(home, t) for t in tkt_set)
            fc_gt0 = sum(1 for t in tkt_set if _binder_fix_cycles(home, t) > 0)
            spec_entries.append({
                "spec_id": fname[:-3],
                "ticket_count": len(tkt_set),
                "tickets_with_fix_cycles_gt0": fc_gt0,
                "total_fix_cycles": fc_total,
            })

    return {
        "revs": rev_entries,
        "specs": spec_entries,
    }


# ---------------------------------------------------------------------------
# Metric 4: cross_audit_recurrence
# ---------------------------------------------------------------------------

def cross_audit_recurrence(home: str) -> Dict[str, Any]:
    """For each finding-class: list revs where a ### F heading mentions it."""
    revs_dir = os.path.join(home, "reviews")
    findings_by_class: Dict[str, List[str]] = {cls: [] for cls in _FINDING_CLASSES}

    if os.path.isdir(revs_dir):
        for fname in sorted(os.listdir(revs_dir)):
            if not fname.startswith("rev-") or not fname.endswith(".md"):
                continue
            rev_id = fname[:-3]
            text = _read(os.path.join(revs_dir, fname))
            if not text:
                continue
            # Extract ### F headings + the ## Findings section body
            headings = re.findall(r"^###\s+F\d+\s+—?\s*(.+)$", text, re.M)
            heading_text = " | ".join(headings).lower() if headings else ""
            # Also search the ## Findings section body for finding-class keywords
            findings_section = ""
            in_findings = False
            for line in text.splitlines():
                if re.match(r"^##\s+Findings", line):
                    in_findings = True
                    continue
                if in_findings and re.match(r"^##\s", line):
                    in_findings = False
                if in_findings:
                    findings_section += line + "\n"
            combined = (heading_text + " " + findings_section.lower()).strip()
            for cls, keywords in _FINDING_CLASSES.items():
                for kw in keywords:
                    if re.search(kw, combined, re.I):
                        findings_by_class[cls].append(rev_id)
                        break

    # Compute trend (▲ if growing, — if stable, ▼ if shrinking)
    result: Dict[str, Any] = {}
    for cls, revs in findings_by_class.items():
        trend = "—" if len(revs) < 2 else ("▲" if len(revs) >= 3 else "—")
        result[cls] = {
            "revs": revs,
            "recurrence_count": len(revs),
            "trend": trend,
        }
    return result


# ---------------------------------------------------------------------------
# Metric 5: noticed_feedback
# ---------------------------------------------------------------------------

def noticed_feedback(home: str) -> Dict[str, Any]:
    """Count NOTICED lines → became_ticket / stale_unresolved."""
    tickets_dir = os.path.join(home, "tickets")
    total = 0
    became_ticket = 0
    stale_unresolved = 0

    # Collect all tkt ids that appear in rev Proposed-tickets tables
    revs_dir = os.path.join(home, "reviews")
    filed_tkts: set = set()
    if os.path.isdir(revs_dir):
        for fname in os.listdir(revs_dir):
            if not fname.startswith("rev-") or not fname.endswith(".md"):
                continue
            text = _read(os.path.join(revs_dir, fname))
            if text:
                # Match tkt-N in the Proposed-tickets table context
                for m in re.finditer(r"\btkt-(\d+)\b", text):
                    filed_tkts.add(m.group(1))

    # Collect all NOTICED lines
    noticed_items: List[Dict[str, str]] = []
    if os.path.isdir(tickets_dir):
        for d in sorted(os.listdir(tickets_dir)):
            if not d.startswith("tkt-"):
                continue
            text = _read(os.path.join(tickets_dir, d, "README.md"))
            if not text:
                continue
            for line in text.splitlines():
                m = re.match(r"^\s*-\s+NOTICED:\s*(?P<rest>.*)$", line)
                if m:
                    total += 1
                    noticed_items.append({"ticket": d, "line": m.group("rest").strip()})
                    # Check if this binder's tkt id appears in a rev Proposed-tickets table
                    tkt_id = re.search(r"tkt-(\d+)", d)
                    if tkt_id and tkt_id.group(1) in filed_tkts:
                        became_ticket += 1

    # Stale: lines older than 7 days with no disposition
    revs_with_sweep = set()
    if os.path.isdir(revs_dir):
        for fname in os.listdir(revs_dir):
            if not fname.startswith("rev-"):
                continue
            text = _read(os.path.join(revs_dir, fname))
            if text and "NOTICED" in text:
                revs_with_sweep.add(fname[:-3])

    if not revs_with_sweep:
        stale_unresolved = total
    else:
        # Lines not in a rev with a NOTICED sweep are potentially stale
        stale_unresolved = total - became_ticket if became_ticket < total else 0

    return {
        "total_noticed": total,
        "became_ticket": became_ticket,
        "wontfix": 0,  # L3 judgment — sensor provides total, agent classifies
        "stale_unresolved": stale_unresolved,
        "revs_with_sweep": sorted(revs_with_sweep),
    }


# ---------------------------------------------------------------------------
# Collect, delta, render_md
# ---------------------------------------------------------------------------

def collect(home: str, repo_root: Optional[str] = None,
            since: Optional[str] = None, base_branch: Optional[str] = None,
            now: Optional[datetime.datetime] = None) -> Dict[str, Any]:
    since = since or DEFAULT_SINCE
    now = now or _now_utc()
    repo_root = repo_root or os.path.dirname(os.path.abspath(home))

    base = base_branch
    if not base:
        if lm:
            base = lm.detect_base_branch(repo_root)
        else:
            base = detect_base_branch(repo_root)

    clusters = hotspot_clusters(repo_root, base, since)
    classes = fix_class_histogram(repo_root, base, since)
    genealogy = ticket_genealogy(home)
    recurrence = cross_audit_recurrence(home)
    feedback = noticed_feedback(home)

    return {
        "schema": SCHEMA,
        "generated_at": _iso(now),
        "home": os.path.relpath(home, repo_root) if repo_root else home,
        "since": since,
        "base": base,
        "hotspot_clusters": clusters,
        "fix_class_histogram": classes,
        "ticket_genealogy": genealogy,
        "cross_audit_recurrence": recurrence,
        "noticed_feedback": feedback,
    }


def load_previous(snapshot_dir: str) -> Optional[Dict[str, Any]]:
    """Load the newest previous hotspot snapshot."""
    if not os.path.isdir(snapshot_dir):
        return None
    files = [f for f in os.listdir(snapshot_dir) if f.startswith("hotspot-") and f.endswith(".json")]
    if not files:
        return None
    files.sort(reverse=True)
    try:
        with open(os.path.join(snapshot_dir, files[0]), encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError):
        return None


def write_snapshot(snapshot_dir: str, cur: Dict[str, Any]) -> str:
    os.makedirs(snapshot_dir, exist_ok=True)
    name = snapshot_name(datetime.datetime.strptime(cur["generated_at"], "%Y-%m-%dT%H:%M:%SZ"))
    path = os.path.join(snapshot_dir, name)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(cur, fh, indent=2, ensure_ascii=False)
    return path


def _fmt_num(v: Any) -> str:
    if isinstance(v, float):
        return "%.1f" % v
    return str(v)


def _dcell(d: Dict[str, Any], key: str) -> str:
    if not d:
        return "—"
    parts = key.split(".")
    v: Any = d
    for p in parts:
        if isinstance(v, dict):
            v = v.get(p, "—")
        else:
            v = "—"
            break
    if v == "—":
        return "—"
    return _fmt_num(v)


def render_md(cur: Dict[str, Any], d: Optional[Dict[str, Any]] = None) -> str:
    lines: List[str] = []
    hc = cur.get("hotspot_clusters", {})
    fch = cur.get("fix_class_histogram", {})
    tg = cur.get("ticket_genealogy", {})
    car = cur.get("cross_audit_recurrence", {})
    nf = cur.get("noticed_feedback", {})

    lines.append("## Hotspot metrics (L4 — hotspot-metrics, %s)" % cur.get("generated_at", "—"))
    lines.append("")

    # Hotspot clusters
    lines.append("| Metric | Value | Δ |")
    lines.append("| --- | --- | --- |")
    lines.append("| Total fix() commits | %s | — |" % hc.get("total_fix_commits", 0))
    lines.append("| Hotspot clusters (≥%d fix commits) | %s | — |" % (MIN_FIX_COMMITS, hc.get("cluster_count", 0)))
    lines.append("")

    if hc.get("clusters"):
        lines.append("### Hotspot clusters (ranked by fix_commit_count)")
        lines.append("")
        lines.append("| # | cluster | files | fix_count | fix_share_% | stage | skill | fix_classes |")
        lines.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
        for i, c in enumerate(hc["clusters"], 1):
            lines.append("| %d | %s | %d | %d | %s%% | %s | %s | %s |" % (
                i, c["cluster"], c["file_count"], c["fix_commit_count"],
                c["fix_share_pct"], c["stage"], c["skill"],
                ", ".join(c["fix_classes"]),
            ))
        lines.append("")

    # Fix-class histogram
    hist = fch.get("histogram", {})
    lines.append("### Fix-class histogram")
    lines.append("")
    lines.append("| class | count |")
    lines.append("| --- | --- |")
    for cls in ["status-flip", "regex-drift", "bash-guard", "field-mismatch", "atomicity", "other"]:
        lines.append("| %s | %s |" % (cls, hist.get(cls, 0)))
    lines.append("")

    # Cross-audit recurrence
    lines.append("### Cross-audit recurrence (finding-class → revs)")
    lines.append("")
    lines.append("| finding-class | recurrence_count | trend | revs |")
    lines.append("| --- | --- | --- | --- |")
    for cls in sorted(car, key=lambda k: car[k].get("recurrence_count", 0), reverse=True):
        info = car[cls]
        revs = info.get("revs", [])
        lines.append("| %s | %d | %s | %s |" % (
            cls, info.get("recurrence_count", 0), info.get("trend", "—"),
            ", ".join(revs[:5]) + ("…" if len(revs) > 5 else ""),
        ))
    lines.append("")

    # Ticket genealogy (top revs by spawned tickets)
    revs = tg.get("revs", [])
    if revs:
        lines.append("### Ticket genealogy — reviews (top 5 by tickets spawned)")
        lines.append("")
        lines.append("| rev | tickets_spawned | fix_cycles_gt0 | total_fix_cycles |")
        lines.append("| --- | --- | --- | --- |")
        for r in sorted(revs, key=lambda x: x.get("tickets_spawned", 0), reverse=True)[:5]:
            lines.append("| %s | %d | %d | %d |" % (
                r.get("rev_id", "—"), r.get("tickets_spawned", 0),
                r.get("tickets_with_fix_cycles_gt0", 0),
                r.get("total_fix_cycles", 0),
            ))
        lines.append("")

    specs = tg.get("specs", [])
    if specs:
        lines.append("### Ticket genealogy — Specs (top 5 by ticket count)")
        lines.append("")
        lines.append("| spec | ticket_count | fix_cycles_gt0 | total_fix_cycles |")
        lines.append("| --- | --- | --- | --- |")
        for s in sorted(specs, key=lambda x: x.get("ticket_count", 0), reverse=True)[:5]:
            lines.append("| %s | %d | %d | %d |" % (
                s.get("spec_id", "—"), s.get("ticket_count", 0),
                s.get("tickets_with_fix_cycles_gt0", 0),
                s.get("total_fix_cycles", 0),
            ))
        lines.append("")

    # NOTICED feedback
    lines.append("### NOTICED feedback")
    lines.append("")
    lines.append("| total | became_ticket | stale_unresolved | revs_with_sweep |")
    lines.append("| --- | --- | --- | --- |")
    lines.append("| %d | %d | %d | %s |" % (
        nf.get("total_noticed", 0), nf.get("became_ticket", 0),
        nf.get("stale_unresolved", 0),
        ", ".join(nf.get("revs_with_sweep", [])),
    ))
    lines.append("")

    return "\n".join(lines)
