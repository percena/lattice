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

tkt-470: on protected branches, direct push fails because the generated commit
lacks required checks (bats, lattice-artifacts). Instead of a direct push, the
safety net creates/updates a deterministic repair branch + PR that receives
normal required checks.

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
        # tkt-459 A1: word-boundary match — a bare substring test made `pr-44`
        # discover pr-440/pr-441 binders and stamp them closed (same canon as
        # binder_rows.merge_row).
        if pm and re.search(rf"\bpr-{int(pr_num)}\b", pm.group(1)):
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


def verify_binder_postconditions(binders, lattice_home):
    """Verify each discovered binder is in a consistent terminal state.

    Returns a list of (binder_path, reason) for each inconsistent binder.
    tkt-470 A3: staged-empty must not return success when postconditions fail.
    """
    inconsistent = []
    for binder in binders:
        try:
            text = open(binder, encoding="utf-8").read()
        except OSError:
            inconsistent.append((binder, "cannot read binder"))
            continue

        # Check status is terminal (closed)
        sm = re.search(r'\|\s*status\s*\|\s*(\S+)\s*\|', text)
        if not sm:
            inconsistent.append((binder, "no status row"))
            continue
        status = sm.group(1)
        if status != "closed":
            inconsistent.append((binder, f"status={status}, expected closed"))
            continue

        # Check transition ledger has a terminal entry
        tid_m = re.match(r'^(tkt-[1-9][0-9]*)', os.path.basename(os.path.dirname(binder)))
        if not tid_m:
            continue
        ticket_id = tid_m.group(1)
        ledger = pathlib.Path(lattice_home) / ".transition-ledger" / f"{ticket_id}.jsonl"
        if not ledger.exists():
            inconsistent.append((binder, f"no transition ledger for {ticket_id}"))
            continue
        try:
            lines = ledger.read_text(encoding="utf-8").strip().splitlines()
            if not lines:
                inconsistent.append((binder, f"empty transition ledger for {ticket_id}"))
                continue
            last_entry = json.loads(lines[-1])
            if last_entry.get("to") != "closed":
                inconsistent.append((binder, f"ledger last to={last_entry.get('to')!r}, expected closed"))
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            inconsistent.append((binder, f"ledger parse error: {exc}"))

    return inconsistent


def commit_and_repair_pr(base_ref, pr_num, dry_run, validator=None, repo=None):
    """Commit staged .lattice/ changes and create/update a repair branch + PR.

    tkt-470 A1: instead of a direct push to the (potentially protected) base,
    push to a deterministic repair branch and create/update a PR that receives
    normal required checks.

    Returns rc (0 success/nothing, 1 failed).
    """
    staged = staged_lattice_files()
    if not staged:
        return 0

    print(f"finish-stamp-ci: staged {len(staged)} file(s): {staged}")

    if dry_run:
        print(f"[dry-run] would commit + create repair PR to {base_ref}")
        return 0

    subprocess.run(["git", "config", "user.name", "github-actions[bot]"], check=True)
    subprocess.run(["git", "config", "user.email",
                    "41898282+github-actions[bot]@users.noreply.github.com"], check=True)

    msg = f"chore(ci): GHA safety-net ledger stamp — pr-{pr_num} merged"
    # tkt-459 A1: commit the STAGED set only.
    cr = run(["git", "commit", "-m", msg])
    if cr.returncode != 0:
        print(f"finish-stamp-ci: git commit failed: {cr.stderr}", file=sys.stderr)
        return 1

    if validator is not None:
        vrc = run_validator(validator)
        if vrc != 0:
            print("finish-stamp-ci: artifact validator FAILED on the stamped tree — "
                  "NOT creating repair PR",
                  file=sys.stderr)
            return 1

    repair_branch = f"lattice/finish-repair/{base_ref}"

    # tkt-470 A1: push to a repair branch, not directly to the protected base.
    push = run(["git", "push", "origin", f"HEAD:{repair_branch}", "--force"])
    if push.returncode != 0:
        print(f"finish-stamp-ci: push to repair branch {repair_branch} failed: {push.stderr}",
              file=sys.stderr)
        return 1

    print(f"finish-stamp-ci: pushed safety-net stamp to repair branch {repair_branch}")

    # tkt-470 A4: check if a PR already exists for this repair branch.
    existing_pr = gh_json(["pr", "list", "--repo", repo or "",
                           "--head", repair_branch, "--base", base_ref,
                           "--state", "open", "--json", "number,url", "--limit", "1"])

    if existing_pr and len(existing_pr) > 0:
        pr_url = existing_pr[0].get("url", "")
        pr_number = existing_pr[0].get("number", "?")
        print(f"finish-stamp-ci: repair PR #{pr_number} already exists — force-pushed update: {pr_url}")
        return 0

    # tkt-470 A5: create a new repair PR — fail loud on creation failure.
    pr_title = f"chore(ci): safety-net ledger repair — pr-{pr_num}"
    pr_body = (f"Automated safety-net repair: the local finish stamp for pr-{pr_num} "
               f"did not land on `{base_ref}`. This PR carries the missing ledger/binder "
               f"updates.\n\nCreated by `finish-stamp-ci.py` (spc-416 A6, tkt-470 A1).")

    pr_create = run(["gh", "pr", "create",
                     "--repo", repo or "",
                     "--base", base_ref,
                     "--head", repair_branch,
                     "--title", pr_title,
                     "--body", pr_body])
    if pr_create.returncode != 0:
        print(f"finish-stamp-ci: repair PR creation FAILED: {pr_create.stderr}",
              file=sys.stderr)
        return 1

    pr_url = pr_create.stdout.strip()
    print(f"finish-stamp-ci: created repair PR: {pr_url}")
    return 0


