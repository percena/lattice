#!/usr/bin/env bash
# CI merge gate for finish-work preflight (spc-186 A6/A8, ADR-007 §5a).
#
# Operationalizes flow.md §2/§3.4 "never merge blind on mergeable": runs a
# `gh pr checks <N> --json` rollup and classifies each non-green check as
# infra-class (billing/quota/rate-limit/timeout/empty-step flake/runner-infra)
# or real, using config-tunable patterns (.lattice/config.yaml ci_gate:) and
# log-pattern + job-run metadata inspection.
#
# ADR-007 §5a — COMPILED CORNER CASE (not an exception):
#   - Infra-only red + local verification evidence present → exit 0 with
#     auto-stamped waiver (trace: rule_id=ci-gate, reason, authorizer=
#     human-at-merge-time). The waiver is part of the rule; no human
#     adjudication is needed for the infra-class path.
#   - Real failures → exit 1 (HARD block). This IS the red line.
#   - Unknown failures → exit 1 (fail-closed — treated as real).
#   - Pending checks → exit 1 (wait for CI to finish).
#
# The waiver trace is written to the binder ## Decision journal (when --binder
# is given) AND emitted as a PR comment body (stdout) for the operator to post.
#
# Usage:
#   ci-gate-check.sh --pr <N> [--home <path>] [--binder <path>] \
#                     [--evidence "<local test output summary>"] [--json] [--dry-run]
#
# Exit:
#   0 — all green OR infra-only red + evidence present (waiver stamped)
#   1 — real/unknown failures present, OR infra-only without evidence, OR pending
#   2 — usage / cannot load PR / gh missing
set -euo pipefail

PR=""
HOME_DIR=""
BINDER=""
EVIDENCE=""
AS_JSON=false
DRY_RUN=false

usage() {
  cat >&2 <<'EOF'
Usage: ci-gate-check.sh --pr <N> [--home path] [--binder <path>]
                        [--evidence "<text>"] [--json] [--dry-run]

  --pr        PR number (required).
  --home      lattice home (optional; default: .lattice at repo root).
  --binder    path to binder README.md (optional; waiver trace stamped into
              its ## Decision journal when infra-only waiver applies).
  --evidence  local verification evidence summary (bats/ci-local output
              excerpt) — REQUIRED for the waiver to stamp; without it,
              infra-only red is treated as a HARD block (fail-closed).
  --json      machine-readable JSON output.
  --dry-run   report what would happen; do not stamp binder or post PR comment.
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR="${2:-}"; shift 2 ;;
    --home) HOME_DIR="${2:-}"; shift 2 ;;
    --binder) BINDER="${2:-}"; shift 2 ;;
    --evidence) EVIDENCE="${2:-}"; shift 2 ;;
    --json) AS_JSON=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

if [[ -z "$PR" || ! "$PR" =~ ^[1-9][0-9]*$ ]]; then
  usage
fi
if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh required" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 required" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve lattice home (same priority as alignment-check.sh / batch-merge-gate.sh)
if [[ -z "$HOME_DIR" ]]; then
  # Bootstrap _lattice-home.sh (can't call shared funcs before sourcing)
  for _c in "${LATTICE_LIB_SCRIPTS:-}" "${SCRIPT_DIR}/../../_lattice-lib/scripts" "${SCRIPT_DIR}/../../../skills/_lattice-lib/scripts"; do
    [[ -n "$_c" && -f "$_c/_lattice-home.sh" ]] && { source "$_c/_lattice-home.sh"; break; }
  done
  # Shared HOME_DIR resolution (tkt-447)
  source_lattice_home_and_resolve "$SCRIPT_DIR" 2>/dev/null || {
    ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
    HOME_DIR="${LATTICE_HOME:-$ROOT/.lattice}"
  }
fi

export CI_GATE_PR="$PR"
export CI_GATE_HOME="$HOME_DIR"
export CI_GATE_BINDER="$BINDER"
export CI_GATE_EVIDENCE="$EVIDENCE"
export CI_GATE_JSON="$AS_JSON"
export CI_GATE_DRY_RUN="$DRY_RUN"
export CI_GATE_LIB="${SCRIPT_DIR}/lib"

