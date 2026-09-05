#!/usr/bin/env python3
"""Spec transition API — the guarded chokepoint for Spec lifecycle transitions
(tkt-473 / spc-475 A21–A25).

Why a separate API: the ticket `transition-api.py` guards *ticket binder*
status flips (M2 execution). Spec lifecycle (M1/M3) has its own terminal
edges `locked → done` and `locked → superseded` (docs/workflow-fsm.md §1:
`Spec status enum: draft | locked | done | superseded`). Before this script
the Spec `status:` flip was a manual front-matter edit by finish-work/create-
spec prose — no chokepoint, no ledger, no child-set closure, no exact PR-set
equality, no soak attestation, and no replayable history. ADR-012 §1 makes
status flips go through a guarded, replayable transition; this script
extends that contract to Specs.

It reuses the #472 operation envelope (tkt-472 A14–A20):
  - stable `operation_id` (idempotent duplicate detection — A23);
  - `--expected-rev` revision guard (refuse before mutation when a concurrent
    writer advanced the ledger — A23);
  - durable write ordering: temp Spec file (fsync) → append ledger → atomic
    rename, with rollback on rename failure (fail-close — A23);
  - crash recovery (W1/W2/W3) keyed on the operation_id embedded in the temp
    filename (A23), mirroring `transition-api.recover_crash`.

Guards (A21/A22):
  done        — Spec status is `locked`; every authoritative child is closed;
                the child set is closed against lineage back-references (no
                omitted historical child); the Spec `prs:` set equals the
                union of child binder `prs:` in BOTH directions (no
                missing/extra PR); Acceptance has no open non-deferred A-item;
                a soak attestation carries an evidence ref and a timestamp
                strictly later than the last child merge (A22).
  superseded  — Spec status is `locked`; `superseded_by` resolves to a real
                tracked Spec file under <home>/specs/. Children are swept by
                spec-supersede.sh (trip-time honesty) AFTER the Spec flips.

Spec ledger: <home>/.transition-ledger/spc-N.jsonl — committed in-repo (same
directory as the ticket ledgers) so CI's replay (validate-lattice-artifacts.py)
accumulates real Spec history. The validator's replay already globs *.jsonl
and matches `spc-N` stems; tkt-473 extends it to snapshot-match a Spec file
against the ledger's final `to` (A24) and to flag a terminal Spec whose
ledger is missing or disagrees (hand-edited snapshot — A24).

Exit codes:
  0  transition recorded (or --dry-run legal/no-op/idempotent)
  1  ILLEGAL Spec edge / guard failure (refused; nothing written)
  2  (reserved — no escape edges on Spec lifecycle today)
  3  usage / io error / transaction aborted (fail-close; nothing written)

Usage:
  python3 spec-transition.py done <spc-id> <owner> \
      [--soak-evidence-ref <ref>] [--soak-attestation-ts <iso8601>] \
      [--reason <text>] [--expected-rev <n>] [--operation-id <uuid>] \
      [--home <path>] [--dry-run]
  python3 spec-transition.py superseded <spc-id> <superseded-by> <owner> \
      [--reason <text>] [--expected-rev <n>] [--operation-id <uuid>] \
      [--home <path>] [--dry-run] [--no-sweep]
  python3 spec-transition.py legal <from> <to>      # exit 0 legal, 1 illegal
  python3 spec-transition.py record <spc-id> <from> <to> <owner> <reason> \
      [--home <path>] [--expected-rev <n>] [--dry-run]   # ledger-only primitive
  python3 spec-transition.py replay-ledger [--home <path>]
"""

from __future__ import annotations

import datetime
import fcntl
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import uuid
from pathlib import Path

_HERE = Path(__file__).resolve().parent

# Spec lifecycle edges guarded by this API (M1/M3 — not M2 ticket execution).
# Mirrored into lib/transition_table.py + the validator's LEGAL_TRANSITIONS so
# the unified ledger replay accepts Spec entries (A23 replayable); the bats
# parity test stays green because the pair is added to both sides.
SPEC_LEGAL_EDGES: set[tuple[str, str]] = {("locked", "done"),
                                          ("locked", "superseded")}
SPEC_STATUS_OK = {"draft", "locked", "done", "superseded"}
SPEC_STATUS_TERMINAL = {"done", "superseded"}

