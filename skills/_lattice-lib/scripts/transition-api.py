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
  0  transition recorded (or --dry-run legal/no-op)
  1  ILLEGAL edge (not in schema) — refused
  2  edge legal ONLY via escape, but no --force-side-state-reason given
  3  usage / io error / transaction aborted (fail-close; nothing written)

Usage:
  python3 transition-api.py commit <ticket-id> <to> <owner> <reason> \
      [--from <expected>] [--wait-reason <r>] [--force-side-state-reason <text>] \
      [--trace <text>] [--append-journal <text>] [--binder <path>] [--dry-run]
      # Atomic binder-bound transition (spc-270 A1.1): locks the binder dir,
      # reads the real prior status, validates the edge + escape + coupled
      # wait_reason, then rewrites status/wait_reason/updated AND appends one
      # ledger entry in one transaction. Canonical writers route here (A1.3).
      # --append-journal writes a structured Decision-journal bullet in the SAME
      # transaction (a crash before commit leaves no trace → no duplicate).
  python3 transition-api.py record <ticket-id> <from> <to> <owner> <reason> \
      [--force-side-state-reason <text>] [--trace <text>] [--dry-run]
      # Ledger-only primitive (no binder mutation); kept for non-canonical /
      # test callers. `from` is caller-supplied and NOT continuity-checked.
  python3 transition-api.py legal <from> <to>   # exit 0 legal, 1 illegal
  python3 transition-api.py replay-ledger      # identity + continuity +
      # snapshot replay (spc-270 A1.4): prints summary, exit 1 on any
      # illegal / discontinuous / identity-mismatch / snapshot-mismatch record
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
import fcntl
import subprocess
import tempfile
from pathlib import Path

# Resolve the lib sibling so this works whether invoked from a skill cwd or a
# worktree root. sys.path[0] is this file's dir.
_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE))
from lib import transition_table as tt  # noqa: E402
from lib import status_vocab as sv  # noqa: E402
from lib import binder_rows  # noqa: E402


def home_for_binder(binder: "Path | str | None") -> "Path | None":
    """The Lattice home that OWNS a binder: `<home>/tickets/<tkt-dir>/README.md`
    -> `<home>` (spc-337 A1 / ADR-012 sec.4). Returns None when the path is not
    shaped like a binder (callers fall back to the env/cwd home)."""
    if not binder:
        return None
    b = Path(binder)
    if b.name == "README.md" and b.parent.parent.name == "tickets":
        return b.parent.parent.parent
    return None


def ledger_path(ticket: str, home: "Path | str | None" = None) -> Path:
    """Per-ticket committed ledger file (spc-254 review F2): a single shared
    gitignored ledger made CI's replay a no-op (the file never existed on a
    fresh checkout). Per-ticket files under .lattice/.transition-ledger/ are
    committed alongside the binder stamp, so CI accumulates them and the
    replay enforces edge legality for real. Per-ticket avoids cross-ticket
    merge conflicts on parallel worktrees.

    Resolution order (spc-337 A1): an explicit `home` (the binder's own home,
    from `home_for_binder`) wins; else `LATTICE_HOME`; else `.lattice` under
    the current directory. Before spc-337 the ledger was ALWAYS resolved from
    cwd while every writer staged it from the binder path, so a stamp run from
    a non-toplevel cwd silently lost its ledger (tkt-335)."""
    if home is None:
        home = os.environ.get("LATTICE_HOME", ".lattice")
    return Path(home) / ".transition-ledger" / f"{ticket}.jsonl"


def resolve_record_home(home_override: "str | None" = None) -> str:
    """Resolve the Lattice home for the ledger-only `record` primitive (the
    one writer with no binder to anchor it; ADR-012 §4 / tkt-352).

    Order: an explicit `--home <path>` → `LATTICE_HOME` →
    `<git show-toplevel>/.lattice` (never bare cwd inside a repo, so a `record`
    run from a non-toplevel subdir still lands the entry under the repo's
    `.lattice`). Falls back to `.lattice` under cwd only outside a git worktree
    (preserves the pre-tkt-352 behaviour for bare-cwd manual backstops)."""
    if home_override:
        return home_override
    env = os.environ.get("LATTICE_HOME")
    if env:
        return env
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5,
        )
        if out.returncode == 0 and out.stdout.strip():
            return str(Path(out.stdout.strip()) / ".lattice")
    except Exception:
        pass
    return ".lattice"


