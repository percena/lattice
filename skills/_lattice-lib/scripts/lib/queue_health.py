"""Queue-health water-level sensor (spc-186 A5, ADR-007 §8).

Advisory-only staleness surfacing for the morning digest + start-work entry
banner. This is a **sensor**, not a red line — it never blocks (ADR-007 §8:
escape metrics / boundary sensor family). Its job is to eliminate the
silent-degradation channel: pr-open piles up silently when triage is skipped,
and deferred/stuck/parked have no water-level.

Water-level states (the pile-up set): parked + stuck + deferred. These hold
the pipeline back and are trip-time-stamped (tkt-136/137/190) — morning triage
is their adjudication venue. `rework` is excluded: it is an active-work state
(PR returned with findings), not a pile-up state. `pr-open` age is surfaced
separately (a night-opened PR waiting indefinitely if triage is skipped has no
escalation path otherwise — rev-20260829-160834Z F4a).

Age computation (spc-186 A4 / tkt-191 dependency):
  - Primary source: the binder `updated` field-table row (bumped atomically
    with each status transition by stamp-pr-open / finish-ledger / ratify).
    For a pr-open binder, `updated` = when it was stamped to pr-open; for a
    side-state binder, `updated` = when it entered that side state.
  - Lazy migration: a binder predating the `updated` row (tkt-191) has no
    age from the binder. For pr-open binders, fall back to `gh pr view <N>
    --json createdAt` (the GitHub PR openedAt — a faithful proxy for when the
    binder was stamped pr-open, since stamp-pr-open runs right after
    `gh pr create`). Side-state binders without `updated` report age
    "unknown" (no gh fallback — the side state was stamped by batch-work /
    spec-supersede, not gh).

Thresholds are config-tunable via `.lattice/config.yaml` under `queue_health:`
(flat-key reader, no PyYAML — same posture as ci_failure_classify.py).
Defaults: pr_open_hours=36, side_state_total=5.

This module is dependency-free so consumer repos can vendor it alone.
"""

from __future__ import annotations

import datetime
import glob
import json
import os
import re
import sys
from typing import Dict, List, Optional, Tuple

# Water-level side states (the pile-up set). Excludes `rework` (active work).
# parked = irreversible/cross-contract decision pending (morning ratification)
# stuck  = needs human investigation (operator-chosen exit)
# deferred = fuse-halt / blocked-by-failure / spec-superseded (trip-time)
WATER_LEVEL_STATES = frozenset({"parked", "stuck", "deferred"})

# Default thresholds (spc-186 A5). Tunable via .lattice/config.yaml queue_health:.
DEFAULT_THRESHOLDS: Dict[str, int] = {
    "pr_open_hours": 36,       # pr-open age beyond this flagged in the digest
    "side_state_total": 5,     # parked+stuck+deferred count beyond this flagged
}

# Field-table row regex: `| field | value |` → captures field name + value.
_FIELD_ROW_RE = re.compile(r"^\|\s*(?P<field>[A-Za-z_]+)\s*\|\s*(?P<value>.*?)\s*\|\s*$")

# PR number extraction from the binder `prs` row: first `pr-N` token.
_PR_NUM_RE = re.compile(r"\bpr-([1-9][0-9]*)\b")


