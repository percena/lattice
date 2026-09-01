#!/usr/bin/env bash
# Portable pre-merge alignment checklist (finish-work §2.5 helper).
# Machine-readable gaps only — does NOT edit issue/PR/binder (agent repairs).
#
# HARD gaps include (among draft/conflict checks):
#   - Fixes/Closes/Resolves #N with open (non-deferred) Acceptance task boxes
#   - binder open Acceptance on a Fixes land
#   - binder A* checked while GitHub issue still has those A* open (GH out of sync)
#     — **skipped** when binder marks adopted: true (binder-first SoT)
#   - PR cites Spec: spc-N but no Spec file under lattice homes (strict HARD; light WARN)
#
# WARN assists (Spec-linked, land-time; not full AC↔diff):
#   - binder covers A* ids not present on Spec Acceptance
#   - Spec cited but no Fixes/Closes/Resolves when Spec.tickets list non-empty
#   - adopted binder: open Acceptance still on issue body (info/WARN only — do not force body rewrite)
#
# Deferred markers (not HARD): "deferred"/"defer", "out-of-scope", "follow-up",
# "→ #N", "Refs #N", or HTML comments — counted only when positioned as an
# annotation (leading keyword, after punctuation, or "keyword:"), never as a
# mid-prose word inside the criterion text.
#
# Usage:
#   alignment-check.sh --pr <N> [--home <lattice-home>] [--json]
#
# Exit:
#   0 — no hard gaps (warnings may still print)
#   1 — hard gaps found
#   2 — usage / cannot load PR
set -euo pipefail

PR=""
HOME_DIR=""
AS_JSON=false

usage() {
  cat >&2 <<'EOF'
Usage: alignment-check.sh --pr <N> [--home path] [--json]
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR="${2:-}"; shift 2 ;;
    --home) HOME_DIR="${2:-}"; shift 2 ;;
    --json) AS_JSON=true; shift ;;
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
# Resolve _lattice-lib only (legacy lattice-lib dual-resolve dropped)
LIB_SCRIPTS=""
for cand in \
  "${LATTICE_LIB_SCRIPTS:-}" \
  "${SCRIPT_DIR}/../../_lattice-lib/scripts" \
  "${SCRIPT_DIR}/../../../skills/_lattice-lib/scripts"
do
  [[ -n "$cand" && -f "$cand/_lattice-home.sh" ]] || continue
  LIB_SCRIPTS="$cand"
  break
done
if [[ -n "$LIB_SCRIPTS" && -f "$LIB_SCRIPTS/_lattice-home.sh" ]]; then
  # shellcheck source=/dev/null
  source "$LIB_SCRIPTS/_lattice-home.sh"
  lattice_export_roots 2>/dev/null || true
  if [[ -z "$HOME_DIR" ]]; then
    HOME_DIR=$(lattice_default_home 2>/dev/null || echo "")
  fi
fi
if [[ -z "$HOME_DIR" ]]; then
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  HOME_DIR="${LATTICE_HOME:-$ROOT/.lattice}"
fi

# Profile: light softens Acceptance HARD → WARN
AC_PROFILE="strict"
if command -v lattice_profile >/dev/null 2>&1; then
  export LATTICE_HOME="${LATTICE_HOME:-$HOME_DIR}"
  AC_PROFILE=$(lattice_profile 2>/dev/null || echo "strict")
elif [[ -n "${LATTICE_PROFILE:-}" ]]; then
  AC_PROFILE=$(printf '%s' "$LATTICE_PROFILE" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
elif [[ -f "$HOME_DIR/config.yaml" ]]; then
  line=$(grep -E '^[[:space:]]*profile:[[:space:]]*' "$HOME_DIR/config.yaml" 2>/dev/null | head -1 || true)
  if [[ -n "$line" ]]; then
    # strip key + comments + quotes/whitespace without nested-quote sed
    AC_PROFILE=$(printf '%s' "$line" | sed -E 's/^[[:space:]]*profile:[[:space:]]*//; s/[[:space:]]*[#].*$//')
    AC_PROFILE=$(printf '%s' "$AC_PROFILE" | tr -d " \"'" | tr '[:upper:]' '[:lower:]')
  fi
fi
case "$AC_PROFILE" in light|strict) ;; *) AC_PROFILE="strict" ;; esac
# When binders live on the feature branch worktree only (not yet on MAIN_ROOT
# checkout), also consider the current show-toplevel .lattice.
WT_HOME=""
if command -v git >/dev/null 2>&1; then
  TOP=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$TOP" && -d "$TOP/.lattice" ]]; then
    WT_HOME="$TOP/.lattice"
  fi