def resolve_state_home() -> str:
    """Resolve the out-of-repo runtime state dir (ADR-011 / spc-282 A2).

    The .jsonl ledger STAYS committed in-repo, but its flock .lock sidecar
    relocates OUT OF REPO so it never leaks as untracked dirt in a fresh
    customer repo. Keyed by repo fingerprint so same-clone concurrent
    recorders still serialize on one lock."""
    import hashlib
    override = os.environ.get("LATTICE_BATCH_GATE_HOME") or os.environ.get("LATTICE_STATE_HOME")
    if override:
        return override
    helper = _HERE / "lattice-state-home.sh"
    if helper.is_file():
        try:
            out = subprocess.run(
                ["bash", str(helper)], capture_output=True, text=True, timeout=5
            )
            if out.returncode == 0 and out.stdout.strip():
                return out.stdout.strip()
        except Exception:
            pass
    try:
        git_common = subprocess.run(
            ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
            capture_output=True, text=True, timeout=5,
        ).stdout.strip()
    except Exception:
        git_common = ""
    if not git_common:
        # Fallback: co-located lock (legacy behavior) so the API never deadlocks
        # a legitimate transition when the state home is unresolvable.
        return ""
    fp = hashlib.sha1(git_common.encode()).hexdigest()[:12]
    root = os.environ.get("XDG_STATE_HOME") or os.path.join(
        os.environ.get("HOME", ""), ".local", "state"
    )
    home = os.path.join(root, "lattice", fp)
    try:
        os.makedirs(home, exist_ok=True)
    except OSError:
        pass
    return home


def lock_path(ticket: str, ledger_home: "Path | str | None" = None) -> Path:
    """Flock sidecar for the per-ticket ledger. Per ADR-011 / spc-282 A2 the
    .lock lives OUT OF REPO (state home) so it does not leak; the .jsonl it
    guards stays committed in-repo. Returns a state-home path when resolvable,
    else the legacy co-located .jsonl.lock (never deadlocks a transition).
    `ledger_home` (spc-337 A1) is the binder's own home so the co-located
    fallback never lands under a foreign cwd either."""
    home = resolve_state_home()
    if home:
        return Path(home) / ".transition-ledger" / f"{ticket}.lock"
    # Legacy fallback: co-located with the ledger (pre-ADR-011 behavior).
    return ledger_path(ticket, ledger_home).with_suffix(".jsonl.lock")


def _binder_for_ticket(ticket: str, override: str | None = None) -> Path | None:
    """Resolve a ticket's binder README from its ticket-id (spc-270 A1.1).

    `--binder <path>` short-circuits discovery. Otherwise the binder is the
    single `tkt-<id>-*` directory under LATTICE_HOME/tickets/. Returns None
    when no binder exists (a `commit` against a missing binder fails closed
    by the caller — never silently fabricates a flip)."""
    if override:
        return Path(override)
    home = Path(os.environ.get("LATTICE_HOME", ".lattice"))
    tickets_dir = home / "tickets"
    if not tickets_dir.is_dir():
        return None
    # tkt-<id>-<slug>/README.md — match the id segment exactly.
    pat = re.compile(rf"^{re.escape(ticket)}-[^\s/]+$")
    matches = [d for d in tickets_dir.iterdir() if d.is_dir() and pat.match(d.name)]
    if len(matches) != 1:
        return None
    binder = matches[0] / "README.md"
    return binder if binder.is_file() else None


# Field-table row readers/writers (spc-270 A1.1). A binder field row is
# `| <name> | <value> |`. The cell value may be a placeholder like `(none)`.
_FIELD_RE_TMPL = r"(?m)^\| {name} \| (.+?) \|"


def _read_field(text: str, name: str) -> str | None:
    m = re.search(_FIELD_RE_TMPL.format(name=re.escape(name)), text)
    return m.group(1).strip() if m else None


def _rewrite_field(text: str, name: str, value: str) -> str:
    """Replace a field row's cell. Returns text unchanged when the row is
    absent (lazy migration — `commit` never inserts rows a binder lacks;
    status_vocab/updated are present on every binder created by the template)."""
    pat = re.compile(_FIELD_RE_TMPL.format(name=re.escape(name)))
    if not pat.search(text):
        return text
    return pat.sub(lambda m: f"| {name} | {value} |", text, count=1)