_FM_STATUS_RE = re.compile(r"^status:\s*(\S.*?)\s*$", re.M)
_FM_SUPERSEDED_BY_RE = re.compile(r"^superseded_by:\s*(\S.*?)\s*$", re.M)
_FM_TICKETS_RE = re.compile(r"^tickets:\s*(\[.*\])\s*$", re.M)
_FM_PRS_RE = re.compile(r"^prs:\s*(\[.*\])\s*$", re.M)
_FM_UPDATED_RE = re.compile(r"^updated:\s*(\S.*?)\s*$", re.M)
_FM_ID_RE = re.compile(r"^id:\s*(spc-[1-9][0-9]*)\s*$", re.M)
_SPEC_ID_RE = re.compile(r"^spc-([1-9][0-9]*)$")
# Binder card rows (first table block) — mirror validator regexes.
_SPEC_REF_RE = re.compile(r"^\|\s*spec\s*\|\s*(spc-[1-9][0-9]*)\b", re.I | re.M)
_PRS_TABLE_RE = re.compile(r"^\|\s*prs\s*\|\s*([^|]+?)\s*\|", re.I | re.M)
_STATUS_TABLE_RE = re.compile(r"^\|\s*status\s*\|\s*([^|]*?)\s*\|", re.I | re.M)
# Finish ledger: `- pr-N merged: <iso8601> — ...`
_FINISH_MERGED_RE = re.compile(r"^\s*-\s+pr-\d+\s+merged:\s*(\S+)", re.M)
_ACCEPT_DEFERRED_RE = re.compile(r"\(deferred\)", re.I)
_A_HEADING_RE = re.compile(r"\*\*A(\d+)\*\*")
_HEADING_RE = re.compile(r"^(#+)\s")
_ACCEPT_HEADING_RE = re.compile(r"^#+\s.*Acceptance", re.I)


# ---------------------------------------------------------------------------
# Path / home resolution (mirror transition-api.py; self-contained so this
# script stays dependency-free and runnable from any skill cwd / worktree).
# ---------------------------------------------------------------------------

def _resolve_home(home_override: "str | None" = None) -> Path:
    if home_override:
        return Path(home_override)
    env = os.environ.get("LATTICE_HOME")
    if env:
        return Path(env)
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5,
        )
        if out.returncode == 0 and out.stdout.strip():
            return Path(out.stdout.strip()) / ".lattice"
    except Exception:
        pass
    return Path(".lattice")


def _resolve_state_home() -> str:
    """Out-of-repo runtime state dir for the flock sidecar (ADR-011). The
    .jsonl ledger STAYS committed in-repo; its .lock lives out-of-repo so it
    never leaks as untracked dirt. Keyed by repo fingerprint."""
    override = (os.environ.get("LATTICE_BATCH_GATE_HOME")
                or os.environ.get("LATTICE_STATE_HOME"))
    if override:
        return override
    helper = _HERE / "lattice-state-home.sh"
    if helper.is_file():
        try:
            out = subprocess.run(
                ["bash", str(helper)], capture_output=True, text=True, timeout=5)
            if out.returncode == 0 and out.stdout.strip():
                return out.stdout.strip()
        except Exception:
            pass
    try:
        git_common = subprocess.run(
            ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
            capture_output=True, text=True, timeout=5).stdout.strip()
    except Exception:
        git_common = ""
    if not git_common:
        return ""
    fp = hashlib.sha1(git_common.encode()).hexdigest()[:12]
    root = os.environ.get("XDG_STATE_HOME") or os.path.join(
        os.environ.get("HOME", ""), ".local", "state")
    home = os.path.join(root, "lattice", fp)
    try:
        os.makedirs(home, exist_ok=True)
    except OSError:
        pass
    return home


def _ledger_path(spec_id: str, home: Path) -> Path:
    return home / ".transition-ledger" / f"{spec_id}.jsonl"


def _lock_path(spec_id: str) -> Path:
    state = _resolve_state_home()
    if state:
        return Path(state) / ".transition-ledger" / f"{spec_id}.lock"
    # Legacy co-located fallback (never deadlocks a legitimate transition).
    return _ledger_path(spec_id, _resolve_home()).with_suffix(".jsonl.lock")


def _ledger_rev(spec_id: str, home: Path) -> int:
    lp = _ledger_path(spec_id, home)
    if not lp.is_file():
        return 0
    return sum(1 for ln in lp.read_text(encoding="utf-8").splitlines()
               if ln.strip())


def _find_entry_by_opid(spec_id: str, opid: str, home: Path) -> "dict | None":
    lp = _ledger_path(spec_id, home)
    if not lp.is_file():
        return None
    for line in lp.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if entry.get("operation_id") == opid:
            return entry
    return None


def _release_lock_fd(lock_fd: int) -> None:
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
    except OSError:
        pass
    try:
        os.close(lock_fd)
    except OSError:
        pass


def _append_ledger_locked(lp: Path, entry: dict) -> None:
    lockp = _lock_path(entry["spec"])
    lockp.parent.mkdir(parents=True, exist_ok=True)
    lock_fd = os.open(str(lockp), os.O_CREAT | os.O_WRONLY, 0o644)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        with lp.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(entry, separators=(",", ":")) + "\n")
    finally:
        _release_lock_fd(lock_fd)