fi

export AC_PR="$PR"
export AC_HOME="$HOME_DIR"
export AC_HOME2="${WT_HOME:-}"
export AC_JSON="$AS_JSON"
export AC_PROFILE="$AC_PROFILE"
SCRIPT_DIR_AC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ALIGNMENT_CHECK_LIB="${SCRIPT_DIR_AC}/lib"

python3 - <<'PY'
import json, os, re, subprocess, sys
from pathlib import Path

pr = os.environ["AC_PR"]
home = Path(os.environ["AC_HOME"])
home2 = Path(os.environ["AC_HOME2"]) if os.environ.get("AC_HOME2") else None
as_json = os.environ.get("AC_JSON", "false").lower() == "true"

def lattice_dirs():
    seen = set()
    for h in (home, home2):
        if h and h not in seen:
            seen.add(h)
            yield h

hard = []
warn = []
info = []
profile = (os.environ.get("AC_PROFILE") or "strict").strip().lower()
if profile not in ("strict", "light"):
    profile = "strict"
light = profile == "light"
if light:
    info.append("profile=light — open Acceptance on Fixes is WARN (not HARD)")

def gh_json(args):
    try:
        out = subprocess.check_output(["gh", *args], text=True, stderr=subprocess.DEVNULL)
        return json.loads(out)
    except Exception as e:
        return None

# stateReason is not a gh issue view --json field on all gh versions (same
# asymmetry as baseRefOid — tkt-293). Fetch via REST, which is stable.
CONTRADICTION_REASONS = {"not_planned", "duplicate", "out_of_date"}
VALID_STATE_REASONS = {"completed", "not_planned", "reopened", "duplicate", "out_of_date"}

def gh_state_reason(iid, repo_id, api_hostname=""):
    if not repo_id:
        return ""
    api_args = ["gh", "api", f"repos/{repo_id}/issues/{iid}", "--jq", ".state_reason"]
    # Pass --hostname for GHE instances (tkt-311 A1). For github.com the
    # flag is a no-op (gh resolves the default host).
    if api_hostname:
        api_args += ["--hostname", api_hostname]
    try:
        out = subprocess.check_output(api_args, text=True, stderr=subprocess.DEVNULL).strip()
        # Defense-in-depth: discard null or error-body output (tkt-301).
        return out if out in VALID_STATE_REASONS else ""
    except Exception:
        return ""

pr_data = gh_json(["pr", "view", pr, "--json", "number,title,body,state,headRefName,baseRefName,url,isDraft,mergeable"])
if not pr_data:
    print("Error: cannot load PR", pr, file=sys.stderr)
    sys.exit(2)

body = pr_data.get("body") or ""
title = pr_data.get("title") or ""
head = pr_data.get("headRefName") or ""
url = pr_data.get("url") or ""

# Extract owner/repo from the PR URL for REST issue close-reason lookups (tkt-294).
# Match the LAST two path segments before /pull/ to handle GHE path-prefixed
# URLs like https://github.acme.io/org/team/repo/pull/1 (tkt-302).
# Also extract the hostname for --hostname flag on gh api (tkt-311 A1).
_repo_match = re.match(r'https?://([^/]+)/(.+)/pull/\d+', url)
if _repo_match:
    api_hostname = _repo_match.group(1)
    _segments = _repo_match.group(2).split('/')
    repo_id = '/'.join(_segments[-2:]) if len(_segments) >= 2 else _repo_match.group(2)
else:
    api_hostname = ""
    repo_id = ""

# Executable closing keywords (shared fence-aware extractor with close-fixed-issues).
# Refs does not auto-close. Repository-qualified Fixes owner/repo#N stay non-local.
import importlib.util

_closing_path = Path(os.environ.get("ALIGNMENT_CHECK_LIB", "")) / "closing_directives.py"
_spec = importlib.util.spec_from_file_location("closing_directives", _closing_path)
if _spec is None or _spec.loader is None or not _closing_path.is_file():
    print("Error: missing closing directive extractor:", _closing_path, file=sys.stderr)
    sys.exit(2)