def _append_journal_trace(text: str, entry: str) -> str:
    """Append one dated bullet to `## Decision journal`, creating the section
    if absent (mirrors the append_journal_trace embedded in each writer's
    python heredoc). Used by `commit --append-journal` so a writer's structured
    trace lands in the SAME atomic transaction as the status flip + ledger
    (spc-270 A1.3): a crash before `commit` leaves no journal entry, so a
    re-run appends it exactly once (no duplicate-trace regression). Returns
    text unchanged when `entry` is empty/None."""
    if not entry:
        return text
    m_hdr = re.search(r"^## Decision journal[ \t]*\n", text, re.MULTILINE)
    if m_hdr:
        body_start = m_hdr.end()
        tail = text[body_start:]
        bnd = re.search(r"\n## ", tail)
        body = tail[: bnd.start()] if bnd else tail
        trailing = tail[bnd.start():] if bnd else ""
        stripped = body.strip("\n")
        new_body = (stripped + "\n" + entry + "\n") if stripped else (entry + "\n")
        return text[:body_start] + "\n" + new_body + trailing
    # No journal section: insert one before the first standard tail section,
    # else at EOF (keeps the binder well-formed).
    anchor = re.search(
        r"\n(## (?:Notes|References|Lineage|Finish|Pending decisions|Attempts)\b)",
        text,
    )
    block = f"\n## Decision journal\n\n{entry}\n"
    if anchor:
        return text[: anchor.start()] + block + text[anchor.start():]
    return text.rstrip("\n") + "\n" + block


def _ensure_wait_reason_row(text: str, value: str) -> str:
    """Insert a `| wait_reason | <value> |` row after the status row when the
    binder lacks one (spc-270 A1.3). _rewrite_field is a no-op when the row is
    absent (lazy migration), so a deferred/stuck flip with --wait-reason on a
    minimal binder would ship without the coupled wait_reason and the validator
    would flag it. Mirror the status row's pipe count so the table stays
    well-formed: a 3-col status row gets a 3-col insert (value + description),
    a 2-col row gets a 2-col insert. Returns text unchanged when a wait_reason
    row is already present or no status row exists."""
    if re.search(r"(?m)^\| wait_reason \|", text):
        return text
    m_status = re.search(r"(?m)^(.*?\|\s*status\s*\|.*\|.*)$", text)
    if not m_status:
        return text
    status_line = m_status.group(0)
    pipe_count = status_line.count("|")
    if pipe_count >= 4:
        new_row = f"| wait_reason | {value} | ({value}) |"
    else:
        new_row = f"| wait_reason | {value} |"
    end = m_status.end()
    return text[:end] + "\n" + new_row + text[end:]


def _validate_coupled_wait_reason(to: str, wait_reason: str | None) -> tuple[bool, str]:
    """Coupled-field policy (spc-270 A1.1): a status that carries an external
    signal requires a wait_reason from its reason vocabulary; any other status
    must clear it to `(none)`. Returns (ok, message)."""
    if to == "stuck":
        allowed = sv.STUCK_REASONS
    elif to == "deferred":
        allowed = sv.DEFERRED_REASONS
    else:
        # parked / rework hold a signal but do not gate on wait_reason; any
        # non-terminal without a reason vocabulary clears it to `(none)`.
        return True, ""
    if not wait_reason or wait_reason not in allowed:
        return False, (f"status '{to}' requires wait_reason in "
                       f"{sorted(allowed)}; got {wait_reason!r}")
    return True, ""


