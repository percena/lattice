#!/usr/bin/env python3
"""Recoverable coordinator — the persistent spine for batch/finish DAG
execution (spc-254 A5 / D4; rev-20260830-141357Z F4).

WHY: the durable execution core (DAG, layer/wave barrier, node attempt,
PID/PR/OID, marker owner, failure class, resume cursor) previously lived in
host LLM context. A host restart or context compaction lost the recovery
point and re-derived it by re-interpreting artifacts. This coordinator
persists that state to a versioned JSON file under
.lattice/.coordinator/<batch-id>.json so a restart resumes from the
persisted cursor without re-deriving.

D4 — coordinator constrains the path, not the model. This module performs
NO model inference: it never invokes claude / an LLM / agents --json. It does
only (a) JSON state file I/O and (b) one transition-api.py subprocess call
per settled node to record the binder status flip (consuming tkt-255). Scope,
brief, and exception interpretation stay in the Skills.

Consumes:
  - tkt-255 transition API — record-node calls transition-api.py to flip the
    binder status (in-progress -> pr-open on ok; in-progress -> stuck on
    unknown/timeout) so the binder SoT tracks the node's settled state.
  - tkt-257 classification — record-node receives ok|failed|timeout|unknown
    (the four-signal classification from run-process-wave's classify_node)
    and persists it as the node's failure_class.

State file shape (.lattice/.coordinator/<batch-id>.json):
  {
    "batch_id": "...", "started": "...", "updated": "...",
    "marker_owner": {"pid": N, "written_iso": "..."},
    "dag": [{"layer": 0, "waves": [{"wave": 0, "nodes": [
      {"ticket":"tkt-A","worktree":"/p","brief_file":"/p","timebox_min":60,
       "status":"ok","attempt":1,"pid":1234,"pr":42,"oid":"abc",
       "failure_class":"ok","marker_owner_pid":12345,
       "started_epoch":0,"ended_epoch":0,"reason":""}
    ]}]}],
    "resume_cursor": {"layer":0,"wave":0},
    "settled_tickets": ["tkt-A"]
  }

Exit codes: 0 ok; 1 state-missing / not-found; 2 usage; 3 io error.

Usage:
  coordinator.py init --batch-id <id> --lattice-home <dir>
  coordinator.py set-marker-owner --batch-id <id> --pid <PID> [--lattice-home <dir>]
  coordinator.py load-dag --batch-id <id> --layers-json <path> [--lattice-home <dir>]
  coordinator.py record-spawn --batch-id <id> --ticket <tkt> --layer <L> --wave <W> \
      --pid <PID> --worktree <path> --brief-file <path> --timebox <min> [--lattice-home <dir>]
  coordinator.py record-node --batch-id <id> --ticket <tkt> --status <class> \
      [--pid <PID>] [--pr <N>] [--oid <hex>] [--failure-class <class>] \
      [--reason <text>] --transition-api <path> [--lattice-home <dir>]
  coordinator.py advance-cursor --batch-id <id> --layer <L> --wave <W> [--lattice-home <dir>]
  coordinator.py resume --batch-id <id> [--lattice-home <dir>]
  coordinator.py status --batch-id <id> [--lattice-home <dir>]
  coordinator.py --self-test
  coordinator.py --help
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
import fcntl
from pathlib import Path
from typing import Optional

# Resolve the _lattice-lib sibling so transition-api.py is found by default.
_HERE = Path(__file__).resolve().parent
_LIB_DIR = _HERE.parent.parent / "_lattice-lib" / "scripts"  # ../../_lattice-lib/scripts
DEFAULT_TRANSITION_API = str(_LIB_DIR / "transition-api.py")


def now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def resolve_state_home() -> str:
    """Resolve Lattice's out-of-repo runtime state dir (ADR-011 / spc-282 A2).

    Coordinator state (.coordinator/<batch-id>.json + .lock + .state temps)
    lives OUT OF THE REPO TREE so it never leaks as untracked dirt in a fresh
    customer repo. Keyed by repo fingerprint (sha1(git-common-dir abspath)[:12])
    so all sibling worktrees of one MAIN clone resolve one coordinator spine.

    Priority: LATTICE_BATCH_GATE_HOME / LATTICE_STATE_HOME override →
    lattice-state-home.sh helper → inline fallback.
    """
    override = os.environ.get("LATTICE_BATCH_GATE_HOME") or os.environ.get("LATTICE_STATE_HOME")
    if override:
        return override
    # _HERE = skills/batch-work/scripts/lib; the _lattice-lib sibling is at
    # skills/_lattice-lib/scripts (3 up to skills/, NOT the pre-existing _LIB_DIR
    # which mis-resolves to batch-work/_lattice-lib). Compute the correct path
    # so the SoT helper is actually reached.
    helper = _HERE.parent.parent.parent / "_lattice-lib" / "scripts" / "lattice-state-home.sh"
    if helper.is_file():
        try:
            out = subprocess.run(
                ["bash", str(helper)], capture_output=True, text=True, timeout=5
            )
            if out.returncode == 0 and out.stdout.strip():
                return out.stdout.strip()
        except Exception:
            pass
    # Inline fallback (same algorithm as lattice-state-home.sh).
    import hashlib
    try:
        git_common = subprocess.run(
            ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
            capture_output=True, text=True, timeout=5,
        ).stdout.strip()
    except Exception:
        git_common = ""
    if not git_common:
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


def state_dir(lattice_home: str) -> Path:
    # ADR-011 / spc-282 A2: coordinator state relocates OUT of repo to the
    # state home (keyed by repo fingerprint). lattice_home is a legacy fallback
    # only when the state home cannot be resolved.
    home = resolve_state_home()
    if home:
        return Path(home) / ".coordinator"
    return Path(lattice_home) / ".coordinator"


def state_path(batch_id: str, lattice_home: str) -> Path:
    return state_dir(lattice_home) / f"{batch_id}.json"


def load_state(batch_id: str, lattice_home: str) -> dict:
    p = state_path(batch_id, lattice_home)
    if not p.is_file():
        print(f"error: coordinator state not found: {p}", file=sys.stderr)
        sys.exit(1)
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"error: coordinator state corrupted: {exc}", file=sys.stderr)
        sys.exit(1)


def save_state(state: dict, lattice_home: str) -> None:
    """Atomic write (temp + rename) with a flock so concurrent recorders
    (batch-work spawns sibling worktrees) cannot interleave or lose updates."""
    p = state_path(state["batch_id"], lattice_home)
    p.parent.mkdir(parents=True, exist_ok=True)
    state["updated"] = now_iso()
    lock_fd = os.open(str(p) + ".lock", os.O_CREAT | os.O_WRONLY, 0o644)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        # Read-merge-write under the lock so concurrent record-spawn/record-node
        # callers do not clobber each other's node updates (optimistic-merge).
        if p.is_file():
            try:
                cur = json.loads(p.read_text(encoding="utf-8"))
                _merge_state(cur, state)
                state = cur
                state["updated"] = now_iso()
            except (json.JSONDecodeError, KeyError):
                pass  # corrupted/missing — overwrite with the new state
        fd, tmp = tempfile.mkstemp(dir=str(p.parent), prefix=".state.")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(json.dumps(state, indent=2, sort_keys=True) + "\n")
            os.replace(tmp, p)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        os.close(lock_fd)


def _merge_state(cur: dict, new: dict) -> None:
    """Field-level merge so a caller updating one node does not wipe another
    caller's concurrent node update. DAG nodes are keyed by ticket; the resume
    cursor + marker_owner + settled_tickets are replaced wholesale."""
    if "marker_owner" in new and new["marker_owner"]:
        cur["marker_owner"] = new["marker_owner"]
    if "dag" in new:
        # Merge per-layer/wave/node by key; new nodes overwrite matching tickets.
        cur_layers = {l["layer"]: l for l in cur.get("dag", [])}
        for nl in new["dag"]:
            lid = nl["layer"]
            if lid not in cur_layers:
                cur_layers[lid] = nl
                continue
            cl = cur_layers[lid]
            cur_waves = {w["wave"]: w for w in cl.get("waves", [])}
            for nw in nl.get("waves", []):
                wid = nw["wave"]
                if wid not in cur_waves:
                    cur_waves[wid] = nw
                    continue
                cw = cur_waves[wid]
                cur_nodes = {n["ticket"]: n for n in cw.get("nodes", [])}
                for nn in nw.get("nodes", []):
                    cur_nodes[nn["ticket"]] = nn  # overwrite (update)
                cw["nodes"] = list(cur_nodes.values())
                cur_waves[wid] = cw
            cl["waves"] = list(cur_waves.values())
            cur_layers[lid] = cl
        cur["dag"] = [cur_layers[k] for k in sorted(cur_layers)]
    if "resume_cursor" in new:
        cur["resume_cursor"] = new["resume_cursor"]
    if "settled_tickets" in new:
        # Union so two concurrent record-node calls both register.
        cur_set = set(cur.get("settled_tickets", []))
        cur_set.update(new["settled_tickets"])
        cur["settled_tickets"] = sorted(cur_set)


# ---------------------------------------------------------------------------
# subcommands
# ---------------------------------------------------------------------------

def cmd_init(args: list) -> int:
    batch_id, lattice_home = _need(args, ["--batch-id", "--lattice-home"])
    p = state_path(batch_id, lattice_home)
    if p.is_file():
        print(f"exists: {p}")
        return 0
    state = {
        "batch_id": batch_id,
        "started": now_iso(),
        "updated": now_iso(),
        "marker_owner": None,
        "dag": [],
        "resume_cursor": {"layer": 0, "wave": 0},
        "settled_tickets": [],
    }
    save_state(state, lattice_home)
    print(f"init: {p}")
    return 0


def cmd_set_marker_owner(args: list) -> int:
    kv = _parse(args, ["--batch-id", "--pid"], ["--lattice-home"])
    batch_id = kv["--batch-id"]
    lattice_home = kv.get("--lattice-home") or os.environ.get("LATTICE_HOME", ".lattice")
    pid = kv["--pid"]
    state = load_state(batch_id, lattice_home)
    state["marker_owner"] = {"pid": int(pid), "written_iso": now_iso()}
    save_state(state, lattice_home)
    print(f"marker-owner: batch={batch_id} pid={pid}")
    return 0


def cmd_load_dag(args: list) -> int:
    kv = _parse(args, ["--batch-id", "--layers-json"], ["--lattice-home"])
    batch_id = kv["--batch-id"]
    lattice_home = kv.get("--lattice-home") or os.environ.get("LATTICE_HOME", ".lattice")
    layers_path = kv["--layers-json"]
    try:
        plan = json.loads(Path(layers_path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"error: --layers-json unreadable: {exc}", file=sys.stderr)
        return 3
    layers = plan.get("layers", []) if isinstance(plan, dict) else plan
    # Normalize: each node gets the full field set so later updates merge cleanly.
    for layer in layers:
        for wave in layer.get("waves", []):
            for node in wave.get("nodes", []):
                node.setdefault("status", "pending")
                node.setdefault("attempt", 0)
                node.setdefault("pid", None)
                node.setdefault("pr", None)
                node.setdefault("oid", None)
                node.setdefault("failure_class", None)
                node.setdefault("marker_owner_pid", None)
                node.setdefault("started_epoch", 0)
                node.setdefault("ended_epoch", 0)
                node.setdefault("reason", "")
    state = load_state(batch_id, lattice_home)
    state["dag"] = layers
    save_state(state, lattice_home)
    nl = len(layers)
    nn = sum(len(w.get("nodes", [])) for l in layers for w in l.get("waves", []))
    print(f"load-dag: {nl} layer(s), {nn} node(s)")
    return 0


def cmd_record_spawn(args: list) -> int:
    kv = _parse(
        args,
        ["--batch-id", "--ticket", "--layer", "--wave", "--pid",
         "--worktree", "--brief-file", "--timebox"],
        ["--lattice-home"],
    )
    batch_id = kv["--batch-id"]
    lattice_home = kv.get("--lattice-home") or os.environ.get("LATTICE_HOME", ".lattice")
    node = {
        "ticket": kv["--ticket"],
        "worktree": kv["--worktree"],
        "brief_file": kv["--brief-file"],
        "timebox_min": int(kv["--timebox"]),
        "status": "running",
        "attempt": 1,
        "pid": int(kv["--pid"]),
        "pr": None,
        "oid": None,
        "failure_class": None,
        "marker_owner_pid": int(kv["--pid"]) if kv.get("--pid") else None,
        "started_epoch": int(time.time()),
        "ended_epoch": 0,
        "reason": "spawned",
    }
    wave = {"wave": int(kv["--wave"]), "nodes": [node]}
    layer = {"layer": int(kv["--layer"]), "waves": [wave]}
    state = load_state(batch_id, lattice_home)
    state["dag"] = [layer]  # merge adds/overwrites this node
    save_state(state, lattice_home)
    print(f"record-spawn: {kv['--ticket']} pid={kv['--pid']} "
          f"layer={kv['--layer']} wave={kv['--wave']}")
    return 0


def cmd_record_node(args: list) -> int:
    kv = _parse(
        args,
        ["--batch-id", "--ticket", "--status"],
        ["--pid", "--pr", "--oid", "--failure-class", "--reason",
         "--transition-api", "--lattice-home"],
    )
    batch_id = kv["--batch-id"]
    lattice_home = kv.get("--lattice-home") or os.environ.get("LATTICE_HOME", ".lattice")
    status = kv["--status"]
    ticket = kv["--ticket"]
    failure_class = kv.get("--failure-class") or status
    tapi = kv.get("--transition-api") or DEFAULT_TRANSITION_API

    # Persist the node's settled state (failure class, PID/PR/OID, epochs).
    node = {
        "ticket": ticket,
        "status": status,
        "failure_class": failure_class,
        "pid": int(kv["--pid"]) if kv.get("--pid") else None,
        "pr": int(kv["--pr"]) if kv.get("--pr") else None,
        "oid": kv.get("--oid"),
        "ended_epoch": int(time.time()),
        "reason": kv.get("--reason") or status,
    }
    state = load_state(batch_id, lattice_home)
    _patch_node(state, ticket, node)
    settled = set(state.get("settled_tickets", []))
    settled.add(ticket)
    state["settled_tickets"] = sorted(settled)
    save_state(state, lattice_home)

    # tkt-298: the coordinator no longer duplicates the ok→pr-open flip. The
    # worker (spawned agent) owns that flip: it runs start-work (in-progress
    # stamp) then create-pr → stamp-pr-open, which (post-tkt-271 A1.3) flips
    # the binder in-progress→pr-open via `commit` and records the ledger
    # atomically. The worker STOPS at create-pr, so by the time the coordinator
    # settles an `ok` node the binder is already pr-open; a second record would
    # be a discontinuity (A1.5). For `unknown`/`timeout` (worker crashed/timed
    # out — no PR created, binder still in-progress) the coordinator IS the
    # sole recorder, so it flips the binder to `stuck` via `commit`
    # (in-progress→stuck + wait_reason: unblock) — binder + ledger agree
    # atomically (A1.3); the validator's snapshot/continuity checks stay clean.
    # Best-effort: a missing/errored transition-api or a missing binder (worker
    # crashed before start-work stamped one) MUST NOT lose the persisted DAG
    # state (already written above); it warns so the host's triage still sees
    # the unrecorded binder flip. `failed` records the failure class only (host
    # triages the crashed worker's binder).
    if status in ("unknown", "timeout"):
        reason = kv.get("--reason") or f"coordinator: node {status}"
        if Path(tapi).is_file():
            env = dict(os.environ, LATTICE_HOME=lattice_home)
            try:
                result = subprocess.run(
                    [sys.executable, tapi, "commit", ticket,
                     "stuck", "system", reason,
                     "--wait-reason", "unblock",
                     "--trace", "wait_reason: unblock"],
                    env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                    check=False, timeout=10,
                )
                if result.returncode != 0:
                    print(f"warn: transition-api commit returned {result.returncode} "
                          f"for {ticket} (binder missing/crashed before stamp?); "
                          f"DAG state unchanged", file=sys.stderr)
            except (subprocess.TimeoutExpired, OSError) as exc:
                print(f"warn: transition-api commit failed for {ticket}: {exc}",
                      file=sys.stderr)
        else:
            print(f"warn: transition-api not found; cannot commit stuck flip "
                  f"for {ticket}", file=sys.stderr)
    print(f"record-node: {ticket} status={status} failure_class={failure_class}")
    return 0


def _patch_node(state: dict, ticket: str, patch: dict) -> None:
    """Apply a partial node update (merge patch fields) to the node matching
    <ticket> in the persisted DAG. No-op if the node has not been spawned
    yet (the coordinator accumulates whatever was recorded)."""
    for layer in state.get("dag", []):
        for wave in layer.get("waves", []):
            for node in wave.get("nodes", []):
                if node.get("ticket") == ticket:
                    for k, v in patch.items():
                        if v is not None:
                            node[k] = v
                    return
    # Node not yet in the DAG (e.g. spawned-but-dead before record-spawn ran):
    # append a minimal node entry on layer 0 wave 0 so the settled state is
    # still captured for resume (a missing entry would let a restart re-run a
    # ticket that already settled — the exact re-derivation A5 forbids).
    if not state.get("dag"):
        state["dag"] = [{"layer": 0, "waves": [{"wave": 0, "nodes": []}]}]
    node = {"ticket": ticket, "status": "pending", "attempt": 0,
            "pid": None, "pr": None, "oid": None, "failure_class": None,
            "marker_owner_pid": None, "started_epoch": 0, "ended_epoch": 0,
            "worktree": "", "brief_file": "", "timebox_min": 0, "reason": ""}
    for k, v in patch.items():
        if v is not None:
            node[k] = v
    state["dag"][0]["waves"][0]["nodes"].append(node)


def cmd_advance_cursor(args: list) -> int:
    kv = _parse(args, ["--batch-id", "--layer", "--wave"], ["--lattice-home"])
    batch_id = kv["--batch-id"]
    lattice_home = kv.get("--lattice-home") or os.environ.get("LATTICE_HOME", ".lattice")
    state = load_state(batch_id, lattice_home)
    state["resume_cursor"] = {"layer": int(kv["--layer"]), "wave": int(kv["--wave"])}
    save_state(state, lattice_home)
    print(f"advance-cursor: layer={kv['--layer']} wave={kv['--wave']}")
    return 0


def cmd_resume(args: list) -> int:
    kv = _parse(args, ["--batch-id"], ["--lattice-home"])
    batch_id = kv["--batch-id"]
    lattice_home = kv.get("--lattice-home") or os.environ.get("LATTICE_HOME", ".lattice")
    state = load_state(batch_id, lattice_home)
    settled = set(state.get("settled_tickets", []))
    cursor = state.get("resume_cursor", {"layer": 0, "wave": 0})
    pending = []
    for layer in state.get("dag", []):
        if layer["layer"] < cursor["layer"]:
            continue
        for wave in layer.get("waves", []):
            if layer["layer"] == cursor["layer"] and wave["wave"] < cursor["wave"]:
                continue
            for node in wave.get("nodes", []):
                if node["ticket"] not in settled:
                    pending.append({
                        "ticket": node["ticket"],
                        "layer": layer["layer"],
                        "wave": wave["wave"],
                        "worktree": node.get("worktree", ""),
                        "brief_file": node.get("brief_file", ""),
                        "timebox_min": node.get("timebox_min", 0),
                    })
    resume = {
        "batch_id": batch_id,
        "resume_cursor": cursor,
        "settled_tickets": sorted(settled),
        "pending": pending,
        "marker_owner": state.get("marker_owner"),
    }
    print(json.dumps(resume, indent=2))
    return 0


def cmd_status(args: list) -> int:
    kv = _parse(args, ["--batch-id"], ["--lattice-home"])
    batch_id = kv["--batch-id"]
    lattice_home = kv.get("--lattice-home") or os.environ.get("LATTICE_HOME", ".lattice")
    state = load_state(batch_id, lattice_home)
    print(json.dumps(state, indent=2, sort_keys=True))
    return 0


# ---------------------------------------------------------------------------
# arg parsing helpers
# ---------------------------------------------------------------------------

def _parse(args: list, required: list, optional: list = None) -> dict:
    """Flag/value parser. `required` keys must be present or exit 2."""
    optional = optional or []
    kv: dict = {}
    i = 0
    while i < len(args):
        flag = args[i]
        if flag in required or flag in optional:
            if i + 1 >= len(args):
                print(f"usage error: {flag} needs a value", file=sys.stderr)
                sys.exit(2)
            kv[flag] = args[i + 1]
            i += 2
        elif flag == "--lattice-home":  # always accepted as optional
            if i + 1 >= len(args):
                print("usage error: --lattice-home needs a value", file=sys.stderr)
                sys.exit(2)
            kv["--lattice-home"] = args[i + 1]
            i += 2
        else:
            print(f"usage error: unknown arg '{flag}'", file=sys.stderr)
            sys.exit(2)
    missing = [k for k in required if k not in kv]
    if missing:
        print(f"usage error: missing required {missing}", file=sys.stderr)
        sys.exit(2)
    return kv


def _need(args: list, flags: list) -> tuple:
    """Strict required-only parser (returns a tuple in flag order)."""
    kv = _parse(args, flags)
    return tuple(kv[f] for f in flags)


# ---------------------------------------------------------------------------
# self-test
# ---------------------------------------------------------------------------

def self_test() -> int:
    import tempfile
    fail = 0

    def chk(label: str, fn) -> None:
        nonlocal fail
        if fn():
            print(f"PASS: {label}")
        else:
            print(f"FAIL: {label}")
            fail += 1

    home = tempfile.mkdtemp(prefix="coord-st.")
    bid = "st-batch"

    def run(*a) -> int:
        return subprocess.run(
            [sys.executable, str(_HERE / "coordinator.py"), *a],
            env=dict(os.environ, LATTICE_HOME=home),
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        ).returncode

    # T1: init creates the state file
    def t1() -> bool:
        r = run("init", "--batch-id", bid, "--lattice-home", home)
        return r == 0 and state_path(bid, home).is_file()
    chk("T1: init creates state file", t1)

    # T2: load-dag persists layers
    def t2() -> bool:
        lj = Path(home) / "layers.json"
        lj.write_text(json.dumps({"layers": [
            {"layer": 0, "waves": [{"wave": 0, "nodes": [
                {"ticket": "tkt-A", "worktree": "/p", "brief_file": "/b",
                 "timebox_min": 5}]}]},
            {"layer": 1, "waves": [{"wave": 0, "nodes": [
                {"ticket": "tkt-B", "worktree": "/q", "brief_file": "/c",
                 "timebox_min": 10}]}]},
        ]}), encoding="utf-8")
        r = run("load-dag", "--batch-id", bid, "--layers-json", str(lj),
                "--lattice-home", home)
        if r != 0:
            return False
        st = load_state(bid, home)
        return len(st["dag"]) == 2 and st["dag"][0]["waves"][0]["nodes"][0]["ticket"] == "tkt-A"
    chk("T2: load-dag persists 2 layers", t2)

    # T3: record-spawn + record-node updates the node in place (merge, no wipe)
    def t3() -> bool:
        run("record-spawn", "--batch-id", bid, "--ticket", "tkt-A",
            "--layer", "0", "--wave", "0", "--pid", "4242",
            "--worktree", "/p", "--brief-file", "/b", "--timebox", "5",
            "--lattice-home", home)
        st = load_state(bid, home)
        n = st["dag"][0]["waves"][0]["nodes"][0]
        if n.get("status") != "running" or n.get("pid") != 4242:
            return False
        # record-node for a non-ok node without transition-api must still persist
        run("record-node", "--batch-id", bid, "--ticket", "tkt-A",
            "--status", "failed", "--pid", "4242", "--failure-class", "failed",
            "--reason", "crash", "--transition-api", "/nonexistent/tapi.py",
            "--lattice-home", home)
        st = load_state(bid, home)
        n = st["dag"][0]["waves"][0]["nodes"][0]
        return (n.get("status") == "failed" and n.get("failure_class") == "failed"
                and "tkt-A" in st.get("settled_tickets", []))
    chk("T3: record-spawn + record-node merge-update (no wipe)", t3)

    # T4: resume reports the pending (unsettled) ticket only
    def t4() -> bool:
        r = subprocess.run(
            [sys.executable, str(_HERE / "coordinator.py"), "resume",
             "--batch-id", bid, "--lattice-home", home],
            env=dict(os.environ, LATTICE_HOME=home),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        if r.returncode != 0:
            return False
        out = json.loads(r.stdout)
        return ("tkt-A" in out["settled_tickets"]
                and any(p["ticket"] == "tkt-B" for p in out["pending"]))
    chk("T4: resume lists settled + pending (no re-derive)", t4)

    # T5: advance-cursor moves the resume point
    def t5() -> bool:
        run("advance-cursor", "--batch-id", bid, "--layer", "1", "--wave", "0",
            "--lattice-home", home)
        st = load_state(bid, home)
        return st["resume_cursor"] == {"layer": 1, "wave": 0}
    chk("T5: advance-cursor moves resume point", t5)

    # T6: NO model inference — the coordinator source never invokes claude /
    # agents / an LLM as a subprocess target. D4: constrain the path, not the
    # model. This is a static source check: a subprocess call whose argv
    # references "claude" or "agents" would violate D4.
    def t6() -> bool:
        import re
        src = Path(__file__).read_text(encoding="utf-8")
        calls = re.findall(r"subprocess\.\w+\([^)]*\)", src, re.DOTALL)
        bad = [c for c in calls if re.search(r'["\']claude|["\']agents\b', c)]
        return not bad
    chk("T6: no model inference (no claude/agents subprocess)", t6)

    import shutil
    shutil.rmtree(home, ignore_errors=True)
    print()
    if fail == 0:
        print("coordinator.py --self-test passed")
    else:
        print(f"coordinator.py --self-test FAILED ({fail} failure(s))")
        return 1
    return 0


def main(argv: list) -> int:
    if len(argv) < 2 or argv[1] in ("--help", "-h"):
        print(__doc__)
        return 0
    cmd, rest = argv[1], argv[2:]
    if cmd == "--self-test":
        return self_test()
    handlers = {
        "init": cmd_init,
        "set-marker-owner": cmd_set_marker_owner,
        "load-dag": cmd_load_dag,
        "record-spawn": cmd_record_spawn,
        "record-node": cmd_record_node,
        "advance-cursor": cmd_advance_cursor,
        "resume": cmd_resume,
        "status": cmd_status,
    }
    fn = handlers.get(cmd)
    if fn is None:
        print(f"unknown command: {cmd}", file=sys.stderr)
        return 2
    return fn(rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