_closing = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_closing)
closing_ids, unsupported_closing_refs = _closing.extract_closing_directives(body)
# Refs scan is fence-aware like the closing extractor: a fenced `Refs #N`
# example must not trigger an issue load or a spurious binder gate. Inline
# code spans (`Refs #N`) are stripped too — reusing the extractor's regex so
# the refs scan matches exactly what the closing extractor considers prose.
body_prose = "\n".join(_closing.visible_prose_lines(body))
body_prose = _closing._CODE_SPAN_RE.sub(" ", body_prose)
refs_ids = sorted({int(x) for x in re.findall(r"(?i)\brefs\s+#(\d+)\b", body_prose)})
issue_ids = sorted(set(closing_ids) | set(refs_ids))
if unsupported_closing_refs:
    info.append(
        "unsupported repository-qualified closing refs (not local will_close): "
        + ", ".join(unsupported_closing_refs)
    )
# ticket-in-branch
m = re.search(r"(?:^|/)tkt-(\d+)(?:-|$)", head)
branch_tkt = int(m.group(1)) if m else None
if branch_tkt and branch_tkt not in issue_ids:
    warn.append(f"branch encodes tkt-{branch_tkt} but PR body has no Fixes/Refs #{branch_tkt}")

# Spec-first head (spc-N-…) without issue keywords
m_spc = re.search(r"(?:^|/)spc-(\d+)(?:-|$)", head)
branch_spc = f"spc-{m_spc.group(1)}" if m_spc else None
if branch_spc and not issue_ids:
    warn.append(
        f"branch encodes {branch_spc} (Spec-first) but PR body has no Fixes/Refs #N — "
        "confirm issue linkage or intentional Spec-only ship"
    )

if not issue_ids and not branch_tkt and not branch_spc:
    warn.append("no Fixes/Refs #N in PR body and no tkt-N/spc-N in branch name")

# Normative cite is `Spec: spc-N` (create-pr templates). Bare
# `spc-N` in prose must not HARD-fail missing Spec load (false positive).
spec_ids = re.findall(r"(?i)\bSpec\s*:\s*spc-(\d+)\b", body)
# preserve order, unique
_seen = set()
_spec_ordered = []
for x in spec_ids:
    sid = f"spc-{x}"
    if sid not in _seen:
        _seen.add(sid)
        _spec_ordered.append(sid)
spec_ids = _spec_ordered
if branch_spc and branch_spc not in spec_ids:
    warn.append(f"branch encodes {branch_spc} but PR body has no Spec: {branch_spc} line")

# --- Acceptance task-list parsing (issue + binder) ---
# Machine gate: open boxes that will be closed by Fixes/Closes/Resolves must
# be checked off (or explicitly deferred) before merge. Does not judge whether
# the diff implements a criterion — only that cold-reader status is honest.
# Deferral rule: a keyword counts only as an annotation, not prose — it must
# be a whole word that (a) opens the box text right after the optional
# **A-id**, (b) follows an HTML comment opener or punctuation separator
# (: ; , ( [ — – or a spaced/double dash), or (c) is itself followed by ':'.
# "**A2** deferred: follow-up ticket #N" stays deferred while
# "**A2** add follow-up email reminders" stays actionable.
DEFER_KEYWORD = r"(?:defer(?:red|ral)?|out[- ]of[- ]scope|follow[- ]?up)"
DEFER_RE = re.compile(
    r"(?i)"
    r"(?:^(?:\*\*A\d+\*\*[:.]?\s*)?|<!--\s*|[:;,(\[—–]\s*|\s-\s+|--\s*)"
    + DEFER_KEYWORD
    + r"\b"
    r"|\b" + DEFER_KEYWORD + r"(?=\s*:)"
    r"|→\s*#\d+"
    r"|\brefs\s+#\d+"
)
A_ID_RE = re.compile(r"\*\*A(\d+)\*\*|\bA(\d+)\b")
# GitHub-valid task-list syntax: -, *, + bullets and ordered 1. / 1) markers,
# with 1-4 spaces between the marker and the [ ] box.
BOX_RE = re.compile(r"^\s*(?:[-*+]|\d{1,9}[.)])[ \t]{1,4}\[([ xX])\]\s+(.*)$", re.M)