def cmd_commit(args: list) -> int:
    """Atomic binder-bound transition (spc-270 A1.1–A1.2).

    Locks the binder directory, reads the REAL prior status + coupled fields,
    validates the versioned edge + escape + coupled wait_reason, then in one
    locked transaction rewrites status/wait_reason/updated AND appends one
    ticket-bound ledger entry. A failure at validation, ledger append, or
    binder write leaves neither partial binder state nor a misleading ledger
    record (fail-close). `record` remains as the ledger-only primitive for
    non-mutating callers; canonical writers route here.
    """
    if not args or args[0] in ("--help", "-h"):
        print("usage: transition-api.py commit <ticket-id> <to> <owner> "
              "<reason> [--from <expected>] [--wait-reason <r>] "
              "[--force-side-state-reason <text>] [--trace <text>] "
              "[--append-journal <text>] [--binder <path>] [--dry-run]")
        return 0 if (args and args[0] in ("--help", "-h")) else 3
    ticket, to, owner, reason = args[:4]
    rest = args[4:]
    expected_from = None
    wait_reason = None
    force_reason = None
    trace_override = None
    journal_entry = None
    binder_override = None
    dry = False
    i = 0
    while i < len(rest):
        a = rest[i]
        if a == "--from" and i + 1 < len(rest):
            expected_from = rest[i + 1]; i += 2
        elif a == "--wait-reason" and i + 1 < len(rest):
            wait_reason = rest[i + 1]; i += 2
        elif a == "--force-side-state-reason" and i + 1 < len(rest):
            force_reason = rest[i + 1]; i += 2
        elif a == "--trace" and i + 1 < len(rest):
            trace_override = rest[i + 1]; i += 2
        elif a == "--append-journal" and i + 1 < len(rest):
            journal_entry = rest[i + 1]; i += 2
        elif a == "--binder" and i + 1 < len(rest):
            binder_override = rest[i + 1]; i += 2
        elif a == "--dry-run":
            dry = True; i += 1
        else:
            print(f"unknown arg: {a}", file=sys.stderr); return 3

    binder = _binder_for_ticket(ticket, binder_override)
    if binder is None:
        print(f"commit: no binder found for {ticket} (use --binder <path> "
              f"or run from a repo with .lattice/tickets/{ticket}-*/README.md)",
              file=sys.stderr)
        return 3
    if not binder.is_file():
        print(f"commit: binder not a file: {binder}", file=sys.stderr)
        return 3

    lock_dir = binder.parent.resolve()
    lock_fd = os.open(str(lock_dir), os.O_RDONLY)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        return _commit_locked(binder, ticket, to, owner, reason,
                              expected_from, wait_reason, force_reason,
                              trace_override, journal_entry, dry)
    except OSError as exc:
        print(f"commit: cannot lock binder directory {lock_dir}: {exc}",
              file=sys.stderr)
        return 3
    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
        except OSError:
            pass
        os.close(lock_fd)


def _resolve_metric(edge, reason: str) -> "str | None":
    """Per-edge metric, except that a `direct-jump` edge counts a CANCEL as
    `cancel-count` — only a merge from queued/in-progress is a direct jump
    (ADR-012 §3; spc-337 A2 review cycle 1)."""
    if edge is None:
        return None
    if edge.metric == "direct-jump" and "merge" not in str(reason or ""):
        return "cancel-count"
    return edge.metric


def prepare_commit_text(orig_text: str, ticket: str, to: str, owner: str,
                        reason: str, expected_from: str | None = None,
                        wait_reason: str | None = None,
                        force_reason: str | None = None,
                        trace_override: str | None = None,
                        journal_entry: str | None = None
                        ) -> tuple[int, str | None, dict | None]:
    """PURE (no disk I/O) validation + snapshot build for a binder-bound
    transition (spc-297). Writers call this inside their own dir lock, merge
    the returned `new_text` (status+wait_reason+updated+journal flipped) with
    their non-status field mutations, then call `commit_transaction` for the
    atomic disk write — restoring single-write atomicity (the writer mutates
    the binder ONCE: its own fields + the prepared flip + ledger).

    Returns `(rc, new_text, entry)`:
      rc=0  success — `new_text` is `orig_text` with status→to, wait_reason
            resolved (and the row inserted when --wait-reason given on a
            minimal binder), `updated` bumped, and the journal trace appended;
            `entry` is the ledger dict.
      rc=1  illegal edge / continuity-guard mismatch / bad coupled wait_reason
      rc=2  escape-required edge without --force-side-state-reason
      rc=3  no `| status |` row in orig_text
    On rc!=0 the same stderr message as the `commit` CLI is printed and
    `new_text`/`entry` are None."""
    prior = _read_field(orig_text, "status")
    if prior is None:
        print(f"commit: binder has no `| status |` row — refusing to mutate a "
              f"binder whose status row is absent", file=sys.stderr)
        return 3, None, None
    if expected_from is not None and prior != expected_from:
        print(f"commit: expected from={expected_from!r} but binder status is "
              f"{prior!r} (continuity guard; refusing)", file=sys.stderr)
        return 1, None, None
    if not tt.is_legal_edge(prior, to):
        print(f"ILLEGAL transition: {prior} -> {to} (not in schema; refused)",
              file=sys.stderr)
        return 1, None, None
    if tt.requires_escape(prior, to) and not force_reason:
        print(f"ILLEGAL without operator override: {prior} -> {to} requires "
              f"--force-side-state-reason (side-state guard; no agent "
              f"self-adjudication)", file=sys.stderr)
        return 2, None, None
    ok, msg = _validate_coupled_wait_reason(to, wait_reason)
    if not ok:
        print(f"ILLEGAL coupled field: {msg}", file=sys.stderr)
        return 1, None, None

    edge = tt.edge_for(prior, to)
    entry = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "ticket": ticket,
        "from": prior,
        "to": to,
        "owner": owner,
        "reason": reason,
        "guard": edge.guard,
        "escape_used": force_reason is not None,
        "force_side_state_reason": force_reason,
        "trace": trace_override or (edge.trace if edge else None),
        # spc-337 A2 (review cycle 1): `direct-jump` means a MERGE observed from
        # queued/in-progress; a cancel on the same edge counts as a cancel.
        "metric": _resolve_metric(edge, reason),
    }
    new_text = _rewrite_field(orig_text, "status", to)
    resolved_wait_reason = wait_reason if wait_reason else "(none)"
    new_text = _rewrite_field(new_text, "wait_reason", resolved_wait_reason)
    if wait_reason:
        new_text = _ensure_wait_reason_row(new_text, resolved_wait_reason)
    updated_stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    new_text = binder_rows.stamp_updated(new_text, updated_stamp)
    new_text = _append_journal_trace(new_text, journal_entry or "")
    return 0, new_text, entry


