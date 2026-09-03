"""CI failure classifier for the finish-work CI merge gate (spc-186 A6/A8,
ADR-007 §5a).

Compiles the infra-class corner case INTO the rule: a CI failure is
classified as **infra-class** (billing/quota/rate-limit/timeout/empty-step
flake/runner-infra) or **real**. Infra-only red + local verification evidence
passes with an auto-stamped waiver (a compiled corner case, NOT an
exception requiring human adjudication — ADR-007 §5a). Real failures block
HARD.

Pattern set is config-tunable via `.lattice/config.yaml` under `ci_gate:
infra_patterns`. The default set ships with the script (see DEFAULT_PATTERNS)
so the gate works without config.

This module is dependency-free (no PyYAML) so consumer repos can vendor it
alone. Config is parsed with a minimal flat-key YAML reader.

Classification inputs:
  - check_name:    the GitHub check name (e.g. "lint-heavy")
  - conclusion:    the check conclusion (FAILURE / CANCELLED / TIMED_OUT / etc.)
  - log_excerpt:   a short log excerpt from `gh run view --log-failed` (may be
                   empty — empty + short-duration is the empty-step flake signal)

Returns a dict:
  {"class": "infra"|"real"|"unknown", "category": str, "pattern": str}
  - class=infra  → infra-class failure (compiled waiver eligible)
  - class=real   → real failure (HARD block)
  - class=unknown → cannot classify (treated as real by the gate — fail-closed)
"""

from __future__ import annotations

import os
import re
import sys
from typing import Dict, List, Optional, Tuple

# Default infra-class pattern set. Each category maps to a list of
# case-insensitive substring patterns matched against the log excerpt +
# check name. The set is the initial list proposed for operator confirm
# (binder "Anticipated decisions" — must-ask).
#
# Categories (ADR-007 §5a + flow.md §2 preflight):
#   billing     — billing block / spending limit / payment required / quota
#   rate_limit  — primary/secondary rate limit / too many requests
#   timeout     — timeout / timed out / deadline exceeded
#   empty_step  — no failing-step log output (detected by the gate script,
#                 not pattern-matched here; classifier flags empty log)
#   runner_infra— runner offline / connection refused / ephemeral runner
DEFAULT_PATTERNS: Dict[str, List[str]] = {
    "billing": [
        "billing",
        "usage limit",
        "quota exceeded",
        "quota",
        "payment required",
        "spending limit",
        "account suspended",
        "action required: update billing",
    ],
    "rate_limit": [
        "rate limit",
        "rate-limited",
        "secondary rate limit",
        "too many requests",
        "api rate limit",
        "abuse detection",
    ],
    "timeout": [
        "timeout",
        "timed out",
        "timed_out",
        "deadline exceeded",
        "context deadline",
        "the operation was canceled",
    ],
    "runner_infra": [
        "runner offline",
        "runner unavailable",
        "self-hosted runner",
        "connection refused",
        "ephemeral runner",
        "runner provision",
        "network is unreachable",
        "temporarily unavailable",
    ],
}

# Conclusions that count as failures for classification.
FAILURE_CONCLUSIONS = frozenset({
    "FAILURE", "CANCELLED", "TIMED_OUT", "STARTUP_FAILURE", "ACTION_REQUIRED",
})