def is_deferred(line: str) -> bool:
    return bool(DEFER_RE.search(line))


def a_id(line: str):
    m = A_ID_RE.search(line)
    if not m:
        return None
    return f"A{m.group(1) or m.group(2)}"


def parse_boxes(text: str):
    """Return (open_actionable, open_deferred, done_ids, open_ids).

    open_actionable / open_deferred: list of short labels (A1 or first 60 chars).
    done_ids / open_ids: sets of A* ids only.
    """
    open_actionable, open_deferred = [], []
    done_ids, open_ids = set(), set()
    # Fence-aware like the closing-directive extractor: a fenced example
    # containing `## Acceptance` would end the real section early, and fenced
    # `- [ ] A1 …` sample rows would count as real open boxes (spurious HARD
    # gap) or mask a real one.
    text = "\n".join(_closing.visible_prose_lines(text))
    # Prefer Acceptance section if present; else whole body (ticket templates
    # put checkboxes only under Acceptance).
    section = text
    am = re.search(r"(?im)^##+\s*Acceptance\b.*$", text)
    if am:
        start = am.end()
        nxt = re.search(r"(?m)^##+\s+", text[start:])
        section = text[start : start + nxt.start()] if nxt else text[start:]
    for m in BOX_RE.finditer(section):
        checked = m.group(1).lower() == "x"
        rest = m.group(2).strip()
        aid = a_id(rest)
        label = aid or (rest[:60] + ("…" if len(rest) > 60 else ""))
        if checked:
            if aid:
                done_ids.add(aid)
            continue
        if is_deferred(rest):
            open_deferred.append(label)
            continue
        open_actionable.append(label)
        if aid:
            open_ids.add(aid)
    return open_actionable, open_deferred, done_ids, open_ids


issues = []
issue_boxes = {}  # iid -> parse_boxes result
# Pre-scan binders for adopted: true so issue open-box HARD can be softened
adopted_ids = set()
_pre_ids = list(issue_ids)
# branch_tkt may be set later in flow; scan known issue_ids first, re-scan after binders if needed
for _iid in list(issue_ids):
    for h in lattice_dirs():
        td = h / "tickets"
        if not td.is_dir():
            continue
        for match in list(td.glob(f"tkt-{_iid}-*")) + list((td / "archive").glob(f"tkt-{_iid}-*") if (td / "archive").is_dir() else []):
            readme = match / "README.md"
            if readme.is_file():
                try:
                    _bt = readme.read_text(encoding="utf-8", errors="replace")
                except OSError:
                    continue
                if re.search(r"(?im)(?:\|\s*adopted\s*\|\s*true\s*\|)|(?:^adopted\s*:\s*true\b)", _bt):
                    adopted_ids.add(_iid)

for iid in issue_ids:
    data = gh_json(["issue", "view", str(iid), "--json", "number,title,body,state,labels"])
    if not data:
        hard.append(f"cannot load issue #{iid}")
        continue
    issues.append(data)
    if data.get("state") == "CLOSED":
        sr = gh_state_reason(iid, repo_id, api_hostname)
        if sr and sr in CONTRADICTION_REASONS and iid in closing_ids:
            warn.append(
                f"issue #{iid} is closed as {sr.upper()} but PR #{pr} Fixes/Closes it — "
                "reconcile close-reason vs the delivering PR (re-close as completed, or drop the Fixes/Retarget)"
            )
            info.append(f"issue #{iid} already CLOSED (reason: {sr}) — contradiction WARN emitted")
        elif sr:
            info.append(f"issue #{iid} already CLOSED (reason: {sr})")
        else:
            info.append(f"issue #{iid} already CLOSED (close-reason unavailable — REST fetch failed or repo_id unresolved)")
    ibody = data.get("body") or ""
    boxes = parse_boxes(ibody)
    issue_boxes[iid] = boxes
    open_a, open_d, done_ids, open_ids = boxes
    will_close = iid in closing_ids
    if open_a:
        preview = ", ".join(open_a[:6]) + ("…" if len(open_a) > 6 else "")
        if will_close and iid in adopted_ids:
            # adopted — issue body open boxes are not HARD; binder gates later
            info.append(
                f"adopted issue #{iid} has {len(open_a)} open body Acceptance item(s) — "
                f"binder-first SoT; not HARD: {preview}"
            )
        elif will_close:
            msg = (
                f"issue #{iid} has {len(open_a)} open Acceptance item(s) "
                f"while PR Fixes/Closes it — check off (or mark deferred/out-of-scope) before merge: {preview}"
            )
            (warn if light else hard).append(msg)
        else:
            warn.append(
                f"issue #{iid} (Refs, not auto-closed) has {len(open_a)} open Acceptance item(s): {preview}"
            )
    elif open_d:
        info.append(f"issue #{iid} has {len(open_d)} deferred open box(es) — OK")
    elif not done_ids and not re.search(r"(?im)^##+\s*Acceptance\b", ibody):
        info.append(f"issue #{iid} has no Acceptance task list — skip checkbox gate")

