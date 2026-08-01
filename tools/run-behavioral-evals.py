#!/usr/bin/env python3
"""Execute isolated skill behavioral evals through a pluggable provider."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import re
import shlex
import signal
import subprocess
import sys
import time
from typing import Any
import uuid


PROTOCOL_VERSION = 1
SCHEMA_VERSION = 1
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")


class HarnessError(RuntimeError):
    """Provider, protocol, or corpus failure."""


@dataclass(frozen=True)
class EvalCase:
    skill_name: str
    case_id: str
    prompt: str
    expectations: tuple[str, ...]
    source: Path

    @property
    def key(self) -> str:
        return f"{self.skill_name}/{self.case_id}"


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def print_progress(message: str, *, json_mode: bool) -> None:
    print(message, file=sys.stderr if json_mode else sys.stdout)


def discover_cases(root: Path) -> tuple[list[EvalCase], list[str]]:
    cases: list[EvalCase] = []
    errors: list[str] = []
    seen_keys: set[str] = set()
    files = sorted((root / "skills").glob("*/evals/evals.json"))
    if not files:
        errors.append("no skills/*/evals/evals.json files found")
        return cases, errors

    for path in files:
        relative = path.relative_to(root).as_posix()
        try:
            data = load_json(path)
        except (OSError, json.JSONDecodeError) as exc:
            errors.append(f"{relative}: invalid JSON: {exc}")
            continue
        if not isinstance(data, dict):
            errors.append(f"{relative}: root must be an object")
            continue
        if data.get("schema_version") != SCHEMA_VERSION:
            errors.append(f"{relative}: schema_version must be {SCHEMA_VERSION}")
        skill_name = data.get("skill_name")
        expected_name = path.parents[1].name
        if skill_name != expected_name:
            errors.append(
                f"{relative}: skill_name must match directory ({expected_name!r}), got {skill_name!r}"
            )
            continue
        raw_cases = data.get("cases")
        if not isinstance(raw_cases, list) or not raw_cases:
            errors.append(f"{relative}: cases must be a non-empty array")
            continue
        for index, raw in enumerate(raw_cases):
            label = f"{relative}:cases[{index}]"
            if not isinstance(raw, dict):
                errors.append(f"{label}: case must be an object")
                continue
            case_id = raw.get("id")
            if not isinstance(case_id, str) or not ID_RE.fullmatch(case_id):
                errors.append(f"{label}: id must match {ID_RE.pattern}")
                continue
            key = f"{skill_name}/{case_id}"
            if key in seen_keys:
                errors.append(f"{label}: duplicate case id {key}")
                continue
            seen_keys.add(key)
            if raw.get("type") != "behavioral":
                errors.append(f"{label}: type must be 'behavioral'")
            prompt = raw.get("prompt")
            if not isinstance(prompt, str) or not prompt.strip():
                errors.append(f"{label}: prompt must be a non-empty string")
                continue
            expectations = raw.get("expect")
            if (
                not isinstance(expectations, list)
                or not expectations
                or any(not isinstance(item, str) or not item.strip() for item in expectations)
            ):
                errors.append(f"{label}: expect must be a non-empty string array")
                continue
            cases.append(
                EvalCase(
                    skill_name=skill_name,
                    case_id=case_id,
                    prompt=prompt,
                    expectations=tuple(expectations),
                    source=path,
                )
            )
    return cases, errors


def resolve_provider_command(raw: str, cwd: Path) -> list[str]:
    command = shlex.split(raw)
    if not command:
        raise HarnessError("provider command is empty")
    resolved: list[str] = []
    for token in command:
        candidate = (cwd / token).resolve()
        if ("/" in token or token.startswith(".")) and candidate.exists():
            resolved.append(str(candidate))
        else:
            resolved.append(token)
    return resolved


def _stream_text(stream: Any) -> str:
    # TimeoutExpired captures raw bytes even under text=True; decode so the
    # artifact stays JSON-serializable instead of crashing the harness.
    if isinstance(stream, bytes):
        return stream.decode("utf-8", errors="replace")
    return stream or ""


def call_provider(
    command: list[str],
    request: dict[str, Any],
    sandbox: Path,
    artifact: Path,
    timeout: float,
) -> dict[str, Any]:
    sandbox.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    try:
        # start_new_session puts the provider in its own process group so a
        # timeout can kill the whole group — provider grandchildren must not
        # outlive the harness deadline.
        process = subprocess.Popen(
            command,
            cwd=sandbox,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
    except OSError as exc:
        # Missing/unexecutable provider binary is a harness error (exit 2),
        # not a skill-quality failure; keep the forensic artifact.
        record = {
            "duration_ms": round((time.monotonic() - started) * 1000),
            "error": f"provider command failed to start: {exc}",
            "request": request,
            "stderr": "",
            "stdout": "",
        }
        write_json(artifact, record)
        raise HarnessError(record["error"]) from exc
    with process:
        try:
            stdout_text, stderr_text = process.communicate(
                json.dumps(request, sort_keys=True) + "\n", timeout=timeout
            )
        except subprocess.TimeoutExpired as exc:
            try:
                os.killpg(os.getpgid(process.pid), signal.SIGKILL)
            except OSError:
                process.kill()
            process.wait()
            record = {
                "duration_ms": round((time.monotonic() - started) * 1000),
                "error": f"provider timed out after {timeout}s",
                "request": request,
                "stderr": _stream_text(exc.stderr),
                "stdout": _stream_text(exc.stdout),
            }
            write_json(artifact, record)
            raise HarnessError(record["error"]) from exc

    record: dict[str, Any] = {
        "duration_ms": round((time.monotonic() - started) * 1000),
        "request": request,
        "returncode": process.returncode,
        "stderr": stderr_text,
        "stdout": stdout_text,
    }
    if process.returncode != 0:
        write_json(artifact, record)
        raise HarnessError(
            f"provider exited {process.returncode}: {stderr_text.strip() or stdout_text.strip()}"
        )
    try:
        response = json.loads(stdout_text)
    except json.JSONDecodeError as exc:
        write_json(artifact, record)
        raise HarnessError(f"provider returned invalid JSON: {exc}") from exc
    if not isinstance(response, dict):
        write_json(artifact, record)
        raise HarnessError("provider response must be a JSON object")
    if response.get("protocol_version") != PROTOCOL_VERSION:
        write_json(artifact, record)
        raise HarnessError(
            f"provider protocol_version must be {PROTOCOL_VERSION}, got {response.get('protocol_version')!r}"
        )
    record["response"] = response
    write_json(artifact, record)
    return response


def validate_assertions(
    response: dict[str, Any], expectations: tuple[str, ...]
) -> list[dict[str, Any]]:
    raw = response.get("assertions")
    if not isinstance(raw, list) or len(raw) != len(expectations):
        raise HarnessError(
            f"assert provider must return {len(expectations)} assertions, got "
            f"{len(raw) if isinstance(raw, list) else 'non-array'}"
        )
    by_index: dict[int, dict[str, Any]] = {}
    for item in raw:
        if not isinstance(item, dict):
            raise HarnessError("every assertion must be an object")
        index = item.get("index")
        passed = item.get("passed")
        evidence = item.get("evidence")
        if not isinstance(index, int) or index < 0 or index >= len(expectations):
            raise HarnessError(f"invalid assertion index: {index!r}")
        if index in by_index:
            raise HarnessError(f"duplicate assertion index: {index}")
        if not isinstance(passed, bool):
            raise HarnessError(f"assertion {index} passed must be boolean")
        if not isinstance(evidence, str) or not evidence.strip():
            raise HarnessError(f"assertion {index} evidence must be non-empty")
        by_index[index] = {
            "evidence": evidence,
            "expectation": expectations[index],
            "index": index,
            "passed": passed,
        }
    if set(by_index) != set(range(len(expectations))):
        raise HarnessError("assertion indices must cover every expectation exactly once")
    return [by_index[index] for index in range(len(expectations))]


def load_skill_text(root: Path, skill_name: str) -> tuple[str, str]:
    path = root / "skills" / skill_name / "SKILL.md"
    if not path.is_file():
        raise HarnessError(f"missing candidate skill: {path}")
    return path.read_text(encoding="utf-8"), path.as_posix()


def load_baseline_text(baseline_root: Path | None, skill_name: str) -> tuple[str | None, str | None]:
    if baseline_root is None:
        return None, None
    candidates = [
        baseline_root / "skills" / skill_name / "SKILL.md",
        baseline_root / skill_name / "SKILL.md",
    ]
    for path in candidates:
        if path.is_file():
            return path.read_text(encoding="utf-8"), path.resolve().as_posix()
    raise HarnessError(
        f"baseline skill {skill_name!r} not found under {baseline_root} "
        "(expected skills/<name>/SKILL.md or <name>/SKILL.md)"
    )


def run_variant(
    *,
    command: list[str],
    case: EvalCase,
    variant: str,
    skill_text: str | None,
    skill_path: str | None,
    case_dir: Path,
    run_id: str,
    timeout: float,
) -> dict[str, Any]:
    variant_dir = case_dir / variant
    invoke_request = {
        "case_id": case.case_id,
        "expectations": list(case.expectations),
        "phase": "invoke",
        "prompt": case.prompt,
        "protocol_version": PROTOCOL_VERSION,
        "run_id": run_id,
        "skill_name": case.skill_name,
        "skill_path": skill_path,
        "skill_text": skill_text,
        "variant": variant,
    }
    invoke_response = call_provider(
        command,
        invoke_request,
        variant_dir / "invoke-sandbox",
        variant_dir / "invoke.json",
        timeout,
    )
    text = invoke_response.get("text")
    if not isinstance(text, str) or not text.strip():
        raise HarnessError("invoke provider response requires non-empty text")

    assert_request = {
        "case_id": case.case_id,
        "expectations": list(case.expectations),
        "phase": "assert",
        "prompt": case.prompt,
        "protocol_version": PROTOCOL_VERSION,
        "response_text": text,
        "run_id": run_id,
        "skill_name": case.skill_name,
        "variant": variant,
    }
    assert_response = call_provider(
        command,
        assert_request,
        variant_dir / "assert-sandbox",
        variant_dir / "assert.json",
        timeout,
    )
    assertions = validate_assertions(assert_response, case.expectations)
    passed = sum(1 for assertion in assertions if assertion["passed"])
    result = {
        "assertions": assertions,
        "passed": passed,
        "response_text": text,
        "score": passed / len(assertions),
        "total": len(assertions),
    }
    write_json(variant_dir / "result.json", result)
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, help="repository root (defaults from this script)")
    parser.add_argument(
        "--provider-command",
        help=(
            "JSON provider command; receives request on stdin. Parsed with "
            "shlex, so paths containing spaces work when quoted, e.g. "
            "\"python3 '/pa th/provider.py'\""
        ),
    )
    parser.add_argument("--baseline-skill-root", type=Path, help="previous skill tree; default is no-skill")
    parser.add_argument("--artifacts-dir", type=Path, help="output directory")
    parser.add_argument("--run-id", help="stable run id (tests); defaults to timestamp + UUID")
    parser.add_argument("--skill", action="append", default=[], help="limit to skill (repeatable)")
    parser.add_argument("--case", action="append", default=[], help="limit to case id or skill/case")
    parser.add_argument("--timeout", type=float, default=120.0, help="provider timeout per phase")
    parser.add_argument("--min-candidate-pass-rate", type=float, default=1.0)
    parser.add_argument("--allow-regression", action="store_true")
    parser.add_argument("--require-improvement", action="store_true")
    parser.add_argument("--validate-only", action="store_true")
    parser.add_argument("--json", action="store_true", help="print summary JSON")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = (args.repo_root or Path(__file__).resolve().parents[1]).resolve()
    cases, corpus_errors = discover_cases(root)
    if corpus_errors:
        for error in corpus_errors:
            print(f"ERROR: {error}", file=sys.stderr)
        print_progress(
            f"behavioral corpus: FAILED ({len(corpus_errors)} error(s))",
            json_mode=args.json,
        )
        return 2

    if args.skill:
        wanted = set(args.skill)
        unknown = wanted - {case.skill_name for case in cases}
        if unknown:
            print(f"ERROR: unknown skill filter(s): {', '.join(sorted(unknown))}", file=sys.stderr)
            return 2
        cases = [case for case in cases if case.skill_name in wanted]
    if args.case:
        wanted_cases = set(args.case)
        cases = [
            case
            for case in cases
            if case.case_id in wanted_cases or case.key in wanted_cases
        ]
        found = {case.case_id for case in cases} | {case.key for case in cases}
        unknown = wanted_cases - found
        if unknown:
            print(f"ERROR: unknown case filter(s): {', '.join(sorted(unknown))}", file=sys.stderr)
            return 2

    print_progress(
        f"behavioral corpus: OK ({len(cases)} selected case(s))",
        json_mode=args.json,
    )
    if args.validate_only:
        if args.json:
            print(
                json.dumps(
                    {
                        "ok": True,
                        "schema_version": SCHEMA_VERSION,
                        "selected_cases": len(cases),
                        "validation_only": True,
                    },
                    indent=2,
                    sort_keys=True,
                )
            )
        return 0
    if not args.provider_command:
        print("ERROR: --provider-command is required unless --validate-only", file=sys.stderr)
        return 2
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        print("ERROR: --timeout must be a finite number greater than 0", file=sys.stderr)
        return 2
    if (
        not math.isfinite(args.min_candidate_pass_rate)
        or not 0.0 <= args.min_candidate_pass_rate <= 1.0
    ):
        print("ERROR: --min-candidate-pass-rate must be between 0 and 1", file=sys.stderr)
        return 2
    if args.allow_regression and args.require_improvement:
        print("ERROR: --allow-regression and --require-improvement are mutually exclusive", file=sys.stderr)
        return 2

    run_id = args.run_id or (
        datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    )
    artifacts_dir = (
        args.artifacts_dir or root / "evals" / "artifacts" / run_id
    ).resolve()
    # Best-effort preflight; the exists/iterdir window is TOCTOU-racy, which is
    # accepted for a single-user CLI harness (any race is operator-vs-self).
    if artifacts_dir.exists():
        if not artifacts_dir.is_dir():
            print(f"ERROR: artifacts path is not a directory: {artifacts_dir}", file=sys.stderr)
            return 2
        if any(artifacts_dir.iterdir()):
            print(f"ERROR: artifacts directory is not empty: {artifacts_dir}", file=sys.stderr)
            return 2
    baseline_root = args.baseline_skill_root.resolve() if args.baseline_skill_root else None
    try:
        command = resolve_provider_command(args.provider_command, Path.cwd())
    except (ValueError, HarnessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    manifest = {
        "artifacts_dir": artifacts_dir.as_posix(),
        "baseline": "previous-skill" if baseline_root else "no-skill",
        "baseline_skill_root": baseline_root.as_posix() if baseline_root else None,
        "case_count": len(cases),
        "min_candidate_pass_rate": args.min_candidate_pass_rate,
        "provider_command": command,
        "protocol_version": PROTOCOL_VERSION,
        "repo_root": root.as_posix(),
        "require_improvement": args.require_improvement,
        "require_non_regression": not args.allow_regression,
        "run_id": run_id,
        "schema_version": SCHEMA_VERSION,
        "selected_cases": [case.key for case in cases],
    }
    write_json(artifacts_dir / "manifest.json", manifest)

    results: list[dict[str, Any]] = []
    harness_errors = 0
    quality_failures = 0
    for case in cases:
        case_dir = artifacts_dir / "cases" / case.skill_name / case.case_id
        try:
            candidate_text, candidate_path = load_skill_text(root, case.skill_name)
            baseline_text, baseline_path = load_baseline_text(baseline_root, case.skill_name)
            candidate = run_variant(
                command=command,
                case=case,
                variant="candidate",
                skill_text=candidate_text,
                skill_path=candidate_path,
                case_dir=case_dir,
                run_id=run_id,
                timeout=args.timeout,
            )
            baseline = run_variant(
                command=command,
                case=case,
                variant="baseline",
                skill_text=baseline_text,
                skill_path=baseline_path,
                case_dir=case_dir,
                run_id=run_id,
                timeout=args.timeout,
            )
            candidate_rate = candidate["score"]
            baseline_rate = baseline["score"]
            threshold_ok = candidate_rate + 1e-12 >= args.min_candidate_pass_rate
            comparison_ok = True
            if args.require_improvement:
                comparison_ok = candidate_rate > baseline_rate + 1e-12
            elif not args.allow_regression:
                comparison_ok = candidate_rate + 1e-12 >= baseline_rate
            passed = threshold_ok and comparison_ok
            if not passed:
                quality_failures += 1
            result = {
                "baseline": baseline,
                "candidate": candidate,
                "case_id": case.case_id,
                "comparison_delta": candidate_rate - baseline_rate,
                "comparison_ok": comparison_ok,
                "key": case.key,
                "passed": passed,
                "skill_name": case.skill_name,
                "threshold_ok": threshold_ok,
            }
        except HarnessError as exc:
            harness_errors += 1
            result = {
                "case_id": case.case_id,
                "error": str(exc),
                "key": case.key,
                "passed": False,
                "skill_name": case.skill_name,
            }
        write_json(case_dir / "result.json", result)
        results.append(result)
        state = "PASS" if result["passed"] else "FAIL"
        print_progress(
            f"{state} {case.key}" + (f": {result['error']}" if "error" in result else ""),
            json_mode=args.json,
        )

    summary = {
        "failed_cases": [result["key"] for result in results if not result["passed"]],
        "harness_errors": harness_errors,
        "ok": harness_errors == 0 and quality_failures == 0,
        "passed_cases": sum(1 for result in results if result["passed"]),
        "quality_failures": quality_failures,
        "results": results,
        "run_id": run_id,
        "total_cases": len(results),
    }
    write_json(artifacts_dir / "summary.json", summary)
    if args.json:
        print(json.dumps(summary, indent=2, sort_keys=True))
    else:
        print(
            f"behavioral evals: passed={summary['passed_cases']}/{summary['total_cases']} "
            f"quality_failures={quality_failures} harness_errors={harness_errors} "
            f"artifacts={artifacts_dir}"
        )
    if harness_errors:
        return 2
    return 1 if quality_failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