def _rollback_ledger(lp: Path, entry: dict) -> None:
    lockp = _lock_path(entry["spec"])
    lockp.parent.mkdir(parents=True, exist_ok=True)
    lock_fd = os.open(str(lockp), os.O_CREAT | os.O_WRONLY, 0o644)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        lines = lp.read_text(encoding="utf-8").splitlines()
        needle = json.dumps(entry, separators=(",", ":"))
        idx = None
        for i in range(len(lines) - 1, -1, -1):
            if lines[i].strip() == needle:
                idx = i
                break
        if idx is None:
            print(f"spec-transition: WARNING — rollback found no matching "
                  f"entry in {lp.name}; ledger may have a dangling entry",
                  file=sys.stderr)
        else:
            kept = lines[:idx] + lines[idx + 1:]
            lp.write_text(("\n".join(kept) + "\n") if kept else "",
                          encoding="utf-8")
    except OSError as exc:
        print(f"spec-transition: WARNING — rollback failed for {lp.name}: "
              f"{exc}; ledger may have a dangling entry", file=sys.stderr)
    finally:
        _release_lock_fd(lock_fd)


# ---------------------------------------------------------------------------
# Spec / binder parsing.
# ---------------------------------------------------------------------------

def _find_spec_file(home: Path, spec_id: str) -> "Path | None":
    """Resolve <home>/specs/spc-N-<slug>.md or spc-N.md (mirror find-spec.sh)."""
    if not _SPEC_ID_RE.fullmatch(spec_id):
        return None
    specs = home / "specs"
    if not specs.is_dir():
        return None
    matches = [p for p in specs.glob(f"{spec_id}-*.md") if p.is_file()]
    slugless = specs / f"{spec_id}.md"
    if slugless.is_file():
        matches.append(slugless)
    if len(matches) != 1:
        return None
    return matches[0]


def _fm_value(text: str, rx: re.Pattern) -> "str | None":
    m = rx.search(text)
    return m.group(1).strip().strip("'\"") if m else None


def _spec_status(text: str) -> "str | None":
    v = _fm_value(text, _FM_STATUS_RE)
    return v.lower() if v else None


def _spec_superseded_by(text: str) -> "str | None":
    v = _fm_value(text, _FM_SUPERSEDED_BY_RE)
    if not v or v.lower() in ("null", "none", "(none)"):
        return None
    return v


def _spec_ticket_ids(text: str) -> set:
    raw = _fm_value(text, _FM_TICKETS_RE) or ""
    return {f"tkt-{n}" for n in re.findall(r"tkt-([1-9][0-9]*)", raw)}


def _spec_prs(text: str) -> set:
    raw = _fm_value(text, _FM_PRS_RE) or ""
    return set(re.findall(r"pr-[1-9][0-9]*", raw))


def _first_table_block(text: str) -> str:
    lines, in_t = [], False
    for line in text.splitlines():
        if line.startswith("|"):
            in_t = True
            lines.append(line)
        elif in_t:
            break
    return "\n".join(lines)


def _table_field(table: str, rx: re.Pattern) -> str:
    m = rx.search(table)
    return m.group(1).strip() if m else ""


def _binder_status(text: str) -> "str | None":
    v = _table_field(_first_table_block(text), _STATUS_TABLE_RE)
    return v.lower() or None


def _binder_spec_ref(text: str) -> "str | None":
    v = _table_field(_first_table_block(text), _SPEC_REF_RE)
    return v or None


def _binder_prs(text: str) -> set:
    cell = _table_field(_first_table_block(text), _PRS_TABLE_RE)
    return set(re.findall(r"pr-[1-9][0-9]*", cell))


def _binder_for_ticket(home: Path, tkt_id: str) -> "Path | None":
    td = home / "tickets"
    if not td.is_dir():
        return None
    pat = re.compile(rf"^{re.escape(tkt_id)}-[^\s/]+$")
    matches = [d for d in td.iterdir() if d.is_dir() and pat.match(d.name)]
    if len(matches) != 1:
        return None
    b = matches[0] / "README.md"
    return b if b.is_file() else None


def _all_binders(home: Path) -> list:
    """All active child binder READMEs (excludes archive)."""
    td = home / "tickets"
    if not td.is_dir():
        return []
    out = []
    for d in sorted(td.iterdir()):
        if not d.is_dir() or not d.name.startswith("tkt-"):
            continue
        if d.name == "archive":
            continue
        r = d / "README.md"
        if r.is_file():
            out.append(r)
    return out


def _child_merge_ts(binder_text: str) -> "str | None":
    """The `pr-N merged: <ts>` timestamp from a child's ## Finish ledger."""
    m = _FINISH_MERGED_RE.search(binder_text)
    return m.group(1) if m else None


def _open_acceptance_aids(text: str) -> list:
    """Open, non-deferred A-ids in the Spec Acceptance section (mirror
    validator.spec_done_open_acceptance)."""
    open_ids: list = []
    in_sec = False
    level = 0
    for line in text.splitlines():
        hm = _HEADING_RE.match(line)
        if hm:
            if _ACCEPT_HEADING_RE.match(line):
                in_sec = True
                level = len(hm.group(1))
                open_ids.extend(_open_non_deferred_aids(line))
                continue
            if in_sec and len(hm.group(1)) <= level:
                in_sec = False
                continue
        if in_sec:
            open_ids.extend(_open_non_deferred_aids(line))
    return open_ids