# binders (search all candidate lattice homes)
binders = []
ids_for_binders = issue_ids or ([branch_tkt] if branch_tkt else [])
binder_boxes = {}
for iid in ids_for_binders:
    matches = []
    for h in lattice_dirs():
        td = h / "tickets"
        if not td.is_dir():
            continue
        live_matches = sorted(td.glob(f"tkt-{iid}-*"))
        # Closed binders may live under tickets/archive/
        arch = td / "archive"
        archived_matches = sorted(arch.glob(f"tkt-{iid}-*")) if arch.is_dir() else []
        # Within a home a live binder shadows its archived (stale) copy; the
        # explicit --home keeps priority over the worktree fallback home, and
        # glob order is normalized by sorting.
        matches = live_matches or archived_matches
        if matches:
            break
    if not matches:
        homes = ", ".join(str(h / "tickets") for h in lattice_dirs())
        warn.append(f"no binder dir for tkt-{iid} under {homes or '(no lattice homes)'}")
        continue
    if len(matches) > 1:
        warn.append(
            f"ambiguous binder dirs for tkt-{iid}: using {matches[0]}, "
            f"ignoring {', '.join(str(m) for m in matches[1:])}"
        )
    readme = matches[0] / "README.md"
    if not readme.is_file():
        hard.append(f"binder missing README: {matches[0]}")
        continue
    text = readme.read_text(encoding="utf-8", errors="replace")
    binders.append({"id": iid, "path": str(readme), "text": text})
    # binder-first Acceptance when adopted (do not force issue body rewrite)
    adopted = bool(
        re.search(r"(?im)(?:\|\s*adopted\s*\|\s*true\s*\|)|(?:^adopted\s*:\s*true\b)", text)
    )
    if adopted:
        info.append(f"binder tkt-{iid} adopted: true — binder-first Acceptance SoT")
    if re.search(r"\|\s*status\s*\|\s*closed\s*\|", text, re.I) and pr_data.get("state") == "OPEN":
        warn.append(f"binder tkt-{iid} status=closed while PR still OPEN")
    b_open, b_def, b_done, b_open_ids = parse_boxes(text)
    binder_boxes[iid] = (b_open, b_def, b_done, b_open_ids)
    # Treat as closing land when PR uses Fixes/Closes/Resolves for this id
    will_close = iid in closing_ids
    if b_open:
        preview = ", ".join(b_open[:6]) + ("…" if len(b_open) > 6 else "")
        if will_close:
            msg = (
                f"binder tkt-{iid} has {len(b_open)} open Acceptance item(s) "
                f"for a Fixes/Closes land — check off (or mark deferred) before merge: {preview}"
            )
            (warn if light else hard).append(msg)
        else:
            warn.append(f"binder tkt-{iid} has {len(b_open)} open Acceptance item(s): {preview}")
    # GH issue out of sync with binder: binder checked A* but issue still open
    # Adopted binders: binder is SoT — do not HARD-require gh issue edit
    if iid in issue_boxes:
        i_open_a, _, i_done, i_open_ids = issue_boxes[iid]
        stale = sorted(b_done & i_open_ids, key=lambda x: int(x[1:]))
        if stale and iid in closing_ids:
            if adopted:
                info.append(
                    f"adopted tkt-{iid}: binder checked {', '.join(stale)} while issue boxes still open — "
                    "OK (binder-first); prefer settlement comment, do not rewrite issue body"
                )
            else:
                msg = (
                    f"issue #{iid} Acceptance not synced with binder: binder checked "
                    f"{', '.join(stale)} but issue still open — gh issue edit before merge"
                )
                (warn if light else hard).append(msg)
        # Adopted + open issue Acceptance on Fixes land: soft only (issue body may lack Lattice boxes)
        if adopted and will_close and i_open_a:
            preview = ", ".join(i_open_a[:6]) + ("…" if len(i_open_a) > 6 else "")
            info.append(
                f"adopted issue #{iid} still lists open Acceptance on body ({preview}) — "
                "binder is SoT; optional settlement comment"
            )
