#!/usr/bin/env python3
"""finish-stamp.py — simplified local stamp (ADR-013 Option E+ Layer 1).

Replaces the 732-line bash+Python hybrid finish-ledger.sh heredoc + bash staging
with pure Python. Key design decisions (proven by 22/22 dry-run assertions):
  - No commit_transaction (binder write = temp→rename, ledger = record CLI)
  - No FLIP_HAPPENED (staging assertion in same Python process)
  - No || true (subprocess.run checked, fail loud)
  - No hardcoded edge (reads actual prior status from binder)
  - Idempotent (no-op if already closed + ledger consistent)
  - Mode C repair: checks ledger continuity before stamping
  - Cancel path supported (--cancel --reason)

Called by finish-ledger.sh AFTER the front-end resolves gh dates, PR state,
repo identity, and binder path security. This script does the write + stage.
"""
import sys, os, re, json, subprocess, tempfile, stat, datetime, fcntl

def main():
    import argparse
    p = argparse.ArgumentParser(description="Stamp a merged/cancelled ticket binder to closed.")
    p.add_argument("--binder", required=True)
    p.add_argument("--pr", type=int, default=None)
    p.add_argument("--merged-at", default="")
    p.add_argument("--closed-at", default="")
    p.add_argument("--issue", type=int, default=None)
    p.add_argument("--pr-state", default="MERGED")
    p.add_argument("--pr-url", default="")
    p.add_argument("--reason", default="")
    p.add_argument("--cancel", action="store_true")
    p.add_argument("--state-reason", default="")
    p.add_argument("--issue-base", default="")
    args = p.parse_args()

    cancel = args.cancel
    reason = args.reason or ("cancel" if cancel else "merge")

    binder_path = os.path.realpath(args.binder)
    if not os.path.isfile(binder_path):
        print(f"finish-stamp: no binder at {binder_path} — skip (ticket-only flow)", file=sys.stderr)
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
    home = ta.home_for_binder(binder_path)
    if not home:
        home = os.environ.get("LATTICE_HOME", ".lattice")

    # Ticket ID from directory name
    ticket_id = ""
    m_tid = re.match(r'^(tkt-[1-9][0-9]*)', os.path.basename(os.path.dirname(binder_path)))
    if m_tid:
        ticket_id = m_tid.group(1)
    ledger_path = ta.ledger_path(ticket_id, home)

    # Take exclusive dir lock (same as the old heredoc — two finish sessions
    # stamping sibling PRs would otherwise both read old content and the second
    # rename would drop the first PR's line).
    lock_dir = os.path.dirname(os.path.abspath(binder_path)) or "."
    lock_fd = os.open(lock_dir, os.O_RDONLY)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
    except OSError as exc:
        os.close(lock_fd)
        print(f"finish-stamp: ERROR — cannot lock binder directory: {exc}", file=sys.stderr)
        return 1

    try:
        return _stamp_inner(binder_path, ticket_id, ledger_path, home, ta, ta_path,
                            binder_rows, status_vocab, args, cancel, reason)
    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
        except OSError:
            pass
        os.close(lock_fd)