def load_config_patterns(home_dir: Optional[str] = None) -> Dict[str, List[str]]:
    """Load the infra_patterns config from .lattice/config.yaml.

    Falls back to DEFAULT_PATTERNS when the file or section is absent.
    Uses a minimal flat-key reader (no PyYAML dependency).
    """
    patterns = {k: list(v) for k, v in DEFAULT_PATTERNS.items()}
    if not home_dir:
        return patterns
    config_path = os.path.join(home_dir, "config.yaml")
    if not os.path.isfile(config_path):
        return patterns
    try:
        with open(config_path, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return patterns
    # Minimal parser: find ci_gate: infra_patterns: block and collect list items.
    # Supports both inline `[a, b]` and block `- a` / `- "a"` forms.
    # Both forms REPLACE the default pattern list for the category (tkt-327):
    # a user-configured category fully overrides DEFAULT_PATTERNS for that key.
    in_ci_gate = False
    in_patterns = False
    current_cat = None
    for line in text.splitlines():
        stripped = line.rstrip()
        if not stripped or stripped.lstrip().startswith("#"):
            continue
        # Track nesting by indentation (2-space per level)
        if re.match(r"^ci_gate\s*:", stripped):
            in_ci_gate = True
            in_patterns = False
            continue
        if in_ci_gate and re.match(r"^\s{2}infra_patterns\s*:", stripped):
            in_patterns = True
            continue
        if in_ci_gate and re.match(r"^\s{2}\S", stripped):
            # New 2-indent key under ci_gate → stop patterns section
            if not stripped.startswith("  infra_patterns"):
                in_patterns = False
        if in_ci_gate and re.match(r"^\S", stripped):
            # Top-level key → exit ci_gate
            in_ci_gate = False
            in_patterns = False
        if not in_patterns:
            continue
        # Inside infra_patterns: look for `  category: [...]` or `  category:` + `    - item`
        cat_inline = re.match(r"^\s{4}(\w+)\s*:\s*\[(.*)\]\s*$", stripped)
        if cat_inline:
            cat = cat_inline.group(1)
            items = [
                p.strip().strip("\"'")
                for p in cat_inline.group(2).split(",")
                if p.strip()
            ]
            if cat and items:
                patterns[cat] = items
            continue
        cat_block = re.match(r"^\s{4}(\w+)\s*:\s*$", stripped)
        if cat_block:
            current_cat = cat_block.group(1)
            # REPLACE default list (not append) — same override semantics as
            # the inline form `category: [a, b]` (tkt-327). Without this reset,
            # block-form items silently append to DEFAULT_PATTERNS, broadening
            # infra-class waivers beyond intent (e.g. 'quota' stays live).
            patterns[current_cat] = []
            continue
        list_item = re.match(r"^\s{6,}-\s+(.+)\s*$", stripped)
        if list_item and current_cat:
            val = list_item.group(1).strip().strip("\"'")
            if val and val not in patterns[current_cat]:
                patterns[current_cat].append(val)
    return patterns


def classify_failure(
    check_name: str,
    conclusion: str,
    log_excerpt: str,
    patterns: Optional[Dict[str, List[str]]] = None,
) -> Dict[str, str]:
    """Classify a CI failure as infra-class or real.

    Returns: {"class": "infra"|"real"|"unknown", "category": str, "pattern": str}

    - class=infra  → compiled waiver eligible (ADR-007 §5a)
    - class=real   → HARD block
    - class=unknown → cannot decide (gate treats as real — fail-closed)
    """
    if patterns is None:
        patterns = {k: list(v) for k, v in DEFAULT_PATTERNS.items()}

    conclusion_upper = (conclusion or "").upper().strip()
    name_lower = (check_name or "").lower()
    log_lower = (log_excerpt or "").lower()

    # TIMED_OUT: only infra when the log/check-name matches a runner/timeout
    # pattern. A genuinely hanging test suite (deadlock, perf regression,
    # infinite loop) also concludes TIMED_OUT; without an infra signal we
    # classify unknown (fail-closed) rather than waive. Checked before
    # empty-step so a TIMED_OUT with no log is unknown, not empty_step.
    if conclusion_upper == "TIMED_OUT":
        search_text = f"{name_lower}\n{log_lower}"
        timeout_pats = patterns.get("timeout", []) + patterns.get("runner_infra", [])
        matched_pat = None
        for pat in timeout_pats:
            if pat.lower() in search_text:
                matched_pat = pat
                break
        if matched_pat:
            return {
                "class": "infra",
                "category": "timeout",
                "pattern": matched_pat,
            }
        return {
            "class": "unknown",
            "category": "timeout",
            "pattern": "conclusion=TIMED_OUT (no infra/timeout pattern matched)",
        }

    # STARTUP_FAILURE / ACTION_REQUIRED often indicate runner/billing infra.
    # Checked before empty-step: STARTUP_FAILURE with no log is runner_infra,
    # not an empty-step flake.
    if conclusion_upper in ("STARTUP_FAILURE", "ACTION_REQUIRED"):
        # Check for billing in name first
        for pat in patterns.get("billing", []):
            if pat in name_lower or pat in log_lower:
                return {
                    "class": "infra",
                    "category": "billing",
                    "pattern": pat,
                }
        return {
            "class": "infra",
            "category": "runner_infra",
            "pattern": f"conclusion={conclusion_upper}",
        }

    # Empty-step flake: FAILURE conclusion but no log output. This is the
    # flow.md §2 "CI empty-step ≤~5s" signal — a check that failed with
    # no failing-step log. Detected when the gate script passes an empty
    # log_excerpt for a FAILURE conclusion. CANCELLED is EXCLUDED: an
    # operator-cancelled workflow with no failing-step log is not an
    # empty-step flake — it falls through to the CANCELLED→unknown branch
    # (fail-closed) unless an infra pattern matches its log/name.
    if (
        conclusion_upper in FAILURE_CONCLUSIONS
        and conclusion_upper != "CANCELLED"
        and not log_lower.strip()
    ):
        return {
            "class": "infra",
            "category": "empty_step",
            "pattern": "(no failing-step log output)",
        }

    # Pattern-match the log excerpt + check name against each infra category.
    search_text = f"{name_lower}\n{log_lower}"
    for category, pat_list in patterns.items():
        for pat in pat_list:
            if pat.lower() in search_text:
                return {
                    "class": "infra",
                    "category": category,
                    "pattern": pat,
                }

    # CANCELLED without infra pattern → unknown (could be operator cancel
    # or infra). Gate treats unknown as real (fail-closed).
    if conclusion_upper == "CANCELLED":
        return {
            "class": "unknown",
            "category": "cancelled",
            "pattern": "conclusion=CANCELLED (no infra pattern matched)",
        }

    # Default: real failure
    return {
        "class": "real",
        "category": "real",
        "pattern": "(no infra pattern matched)",
    }


def classify_checks(
    checks: List[Dict],
    log_fetcher=None,
    patterns: Optional[Dict[str, List[str]]] = None,
) -> Tuple[List[Dict], List[Dict], List[Dict]]:
    """Classify a list of check dicts from `gh pr checks --json`.

    Each check has: name, state, conclusion, link.
    log_fetcher: optional callable(check) -> str that fetches the log excerpt
                 for a failed check. When None, log_excerpt is "" (empty-step
                 detection still works).

    Returns: (infra_failures, real_failures, unknown_failures)
    Each element: {"name", "conclusion", "category", "pattern", "link", "log_excerpt"}
    """
    infra = []
    real = []
    unknown = []
    for check in checks:
        conclusion = (check.get("conclusion") or "").upper()
        state = (check.get("state") or "").upper()
        # Only classify non-green checks
        if state in ("SUCCESS", "NEUTRAL", "SKIPPED"):
            continue
        if conclusion in ("SUCCESS", "NEUTRAL", "SKIPPED") and state != "PENDING":
            continue
        # Pending checks are not failures (yet) — the gate waits
        if state == "PENDING":
            continue
        if conclusion not in FAILURE_CONCLUSIONS and state != "FAILURE":
            continue

        log_excerpt = ""
        if log_fetcher:
            try:
                log_excerpt = log_fetcher(check) or ""
            except Exception:
                log_excerpt = ""

        result = classify_failure(
            check.get("name", ""),
            conclusion,
            log_excerpt,
            patterns,
        )
        entry = {
            "name": check.get("name", ""),
            "conclusion": conclusion,
            "state": state,
            "category": result["category"],
            "pattern": result["pattern"],
            "link": check.get("link", ""),
            "log_excerpt": log_excerpt[:500],
        }
        if result["class"] == "infra":
            infra.append(entry)
        elif result["class"] == "real":
            real.append(entry)
        else:
            unknown.append(entry)
    return infra, real, unknown


def waiver_trace(
    pr_n: str,
    infra_failures: List[Dict],
    evidence: str,
    timestamp: str,
) -> str:
    """Build the structured waiver trace line for the binder ## Decision journal.

    ADR-007 §5a: this is a compiled corner case, NOT an exception.
    rule_id=ci-gate; authorizer=human-at-merge-time (the local evidence IS
    the human authorization — the operator ran the local checks).
    """
    cats = sorted({f["category"] for f in infra_failures})
    names = [f["name"] for f in infra_failures]
    return (
        f"- {timestamp} — ci-gate compiled waiver (spc-186 A6/A8, ADR-007 §5a). "
        f"rule_id=ci-gate; reason=infra-only failures ({', '.join(cats)}) on "
        f"checks [{', '.join(names)}] + local verification evidence present; "
        f"evidence=\"{evidence}\"; authorizer=human-at-merge-time; "
        f"ts={timestamp}"
    )


def pr_comment_body(
    pr_n: str,
    infra_failures: List[Dict],
    real_failures: List[Dict],
    unknown_failures: List[Dict],
    evidence: str,
    timestamp: str,
) -> str:
    """Build the PR comment body for a ci-gate waiver stamp."""
    lines = ["<!-- lattice:ci-gate-waiver pr-" + pr_n + " -->"]
    lines.append("")
    lines.append(f"## CI gate — compiled infra-class waiver (PR #{pr_n})")
    lines.append("")
    lines.append(
        "Per ADR-007 §5a, infra-only CI failures + local verification evidence "
        "pass with an auto-stamped waiver (compiled corner case, not an exception)."
    )
    lines.append("")
    if infra_failures:
        lines.append("### Infra-class failures (waived)")
        for f in infra_failures:
            lines.append(
                f"- **{f['name']}** — {f['category']} "
                f"(pattern: `{f['pattern']}`) — {f['link']}"
            )
        lines.append("")
    if real_failures:
        lines.append("### Real failures (BLOCK — must fix before merge)")
        for f in real_failures:
            lines.append(
                f"- **{f['name']}** — {f['conclusion']} — {f['link']}"
            )
        lines.append("")
    if unknown_failures:
        lines.append("### Unclassified failures (treated as real — fail-closed)")
        for f in unknown_failures:
            lines.append(
                f"- **{f['name']}** — {f['pattern']} — {f['link']}"
            )
        lines.append("")
    lines.append(f"### Local verification evidence")
    lines.append(f"```\n{evidence}\n```")
    lines.append("")
    lines.append(f"### Waiver trace")
    lines.append(f"`{waiver_trace(pr_n, infra_failures, evidence, timestamp)}`")
    lines.append("")
    lines.append(
        "_authorizer=human-at-merge-time — the local evidence is the authorization_"
    )
    return "\n".join(lines)