def _open_non_deferred_aids(line: str) -> list:
    if not re.match(r"^\s*-\s*\[\s\]", line):
        return []
    if _ACCEPT_DEFERRED_RE.search(line):
        return []
    # Strikethrough wrapping the A-id itself defers it (mirror validator).
    if re.search(r"~~\*\*A\d+\*\*~~", line):
        return []
    return [f"A{n}" for n in _A_HEADING_RE.findall(line)]


def _rewrite_fm_field(text: str, key: str, value: str) -> str:
    """Replace a YAML front-matter `<key>:` line value. Returns text
    unchanged when the line is absent (lazy migration — never inserts)."""
    pat = re.compile(rf"^{re.escape(key)}:\s*(\S.*?)\s*$", re.M)
    if not pat.search(text):
        return text
    return pat.sub(lambda m: f"{key}: {value}", text, count=1)


# ---------------------------------------------------------------------------
# Crash recovery (W1/W2/W3) — mirror transition-api.recover_crash, but the
# mutated file is the Spec file and status is read from YAML front matter.
# ---------------------------------------------------------------------------

def _recover_crash(spec_path: Path, spec_id: str, home: Path) -> "str | None":
    spec_dir = spec_path.parent
    tmps = list(spec_dir.glob(".spec-transition.*.tmp"))
    if not tmps:
        return None
    recovered = None
    for tmp in tmps:
        stem = tmp.stem  # .spec-transition.<opid>
        parts = stem.split(".", 3)  # ['', 'spec-transition', '<opid>']
        if len(parts) < 3:
            tmp.unlink(missing_ok=True)
            continue
        opid = parts[2]
        existing = _find_entry_by_opid(spec_id, opid, home)
        if existing is None:
            # W1: crash before ledger append. Discard.
            tmp.unlink(missing_ok=True)
            print(f"recovery: discarded orphaned spec temp for {spec_id} "
                  f"(op {opid[:8]}… — pre-ledger crash)")
            continue
        cur_status = _spec_status(spec_path.read_text(encoding="utf-8"))
        if cur_status == existing.get("to"):
            # W3: rename already completed. Clean temp.
            tmp.unlink(missing_ok=True)
            continue
        # W2: ledger appended but rename didn't complete.
        tmp_status = _spec_status(tmp.read_text(encoding="utf-8"))
        if tmp_status == existing.get("to"):
            try:
                os.replace(tmp, spec_path)
                recovered = opid
                print(f"recovery: completed interrupted spec rename for "
                      f"{spec_id} ({cur_status} → {tmp_status}, "
                      f"op {opid[:8]}…)")
            except OSError as exc:
                print(f"recovery: WARNING — could not complete spec rename "
                      f"for {spec_id}: {exc}", file=sys.stderr)
        else:
            lp = _ledger_path(spec_id, home)
            _rollback_ledger(lp, existing)
            tmp.unlink(missing_ok=True)
            print(f"recovery: rolled back ambiguous spec crash for {spec_id} "
                  f"(op {opid[:8]}…)")
    return recovered