def commit_transaction(binder: Path, new_text: str, entry: dict,
                       ticket: str | None = None) -> int:
    """The disk-IO half of a binder-bound transition (spc-297). Writers that
    have already prepared `new_text` (their non-status mutations + the
    prepare_commit_text flip) call this for the atomic write: temp binder →
    append ledger → atomic rename, with the A1.2 fail-close ordering (a
    ledger-append or rename failure rolls back so neither a half-mutated
    binder nor a misleading ledger record survives). Preserves the binder file
    mode. `binder` may be a str or Path. Returns 0 on success, 3 on
    io/transaction failure."""
    binder = Path(binder)
    tk = ticket or entry.get("ticket", "")
    # spc-337 A1: the ledger lives in the binder's OWN home, never cwd — the
    # writers stage `<binder home>/.transition-ledger/<tkt>.jsonl`, so the
    # two must agree or the ledger is silently lost (tkt-335).
    lp = ledger_path(tk, home_for_binder(binder))
    lp.parent.mkdir(parents=True, exist_ok=True)
    tmp = binder.with_suffix(".README.md.tmp")
    try:
        tmp.write_text(new_text, encoding="utf-8")
        try:
            os.chmod(tmp, os.stat(binder).st_mode & 0o777)
        except OSError:
            pass
        _append_ledger_locked(lp, entry)
    except OSError as exc:
        try:
            tmp.unlink()
        except OSError:
            pass
        print(f"commit: transaction aborted (write/ledger failure: {exc}); "
              f"binder and ledger unchanged", file=sys.stderr)
        return 3
    try:
        os.replace(tmp, binder)
    except OSError as exc:
        _rollback_ledger(lp, entry)
        print(f"commit: transaction aborted (rename failure: {exc}); "
              f"binder and ledger unchanged", file=sys.stderr)
        return 3
    print(f"committed: {tk} {entry.get('from', '?')} -> {entry.get('to', '?')} "
          f"({entry.get('owner', '?')})")
    return 0


def _commit_locked(binder: Path, ticket: str, to: str, owner: str, reason: str,
                   expected_from: str | None, wait_reason: str | None,
                   force_reason: str | None, trace_override: str | None,
                   journal_entry: str | None, dry: bool) -> int:
    """CLI path: read orig under the caller's dir lock, prepare, then either
    dry-print or commit_transaction. Preserves the `commit` CLI's exit codes
    (1 illegal, 2 escape-required, 3 usage/io) verbatim."""
    orig = binder.read_text(encoding="utf-8")
    rc, new_text, entry = prepare_commit_text(
        orig, ticket, to, owner, reason, expected_from, wait_reason,
        force_reason, trace_override, journal_entry)
    if rc != 0:
        return rc
    if dry:
        print(json.dumps(entry, indent=2))
        return 0
    return commit_transaction(binder, new_text, entry)