if not ids_for_binders:
    info.append("no issue ids — skip binder checks")

# Spec files cited (any lattice home) + land-time Spec-linked assists
def parse_spec_a_ids(text: str):
    """A* ids from Spec Acceptance section (or whole file)."""
    section = text
    am = re.search(r"(?im)^##+\s*Acceptance\b.*$", text)
    if am:
        rest = text[am.end() :]
        nxt = re.search(r"(?im)^##+\s+\S", rest)
        section = rest[: nxt.start()] if nxt else rest
    ids = set()
    for m in A_ID_RE.finditer(section):
        ids.add(f"A{m.group(1) or m.group(2)}")
    return ids


def parse_covers_ids(text: str):
    """covers: A1, A2 from binder front matter or Covers: lines."""
    ids = set()
    for m in re.finditer(r"(?im)^(?:covers|Covers)\s*[:=]\s*(.+)$", text):
        for part in re.findall(r"\bA(\d+)\b", m.group(1)):
            ids.add(f"A{part}")
    # YAML-ish covers: [A1, A2] or covers: A1, A2 in front matter
    fm = re.match(r"(?s)^---\n(.*?)\n---", text)
    if fm:
        for m in re.finditer(r"(?im)^covers\s*:\s*(.+)$", fm.group(1)):
            for part in re.findall(r"\bA(\d+)\b", m.group(1)):
                ids.add(f"A{part}")
    return ids


def parse_spec_tickets_front_matter(text: str):
    """Bare tkt-N ids from Spec front matter tickets: list."""
    fm = re.match(r"(?s)^---\n(.*?)\n---", text)
    if not fm:
        return []
    block = fm.group(1)
    # Collect under tickets: key until next top-level key
    ids = []
    in_tickets = False
    for line in block.splitlines():
        if re.match(r"(?i)^tickets\s*:", line):
            in_tickets = True
            inline = re.sub(r"(?i)^tickets\s*:\s*", "", line).strip()
            if inline and inline not in ("[]", "~", "null"):
                ids.extend(re.findall(r"tkt-(\d+)", inline, flags=re.I))
            continue
        if in_tickets:
            if re.match(r"^\S", line) and not line.strip().startswith("-"):
                break
            m = re.search(r"tkt-(\d+)", line, flags=re.I)
            if m:
                ids.append(m.group(1))
    return sorted({int(x) for x in ids})


spec_files = {}  # sid -> Path
for sid in sorted(set(spec_ids)):
    n = sid.split("-", 1)[1]
    found = []
    for h in lattice_dirs():
        sd = h / "specs"
        if sd.is_dir():
            found.extend(sd.glob(f"spc-{n}-*.md"))
    if not found:
        homes = ", ".join(str(h / "specs") for h in lattice_dirs())
        msg = f"PR cites {sid} but no file under {homes or '(no lattice homes)'} — land-time Spec load failed"
        # Machine-decidable: missing Spec when cited is HARD in strict, WARN in light
        (warn if light else hard).append(msg)
    else:
        spec_files[sid] = found[0]
        info.append(f"spec file ok: {found[0].name}")