def _commit_transaction(spec_path: Path, new_text: str, entry: dict,
                        home: Path) -> int:
    """Atomic disk write: temp Spec (fsync) → append ledger → rename, with
    fail-close rollback (A23). Preserves Spec file mode."""
    lp = _ledger_path(entry["spec"], home)
    lp.parent.mkdir(parents=True, exist_ok=True)
    opid = entry.get("operation_id", str(uuid.uuid4()))
    tmp = spec_path.parent / f".spec-transition.{opid}.tmp"
    try:
        tmp.write_text(new_text, encoding="utf-8")
        fd = os.open(str(tmp), os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
        try:
            os.chmod(tmp, os.stat(spec_path).st_mode & 0o777)
        except OSError:
            pass
        _append_ledger_locked(lp, entry)
    except OSError as exc:
        try:
            tmp.unlink()
        except OSError:
            pass
        print(f"spec-transition: transaction aborted (write/ledger failure: "
              f"{exc}); spec and ledger unchanged", file=sys.stderr)
        return 3
    try:
        os.replace(tmp, spec_path)
    except OSError as exc:
        _rollback_ledger(lp, entry)
        try:
            tmp.unlink()
        except OSError:
            pass
        print(f"spec-transition: transaction aborted (rename failure: {exc}); "
              f"spec and ledger unchanged", file=sys.stderr)
        return 3
    print(f"committed: {entry['spec']} {entry.get('from', '?')} -> "
          f"{entry.get('to', '?')} ({entry.get('owner', '?')})")
    return 0


# ---------------------------------------------------------------------------
# Guard evaluation (A21/A22). PURE — no mutation; returns (ok, detail, entry).
# ---------------------------------------------------------------------------

def _evaluate_done(spec_path: Path, spec_id: str, spec_text: str, home: Path,
                   owner: str, reason: str, soak_ref: "str | None",
                   soak_ts: "str | None", opid: "str | None") -> "tuple[int, str|None, dict|None]":
    prior = _spec_status(spec_text)
    if prior is None:
        return 3, f"spec {spec_id} has no front-matter `status:` line", None
    if prior != "locked":
        return 1, (
            f"ILLEGAL Spec transition: {prior} -> done (only "
            f"locked -> done is guarded; refused)"), None
    # --- A21: authoritative child-set closure -------------------------------
    declared = _spec_ticket_ids(spec_text)
    if not declared:
        return 1, (
            f"spec {spec_id} has no `tickets:` list — cannot close a "
            f"Spec with no children"), None
    # Lineage back-references: every binder whose `spec:` row points here must
    # be declared in `tickets:` (omitted historical child → refuse).
    backrefs = set()
    child_binders: dict[str, str] = {}  # tkt_id -> binder text
    for b in _all_binders(home):
        bt = b.read_text(encoding="utf-8")
        ref = _binder_spec_ref(bt)
        if ref == spec_id:
            tid_m = re.match(r"^(tkt-\d+)", b.parent.name)
            if tid_m:
                tid = tid_m.group(1)
                backrefs.add(tid)
                child_binders[tid] = bt
    omitted = backrefs - declared
    if omitted:
        return 1, (
            f"omitted historical child(ren) {sorted(omitted)} reference "
            f"{spec_id} but are not in its `tickets:` list (authoritative "
            f"child set is not closed; refused)"), None
    # Every declared child must have a closed binder.
    child_prs_union: set = set()
    last_merge_ts: "str | None" = None
    for tid in sorted(declared, key=lambda t: int(t[4:])):
        bt = child_binders.get(tid)
        if bt is None:
            # Not found among active backrefs — try a direct binder lookup.
            b = _binder_for_ticket(home, tid)
            if b is None:
                return 1, (
                    f"declared child {tid} has no binder under "
                    f"tickets/ (cannot prove closure; refused)"), None
            bt = b.read_text(encoding="utf-8")
        st = _binder_status(bt)
        if st != "closed":
            return 1, (
                f"child {tid} status is {st!r}, not `closed` (every "
                f"child must be closed before done; refused)"), None
        child_prs_union |= _binder_prs(bt)
        mts = _child_merge_ts(bt)
        if mts and (last_merge_ts is None or mts > last_merge_ts):
            last_merge_ts = mts
    # --- A21: exact PR-set equality, both directions ------------------------
    spec_prs = _spec_prs(spec_text)
    missing = child_prs_union - spec_prs   # child has a PR the Spec omits
    extra = spec_prs - child_prs_union     # Spec lists a PR no child has
    if missing or extra:
        return 1, (
            f"PR-set mismatch (exact equality both directions required): "
            f"spec prs={sorted(spec_prs)} child union="
            f"{sorted(child_prs_union)}; missing={sorted(missing)} "
            f"extra={sorted(extra)} (reconcile the Spec `prs:` row; "
            f"refused)"), None
    # --- A21: completed Acceptance ----------------------------------------
    open_a = _open_acceptance_aids(spec_text)
    if open_a:
        return 1, (
            f"Acceptance has open non-deferred items "
            f"{sorted(open_a, key=lambda x: int(x[1:]))} (check off "
            f"with proof, mark (deferred), or revert to locked; "
            f"refused)"), None
    # --- A22: soak attestation --------------------------------------------
    if not soak_ref:
        return 1, (
            "missing --soak-evidence-ref (A22: done requires a dogfood "
            "soak attestation with an evidence reference; refused)"), None
    if not soak_ts:
        return 1, (
            "missing --soak-attestation-ts (A22: done requires a soak "
            "attestation timestamp later than the last child merge; "
            "refused)"), None
    if not _valid_iso8601(soak_ts):
        return 1, (
            f"soak attestation ts {soak_ts!r} is not a valid ISO-8601 "
            f"UTC timestamp (YYYY-MM-DDTHH:MM:SSZ; refused)"), None
    if last_merge_ts and soak_ts <= last_merge_ts:
        return 1, (
            f"soak attestation ts {soak_ts} is not later than the last "
            f"child merge {last_merge_ts} (A22: attestation must post-"
            f"date the last child merge; refused)"), None
    entry = _build_entry(spec_id, prior, "done", owner,
                        reason or "Spec done — all children closed, PR union "
                                  "exact, Acceptance complete, soak attested",
                        opid, soak_ref=soak_ref, soak_attestation_ts=soak_ts)
    return 0, None, entry


def _evaluate_superseded(spec_path: Path, spec_id: str, spec_text: str,
                         home: Path, superseded_by: str, owner: str, reason: str,
                         opid: "str | None") -> "tuple[int, str|None, dict|None]":
    prior = _spec_status(spec_text)
    if prior is None:
        return 3, f"spec {spec_id} has no front-matter `status:` line", None
    if prior != "locked":
        return 1, (
            f"ILLEGAL Spec transition: {prior} -> superseded (only "
            f"locked -> superseded is guarded; refused)"), None
    if not _SPEC_ID_RE.fullmatch(superseded_by):
        return 1, (
            f"superseded_by {superseded_by!r} is not a valid spc-N id "
            f"(refused)"), None
    if superseded_by == spec_id:
        return 1, (
            f"superseded_by {superseded_by!r} == spec id (a Spec "
            f"cannot supersede itself; refused)"), None
    target = _find_spec_file(home, superseded_by)
    if target is None:
        return 1, (
            f"superseded_by {superseded_by} does not resolve to a "
            f"tracked Spec file under {home}/specs/ (cannot supersede "
            f"into a fictional Spec; refused)"), None
    entry = _build_entry(spec_id, prior, "superseded", owner,
                         reason or f"Spec superseded by {superseded_by}",
                         opid, superseded_by=superseded_by)
    return 0, None, entry


def _build_entry(spec_id: str, frm: str, to: str, owner: str, reason: str,
                 opid: "str | None", soak_ref: "str | None" = None,
                 soak_attestation_ts: "str | None" = None,
                 superseded_by: "str | None" = None) -> dict:
    entry = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "spec": spec_id,
        # `ticket` mirrors the ticket-ledger identity key so the validator's
        # unified replay (which keys identity on the ledger stem) accepts it.
        "ticket": spec_id,
        "from": frm,
        "to": to,
        "owner": owner,
        "reason": reason,
        "guard": ("all children closed + exact PR union + Acceptance complete "
                  "+ soak attested" if to == "done" else
                  "superseded_by resolves to a real Spec"),
        "operation_id": opid or str(uuid.uuid4()),
    }
    if soak_ref is not None:
        entry["soak_evidence_ref"] = soak_ref
    if soak_attestation_ts is not None:
        entry["soak_attestation_ts"] = soak_attestation_ts
    if superseded_by is not None:
        entry["superseded_by"] = superseded_by
    return entry


