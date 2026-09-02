#!/usr/bin/env bash
# claim-probes.sh — executable claim–implementation probes (spc-369 A2, L2 sensor).
#
# A documented promise ("every script the SKILL names exists", "the FSM doc's
# edges are legal per the schema", …) is only true until the next commit; this
# sensor EXECUTES each promise against the tree instead of re-reading it
# (create-review audit-recipe §3 enforcement-coverage axis + §4 claim–
# implementation reconciliation, mechanised). Seeded from the drift classes
# rev-20260902-015425Z F4/F5 and the tkt-338..342 PR reviews found by hand.
#
# Registry: references/probes.md — one Markdown table
#   | id | claim (where) | probe | expect | severity |
# Overlay:  <home>/lineage-probes.tsv (optional; id<TAB>claim<TAB>probe<TAB>
#   expect<TAB>severity, `#` comments) merged by id — overlay wins, new ids
#   are appended.
#
# Each `probe` is a bash one-liner run with cwd = REPO_ROOT and
#   REPO_ROOT, LATTICE_HOME, PROBE_ID, REGISTRY_DIR   exported.
# `expect` ∈ exit0 | regex:<pattern> (stdout must match) | empty (stdout must
# be empty). A probe that exits 3 is `skip` (prerequisite absent — its stdout
# is the reason). For regex/empty the probe must still exit 0 — any other
# non-zero exit is a `fail` (a crashed probe never passes by accident).
#
# Usage:
#   claim-probes.sh [--home <path>] [--registry <file>] [--overlay <file>]
#                   [--only <id,…>] [--md|--json] [--timeout <s>]
#
# Exit: 0 always (sensor; the report is the product). 2 on usage.
set -euo pipefail

HOME_DIR=""
REGISTRY=""
OVERLAY=""
ONLY=""
MODE="md"
TIMEOUT="20"

usage() {
  cat >&2 <<'USAGE'
Usage: claim-probes.sh [--home <path>] [--registry <file>] [--overlay <file>]
                       [--only <id,...>] [--md|--json] [--timeout <s>]

  --home      lattice home (default: LATTICE_HOME or <repo>/.lattice)
  --registry  probe registry (default: <skill>/references/probes.md)
  --overlay   per-repo overlay TSV (default: <home>/lineage-probes.tsv if present)
  --only      comma-separated probe ids to run (others are not reported)
  --md        Markdown report (default)
  --json      JSON report
  --timeout   per-probe timeout in seconds (default 20)
USAGE
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --home) HOME_DIR="${2:-}"; shift 2 ;;
    --registry) REGISTRY="${2:-}"; shift 2 ;;
    --overlay) OVERLAY="${2:-}"; shift 2 ;;
    --only) ONLY="${2:-}"; shift 2 ;;
    --md) MODE="md"; shift ;;
    --json) MODE="json"; shift ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

[[ "$TIMEOUT" =~ ^[0-9]+$ ]] || { echo "Error: --timeout must be an integer (seconds)" >&2; usage; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Sensor — never blocks (spc-212 A2/D3 degrade path): no python3 → degraded
# report instead of a bare "command not found".
if ! command -v python3 >/dev/null 2>&1; then
  case "$MODE" in
    json) echo '{"schema":1,"probes":[],"summary":{"pass":0,"fail":0,"skip":0},"degraded":"python3 missing"}' ;;
    *) echo "claim-probes: unavailable (python3 missing — install per ensure-python3.sh)." ;;
  esac
  exit 0
fi

# Resolve _lattice-lib through the sibling resolver (installed-dir trust
# anchor; LATTICE_LIB_SCRIPTS is the explicit override — never the cwd).
LIB=""
RESOLVE="$SCRIPT_DIR/../../_lattice-lib/scripts/resolve-lattice-lib.sh"
if [[ -f "$RESOLVE" ]]; then
  LIB=$(bash "$RESOLVE" 2>/dev/null || true)
fi