def run_validator(validator):
    """Run the artifact validator command (list argv) from the repo root before
    pushing a safety-net commit (tkt-459 A4). GITHUB_TOKEN pushes trigger no
    workflows, so `artifacts.yml` never sees a bot stamp — this is the only
    gate a safety-net commit passes through. Returns the validator's rc."""
    print(f"finish-stamp-ci: validating stamped tree: {' '.join(validator)}")
    r = run(validator)
    if r.stdout:
        sys.stdout.write(r.stdout)
    if r.stderr:
        sys.stderr.write(r.stderr)
    return r.returncode


def main():
    p = argparse.ArgumentParser(description="GHA safety-net ledger stamp orchestrator.")
    p.add_argument("--pr", type=int, required=True)
    p.add_argument("--repo", required=True, help="owner/name")
    p.add_argument("--lattice-home", default=".lattice")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--validator-script", default="",
                   help="artifact validator to run before pushing (e.g. tools/validate-lattice-artifacts.py); a non-zero exit aborts the push")
    p.add_argument("--validator-baseline", default="",
                   help="optional --baseline file passed to --validator-script")
    args = p.parse_args()
    validator = None
    if args.validator_script:
        validator = [sys.executable, args.validator_script]
        if args.validator_baseline:
            validator += ["--baseline", args.validator_baseline]

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

    # tkt-470 A2: accumulate child stamp failures.
    child_failures = 0
    for binder in binders:
        if args.dry_run:
            print(f"  [dry-run] would stamp: {binder}")
            continue
        rc = run_stamp(finish_ledger, binder, args.pr, args.repo, closing_issues)
        if rc != 0:
            child_failures += 1
            print(f"  finish-ledger FAILED (rc={rc}) for {binder}",
                  file=sys.stderr)

    # tkt-470 A3: before reporting success on staged-empty, verify postconditions.
    staged = staged_lattice_files()
    if not staged:
        inconsistent = verify_binder_postconditions(binders, args.lattice_home)
        if inconsistent:
            print("finish-stamp-ci: staged-empty but postcondition verification FAILED:",
                  file=sys.stderr)
            for path, reason in inconsistent:
                print(f"  {os.path.relpath(path)}: {reason}", file=sys.stderr)
            return 1
        if child_failures > 0:
            print(f"finish-stamp-ci: {child_failures} child stamp failure(s) — "
                  "postconditions pass but stamp process had errors", file=sys.stderr)
            return 1
        print("finish-stamp-ci: no staged changes — local stamp already landed "
              "(postconditions verified)")
        return 0

    # tkt-470 A2: fail even when there are staged changes if children failed.
    if child_failures > 0:
        print(f"finish-stamp-ci: {child_failures} child stamp failure(s) — "
              "aborting repair PR creation", file=sys.stderr)
        return 1

    # tkt-470 A1: commit + create/update repair PR instead of direct push.
    rc = commit_and_repair_pr(base_ref, args.pr, args.dry_run, validator, args.repo)
    if rc != 0:
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
