#!/usr/bin/env python3
"""finish-stamp-ci.py — GHA safety-net orchestrator (spc-416 A6, Layer 2).

Fires on pull_request:closed(merged). Discovers ticket binder(s) for the merged
PR (by head-branch tkt-N, by closing-issue github row, by prs row), runs
finish-ledger.sh (which delegates to finish-stamp.py — idempotent verify + Mode
C repair + staging), and commits + pushes any staged changes as
github-actions[bot].

Local finish-work is the PRIMARY stamp path (CI-independent, ADR-013 Option E+
Decision 1). This GHA is the SAFETY NET: catches local-stamp failures, repairs
Mode C ledger discontinuity, and verifies the local stamp landed. Race with the
local stamp is benign — both paths are idempotent (spc-416 Decision 7).

Usage:
  python3 finish-stamp-ci.py --pr <N> --repo <owner/name> [--lattice-home .lattice] [--dry-run]
"""
import sys, os, re, json, subprocess, argparse, pathlib


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def gh_json(args):
    """Run a gh --json command; return parsed dict or None."""
    r = run(["gh"] + args)
    if r.returncode != 0:
        return None
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError:
        return None


def discover_binders(tickets_dir, pr_num, head_ref, closing_issues):
    """Return sorted list of binder README paths for the merged PR.

    Three discovery signals (any hit → candidate):
      1. PR head branch tkt-N → binder dir tkt-N-*
      2. closing issue #M → binder github row references /issues/M
      3. prs row contains pr-N (already-stamped — verify path)
    """
    binders = set()
    tdir = pathlib.Path(tickets_dir)

    # 1. head branch → tkt-N
    m = re.match(r'^(tkt-\d+)', head_ref or "")
    if m:
        tid = m.group(1)
        for d in sorted(tdir.glob(f"{tid}-*")):
            if d.is_dir() and (d / "README.md").is_file():
                binders.add(str(d / "README.md"))

    # 2. closing issues → github row
    if closing_issues:
        for b in sorted(tdir.glob("tkt-*/README.md")):
            try:
                text = b.read_text(encoding="utf-8")
            except OSError:
                continue
            gm = re.search(r'\|\s*github\s*\|\s*(\S+)\s*\|', text)
            if not gm:
                continue
            url = gm.group(1)
            for issue_n in closing_issues:
                if f"/issues/{issue_n}" in url:
                    binders.add(str(b))
                    break

    # 3. prs row → pr-N (already-stamped verification)
    for b in sorted(tdir.glob("tkt-*/README.md")):
        try:
            text = b.read_text(encoding="utf-8")
        except OSError:
            continue
        pm = re.search(r'\|\s*prs\s*\|\s*(.*?)\s*\|', text, re.DOTALL)
        if pm and f"pr-{pr_num}" in pm.group(1):
            binders.add(str(b))

    return sorted(binders)


def closing_issues_from_pr(pr_json):
    """Extract closing issue numbers from gh PR JSON."""
    issues = []
    refs = pr_json.get("closingIssuesReferences") or []
    for ref in refs:
        if isinstance(ref, dict) and ref.get("number"):
            issues.append(int(ref["number"]))
    if not issues and pr_json.get("body"):
        for m in re.finditer(r'(?i)(?:fixes|closes|resolves|close)\s+#(\d+)', pr_json["body"]):
            n = int(m.group(1))
            if n not in issues:
                issues.append(n)
    return issues


def run_stamp(finish_ledger, binder, pr_num, repo, closing_issues):
    """Run finish-ledger.sh for one binder. Returns rc."""
    # Pick the closing issue that matches this binder's github row
    issue_args = []
    try:
        btext = open(binder, encoding="utf-8").read()
        gm = re.search(r'\|\s*github\s*\|\s*(\S+)\s*\|', btext)
        if gm:
            for iss in closing_issues:
                if f"/issues/{iss}" in gm.group(1):
                    issue_args = ["--issue", str(iss)]
                    break
    except OSError:
        pass

    cmd = ["bash", finish_ledger, "--pr", str(pr_num),
           "--binder", binder, "--repo", repo] + issue_args
    print(f"  → {' '.join(cmd)}")
    r = run(cmd)
    if r.stdout:
        sys.stdout.write(r.stdout)
    if r.stderr:
        sys.stderr.write(r.stderr)
    return r.returncode


def staged_lattice_files():
    """Return list of staged .lattice/ files."""
    r = run(["git", "diff", "--cached", "--name-only"])
    return [f for f in r.stdout.strip().splitlines() if f.startswith(".lattice/")]