def _valid_iso8601(ts: str) -> bool:
    try:
        datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ")
        return True
    except ValueError:
        return False


# ---------------------------------------------------------------------------
# Snapshot build (PURE): flip status, bump updated, set superseded_by.
# ---------------------------------------------------------------------------

def _prepare_done_text(spec_text: str, entry: dict) -> str:
    new = _rewrite_fm_field(spec_text, "status", "done")
    new = _rewrite_fm_field(new, "updated",
                            time.strftime("%Y-%m-%d", time.gmtime()))
    return new


def _prepare_superseded_text(spec_text: str, entry: dict) -> str:
    new = _rewrite_fm_field(spec_text, "status", "superseded")
    # superseded_by line exists in every Spec template; rewrite it.
    new = _rewrite_fm_field(new, "superseded_by", entry["superseded_by"])
    new = _rewrite_fm_field(new, "updated",
                            time.strftime("%Y-%m-%d", time.gmtime()))
    return new


# ---------------------------------------------------------------------------
# CLI commands.
# ---------------------------------------------------------------------------

def cmd_done(args: list) -> int:
    USAGE = ("usage: spec-transition.py done <spc-id> <owner> "
             "[--soak-evidence-ref <ref>] [--soak-attestation-ts <iso8601>] "
             "[--reason <text>] [--expected-rev <n>] [--operation-id <uuid>] "
             "[--home <path>] [--dry-run]")
    if not args or args[0] in ("--help", "-h"):
        print(USAGE)
        return 0 if (args and args[0] in ("--help", "-h")) else 3
    if len(args) < 2:
        print(USAGE, file=sys.stderr)
        return 3
    spec_id, owner = args[0], args[1]
    rest = args[2:]
    soak_ref = soak_ts = reason = opid = home_ov = None
    expected_rev = None
    dry = False
    i = 0
    while i < len(rest):
        a = rest[i]
        if a == "--soak-evidence-ref" and i + 1 < len(rest):
            soak_ref = rest[i + 1]; i += 2
        elif a == "--soak-attestation-ts" and i + 1 < len(rest):
            soak_ts = rest[i + 1]; i += 2
        elif a == "--reason" and i + 1 < len(rest):
            reason = rest[i + 1]; i += 2
        elif a == "--operation-id" and i + 1 < len(rest):
            opid = rest[i + 1]; i += 2
        elif a == "--expected-rev" and i + 1 < len(rest):
            expected_rev = int(rest[i + 1]); i += 2
        elif a == "--home" and i + 1 < len(rest):
            home_ov = rest[i + 1]; i += 2
        elif a == "--dry-run":
            dry = True; i += 1
        else:
            print(f"unknown arg: {a}", file=sys.stderr); return 3
    return _run_transition(spec_id, "done", owner, reason, home_ov, dry,
                          opid, expected_rev, soak_ref=soak_ref,
                          soak_ts=soak_ts)


