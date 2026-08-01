#!/usr/bin/env python3
"""Deterministic behavioral-eval provider for tests and credential-free CI."""

from __future__ import annotations

import json
import os
from pathlib import Path
import sys


def main() -> int:
    request = json.load(sys.stdin)
    phase = request.get("phase")
    mode = os.environ.get("FAKE_EVAL_MODE", "")
    if mode == f"exit-{phase}":
        print(f"fake provider forced {phase} failure", file=sys.stderr)
        return 7
    if mode == f"malformed-{phase}":
        print("not-json")
        return 0

    scenario_path = os.environ.get("FAKE_EVAL_SCENARIO")
    scenario = json.loads(Path(scenario_path).read_text()) if scenario_path else {}
    key = f"{request.get('skill_name')}/{request.get('case_id')}"
    case_config = scenario.get("cases", {}).get(key, scenario.get("default", {}))
    variant = request.get("variant")

    if phase == "invoke":
        response = {
            "metadata": {"cwd": os.getcwd(), "provider": "fake"},
            "protocol_version": 1,
            "text": case_config.get(
                f"{variant}_text", f"fake response for {key} ({variant})"
            ),
        }
    elif phase == "assert":
        expected = request.get("expectations", [])
        decisions = case_config.get(variant, [True] * len(expected))
        if isinstance(decisions, bool):
            decisions = [decisions] * len(expected)
        if len(decisions) != len(expected):
            print(
                f"scenario decisions for {key}/{variant} must have {len(expected)} items",
                file=sys.stderr,
            )
            return 8
        if any(not isinstance(decision, bool) for decision in decisions):
            print(f"scenario decisions for {key}/{variant} must be booleans", file=sys.stderr)
            return 8
        response = {
            "assertions": [
                {
                    "evidence": f"fake {variant} assertion {index}={str(bool(passed)).lower()}",
                    "index": index,
                    "passed": bool(passed),
                }
                for index, passed in enumerate(decisions)
            ],
            "metadata": {"cwd": os.getcwd(), "provider": "fake"},
            "protocol_version": 1,
        }
    else:
        print(f"unsupported phase: {phase!r}", file=sys.stderr)
        return 9
    print(json.dumps(response, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