def commit_and_push(base_ref, pr_num, dry_run):
    """Commit staged .lattice/ changes and push to base_ref. Returns rc."""
    staged = staged_lattice_files()
    if not staged:
        print("finish-stamp-ci: no staged changes — local stamp already landed or nothing to repair")
        return 0

    print(f"finish-stamp-ci: staged {len(staged)} file(s): {staged}")

    if dry_run:
        print(f"[dry-run] would commit + push to {base_ref}")
        return 0

    subprocess.run(["git", "config", "user.name", "github-actions[bot]"], check=True)
    subprocess.run(["git", "config", "user.email",
                    "41898282+github-actions[bot]@users.noreply.github.com"], check=True)

    msg = f"chore(ci): GHA safety-net ledger stamp — pr-{pr_num} merged"
    cr = run(["git", "commit", "-m", msg, "--", ".lattice/"])
    if cr.returncode != 0:
        print(f"finish-stamp-ci: git commit failed: {cr.stderr}", file=sys.stderr)
        return 1

    push = run(["git", "push", "origin", f"HEAD:{base_ref}"])
    if push.returncode == 0:
        print(f"finish-stamp-ci: pushed safety-net stamp to {base_ref}")
        return 0

    # Push failed — likely a race (local stamp or another run pushed first).
    # Reset to remote, re-run stamps (idempotent), commit only if new changes.
    print(f"finish-stamp-ci: push failed (race?) — fetching {base_ref} and re-verifying")
    fetch = run(["git", "fetch", "origin", f"{base_ref}:refs/remotes/origin/{base_ref}"])
    if fetch.returncode != 0:
        print(f"finish-stamp-ci: fetch failed: {fetch.stderr}", file=sys.stderr)
        return 0  # non-fatal — local stamp or next run will handle

    run(["git", "reset", "--hard", f"origin/{base_ref}"])
    return 2  # signal: re-stamp + retry push (handled by caller)


def main():
    p = argparse.ArgumentParser(description="GHA safety-net ledger stamp orchestrator.")
    p.add_argument("--pr", type=int, required=True)
    p.add_argument("--repo", required=True, help="owner/name")
    p.add_argument("--lattice-home", default=".lattice")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()

    pr = gh_json(["pr", "view", str(args.pr), "--repo", args.repo,
                  "--json", "state,mergedAt,url,baseRefName,headRefName,body,closingIssuesReferences"])
    if not pr:
        print(f"finish-stamp-ci: cannot read PR #{args.pr} via gh", file=sys.stderr)
        return 1
    if pr.get("state") != "MERGED":
        print(f"finish-stamp-ci: PR #{args.pr} state={pr.get('state')} — not MERGED, skip")
        return 0

    base_ref = pr.get("baseRefName") or "dev"
    head_ref = pr.get("headRefName") or ""
    closing_issues = closing_issues_from_pr(pr)

    tickets_dir = os.path.join(args.lattice_home, "tickets")
    if not os.path.isdir(tickets_dir):
        print(f"finish-stamp-ci: no {tickets_dir} — nothing to stamp")
        return 0

    binders = discover_binders(tickets_dir, args.pr, head_ref, closing_issues)
    if not binders:
        print(f"finish-stamp-ci: no binder discovered for PR #{args.pr} "
              f"(head={head_ref}, issues={closing_issues}) — skip")
        return 0

    print(f"finish-stamp-ci: PR #{args.pr} merged into {base_ref} "
          f"→ {len(binders)} binder(s): {[os.path.relpath(b) for b in binders]}")

    script_dir = os.path.dirname(os.path.realpath(__file__))
    finish_ledger = os.path.join(script_dir, "finish-ledger.sh")

    # Stamp pass 1
    for binder in binders:
        if args.dry_run:
            print(f"  [dry-run] would stamp: {binder}")
            continue
        rc = run_stamp(finish_ledger, binder, args.pr, args.repo, closing_issues)
        if rc != 0:
            print(f"  finish-ledger FAILED (rc={rc}) for {binder} — continuing to other binders",
                  file=sys.stderr)

    rc = commit_and_push(base_ref, args.pr, args.dry_run)
    if rc == 2:
        # Race retry: re-run stamps on fresh remote, commit + push again
        print("finish-stamp-ci: re-stamping on fresh remote (idempotent)")
        for binder in binders:
            rc2 = run_stamp(finish_ledger, binder, args.pr, args.repo, closing_issues)
            if rc2 != 0:
                print(f"  re-stamp FAILED (rc={rc2}) for {binder}", file=sys.stderr)
        # Commit + push without further retry (avoid loops)
        staged = staged_lattice_files()
        if not staged:
            print("finish-stamp-ci: race resolved — binder already stamped by other pusher")
            return 0
        subprocess.run(["git", "config", "user.name", "github-actions[bot]"], check=True)
        subprocess.run(["git", "config", "user.email",
                        "41898282+github-actions[bot]@users.noreply.github.com"], check=True)
        msg = f"chore(ci): GHA safety-net ledger stamp — pr-{args.pr} merged"
        run(["git", "commit", "-m", msg, "--", ".lattice/"])
        push = run(["git", "push", "origin", f"HEAD:{base_ref}"])
        if push.returncode != 0:
            print(f"finish-stamp-ci: retry push also failed: {push.stderr} — "
                  "local stamp or next run will handle", file=sys.stderr)
            return 0
        print(f"finish-stamp-ci: pushed safety-net stamp to {base_ref} (retry)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