def cmd_superseded(args: list) -> int:
    USAGE = ("usage: spec-transition.py superseded <spc-id> <superseded-by> "
             "<owner> [--reason <text>] [--expected-rev <n>] "
             "[--operation-id <uuid>] [--home <path>] [--dry-run] [--no-sweep]")
    if not args or args[0] in ("--help", "-h"):
        print(USAGE)
        return 0 if (args and args[0] in ("--help", "-h")) else 3
    if len(args) < 3:
        print(USAGE, file=sys.stderr)
        return 3
    spec_id, superseded_by, owner = args[0], args[1], args[2]
    rest = args[3:]
    reason = opid = home_ov = None
    expected_rev = None
    dry = no_sweep = False
    i = 0
    while i < len(rest):
        a = rest[i]
        if a == "--reason" and i + 1 < len(rest):
            reason = rest[i + 1]; i += 2
        elif a == "--operation-id" and i + 1 < len(rest):
            opid = rest[i + 1]; i += 2
        elif a == "--expected-rev" and i + 1 < len(rest):
            expected_rev = int(rest[i + 1]); i += 2
        elif a == "--home" and i + 1 < len(rest):
            home_ov = rest[i + 1]; i += 2
        elif a == "--dry-run":
            dry = True; i += 1
        elif a == "--no-sweep":
            no_sweep = True; i += 1
        else:
            print(f"unknown arg: {a}", file=sys.stderr); return 3
    rc = _run_transition(spec_id, "superseded", owner, reason, home_ov, dry,
                        opid, expected_rev, superseded_by=superseded_by)
    if rc != 0 or dry or no_sweep:
        return rc
    # Sweep the superseded Spec's still-active children (trip-time honesty).
    home = _resolve_home(home_ov)
    spec_path = _find_spec_file(home, spec_id)
    sweep = _HERE / "spec-supersede.sh"
    if spec_path and sweep.is_file():
        try:
            subprocess.run(["bash", str(sweep), "--spec", str(spec_path),
                            "--home", str(home)],
                           check=False)
        except OSError as exc:
            print(f"spec-transition: child sweep skipped (spec-supersede.sh "
                  f"failed: {exc})", file=sys.stderr)
    return rc


def _run_transition(spec_id: str, to: str, owner: str, reason: "str | None",
                    home_ov: "str | None", dry: bool, opid: "str | None",
                    expected_rev: "int | None",
                    soak_ref: "str | None" = None,
                    soak_ts: "str | None" = None,
                    superseded_by: "str | None" = None) -> int:
    if not _SPEC_ID_RE.fullmatch(spec_id):
        print(f"spec-transition: {spec_id!r} is not a valid spc-N id",
              file=sys.stderr)
        return 3
    home = _resolve_home(home_ov)
    spec_path = _find_spec_file(home, spec_id)
    if spec_path is None or not spec_path.is_file():
        print(f"spec-transition: spec {spec_id} not found under "
              f"{home}/specs/", file=sys.stderr)
        return 3
    # Idempotent duplicate detection (A23).
    if opid:
        existing = _find_entry_by_opid(spec_id, opid, home)
        if existing is not None:
            print(f"committed: {spec_id} {existing.get('from', '?')} -> "
                  f"{existing.get('to', '?')} ({owner}) [idempotent — "
                  f"operation {opid[:8]}… already recorded]")
            return 0
    # Revision guard (A23): refuse before mutation if the ledger advanced.
    if expected_rev is not None:
        actual = _ledger_rev(spec_id, home)
        if actual != expected_rev:
            print(f"spec-transition: expected-revision mismatch: caller "
                  f"expected rev={expected_rev} but ledger has {actual} "
                  f"entries (stale snapshot; refusing)", file=sys.stderr)
            return 3
    spec_dir = spec_path.parent.resolve()
    lock_fd = os.open(str(spec_dir), os.O_RDONLY)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        _recover_crash(spec_path, spec_id, home)
        spec_text = spec_path.read_text(encoding="utf-8")
        if to == "done":
            rc, detail, entry = _evaluate_done(
                spec_path, spec_id, spec_text, home, owner, reason,
                soak_ref, soak_ts, opid)
        else:
            rc, detail, entry = _evaluate_superseded(
                spec_path, spec_id, spec_text, home, superseded_by, owner,
                reason, opid)
        if rc != 0:
            if detail:
                print(detail, file=sys.stderr)
            return rc
        new_text = (_prepare_done_text if to == "done"
                    else _prepare_superseded_text)(spec_text, entry)
        if dry:
            print(json.dumps(entry, indent=2))
            return 0
        return _commit_transaction(spec_path, new_text, entry, home)
    except OSError as exc:
        print(f"spec-transition: cannot lock spec directory {spec_dir}: {exc}",
              file=sys.stderr)
        return 3
    finally:
        _release_lock_fd(lock_fd)


def cmd_legal(args: list) -> int:
    if len(args) != 2:
        print("usage: spec-transition.py legal <from> <to>", file=sys.stderr)
        return 3
    frm, to = args
    legal = (frm, to) in SPEC_LEGAL_EDGES
    print(f"{'legal' if legal else 'ILLEGAL'}: {frm} -> {to}")
    return 0 if legal else 1