# Lattice home: --home > LATTICE_HOME > lattice_default_home (lib) > <toplevel>/.lattice.
if [[ -z "$HOME_DIR" ]]; then
  if [[ -n "${LATTICE_HOME:-}" ]]; then
    HOME_DIR="$LATTICE_HOME"
  elif [[ -n "$LIB" && -f "$LIB/_lattice-home.sh" ]]; then
    # shellcheck source=/dev/null
    source "$LIB/_lattice-home.sh"
    lattice_export_roots 2>/dev/null || true
    HOME_DIR=$(lattice_default_home 2>/dev/null || echo "")
  fi
fi
if [[ -z "$HOME_DIR" ]]; then
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  HOME_DIR="$ROOT/.lattice"
fi
# The home's parent IS the repo root (a fixture repo passes --home
# <fixture>/.lattice; a real checkout resolves to its toplevel). A parent that
# does not exist must never fall through to `/` and produce vacuous passes:
# fail loud (stderr), keep exit 0, and mark every probe `skip` with the reason.
HOME_ERROR=""
if HOME_PARENT="$(cd "$(dirname "$HOME_DIR")" 2>/dev/null && pwd -P)"; then
  HOME_DIR="$HOME_PARENT/$(basename "$HOME_DIR")"
else
  HOME_ERROR="error: --home parent not found: $(dirname "$HOME_DIR")"
  echo "$HOME_ERROR" >&2
fi
REPO_ROOT="$(dirname "$HOME_DIR")"

[[ -n "$REGISTRY" ]] || REGISTRY="$SCRIPT_DIR/../references/probes.md"
if [[ ! -f "$REGISTRY" ]]; then
  case "$MODE" in
    json) printf '{"schema":1,"probes":[],"summary":{"pass":0,"fail":0,"skip":0},"degraded":"registry not found: %s"}\n' "$REGISTRY" ;;
    *) echo "claim-probes: registry not found: $REGISTRY" ;;
  esac
  exit 0
fi
REGISTRY="$(cd "$(dirname "$REGISTRY")" && pwd -P)/$(basename "$REGISTRY")"
if [[ -z "$OVERLAY" && -f "$HOME_DIR/lineage-probes.tsv" ]]; then
  OVERLAY="$HOME_DIR/lineage-probes.tsv"
fi

export CP_HOME="$HOME_DIR"
export CP_HOME_ERROR="$HOME_ERROR"
export CP_REPO_ROOT="$REPO_ROOT"
export CP_REGISTRY="$REGISTRY"
export CP_OVERLAY="$OVERLAY"
export CP_ONLY="$ONLY"
export CP_MODE="$MODE"
export CP_TIMEOUT="$TIMEOUT"

python3 - <<'PY'
import json, os, re, signal, subprocess, sys, time

home = os.environ["CP_HOME"]
repo_root = os.environ["CP_REPO_ROOT"]
registry = os.environ["CP_REGISTRY"]
overlay = os.environ.get("CP_OVERLAY", "")
only = [s.strip() for s in os.environ.get("CP_ONLY", "").split(",") if s.strip()]
mode = os.environ["CP_MODE"]
timeout = int(os.environ["CP_TIMEOUT"])
home_error = os.environ.get("CP_HOME_ERROR", "")
degraded = []  # non-fatal load problems, reported and then ignored

COLUMNS = ("id", "claim", "probe", "expect", "severity")
SEVERITIES = ("high", "med", "low")
EVIDENCE_CHARS = 200


def split_row(line):
    """Split a Markdown table row on unescaped pipes; `\\|` → `|`."""
    cells, cur, i = [], [], 0
    while i < len(line):
        ch = line[i]
        if ch == "\\" and i + 1 < len(line) and line[i + 1] == "|":
            cur.append("|")
            i += 2
            continue
        if ch == "|":
            cells.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
        i += 1
    cells.append("".join(cur))
    # a row is `| a | b |` → drop the empty edge cells
    if cells and cells[0].strip() == "":
        cells = cells[1:]
    if cells and cells[-1].strip() == "":
        cells = cells[:-1]
    return [c.strip() for c in cells]