python3 - <<'PY'
import datetime, json, os, re, subprocess, sys
from pathlib import Path

pr = os.environ["CI_GATE_PR"]
home = Path(os.environ["CI_GATE_HOME"])
binder = os.environ.get("CI_GATE_BINDER") or ""
evidence = os.environ.get("CI_GATE_EVIDENCE") or ""
as_json = os.environ.get("CI_GATE_JSON", "false").lower() == "true"
dry_run = os.environ.get("CI_GATE_DRY_RUN", "false").lower() == "true"
lib_dir = Path(os.environ.get("CI_GATE_LIB", ""))

sys.path.insert(0, str(lib_dir))
import ci_failure_classify as clf

def gh_run(args):
    """Run gh; return (returncode, stdout, stderr)."""
    p = subprocess.run(["gh", *args], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return p.returncode, (p.stdout or ""), (p.stderr or "")


def normalize_check(c):
    """tkt-349: gh >= 2.6x exposes `state` (the conclusion for completed runs:
    SUCCESS / FAILURE / TIMED_OUT / CANCELLED / STARTUP_FAILURE / SKIPPED /
    NEUTRAL, or a pending state) + `bucket` (pass|fail|pending|skipping|cancel);
    `conclusion` is NOT a field. The classifier (ci_failure_classify) keys on
    state FAILURE + conclusion, so derive the legacy pair when absent. Older
    payloads (or test fixtures) that already carry `conclusion` pass through."""
    if not isinstance(c, dict):
        return c
    if "conclusion" in c:
        return c
    bucket = (c.get("bucket") or "").lower()
    st = (c.get("state") or "").upper()
    # A completed-red conclusion wins over the bucket: gh 2.9x files
    # STARTUP_FAILURE under bucket `pending` (its default branch), which would
    # otherwise hide the canonical ADR-007 §5a infra-waiver case behind a
    # never-resolving "pending" block (review of PR #354).
    if st in ("FAILURE", "TIMED_OUT", "CANCELLED", "STARTUP_FAILURE", "ACTION_REQUIRED", "ERROR"):
        c["conclusion"] = st; c["state"] = "FAILURE"
    elif bucket == "pending" or st in ("PENDING", "QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED", "EXPECTED"):
        c["state"] = "PENDING"; c["conclusion"] = ""
    elif bucket == "pass" or st in ("SUCCESS", "NEUTRAL", "SKIPPED"):
        c["conclusion"] = st or "SUCCESS"
    else:
        # fail / cancel / anything else completed-red: keep the precise
        # conclusion (TIMED_OUT, CANCELLED, STARTUP_FAILURE, FAILURE …) and
        # present state=FAILURE so the classifier treats it as a red.
        c["conclusion"] = st or "FAILURE"; c["state"] = "FAILURE"
    return c

# --- Fetch the checks rollup ---
# Distinguish three cases (M2 fix): (1) gh exits non-zero → cannot load →
# exit 2; (2) empty/whitespace output or valid `[]` → no CI configured →
# all-green PASS (no checks = green); (3) non-empty output that fails to
# parse as JSON → malformed → exit 2. A valid `[]` on a no-CI repo is green;
# only malformed JSON is an error.
rc, raw, err = gh_run(["pr", "checks", pr, "--json", "name,state,bucket,link"])
if rc != 0:
    if "Unknown JSON field" in err:
        # tkt-349: a field-list mismatch with the installed gh is a script/CLI
        # contract error, not an auth/PR problem — say so (still fail-closed).
        msg = (f"gh pr checks --json field mismatch for this gh version ({err.strip().splitlines()[0]}); "
               f"the CI gate cannot load the rollup — upgrade gh or fix the field list in ci-gate-check.sh (tkt-349)")
    else:
        msg = f"cannot load gh pr checks for PR #{pr} (gh auth? PR not found? gh exit {rc}{': ' + err.strip().splitlines()[0] if err.strip() else ''})"
    if as_json:
        print(json.dumps({"ok": False, "error": msg}, indent=2))
    else:
        print(f"Error: {msg}", file=sys.stderr)
    sys.exit(2)

raw_stripped = raw.strip()
if raw_stripped == "":
    # No CI configured / no checks for this PR → treat as no checks (green).
    checks = []
else:
    try:
        checks = json.loads(raw)
    except json.JSONDecodeError as exc:
        msg = f"cannot parse gh pr checks output for PR #{pr} (malformed JSON: {exc.msg})"
        if as_json:
            print(json.dumps({"ok": False, "error": msg}, indent=2))
        else:
            print(f"Error: {msg}", file=sys.stderr)
        sys.exit(2)
    if not isinstance(checks, list):
        checks = []
    checks = [normalize_check(c) for c in checks]

# --- Load config patterns ---
patterns = clf.load_config_patterns(str(home))

# --- Log fetcher: for each failed check, get a short log excerpt ---
# The `link` from `gh pr checks --json` is a URL like
# https://github.com/owner/repo/runs/RUNID or .../actions/runs/RUNID.
# We extract the run ID and fetch `gh run view <id> --log-failed | head -50`.
run_id_re = re.compile(r"/(?:runs|actions/runs)/(\d+)")

def fetch_log_excerpt(check):
    link = check.get("link") or ""
    m = run_id_re.search(link)
    if not m:
        return ""
    run_id = m.group(1)
    try:
        out = subprocess.check_output(
            ["gh", "run", "view", run_id, "--log-failed"],
            text=True, stderr=subprocess.DEVNULL, timeout=30,
        )
        # Return first 500 chars — enough for pattern matching
        return out[:500]
    except Exception:
        return ""

# --- Classify ---
infra, real, unknown = clf.classify_checks(checks, fetch_log_excerpt, patterns)

# Check for pending
pending = [c for c in checks if (c.get("state") or "").upper() == "PENDING"]
# Only count pending as blocking if there are no completed-failure checks
# (pending CI may still turn green; but we never merge blind on pending).
has_blocking_pending = bool(pending)

timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# --- Decision ---
# 1. Real or unknown failures → HARD block (exit 1)
# 2. Pending checks → block (exit 1) — wait for CI; checked BEFORE the
#    infra-waiver so waivers apply only to *settled* failures (MH1 fix: a PR
#    with one infra failure + evidence AND checks still PENDING must NOT be
#    waived — CI may still turn red).
# 3. Infra-only red + evidence present → waiver (exit 0)
# 4. Infra-only red WITHOUT evidence → HARD block (fail-closed, exit 1)
# 5. All green → pass (exit 0)

result = {
    "pr": int(pr),
    "timestamp": timestamp,
    "checks_total": len(checks),
    "infra_failures": infra,
    "real_failures": real,
    "unknown_failures": unknown,
    "pending": [{"name": c.get("name", ""), "link": c.get("link", "")} for c in pending],
    "rule_id": "ci-gate",
    "adr": "ADR-007 §5a",
    "compiled_corner_case": True,
    "decision": "",
    "waiver_stamped": False,
    "ok": False,
}

if real or unknown:
    all_fail = real + unknown
    result["decision"] = "BLOCK — real/unknown failures present (HARD)"
    result["ok"] = False
    result["block_reason"] = "real_or_unknown_failures"
elif has_blocking_pending:
    result["decision"] = "BLOCK — CI still pending (wait for completion)"
    result["ok"] = False
    result["block_reason"] = "pending"
elif infra:
    if not evidence:
        result["decision"] = "BLOCK — infra-only red but NO local evidence (fail-closed)"
        result["ok"] = False
        result["block_reason"] = "infra_without_evidence"
    else:
        result["decision"] = "PASS — infra-only red + local evidence present (compiled waiver)"
        result["ok"] = True
        result["waiver_stamped"] = True
        result["waiver_trace"] = clf.waiver_trace(pr, infra, evidence, timestamp)
        result["pr_comment"] = clf.pr_comment_body(
            pr, infra, real, unknown, evidence, timestamp
        )
else:
    result["decision"] = "PASS — all green"
    result["ok"] = True

# --- Stamp binder journal when waiver applies ---
if result["waiver_stamped"] and binder and not dry_run:
    try:
        import fcntl
        from pathlib import Path as P
        bp = P(binder)
        if bp.is_file():
            lock_dir = str(bp.parent) or "."
            lock_fd = os.open(lock_dir, os.O_RDONLY)
            try:
                fcntl.flock(lock_fd, fcntl.LOCK_EX)
            except OSError as exc:
                os.close(lock_fd)
                raise RuntimeError(f"ci-gate-check: cannot lock binder directory: {exc}")
            try:
                text = bp.read_text(encoding="utf-8", errors="replace")
                trace = result["waiver_trace"]
                # Append to ## Decision journal (same pattern as stamp-pr-open)
                m_hdr = re.search(r'^## Decision journal[ \t]*\n', text, re.MULTILINE)
                if m_hdr:
                    body_start = m_hdr.end()
                    tail = text[body_start:]
                    bnd = re.search(r'\n## ', tail)
                    body = tail[:bnd.start()] if bnd else tail
                    trailing = tail[bnd.start():] if bnd else ""
                    stripped = body.strip("\n")
                    new_body = (stripped + "\n" + trace + "\n") if stripped else (trace + "\n")
                    text = text[:body_start] + "\n" + new_body + trailing
                else:
                    anchor = re.search(r'\n(## (?:Notes|References|Lineage|Finish|Pending decisions|Attempts)\b)', text)
                    block = f"\n## Decision journal\n\n{trace}\n"
                    if anchor:
                        text = text[:anchor.start()] + block + text[anchor.start():]
                    else:
                        text = text.rstrip("\n") + "\n" + block
                import tempfile, stat
                d = str(bp.parent)
                fmode = bp.stat().st_mode
                fd2, tmp = tempfile.mkstemp(dir=d, prefix=".ci-gate.", suffix=".tmp")
                try:
                    with os.fdopen(fd2, "w", encoding="utf-8") as fh:
                        fh.write(text)
                        fh.flush()
                        os.fsync(fh.fileno())
                    os.chmod(tmp, stat.S_IMODE(fmode))
                    os.replace(tmp, str(bp))
                except BaseException:
                    if os.path.exists(tmp):
                        os.unlink(tmp)
                    raise
                result["binder_stamped"] = str(bp)
            finally:
                fcntl.flock(lock_fd, fcntl.LOCK_UN)
                os.close(lock_fd)
    except Exception as e:
        result["binder_stamp_error"] = str(e)

# --- Output ---
if as_json:
    print(json.dumps(result, indent=2))
else:
    print(f"# ci-gate-check PR #{pr}")
    print(f"timestamp: {timestamp}")
    print(f"rule_id: ci-gate  (ADR-007 §5a — compiled corner case)")
    print(f"checks: {len(checks)} total")
    if infra:
        print(f"## infra-class failures ({len(infra)}) — compiled waiver eligible")
        for f in infra:
            print(f"  - {f['name']} — {f['category']} (pattern: {f['pattern']}) — {f['link']}")
    if real:
        print(f"## REAL failures ({len(real)}) — HARD BLOCK")
        for f in real:
            print(f"  - {f['name']} — {f['conclusion']} — {f['link']}")
    if unknown:
        print(f"## UNCLASSIFIED failures ({len(unknown)}) — treated as real (fail-closed)")
        for f in unknown:
            print(f"  - {f['name']} — {f['pattern']} — {f['link']}")
    if pending:
        print(f"## PENDING ({len(pending)}) — wait for CI")
        for p in pending:
            print(f"  - {p['name']} — {p['link']}")
    print(f"## decision: {result['decision']}")
    if result["waiver_stamped"]:
        print(f"## waiver trace:")
        print(f"  {result['waiver_trace']}")
        if result.get("binder_stamped"):
            print(f"  (stamped into binder: {result['binder_stamped']})")
        elif dry_run:
            print(f"  (dry-run — binder not stamped)")
        print(f"## PR comment body (post to PR #{pr}):")
        print(result["pr_comment"])
    if not result["ok"]:
        print(f"## summary: BLOCKED (rule_id=ci-gate)")
    else:
        print(f"## summary: PASS (rule_id=ci-gate)")

sys.exit(0 if result["ok"] else 1)
PY