def cmd_record(args: list) -> int:
    if not args or args[0] in ("--help", "-h"):
        print("usage: spec-transition.py record <spc-id> <from> <to> <owner> "
              "<reason> [--home <path>] [--expected-rev <n>] [--dry-run]")
        return 0 if (args and args[0] in ("--help", "-h")) else 3
    if len(args) < 5:
        print("usage: spec-transition.py record <spc-id> <from> <to> <owner> "
              "<reason> [--home <path>] [--expected-rev <n>] [--dry-run]",
              file=sys.stderr)
        return 3
    spec_id, frm, to, owner, reason = args[:5]
    rest = args[5:]
    home_ov = None
    expected_rev = None
    dry = False
    i = 0
    while i < len(rest):
        a = rest[i]
        if a == "--home" and i + 1 < len(rest):
            home_ov = rest[i + 1]; i += 2
        elif a == "--expected-rev" and i + 1 < len(rest):
            expected_rev = int(rest[i + 1]); i += 2
        elif a == "--dry-run":
            dry = True; i += 1
        else:
            print(f"unknown arg: {a}", file=sys.stderr); return 3
    if (frm, to) not in SPEC_LEGAL_EDGES:
        print(f"ILLEGAL Spec transition: {frm} -> {to} (not in Spec schema; "
              f"refused)", file=sys.stderr)
        return 1
    if not _SPEC_ID_RE.fullmatch(spec_id):
        print(f"spec-transition: {spec_id!r} is not a valid spc-N id",
              file=sys.stderr)
        return 3
    home = _resolve_home(home_ov)
    if expected_rev is not None:
        actual = _ledger_rev(spec_id, home)
        if actual != expected_rev:
            print(f"record: expected-revision mismatch: caller expected "
                  f"rev={expected_rev} but ledger has {actual} entries "
                  f"(refusing)", file=sys.stderr)
            return 3
    entry = _build_entry(spec_id, frm, to, owner, reason, None)
    if dry:
        print(json.dumps(entry, indent=2))
        return 0
    lp = _ledger_path(spec_id, home)
    lp.parent.mkdir(parents=True, exist_ok=True)
    lockp = _lock_path(spec_id)
    lockp.parent.mkdir(parents=True, exist_ok=True)
    lock_fd = os.open(str(lockp), os.O_CREAT | os.O_WRONLY, 0o644)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        with lp.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(entry, separators=(",", ":")) + "\n")
    finally:
        _release_lock_fd(lock_fd)
    print(f"recorded: {spec_id} {frm} -> {to} ({owner})")
    return 0


def cmd_replay(args: list) -> int:
    """Replay Spec ledgers (identity + continuity + snapshot), mirroring the
    validator's ticket replay. Exit 1 on any illegal/inconsistent record."""
    home_ov = None
    i = 0
    while i < len(args):
        if args[i] == "--home" and i + 1 < len(args):
            home_ov = args[i + 1]; i += 2
        else:
            i += 1
    home = _resolve_home(home_ov)
    ledger_dir = home / ".transition-ledger"
    if not ledger_dir.is_dir():
        print(f"no ledger dir at {ledger_dir}", file=sys.stderr)
        return 0
    bad = 0
    total = 0
    for lp in sorted(ledger_dir.glob("spc-*.jsonl")):
        spec_id = lp.stem
        prev_to = last_to = None
        for lineno, line in enumerate(
                lp.read_text(encoding="utf-8").splitlines(), 1):
            line = line.strip()
            if not line:
                continue
            total += 1
            try:
                entry = json.loads(line)
            except json.JSONDecodeError as exc:
                print(f"{lp}:{lineno}: malformed JSON: {exc}", file=sys.stderr)
                bad += 1
                continue
            frm, to = entry.get("from", ""), entry.get("to", "")
            espec = entry.get("ticket") or entry.get("spec", "")
            if espec != spec_id:
                print(f"{lp}:{lineno}: identity mismatch: entry {espec!r} "
                      f"!= ledger {spec_id!r}", file=sys.stderr)
                bad += 1
            if (frm, to) not in SPEC_LEGAL_EDGES:
                print(f"{lp}:{lineno}: ILLEGAL Spec edge {frm} -> {to}",
                      file=sys.stderr)
                bad += 1
                prev_to = to
                last_to = to
                continue
            if prev_to is not None and frm != prev_to:
                print(f"{lp}:{lineno}: discontinuity: from={frm!r} but "
                      f"prior to={prev_to!r}", file=sys.stderr)
                bad += 1
            prev_to = to
            last_to = to
        if last_to is not None:
            spec_path = _find_spec_file(home, spec_id)
            if spec_path is not None:
                sst = _spec_status(spec_path.read_text(encoding="utf-8"))
                if sst is not None and sst != last_to:
                    print(f"{lp}: snapshot mismatch: ledger final to={last_to!r}"
                          f" but spec status={sst!r}", file=sys.stderr)
                    bad += 1
    print(f"spec replay: {total} entries, {bad} illegal/inconsistent")
    return 1 if bad else 0


def main(argv: list) -> int:
    if len(argv) < 2 or argv[1] in ("--help", "-h"):
        print(__doc__)
        return 0 if (len(argv) >= 2 and argv[1] in ("--help", "-h")) else 3
    cmd, rest = argv[1], argv[2:]
    if cmd == "done":
        return cmd_done(rest)
    if cmd == "superseded":
        return cmd_superseded(rest)
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