def parse_registry(path):
    """Rows of the first table whose header starts with the five columns.
    Returns (rows, malformed) — malformed rows carry a reason."""
    rows, malformed = [], []
    in_table, header_seen = False, False
    with open(path, encoding="utf-8", errors="replace") as fh:
        for n, raw in enumerate(fh, 1):
            line = raw.rstrip("\n")
            if not line.startswith("|"):
                if header_seen:
                    break  # table ended
                continue
            cells = split_row(line)
            if not header_seen:
                low = [c.lower() for c in cells]
                if len(low) >= 5 and low[0] == "id" and low[1].startswith("claim") \
                        and low[2] == "probe" and low[3] == "expect" and low[4] == "severity":
                    header_seen = True
                continue
            if all(re.fullmatch(r":?-+:?", c or "") for c in cells):
                continue  # separator
            if len(cells) != 5:
                malformed.append((f"row-{n}", f"malformed row (line {n}): {len(cells)} cells, expected 5"))
                continue
            row = dict(zip(COLUMNS, cells))
            row["source"] = f"registry:{n}"
            rows.append(row)
    return rows, malformed


def parse_overlay(path):
    rows, malformed = [], []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for n, raw in enumerate(fh, 1):
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            cells = line.split("\t")
            if len(cells) != 5:
                malformed.append((f"overlay-row-{n}", f"malformed overlay row (line {n}): {len(cells)} fields, expected 5"))
                continue
            row = dict(zip(COLUMNS, [c.strip() for c in cells]))
            row["source"] = f"overlay:{n}"
            rows.append(row)
    return rows, malformed


def strip_code(s):
    """`code` cells are written inside backticks in the registry; unwrap."""
    s = s.strip()
    if len(s) >= 2 and s[0] == "`" and s[-1] == "`":
        return s[1:-1]
    return s


def validate(row):
    """Return a skip reason for a malformed row, else None."""
    if not row["id"]:
        return "malformed row: empty id"
    if not re.fullmatch(r"[a-z0-9][a-z0-9._-]*", row["id"]):
        return f"malformed row: id {row['id']!r} is not [a-z0-9._-]"
    if not row["probe"]:
        return "malformed row: empty probe"
    exp = row["expect"]
    if not (exp == "exit0" or exp == "empty" or exp.startswith("regex:")):
        return f"malformed row: expect {exp!r} not in exit0|regex:<pattern>|empty"
    if exp.startswith("regex:"):
        try:
            re.compile(exp[len("regex:"):])
        except re.error as e:
            return f"malformed row: bad regex ({e})"
    if row["severity"] not in SEVERITIES:
        return f"malformed row: severity {row['severity']!r} not in high|med|low"
    return None


def evidence_of(stdout, stderr, extra=""):
    text = stdout.strip() or stderr.strip()
    text = " ⏎ ".join(l for l in text.splitlines() if l.strip())
    if extra:
        text = f"{extra}{' — ' if text else ''}{text}"
    if len(text) > EVIDENCE_CHARS:
        text = text[:EVIDENCE_CHARS] + "…"
    return text


def run_probe(row):
    env = dict(os.environ)
    env.update({
        "REPO_ROOT": repo_root,
        "LATTICE_HOME": home,
        "PROBE_ID": row["id"],
        "REGISTRY_DIR": os.path.dirname(registry),
    })
    t0 = time.monotonic()
    try:
        proc = subprocess.Popen(
            ["bash", "-c", row["probe"]], cwd=repo_root, env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            start_new_session=True,
        )
        try:
            out, err = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except OSError:
                pass
            out, err = proc.communicate()
            return "fail", None, evidence_of(out, err, f"timeout after {timeout}s"), int((time.monotonic() - t0) * 1000)
    except OSError as e:
        return "fail", None, f"cannot run probe: {e}", int((time.monotonic() - t0) * 1000)
    ms = int((time.monotonic() - t0) * 1000)
    rc = proc.returncode
    if rc == 3:
        return "skip", rc, evidence_of(out, err, "") or "prerequisite absent", ms
    exp = row["expect"]
    if exp == "exit0":
        status = "pass" if rc == 0 else "fail"
        return status, rc, ("" if status == "pass" else evidence_of(out, err, f"exit {rc}")), ms
    if rc != 0:
        return "fail", rc, evidence_of(out, err, f"exit {rc}"), ms
    if exp == "empty":
        if out.strip() == "":
            return "pass", rc, "", ms
        return "fail", rc, evidence_of(out, err), ms
    pat = exp[len("regex:"):]
    if re.search(pat, out, re.MULTILINE):
        return "pass", rc, "", ms
    return "fail", rc, evidence_of(out, err, f"no match for /{pat}/") or "empty stdout", ms