def _append_ledger_locked(lp: Path, entry: dict) -> None:
    """Append one JSONL entry under the per-ticket flock (review F7). The
    binder dir lock already serializes this ticket's writers; this flock
    additionally serializes same-clone concurrent recorders across tickets."""
    # The ledger's own home (<home>/.transition-ledger/<tkt>.jsonl -> <home>)
    # anchors the co-located lock fallback (spc-337 A1: never a foreign cwd).
    lockp = lock_path(entry["ticket"], lp.parent.parent)
    lockp.parent.mkdir(parents=True, exist_ok=True)
    lock_fd = os.open(str(lockp), os.O_CREAT | os.O_WRONLY, 0o644)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        with lp.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(entry, separators=(",", ":")) + "\n")
    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
        except OSError:
            pass
        os.close(lock_fd)


def _rollback_ledger(lp: Path, entry: dict) -> None:
    """Best-effort removal of the just-appended line so a failed rename leaves
    no misleading record. Idempotent: if the line is gone, this is a no-op."""
    try:
        lines = lp.read_text(encoding="utf-8").splitlines()
        needle = json.dumps(entry, separators=(",", ":"))
        if lines and lines[-1].strip() == needle:
            lp.write_text("\n".join(lines[:-1]) + ("\n" if len(lines) > 1 else ""),
                          encoding="utf-8")
    except OSError:
        pass


def cmd_legal(args: list) -> int:
    if len(args) != 2:
        print("usage: transition-api.py legal <from> <to>", file=sys.stderr)
        return 3
    frm, to = args
    legal = tt.is_legal_edge(frm, to)
    print(f"{'legal' if legal else 'ILLEGAL'}: {frm} -> {to}")
    return 0 if legal else 1


def cmd_record(args: list) -> int:
    if not args or args[0] in ("--help", "-h"):
        print("usage: transition-api.py record <ticket-id> <from> <to> "
              "<owner> <reason> [--force-side-state-reason <text>] "
              "[--trace <text>] [--home <path>] [--dry-run]")
        return 0 if (args and args[0] in ("--help", "-h")) else 3
    if len(args) < 5:
        print("usage: transition-api.py record <ticket-id> <from> <to> "
              "<owner> <reason> [--force-side-state-reason <text>] "
              "[--trace <text>] [--home <path>] [--dry-run]", file=sys.stderr)
        return 3
    ticket, frm, to, owner, reason = args[:5]
    rest = args[5:]
    force_reason = None
    trace_override = None
    home_override = None
    dry = False
    i = 0
    while i < len(rest):
        if rest[i] == "--force-side-state-reason" and i + 1 < len(rest):
            force_reason = rest[i + 1]; i += 2
        elif rest[i] == "--trace" and i + 1 < len(rest):
            trace_override = rest[i + 1]; i += 2
        elif rest[i] == "--home" and i + 1 < len(rest):
            home_override = rest[i + 1]; i += 2
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
        "metric": _resolve_metric(edge, reason),
    }
    if dry:
        print(json.dumps(entry, indent=2))
        return 0
    # tkt-352 / ADR-012 §4: `record` has no binder to anchor it, so resolve the
    # home from --home → LATTICE_HOME → <git show-toplevel>/.lattice (never bare
    # cwd) so a run from a non-toplevel subdir lands under the repo's .lattice.
    rec_home = resolve_record_home(home_override)
    lp = ledger_path(ticket, rec_home)
    lp.parent.mkdir(parents=True, exist_ok=True)
    # Atomic append with a flock (review F7): batch-work spawns sibling
    # worktrees; concurrent recorders must not interleave partial JSON lines.
    # ADR-011 / spc-282 A2: the .lock sidecar lives OUT OF REPO (state home)
    # so it does not leak as untracked dirt; the .jsonl it guards stays
    # committed in-repo. Same-clone recorders resolve one lock via fingerprint.
    lockp = lock_path(ticket, rec_home)
    lockp.parent.mkdir(parents=True, exist_ok=True)
    lock_fd = os.open(str(lockp), os.O_CREAT | os.O_WRONLY, 0o644)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        with lp.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(entry, separators=(",", ":")) + "\n")
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        os.close(lock_fd)
    print(f"recorded: {ticket} {frm} -> {to} ({owner})")
    return 0


