#!/usr/bin/env python3
"""finish-stamp.py — simplified local stamp (ADR-013 Option E+ Layer 1).

Replaces the 732-line bash+Python hybrid finish-ledger.sh with ~80 lines of
pure Python. Key design decisions (proven by dry run):
  - No commit_transaction (binder write = temp→rename, ledger = record CLI)
  - No FLIP_HAPPENED (staging assertion in same Python process)
  - No || true (subprocess.run with check=True)
  - No hardcoded edge (reads actual prior status from binder)
  - Idempotent (no-op if already closed)
  - Mode C repair: checks ledger continuity before stamping

DRY RUN PROTOTYPE — do not ship yet. Proves the design works.
"""
import sys, os, re, json, subprocess, tempfile, stat, datetime, shutil

def main():
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("--pr", type=int)
    p.add_argument("--binder", required=True)
    p.add_argument("--merged-at", default="")
    p.add_argument("--closed-at", default="")
    p.add_argument("--issue", type=int)
    p.add_argument("--pr-state", default="MERGED")
    p.add_argument("--pr-url", default="")
    p.add_argument("--reason", default="merge")
    p.add_argument("--home", default="")
    args = p.parse_args()

    binder_path = os.path.realpath(args.binder)
    if not os.path.isfile(binder_path):
        print(f"finish-stamp: no binder at {binder_path} — skip", file=sys.stderr)
        return 0

    # Resolve library path
    script_dir = os.path.dirname(os.path.realpath(__file__))
    lib_dir = os.path.join(script_dir, "lib")
    sys.path.insert(0, lib_dir)
    import binder_rows, status_vocab
    sys.path.insert(0, script_dir)
    import importlib.util
    ta_path = os.path.join(script_dir, "transition-api.py")
    ta_spec = importlib.util.spec_from_file_location("transition_api", ta_path)
    ta = importlib.util.module_from_spec(ta_spec)
    ta_spec.loader.exec_module(ta)

    # Resolve lattice home from binder path
    # .lattice/tickets/tkt-N-slug/README.md → .lattice
    b = binder_path
    home = None
    if os.path.basename(b) == "README.md":
        parent = os.path.dirname(b)
        if os.path.basename(os.path.dirname(parent)) == "tickets":
            home = os.path.dirname(os.path.dirname(parent))
    if not home:
        home = os.environ.get("LATTICE_HOME", ".lattice")

    # Read binder
    text = open(binder_path, encoding="utf-8").read()
    status_match = re.search(r'\|\s*status\s*\|\s*(\S+)\s*\|', text)
    if not status_match:
        print("finish-stamp: ERROR — binder has no | status | row", file=sys.stderr)
        return 1
    prior_status = status_match.group(1)

    # Idempotent: already closed + ledger last to=closed → no-op
    ticket_id = ""
    m_tid = re.match(r'^(tkt-[1-9][0-9]*)', os.path.basename(os.path.dirname(binder_path)))
    if m_tid:
        ticket_id = m_tid.group(1)
    ledger_path = ta.ledger_path(ticket_id, home)

    if status_vocab.is_terminal(prior_status):
        # Already closed — check ledger consistency
        try:
            lines = ledger_path.read_text(encoding="utf-8").strip().splitlines()
            last_to = json.loads(lines[-1]).get("to", "") if lines else ""
        except (OSError, ValueError):
            last_to = ""
        if last_to == "closed":
            print(f"finish-stamp: no change (idempotent — {ticket_id} already closed)")
            return 0
        # Binder says closed but ledger doesn't — repair
        print(f"finish-stamp: WARNING — binder closed but ledger last to={last_to!r}; repairing", file=sys.stderr)

    # --- Mode C repair: check ledger continuity ---
    # If the ledger's last `to` != the binder's prior status, the intermediate
    # edge was lost in squash merge. Insert the missing edge before stamping.
    try:
        lines = ledger_path.read_text(encoding="utf-8").strip().splitlines() if ledger_path.exists() else []
        ledger_last_to = json.loads(lines[-1]).get("to", "") if lines else ""
    except (OSError, ValueError):
        ledger_last_to = ""

    if ledger_last_to and ledger_last_to != prior_status:
        # Missing intermediate edge — insert it
        print(f"finish-stamp: Mode C repair — ledger last to={ledger_last_to!r} but binder status={prior_status!r}; inserting missing edge", file=sys.stderr)
        rc = subprocess.run([
            sys.executable, ta_path, "record", ticket_id,
            ledger_last_to, prior_status, "agent", "create-pr opens the PR",
            "--home", home
        ], capture_output=True, text=True)
        if rc.returncode != 0:
            print(f"finish-stamp: ERROR — Mode C repair failed: {rc.stderr}", file=sys.stderr)
            return 1
        print(f"finish-stamp: Mode C repaired — inserted {ledger_last_to}→{prior_status}")

    # --- Write binder ---
    updated_stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    new_text = text

    # status → closed
    new_text = re.sub(r'(\|\s*status\s*\|\s*)\S+(\s*\|)', r'\1closed\2', new_text, count=1)
    # updated stamp
    new_text = binder_rows.stamp_updated(new_text, updated_stamp)

    # ## Finish body
    entry_line = f"- pr-{args.pr} merged: {args.merged_at}"
    if args.pr_url:
        entry_line += f" — {args.pr_url}"
    if args.pr_state == "MERGED":
        entry_line += " (base merge)"
    finish_section = re.search(r'(^## Finish\s*\n)(.*?)(?=\n## |\Z)', new_text, re.DOTALL | re.MULTILINE)
    if not finish_section:
        new_text = new_text.rstrip() + f"\n\n## Finish\n\n{entry_line}\n"
    else:
        head, body = finish_section.group(1), finish_section.group(2)
        body = re.sub(r'^- \(none yet\)\s*\n?', '', body, flags=re.MULTILINE)
        body = re.sub(rf'^- pr-{args.pr} .*$', '', body, flags=re.MULTILINE)
        body = re.sub(r'\n{3,}', '\n\n', body).rstrip()
        body = (body + "\n" if body else "") + entry_line + "\n"
        new_text = new_text[:finish_section.start()] + head + body + new_text[finish_section.end():]

    # prs row
    if args.pr_url:
        prs_row_re = re.compile(r'(\| prs \|)\s*(.*?)\s*(\|)')
        prs_match = prs_row_re.search(new_text)
        if prs_match:
            merged_row = binder_rows.merge_row(prs_match.group(2), args.pr, args.pr_url)
            new_text = prs_row_re.sub(lambda m: f"{m.group(1)} {merged_row} {m.group(3)}", new_text, count=1)

    # Atomic write: temp → rename
    d = os.path.dirname(binder_path) or "."
    mode = os.stat(binder_path).st_mode
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".finish-stamp.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(new_text)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp, stat.S_IMODE(mode))
        os.replace(tmp, binder_path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    print(f"finish-stamp: stamped binder ({ticket_id}: {prior_status} → closed)")

    # --- Append ledger via record CLI (proven reliable) ---
    rc = subprocess.run([
        sys.executable, ta_path, "record", ticket_id,
        prior_status, "closed", "human", args.reason,
        "--home", home
    ], capture_output=True, text=True)
    if rc.returncode != 0:
        print(f"finish-stamp: ERROR — record CLI failed (rc={rc.returncode}): {rc.stderr}", file=sys.stderr)
        return 1
    print(f"finish-stamp: recorded ledger entry ({prior_status} → closed)")

    # --- Stage both files (NO || true — fail loud) ---
    repo_root = subprocess.run(
        ["git", "-C", os.path.dirname(binder_path), "rev-parse", "--show-toplevel"],
        capture_output=True, text=True
    ).stdout.strip()
    if not repo_root:
        print("finish-stamp: ERROR — binder not in a git repo", file=sys.stderr)
        return 1

    ledger_rel = str(ledger_path).replace(repo_root + "/", "")
    if ledger_rel == str(ledger_path):
        ledger_rel = f".lattice/.transition-ledger/{ticket_id}.jsonl"

    for path in [binder_path, str(ledger_path)]:
        result = subprocess.run(["git", "-C", repo_root, "add", "--", path],
                                capture_output=True, text=True)
        if result.returncode != 0:
            print(f"finish-stamp: ERROR — git add failed for {path}: {result.stderr}", file=sys.stderr)
            return 1

    # --- Verify staging (fail loud — no FLIP_HAPPENED) ---
    staged = subprocess.run(
        ["git", "-C", repo_root, "diff", "--cached", "--name-only"],
        capture_output=True, text=True
    ).stdout.strip().splitlines()
    staged_set = set(staged)

    binder_rel = binder_path.replace(repo_root + "/", "")
    if binder_rel not in staged_set:
        print(f"finish-stamp: ERROR — binder {binder_rel} NOT staged after git add", file=sys.stderr)
        return 1
    if ledger_rel not in staged_set:
        print(f"finish-stamp: ERROR — ledger {ledger_rel} NOT staged after git add", file=sys.stderr)
        print(f"  common cause: .transition-ledger/ is gitignored, or held index lock", file=sys.stderr)
        return 1

    print(f"finish-stamp: staged binder + ledger ({ticket_id})")
    print(f"flip: 1")
    return 0

if __name__ == "__main__":
    sys.exit(main())
