#!/usr/bin/env python3
"""Transition API — the single chokepoint status writers go through to flip a
ticket binder status (spc-254 A3 / D5; rev-20260830-141357Z F2).

Why a single API: the three writers (reconcile-state.sh, finish-ledger.sh,
stamp-pr-open.sh) previously each stamped `status:` directly, so edge
legality was enforced only by per-script discipline. This API:

  1. validates the (from, to) edge against lib/transition_table.py (the SoT);
  2. for side-state-guard edges, requires an operator-adjudicated
     --force-side-state-reason (rejects without it — no agent self-adjudication);
  3. appends a structured JSONL entry to the transition ledger
     (.lattice/.transition-ledger.jsonl) so the validator can replay history
     and reject an illegal edge between two legal snapshots (A3).

Exit codes:
  0  transition recorded (or --dry-run legal)
  1  ILLEGAL edge (not in schema) — refused
  2  edge legal ONLY via escape, but no --force-side-state-reason given
  3  usage / io error

Usage:
  python3 transition-api.py record <ticket-id> <from> <to> <owner> <reason> \
      [--force-side-state-reason <text>] [--trace <text>] [--dry-run]
  python3 transition-api.py legal <from> <to>   # exit 0 legal, 1 illegal
  python3 transition-api.py replay-ledger      # prints ledger replay summary
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

# Resolve the lib sibling so this works whether invoked from a skill cwd or a
# worktree root. sys.path[0] is this file's dir.
_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE))
from lib import transition_table as tt  # noqa: E402


def ledger_path() -> Path:
    home = os.environ.get("LATTICE_HOME", ".lattice")
    return Path(home) / ".transition-ledger.jsonl"


def cmd_legal(args: list) -> int:
    if len(args) != 2:
        print("usage: transition-api.py legal <from> <to>", file=sys.stderr)
        return 3
    frm, to = args
    legal = tt.is_legal_edge(frm, to)
    print(f"{'legal' if legal else 'ILLEGAL'}: {frm} -> {to}")
    return 0 if legal else 1


def cmd_record(args: list) -> int:
    if len(args) < 5:
        print("usage: transition-api.py record <ticket-id> <from> <to> "
              "<owner> <reason> [--force-side-state-reason <text>] "
              "[--trace <text>] [--dry-run]", file=sys.stderr)
        return 3
    ticket, frm, to, owner, reason = args[:5]
    rest = args[5:]
    force_reason = None
    trace_override = None
    dry = False
    i = 0
    while i < len(rest):
        if rest[i] == "--force-side-state-reason" and i + 1 < len(rest):
            force_reason = rest[i + 1]; i += 2
        elif rest[i] == "--trace" and i + 1 < len(rest):
            trace_override = rest[i + 1]; i += 2
        elif rest[i] == "--dry-run":
            dry = True; i += 1
        else:
            print(f"unknown arg: {rest[i]}", file=sys.stderr); return 3

    if not tt.is_legal_edge(frm, to):
        e = tt.edge_for(frm, to)
        print(f"ILLEGAL transition: {frm} -> {to} "
              f"(not in schema; refused)", file=sys.stderr)
        return 1
    if tt.requires_escape(frm, to) and not force_reason:
        print(f"ILLEGAL without operator override: {frm} -> {to} "
              f"requires --force-side-state-reason (side-state guard; "
              f"no agent self-adjudication)", file=sys.stderr)
        return 2

    edge = tt.edge_for(frm, to)
    entry = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "ticket": ticket,
        "from": frm,
        "to": to,
        "owner": owner,
        "reason": reason,
        "guard": edge.guard,
        "escape_used": force_reason is not None,
        "force_side_state_reason": force_reason,
        "trace": trace_override or (edge.trace if edge else None),
        "metric": edge.metric if edge else None,
    }
    if dry:
        print(json.dumps(entry, indent=2))
        return 0
    lp = ledger_path()
    lp.parent.mkdir(parents=True, exist_ok=True)
    with lp.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry, separators=(",", ":")) + "\n")
    print(f"recorded: {ticket} {frm} -> {to} ({owner})")
    return 0


def cmd_replay(args: list) -> int:
    """Replay the ledger and report any illegal (from,to) pair. Used by the
    validator; exit 0 = all entries legal, 1 = at least one illegal edge."""
    lp = ledger_path()
    if not lp.exists():
        print(f"no ledger at {lp}", file=sys.stderr)
        return 0  # no ledger = nothing to replay (not an error)
    bad = 0
    total = 0
    for lineno, line in enumerate(lp.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        total += 1
        try:
            entry = json.loads(line)
        except json.JSONDecodeError as exc:
            print(f"ledger:{lineno}: malformed JSON: {exc}", file=sys.stderr)
            bad += 1
            continue
        frm, to = entry.get("from", ""), entry.get("to", "")
        if not tt.is_legal_edge(frm, to):
            print(f"ledger:{lineno}: ILLEGAL edge {frm} -> {to} "
                  f"(ticket {entry.get('ticket', '?')})", file=sys.stderr)
            bad += 1
            continue
        if tt.requires_escape(frm, to) and not entry.get("force_side_state_reason"):
            print(f"ledger:{lineno}: ILLEGAL escape-required edge {frm} -> {to} "
                  f"without operator override (ticket {entry.get('ticket', '?')})",
                  file=sys.stderr)
            bad += 1
    print(f"replay: {total} entries, {bad} illegal")
    return 1 if bad else 0


def main(argv: list) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 3
    cmd, rest = argv[1], argv[2:]
    if cmd == "legal":
        return cmd_legal(rest)
    if cmd == "record":
        return cmd_record(rest)
    if cmd == "replay-ledger":
        return cmd_replay(rest)
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv))