def cmd_replay(args: list) -> int:
    """Replay all per-ticket ledgers (spc-270 A1.4).

    Beyond per-entry edge legality + escape (spc-254 A3), this now enforces the
    three continuity invariants the append-only version left to trust:
      - identity:   each entry's `ticket` == the ledger file's ticket id;
      - continuity: entry[i].from == entry[i-1].to (no discontinuity);
      - snapshot:   the last entry's `to` == the binder's current `status`
                    (the ledger and the binder agree on the present state).
    Used by the validator; exit 0 = all entries legal + consistent, 1 = at
    least one illegal/inconsistent record. Globs home/.transition-ledger/*.jsonl
    (review F2: per-ticket committed files so CI accumulates real history)."""
    home = Path(os.environ.get("LATTICE_HOME", ".lattice"))
    ledger_dir = home / ".transition-ledger"
    if not ledger_dir.is_dir():
        print(f"no ledger dir at {ledger_dir}", file=sys.stderr)
        return 0  # no ledger = nothing to replay (not an error)
    bad = 0
    total = 0
    for lp in sorted(ledger_dir.glob("*.jsonl")):
        file_ticket = lp.stem  # tkt-N
        prev_to: str | None = None
        last_to: str | None = None
        for lineno, line in enumerate(
            lp.read_text(encoding="utf-8").splitlines(), 1
        ):
            line = line.strip()
            if not line:
                continue
            total += 1
            try:
                entry = json.loads(line)
            except json.JSONDecodeError as exc:
                print(f"{lp}:{lineno}: malformed JSON: {exc}",
                      file=sys.stderr)
                bad += 1
                continue
            frm, to = entry.get("from", ""), entry.get("to", "")
            eticket = entry.get("ticket", "?")
            # Identity: the entry must belong to this ledger's ticket.
            if eticket != file_ticket:
                print(f"{lp}:{lineno}: identity mismatch: entry ticket "
                      f"{eticket!r} != ledger {file_ticket!r}", file=sys.stderr)
                bad += 1
            # Edge legality + escape (spc-254 A3).
            if not tt.is_legal_edge(frm, to):
                print(f"{lp}:{lineno}: ILLEGAL edge {frm} -> {to} "
                      f"(ticket {eticket})", file=sys.stderr)
                bad += 1
                prev_to = to
                last_to = to
                continue
            if tt.requires_escape(frm, to) and not entry.get(
                "force_side_state_reason"
            ):
                print(f"{lp}:{lineno}: ILLEGAL escape-required edge "
                      f"{frm} -> {to} without operator override "
                      f"(ticket {eticket})", file=sys.stderr)
                bad += 1
            # Continuity: each entry's `from` must equal the prior `to`.
            if prev_to is not None and frm != prev_to:
                print(f"{lp}:{lineno}: discontinuity: entry from={frm!r} "
                      f"but prior to={prev_to!r}", file=sys.stderr)
                bad += 1
            prev_to = to
            last_to = to
        # Final snapshot: the ledger's last `to` must equal the binder status.
        if last_to is not None:
            binder = _binder_for_ticket(file_ticket)
            if binder is not None:
                bstatus = _read_field(binder.read_text(encoding="utf-8"),
                                      "status")
                if bstatus is not None and bstatus != last_to:
                    print(f"{lp}: snapshot mismatch: ledger final "
                          f"to={last_to!r} but binder status={bstatus!r}",
                          file=sys.stderr)
                    bad += 1
    print(f"replay: {total} entries, {bad} illegal/inconsistent")
    return 1 if bad else 0


def main(argv: list) -> int:
    if len(argv) < 2 or argv[1] in ("--help", "-h"):
        # `--help` (and no-arg) print the docstring usage; exit 0 for an
        # explicit --help, 3 for a bare invocation (tkt-352 A2).
        print(__doc__)
        return 0 if (len(argv) >= 2 and argv[1] in ("--help", "-h")) else 3
    cmd, rest = argv[1], argv[2:]
    if cmd == "legal":
        return cmd_legal(rest)
    if cmd == "record":
        return cmd_record(rest)
    if cmd == "commit":
        return cmd_commit(rest)
    if cmd == "replay-ledger":
        return cmd_replay(rest)
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv))