# covers honesty + Spec.tickets vs Fixes assist (WARN; not full POST_SPLIT)
for sid, spath in sorted(spec_files.items()):
    try:
        stext = spath.read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        warn.append(f"cannot read Spec {sid} at {spath}: {e}")
        continue
    spec_a = parse_spec_a_ids(stext)
    if not spec_a:
        info.append(f"{sid}: no A* ids in Acceptance — skip covers honesty")
    else:
        info.append(f"{sid}: Spec A* = {', '.join(sorted(spec_a, key=lambda x: int(x[1:])))}")
    # binder covers must exist on Spec
    for b in binders:
        try:
            btext = Path(b["path"]).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        cov = parse_covers_ids(btext)
        if not cov:
            continue
        orphan = sorted(cov - spec_a, key=lambda x: int(x[1:]) if x[1:].isdigit() else 0)
        if orphan and spec_a:
            warn.append(
                f"binder {Path(b['path']).parent.name} covers {', '.join(orphan)} "
                f"not found on {sid} Acceptance — land-time covers honesty"
            )
    # Spec lists tickets but PR has no closing keywords (WARN)
    spec_tkt_nums = parse_spec_tickets_front_matter(stext)
    if spec_tkt_nums and not closing_ids:
        warn.append(
            f"{sid} lists tickets {spec_tkt_nums} but PR has no Fixes/Closes/Resolves — "
            "confirm intentional Spec-only or Refs-only land"
        )

# Draft / mergeable
if pr_data.get("isDraft"):
    hard.append("PR is draft")
_mergeable = pr_data.get("mergeable") or ""
if _mergeable == "CONFLICTING":
    hard.append("PR mergeable=CONFLICTING (run update-pr-base / resolve conflicts)")
elif _mergeable != "MERGEABLE":
    # GitHub reports UNKNOWN while it recomputes mergeability (routine right
    # after a push). Passing the gate on UNKNOWN means a conflicting PR checked
    # at the wrong moment reads as aligned. update-pr-base.sh already treats
    # non-MERGEABLE as fail-closed; warn rather than HARD so a transient
    # UNKNOWN does not block a land the operator can re-check.
    warn.append(
        f"PR mergeable={_mergeable or 'unset'} (GitHub still computing?) — "
        "re-run alignment-check before merging to confirm it is not CONFLICTING"
    )

# Title empty
if not title.strip():
    hard.append("PR title empty")

# Body thin
if len(body.strip()) < 40:
    warn.append("PR body very short — ensure Why/How + Fixes/Refs")

result = {
    "ok": len(hard) == 0,
    "profile": profile,
    "pr": int(pr),
    "url": url,
    "head": head,
    "issue_ids": issue_ids,
    "closing_ids": closing_ids,
    "unsupported_closing_refs": unsupported_closing_refs,
    "refs_ids": refs_ids,
    "branch_tkt": branch_tkt,
    "branch_spc": branch_spc,
    "spec_ids": spec_ids,
    "hard": hard,
    "warn": warn,
    "info": info,
    "binder_paths": [b["path"] for b in binders],
    "human_required": "acceptance_vs_diff",
}

if as_json:
    print(json.dumps(result, indent=2))
else:
    print(f"# alignment-check PR #{pr}")
    print(f"profile: {profile}")
    print(f"head: {head}")
    print(f"issues: {issue_ids or '(none)'}  Fixes/Closes: {closing_ids or '(none)'}  Refs: {refs_ids or '(none)'}")
    if unsupported_closing_refs:
        print(f"unsupported_closing_refs: {unsupported_closing_refs}")
    print(f"branch_tkt: {branch_tkt}  branch_spc: {branch_spc}  specs: {spec_ids or '(none)'}")
    print("human_required: acceptance_vs_diff (+ land-time Spec drift when Spec applies)")
    for b in binders:
        print(f"binder: {b['path']}")
    if hard:
        print("## HARD gaps")
        for x in hard:
            print(f"- [ ] {x}")
        print("## repair hint")
        print("- Check off completed Acceptance on GitHub issue + binder (gh issue edit / edit binder)")
        print("- Or mark leftover items deferred/out-of-scope / follow-up #N on the checkbox line")
        print("- Land-time Spec drift: update tickets/diff or amend Spec — do not merge half-done Fixes")
        print("- Re-run: alignment-check.sh --pr N  (then merge only when ok)")
    if warn:
        print("## WARN")
        for x in warn:
            print(f"- {x}")
    if info:
        print("## INFO")
        for x in info:
            print(f"- {x}")
    print(f"## summary: ok={result['ok']} hard={len(hard)} warn={len(warn)}")
    if result["ok"]:
        print(
            f"alignment: checklist_ok (PR #{pr} ↔ issues {issue_ids} ↔ binders {len(binders)}) — "
            "still verify Acceptance↔diff + land-time Spec drift in-session"
        )
    else:
        print("alignment: HARD gaps — fix before gh pr merge")

sys.exit(0 if result["ok"] else 1)
PY