def _stamp_inner(binder_path, ticket_id, ledger_path, home, ta, ta_path,
                 binder_rows, status_vocab, args, cancel, reason):
    # Read binder INSIDE the lock
    text = open(binder_path, encoding="utf-8").read()
    orig = text

    status_match = re.search(r'\|\s*status\s*\|\s*(\S+)\s*\|', text)
    if not status_match:
        print("finish-stamp: ERROR — binder has no | status | row", file=sys.stderr)
        return 1
    prior_status = status_match.group(1)

    merged = (not cancel) and args.pr_state == "MERGED"
    already_closed = status_vocab.is_terminal(prior_status)
    # flip_close: only flip to closed when there's terminal evidence
    # (cancel, OR merged PR, OR closing issue actually closed). A CLOSED PR
    # without a closing issue is NOT terminal — the ## Finish body is updated
    # but the status stays non-terminal (tkt-179 A3, finish-work SKILL.md).
    issue_closed = bool(args.issue and args.closed_at)
    flip_close = cancel or merged or issue_closed

    # --- Mode C repair: check ledger continuity ---
    # Only when NOT already closed (we're about to flip). Skip when ledger's
    # last `to` is terminal (closed→rework is illegal — data inconsistency,
    # not a missing intermediate edge).
    try:
        lines = ledger_path.read_text(encoding="utf-8").strip().splitlines() if ledger_path.exists() else []
        ledger_last_to = json.loads(lines[-1]).get("to", "") if lines else ""
    except (OSError, ValueError):
        ledger_last_to = ""

    if (not already_closed) and ledger_last_to and ledger_last_to != prior_status \
       and not status_vocab.is_terminal(ledger_last_to):
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

    # --- Build ## Finish entry line ---
    if cancel:
        entry_line = f"- cancelled: {args.reason}"
        if args.closed_at:
            entry_line += f" — {args.closed_at}"
        elif args.issue:
            entry_line += f" — closedAt: unavailable (issue #{args.issue} CLOSED but closedAt null)"
        entry_pat = re.compile(r'^- cancelled: .*$', re.MULTILINE)
    else:
        if merged:
            entry_line = f"- pr-{args.pr} merged: {args.merged_at}"
        else:
            entry_line = f"- pr-{args.pr} closed without merge"
        if args.pr_url:
            entry_line += f" — {args.pr_url}"
        if merged:
            entry_line += " (base merge)"
        entry_pat = re.compile(rf'^- pr-{re.escape(str(args.pr))} (?:merged:|closed without merge).*$', re.MULTILINE)

    # --- Anomaly lines (ADR-012 §3: direct jump / side state) ---
    anomaly_line = ""
    if (not cancel) and merged and prior_status in {"parked", "stuck", "deferred", "rework"}:
        anomaly_line = f"\n- anomaly: prior status `{prior_status}` before terminal merge — external truth preserved"
    elif (not cancel) and merged and prior_status in {"queued", "in-progress"}:
        anomaly_line = (f"\n- anomaly: direct jump — prior status `{prior_status}` before terminal merge; "
                        f"in-progress/pr-open stamps were skipped (ADR-012 §3; metric direct-jump)")

    # --- Issue line ---
    issue_line = ""
    if args.issue and args.closed_at:
        base = ""
        if args.pr_url:
            base = args.pr_url.split("/pull/")[0]
        elif args.issue_base:
            base = args.issue_base
        reason_suffix = f" (reason: {args.state_reason})" if args.state_reason else ""
        if base:
            issue_line = f"\n- issue #{args.issue} closed: {args.closed_at}{reason_suffix} — {base}/issues/{args.issue}"
        else:
            issue_line = f"\n- issue #{args.issue} closed: {args.closed_at}{reason_suffix} — https://github.com/<org>/<repo>/issues/{args.issue}"
    elif args.issue and not cancel and not args.closed_at:
        issue_line = f"\n- issue #{args.issue}: not closed (closed-without-merge? status recorded without mergedAt claim)"

    # Issue close-reason anomaly
    if (not cancel) and args.issue and args.state_reason and args.state_reason != "completed":
        anomaly_line += f"\n- anomaly: issue #{args.issue} closed as {args.state_reason.upper()} while PR #{args.pr} delivers it — reconcile close-reason vs delivery"

    # --- Update ## Finish section ---
    m = re.search(r'(^## Finish\s*\n)(.*?)(?=\n## |\Z)', text, re.DOTALL | re.MULTILINE)
    if not m:
        text = text.rstrip() + "\n\n## Finish\n\n" + entry_line + anomaly_line + issue_line + "\n"
    else:
        head, body = m.group(1), m.group(2)
        if entry_pat.search(body):
            body = entry_pat.sub(entry_line, body)
            if anomaly_line:
                anom_pat = re.compile(r'^- anomaly: .*$', re.MULTILINE)
                body = anom_pat.sub('', body)
                body = re.sub(r'\n{3,}', '\n\n', body).rstrip()
                body = body + anomaly_line + "\n" if body else anomaly_line + "\n"
            if issue_line:
                iss_pat = re.compile(rf'^- issue #{re.escape(str(args.issue))}.*$', re.MULTILINE) if args.issue else None
                iss_m = iss_pat.search(body) if iss_pat else None
                if iss_m:
                    body = iss_pat.sub(issue_line.lstrip("\n"), body)
                else:
                    body = body.rstrip() + issue_line + "\n"
        else:
            body = re.sub(r'^- \(none yet\)\s*\n?', '', body, flags=re.MULTILINE)
            body = body.rstrip()
            if body:
                body = body + "\n" + entry_line + anomaly_line + issue_line + "\n"
            else:
                body = "\n" + entry_line + anomaly_line + issue_line + "\n"
        text = text[:m.start()] + head + body + text[m.end():]

    # --- status → closed (only when flip_close: cancel, merged, or issue closed) ---
    should_flip = flip_close and not already_closed
    if should_flip:
        text = re.sub(r'(\|\s*status\s*\|\s*)\S+(\s*\|)', r'\1closed\2', text, count=1)

    # --- prs row (not for cancel — no PR) ---
    if args.pr_url and not cancel:
        prs_row_re = re.compile(r'(\| prs \|)\s*(.*?)\s*(\|)')
        prs_match = prs_row_re.search(text)
        if prs_match:
            merged_row = binder_rows.merge_row(prs_match.group(2), args.pr, args.pr_url)
            text = prs_row_re.sub(lambda m: f"{m.group(1)} {merged_row} {m.group(3)}", text, count=1)

    # --- Determine what changed (content only — updated stamp applied later) ---
    # A3 idempotency: compare content BEFORE the updated-stamp bump, so a re-run
    # on an already-closed binder with a consistent ledger is a true no-op (no
    # staged timestamp bump, no noise commit). The GHA safety net (A6) relies on
    # this — without it, every pull_request:closed fires a timestamp-bump commit.
    content_changed = text != orig
    # flip_happened = a real status flip (non-terminal → closed) — controls ledger
    flip_happened = should_flip and content_changed

    # Check if ledger needs repair (binder closed but ledger missing to=closed)
    ledger_needs_repair = False
    if already_closed and not flip_happened:
        try:
            lines = ledger_path.read_text(encoding="utf-8").strip().splitlines()
            last_to = json.loads(lines[-1]).get("to", "") if lines else ""
            if last_to != "closed":
                ledger_needs_repair = True
        except (OSError, ValueError):
            ledger_needs_repair = True

    # --- Idempotent no-op (A3): no content change AND ledger consistent → skip ---
    if not content_changed and not ledger_needs_repair:
        print(f"finish-stamp: no change (idempotent — {ticket_id} already closed)")
        return 0

    # --- Apply updated stamp ONLY when the binder content actually changed ---
    # (not on a pure ledger repair — the binder is untouched in that case)
    written = content_changed
    if written:
        updated_stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        text = binder_rows.stamp_updated(text, updated_stamp)

    # --- Atomic write: temp → rename (only if text changed) ---
    if written:
        d = os.path.dirname(binder_path) or "."
        mode = os.stat(binder_path).st_mode
        fd, tmp = tempfile.mkstemp(dir=d, prefix=".finish-stamp.", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(text)
                fh.flush()
                os.fsync(fh.fileno())
            os.chmod(tmp, stat.S_IMODE(mode))
            os.replace(tmp, binder_path)
        except BaseException:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise

    if written:
        print("finish-stamp: stamped")
    elif ledger_needs_repair:
        print("finish-stamp: ledger repair (binder unchanged)")
    print(f"flip: {1 if flip_happened else 0}")

    # --- Append ledger via record CLI (only on actual flip or repair) ---
    if flip_happened or ledger_needs_repair:
        # A1 fix (spc-424): when repairing a missing ledger for an already-closed
        # binder, prior_status is "closed" (read from the binder we already wrote).
        # closed→closed is NOT a legal edge. If ledger_last_to is empty (no ledger
        # at all), use "open" — the legal legacy edge (transition_table.py:157) —
        # so a valid ledger entry is recorded instead of the record CLI rejecting
        # an illegal edge.
        if flip_happened:
            record_from = prior_status
        elif ledger_last_to:
            record_from = ledger_last_to
        else:
            # No ledger at all, binder already closed — can't know original prior
            # status; use the legacy edge to produce a valid entry.
            record_from = "open"
        rc = subprocess.run([
            sys.executable, ta_path, "record", ticket_id,
            record_from, "closed", "human", reason,
            "--home", home
        ], capture_output=True, text=True)
        if rc.returncode != 0:
            print(f"finish-stamp: ERROR — record CLI failed (rc={rc.returncode}): {rc.stderr}", file=sys.stderr)
            return 1
        print(f"finish-stamp: recorded ledger entry ({record_from} → closed)")

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
    binder_rel = binder_path.replace(repo_root + "/", "")

    # Stage binder if written, ledger if flip or repair
    paths_to_stage = []
    if written:
        paths_to_stage.append(binder_path)
    if flip_happened or ledger_needs_repair:
        paths_to_stage.append(str(ledger_path))

    for path in paths_to_stage:
        result = subprocess.run(["git", "-C", repo_root, "add", "--", path],
                                capture_output=True, text=True)
        if result.returncode != 0:
            print(f"finish-stamp: ERROR — git add failed for {path}: {result.stderr}", file=sys.stderr)
            return 1

    # --- Verify staging (fail loud — no FLIP_HAPPENED variable propagation) ---
    staged = subprocess.run(
        ["git", "-C", repo_root, "diff", "--cached", "--name-only"],
        capture_output=True, text=True
    ).stdout.strip().splitlines()
    staged_set = set(staged)

    if written and binder_rel not in staged_set:
        print(f"finish-stamp: ERROR — binder {binder_rel} NOT staged after git add", file=sys.stderr)
        return 1
    if (flip_happened or ledger_needs_repair) and ledger_rel not in staged_set:
        print(f"finish-stamp: ERROR — ledger {ledger_rel} NOT staged after git add", file=sys.stderr)
        print(f"  common cause: .transition-ledger/ is gitignored, or held index lock", file=sys.stderr)
        return 1

    staged_parts = []
    if written:
        staged_parts.append("binder")
    if flip_happened or ledger_needs_repair:
        staged_parts.append("ledger")
    if staged_parts:
        print(f"finish-stamp: staged {' + '.join(staged_parts)} ({ticket_id})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