def unwrap(rows):
    """Registry cells are conventionally backticked; overlay cells may be."""
    for r in rows:
        for k in ("id", "probe", "expect", "severity"):
            r[k] = strip_code(r[k])
    return rows


# --- load + merge -----------------------------------------------------------
# A sensor never tracebacks: an unreadable registry/overlay is reported as a
# degraded line and ignored (exit stays 0).
try:
    rows, malformed = parse_registry(registry)
except OSError as e:
    rows, malformed = [], []
    degraded.append(f"registry unreadable: {registry} ({e.strerror or e}) (ignored)")
unwrap(rows)
if overlay:
    try:
        orows, omal = parse_overlay(overlay)
    except OSError as e:
        orows, omal = [], []
        degraded.append(f"overlay unreadable: {overlay} ({e.strerror or e}) (ignored)")
    unwrap(orows)
    malformed.extend(omal)
    by_id = {r["id"]: i for i, r in enumerate(rows)}
    for o in orows:
        if o["id"] in by_id:
            rows[by_id[o["id"]]] = o  # overlay wins
        else:
            rows.append(o)
            by_id[o["id"]] = len(rows) - 1

results = []
for r in rows:
    if only and r["id"] not in only:
        continue
    reason = home_error or validate(r)
    if reason:
        results.append({"id": r["id"] or "(no id)", "claim": r["claim"], "status": "skip",
                        "severity": r["severity"] if r["severity"] in SEVERITIES else "low",
                        "expect": r["expect"], "exit": None, "evidence": reason,
                        "duration_ms": 0, "source": r["source"]})
        continue
    status, rc, ev, ms = run_probe(r)
    results.append({"id": r["id"], "claim": r["claim"], "status": status, "severity": r["severity"],
                    "expect": r["expect"], "exit": rc, "evidence": ev, "duration_ms": ms,
                    "source": r["source"]})
if not only:
    for mid, reason in malformed:
        results.append({"id": mid, "claim": "", "status": "skip", "severity": "low", "expect": "",
                        "exit": None, "evidence": reason, "duration_ms": 0, "source": mid})
else:
    seen = {r["id"] for r in results}
    for want in only:
        if want not in seen:
            results.append({"id": want, "claim": "", "status": "skip", "severity": "low", "expect": "",
                            "exit": None, "evidence": "not in registry", "duration_ms": 0, "source": "--only"})

summary = {k: sum(1 for r in results if r["status"] == k) for k in ("pass", "fail", "skip")}
summary_line = f"claim-probes: {summary['pass']} pass, {summary['fail']} fail, {summary['skip']} skip"

if mode == "json":
    print(json.dumps({
        "schema": 1, "repo_root": repo_root, "lattice_home": home, "registry": registry,
        "overlay": overlay or None, "timeout_s": timeout, "probes": results,
        "summary": summary, "summary_line": summary_line,
        "degraded": ([home_error] if home_error else []) + degraded,
    }, indent=2, ensure_ascii=False))
else:
    def md(s):
        return str(s).replace("|", "\\|")
    for line in degraded:
        print(f"claim-probes: {line}")
    if home_error:
        print(f"claim-probes: {home_error}")
    print("| probe | status | severity | evidence |")
    print("| --- | --- | --- | --- |")
    for r in results:
        print(f"| {md(r['id'])} | {r['status']} | {md(r['severity'])} | {md(r['evidence'])} |")
    print()
    print(summary_line)
PY
