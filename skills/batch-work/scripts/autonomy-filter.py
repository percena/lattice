#!/usr/bin/env python3
"""autonomy-filter.py — the scripted step behind batch-work `--min-autonomy`
(spc-433 A2 / tkt-461 A10).

Reads each ticket binder's `| autonomy | N |` row (0-4, autonomy-rubric.md)
and partitions the requested ticket ids into `selected` (autonomy >= threshold)
and `skipped` (never-spawned reason `autonomy-below-threshold`; the binder is
left `queued` — still schedulable day-interactive). A binder without the row
scores 2 (medium, the rubric default); `--min-autonomy 0` disables the filter.

Advisory sensor: exit 0 with JSON on stdout, even when nothing is selected.
Exit 2 only on usage errors. Python 3.8+ stdlib only.

Usage:
  autonomy-filter.py --min-autonomy N [--home <lattice-home>] tkt-A [tkt-B …]
  autonomy-filter.py --min-autonomy N --home .lattice --all

Output:
  {"min_autonomy": N, "selected": ["tkt-A"], "skipped": [{"id": "tkt-B",
   "autonomy": 1, "reason": "autonomy-below-threshold"}], "missing_binder": [...]}
"""
import argparse
import glob
import json
import os
import re
import sys

DEFAULT_AUTONOMY = 2  # autonomy-rubric.md: "Default: 2 (medium)"
AUTONOMY_ROW_RE = re.compile(r"^\|\s*autonomy\s*\|\s*([^|]*?)\s*\|", re.M)


def first_table_block(text):
    """The binder card is the first |-prefixed block; later example tables
    must not shadow it (same rule as validate-lattice-artifacts.py)."""
    out, started = [], False
    for line in text.splitlines():
        if line.lstrip().startswith("|"):
            started = True
            out.append(line)
        elif started:
            break
    return "\n".join(out)


def binder_for(home, ticket):
    hits = sorted(glob.glob(os.path.join(home, "tickets", f"{ticket}-*", "README.md")))
    return hits[0] if len(hits) == 1 else None


def autonomy_of(binder_path):
    """Return (score, source) — source is 'row' or 'default'."""
    try:
        with open(binder_path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return DEFAULT_AUTONOMY, "default"
    m = AUTONOMY_ROW_RE.search(first_table_block(text))
    if not m:
        return DEFAULT_AUTONOMY, "default"
    val = m.group(1).strip()
    if re.fullmatch(r"[0-4]", val):
        return int(val), "row"
    return DEFAULT_AUTONOMY, "default"  # malformed row: the validator flags it


def main(argv=None):
    p = argparse.ArgumentParser(description="batch-work --min-autonomy filter (spc-433).")
    p.add_argument("--min-autonomy", type=int, required=True,
                   help="0-4; tickets below this stay queued (0 disables)")
    p.add_argument("--home", default=os.environ.get("LATTICE_HOME", ".lattice"))
    p.add_argument("--all", action="store_true", help="every tkt-N binder under --home/tickets")
    p.add_argument("tickets", nargs="*", help="tkt-N ids (or bare N)")
    a = p.parse_args(argv)
    if not (0 <= a.min_autonomy <= 4):
        print("autonomy-filter: --min-autonomy must be 0-4", file=sys.stderr)
        return 2
    ids = []
    if a.all:
        for d in sorted(glob.glob(os.path.join(a.home, "tickets", "tkt-*"))):
            m = re.match(r"^(tkt-\d+)-", os.path.basename(d))
            if m and os.path.isfile(os.path.join(d, "README.md")):
                ids.append(m.group(1))
    for t in a.tickets:
        ids.append(f"tkt-{t}" if t.isdigit() else t)
    if not ids:
        print("autonomy-filter: no ticket ids (pass tkt-N… or --all)", file=sys.stderr)
        return 2
    out = {"min_autonomy": a.min_autonomy, "selected": [], "skipped": [], "missing_binder": []}
    for t in ids:
        b = binder_for(a.home, t)
        if b is None:
            out["missing_binder"].append(t)
            continue
        score, src = autonomy_of(b)
        if a.min_autonomy == 0 or score >= a.min_autonomy:
            out["selected"].append(t)
        else:
            out["skipped"].append({"id": t, "autonomy": score, "source": src,
                                   "reason": "autonomy-below-threshold"})
    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