def load_thresholds(home_dir: Optional[str] = None) -> Dict[str, int]:
    """Load queue_health thresholds from .lattice/config.yaml.

    Falls back to DEFAULT_THRESHOLDS when the file or section is absent.
    Minimal flat-key reader (no PyYAML) — same posture as ci_failure_classify.
    """
    t = dict(DEFAULT_THRESHOLDS)
    if not home_dir:
        return t
    config_path = os.path.join(home_dir, "config.yaml")
    if not os.path.isfile(config_path):
        return t
    try:
        with open(config_path, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return t
    in_block = False
    for line in text.splitlines():
        stripped = line.rstrip()
        if not stripped or stripped.lstrip().startswith("#"):
            continue
        # Enter the queue_health: block (top-level key).
        if re.match(r"^queue_health\s*:", stripped):
            in_block = True
            continue
        # Exit when a new top-level key appears (column 0, non-space).
        if in_block and re.match(r"^\S", stripped):
            in_block = False
            continue
        if not in_block:
            continue
        # Inside queue_health: look for `  key: value` pairs.
        m = re.match(r"^\s{2,}(\w+)\s*:\s*(\d+)\s*$", stripped)
        if m and m.group(1) in t:
            t[m.group(1)] = int(m.group(2))
    return t


def _parse_field_rows(text: str) -> Dict[str, str]:
    """Parse binder field-table rows into a {field: value} dict."""
    rows: Dict[str, str] = {}
    for line in text.splitlines():
        m = _FIELD_ROW_RE.match(line)
        if m:
            rows[m.group("field")] = m.group("value").strip()
    return rows


def _parse_iso(ts: str) -> Optional[datetime.datetime]:
    """Parse an ISO-8601 UTC timestamp (YYYY-MM-DDTHH:MM:SSZ or YYYY-MM-DD).

    Returns a timezone-aware UTC datetime, or None when unparseable.
    Accepts the binder's date-only `created` form (YYYY-MM-DD) too — the
    validator stamps `created` at seconds precision, but historical / hand
    binders may carry only a date; for age-banding that precision is enough.
    """
    ts = ts.strip()
    if not ts:
        return None
    for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d"):
        try:
            dt = datetime.datetime.strptime(ts, fmt)
            return dt.replace(tzinfo=datetime.timezone.utc)
        except ValueError:
            continue
    return None


def _age_hours(now: datetime.datetime, then: datetime.datetime) -> float:
    """Elapsed hours from `then` to `now` (both UTC-aware)."""
    return (now - then).total_seconds() / 3600.0


def _find_binders(tickets_dir: str) -> List[Tuple[str, str]]:
    """Return [(tkt_id, binder_path)] for every tkt-N-*/README.md under tickets_dir."""
    out: List[Tuple[str, str]] = []
    if not os.path.isdir(tickets_dir):
        return out
    for name in sorted(os.listdir(tickets_dir)):
        m = re.match(r"^(tkt-[1-9][0-9]*)", name)
        if not m:
            continue
        binder = os.path.join(tickets_dir, name, "README.md")
        if os.path.isfile(binder):
            out.append((m.group(1), binder))
    return out


def scan_binders(
    tickets_dir: str,
    now: Optional[datetime.datetime] = None,
    gh_fallback: Optional[object] = None,
) -> Dict[str, object]:
    """Scan all ticket binders and compute water-level data.

    Args:
      tickets_dir: path to .lattice/tickets/
      now: UTC now (defaults to datetime.now(utc)); injectable for tests.
      gh_fallback: optional callable(pr_n:int) -> ISO-8601 str for the pr-open
        createdAt fallback (lazy migration). None = no gh fallback; the
        queue-health script wires the real gh call here.

    Returns a dict:
      {
        "side_states": [ {ticket, status, age_hours, updated, wait_reason} ],
        "pr_open":     [ {ticket, pr_n, age_hours, updated, source} ],
        "side_state_total": int,
        "scanned": int,            # binders scanned
      }
    Ages are None when the timestamp is absent/unparseable (lazy migration).
    """
    if now is None:
        now = datetime.datetime.now(datetime.timezone.utc)

    side_states: List[Dict[str, object]] = []
    pr_open: List[Dict[str, object]] = []
    scanned = 0
    # spc-337 A1 / ADR-012 §4 — ledger coverage is the conformance sensor:
    # terminal binders without a per-ticket transition ledger, and the number
    # of direct-jump terminal edges (queued|in-progress → closed on a merge).
    ledger_dir = os.path.join(os.path.dirname(os.path.abspath(tickets_dir)), ".transition-ledger")
    terminal = 0
    terminal_with_ledger = 0
    missing_ledger: List[str] = []
    direct_jumps = 0

    for tkt_id, binder_path in _find_binders(tickets_dir):
        scanned += 1
        try:
            with open(binder_path, encoding="utf-8") as fh:
                text = fh.read()
        except OSError:
            continue
        fields = _parse_field_rows(text)
        status = fields.get("status", "").strip()
        updated_raw = fields.get("updated", "").strip()
        wait_reason = fields.get("wait_reason", "").strip()

        if status == "closed":
            terminal += 1
            lp = os.path.join(ledger_dir, f"{tkt_id}.jsonl")
            legacy = glob.glob(os.path.join(ledger_dir, f"{tkt_id}-*.jsonl"))
            if os.path.isfile(lp) or legacy:
                terminal_with_ledger += 1
                direct_jumps += _count_direct_jumps(lp if os.path.isfile(lp) else legacy[0])
            else:
                missing_ledger.append(tkt_id)

        if status in WATER_LEVEL_STATES:
            age = None
            updated_dt = _parse_iso(updated_raw) if updated_raw else None
            if updated_dt:
                age = round(_age_hours(now, updated_dt), 1)
            side_states.append({
                "ticket": tkt_id,
                "status": status,
                "age_hours": age,
                "updated": updated_raw or None,
                "wait_reason": wait_reason or None,
            })
        elif status == "pr-open":
            pr_n_str = fields.get("prs", "")
            pr_match = _PR_NUM_RE.search(pr_n_str)
            pr_n = int(pr_match.group(1)) if pr_match else None
            age = None
            source = None
            updated_dt = _parse_iso(updated_raw) if updated_raw else None
            if updated_dt:
                age = round(_age_hours(now, updated_dt), 1)
                source = "binder.updated"
            elif pr_n is not None and gh_fallback is not None:
                opened = gh_fallback(pr_n)
                if opened:
                    opened_dt = _parse_iso(opened)
                    if opened_dt:
                        age = round(_age_hours(now, opened_dt), 1)
                        source = "gh.pr.createdAt"
            pr_open.append({
                "ticket": tkt_id,
                "pr_n": pr_n,
                "age_hours": age,
                "updated": updated_raw or None,
                "source": source,
            })

    return {
        "side_states": side_states,
        "pr_open": pr_open,
        "side_state_total": len(side_states),
        "scanned": scanned,
        "ledger_coverage": {
            "terminal": terminal,
            "with_ledger": terminal_with_ledger,
            "missing": sorted(missing_ledger),
            "direct_jumps": direct_jumps,
        },
    }


def _count_direct_jumps(ledger_path: str) -> int:
    """Count ledger entries whose metric is `direct-jump` (a merge observed
    from queued/in-progress — the intermediate stamps were skipped; spc-337 A2).
    Malformed lines are ignored (the validator owns malformed-ledger errors)."""
    n = 0
    try:
        with open(ledger_path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    e = json.loads(line)
                except ValueError:
                    continue
                # A direct jump is a MERGE from queued/in-progress; a cancel on
                # the same edge is not (review cycle 1 of spc-337 A2).
                if (
                    e.get("to") == "closed"
                    and e.get("from") in ("queued", "in-progress")
                    and "merge" in str(e.get("reason", ""))
                ):
                    n += 1
    except OSError:
        pass
    return n


def format_banner(data: Dict[str, object], thresholds: Dict[str, int]) -> str:
    """One-line water-level banner for start-work entry.

    Empty string when the queue is clean. Per the binder AC, the banner fires
    when **any** side-state pile-up exists (side_state_total > 0 — even one
    parked/stuck/deferred is worth surfacing at entry) or a pr-open binder is
    stale beyond the `pr_open_hours` threshold. The `side_state_total`
    threshold (default 5) gates the digest's OVER flag, not the banner —
    start-work is the quick-entry nudge, the digest is the detailed report.
    Advisory only — never blocks (ADR-007 §8 sensor posture).
    """
    side_total: int = data["side_state_total"]  # type: ignore[assignment]
    pr_open_list: List[Dict[str, object]] = data["pr_open"]  # type: ignore[assignment]
    pr_open_hours = thresholds["pr_open_hours"]
    side_thresh = thresholds["side_state_total"]

    stale_pr_open = [
        p for p in pr_open_list
        if p["age_hours"] is not None and p["age_hours"] > pr_open_hours
    ]
    parts: List[str] = []
    if side_total > 0:
        parts.append(
            f"{side_total} parked/stuck/deferred (threshold {side_thresh})"
        )
    if stale_pr_open:
        parts.append(f"{len(stale_pr_open)} pr-open > {pr_open_hours}h")
    if not parts:
        return ""
    return "water-level: " + " · ".join(parts) + " — triage advised (ADR-007 §8 sensor)"


def format_section(data: Dict[str, object], thresholds: Dict[str, int]) -> str:
    """Detailed "Queue health" section for the review-delivery morning digest.

    Always emitted (zero rows is a valid good result — state it, don't skip).
    """
    side_states: List[Dict[str, object]] = data["side_states"]  # type: ignore[assignment]
    pr_open_list: List[Dict[str, object]] = data["pr_open"]  # type: ignore[assignment]
    side_total: int = data["side_state_total"]  # type: ignore[assignment]
    scanned: int = data["scanned"]  # type: ignore[assignment]
    pr_open_hours = thresholds["pr_open_hours"]
    side_thresh = thresholds["side_state_total"]

    lines: List[str] = []
    lines.append("## Queue health (staleness water-level — spc-186 A5, ADR-007 §8)")
    lines.append("")
    lines.append(
        f"> Advisory sensor — never a HARD block. {scanned} binder(s) scanned. "
        f"Thresholds: pr-open > {pr_open_hours}h · side-state total > {side_thresh}."
    )
    lines.append("")

    # Side-state water levels (parked/stuck/deferred) with ages.
    lines.append(f"### Side-state water levels (parked/stuck/deferred) — {side_total} total")
    if side_states:
        over = side_total > side_thresh
        flag = " ⚠ OVER" if over else ""
        lines.append(f"**Count: {side_total} (threshold {side_thresh}){flag}**")
        lines.append("")
        lines.append("| Ticket | Status | Age (h) | Updated | Wait reason |")
        lines.append("| --- | --- | --- | --- | --- |")
        # Sort: oldest first (None ages last), so the stalest pile-up leads.
        for s in sorted(
            side_states,
            key=lambda d: (d["age_hours"] is None, -(d["age_hours"] or 0)),
        ):
            age = "unknown" if s["age_hours"] is None else f"{s['age_hours']}"
            upd = s["updated"] or "(no row)"
            wr = s["wait_reason"] or "(none)"
            lines.append(f"| {s['ticket']} | {s['status']} | {age} | {upd} | {wr} |")
    else:
        lines.append(f"**Count: 0 (threshold {side_thresh}) — no pile-up.**")
    lines.append("")

    # pr-open aging.
    stale_pr_open = [
        p for p in pr_open_list
        if p["age_hours"] is not None and p["age_hours"] > pr_open_hours
    ]
    lines.append(f"### pr-open aging — {len(pr_open_list)} open, {len(stale_pr_open)} beyond {pr_open_hours}h")
    if pr_open_list:
        lines.append("")
        lines.append("| Ticket | PR | Age (h) | Source |")
        lines.append("| --- | --- | --- | --- |")
        for p in sorted(
            pr_open_list,
            key=lambda d: (d["age_hours"] is None, -(d["age_hours"] or 0)),
        ):
            pr = f"pr-{p['pr_n']}" if p["pr_n"] is not None else "?"
            age = "unknown" if p["age_hours"] is None else f"{p['age_hours']}"
            src = p["source"] or "(no timestamp)"
            flag = " ⚠" if (p["age_hours"] is not None and p["age_hours"] > pr_open_hours) else ""
            lines.append(f"| {p['ticket']} | {pr} | {age}{flag} | {src} |")
    else:
        lines.append("No pr-open binders.")
    lines.append("")
    # Ledger coverage (spc-337 A1 / ADR-012 §4) — conformance sensor.
    cov = data.get("ledger_coverage") or {}
    if cov:
        t = int(cov.get("terminal", 0)); w = int(cov.get("with_ledger", 0))
        missing = list(cov.get("missing") or [])
        dj = int(cov.get("direct_jumps", 0))
        pct = f" ({100.0 * w / t:.0f}%)" if t else ""
        lines.append(f"### Ledger coverage — {w}/{t} terminal binders with a transition ledger{pct} · direct jumps: {dj}")
        if missing:
            shown = ", ".join(missing[:10]) + (f" … (+{len(missing) - 10})" if len(missing) > 10 else "")
            lines.append(f"Missing ledger: {shown} — legacy binders are baselined; a post-cutoff miss is a validator error (`closed_without_ledger`).")
        else:
            lines.append("Every terminal binder carries a ledger.")
        lines.append("")
    lines.append(
        "_Source: binder `updated` (tkt-191) for age; `gh pr view` createdAt "
        "fallback for pr-open binders predating the row (lazy migration); "
        "`.transition-ledger/*.jsonl` for coverage and direct jumps (spc-337)._"
    )
    return "\n".join(lines)
