#!/usr/bin/env python3
"""check-bats-assertions — flag bats assertion forms that bash set -e never
fires on, so they cannot gate a test (tkt-167):

  1. bare `[[ ... ]]` assertion statements (compound commands are exempt from
     errexit; effective only as a test body's LAST command — ban everywhere)
  2. bare `! <cmd>` assertion lines (negation exemption; the `!` form only
     gates in terminal position — ban everywhere)
  3. `grep -q` inside a `[ -z "$( ... )" ]` wrapper (the -q suppresses output,
     so the substitution is always empty and the assertion is always true)

Usage: check-bats-assertions.py [bats-file ...]   (default: all under repo)
Exit 0 when clean, 1 with findings.
"""
import re
import subprocess
import sys

BARE_BRACKET = re.compile(r"^\s*\[\[\s+.+?\s*\]\]\s*(?:#.*)?$")
BARE_NOT = re.compile(r"^\s*!\s+\S")
Q_IN_SUBST = re.compile(r"\[\s*-z\s+\"\$\([^)]*\|\s*grep\s+-q")
CONTROL_PREFIXES = ("if ", "while ", "until ", "elif ")


def findings(path: str) -> list[str]:
    out = []
    with open(path, encoding="utf-8") as f:
        for i, line in enumerate(f, 1):
            if BARE_BRACKET.match(line):
                out.append(f"{path}:{i}: bare [[ ]] assertion is exempt from set -e")
            elif BARE_NOT.match(line):
                rest = line.lstrip()[2:].lstrip()
                if not rest.startswith(CONTROL_PREFIXES):
                    out.append(f"{path}:{i}: bare `! cmd` assertion is exempt from set -e")
            if Q_IN_SUBST.search(line):
                out.append(f"{path}:{i}: grep -q inside a [ -z \"$(…)\" ] wrapper is always-true")
    return out


def main() -> int:
    paths = sys.argv[1:]
    if not paths:
        root = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        paths = subprocess.run(
            ["git", "-C", root, "ls-files", "*.bats"],
            check=True, capture_output=True, text=True,
        ).stdout.split()
        paths = [f"{root}/{p}" for p in paths]
    all_findings = []
    for p in paths:
        all_findings.extend(findings(p))
    if all_findings:
        print("check-bats-assertions: FAILED (ineffective assertion forms found)")
        for f in all_findings:
            print(f"  {f}")
        return 1
    print(f"check-bats-assertions: OK ({len(paths)} bats files clean)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
