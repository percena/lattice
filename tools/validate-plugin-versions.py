#!/usr/bin/env python3
"""Validate Claude plugin manifests and version-derived cache identities.

The marketplace is the catalog, while each plugin manifest is the packaged
source of truth.  When a path materialized into a plugin cache changes, the
plugin's semantic version must increase relative to the selected base commit.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
from typing import Any


SEMVER_RE = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-((?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)"
    r"(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*))?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)


def git(root: Path, *args: str, check: bool = True) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), *args],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if check and result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(f"git {' '.join(args)} failed: {detail}")
    return result.stdout


def load_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def load_json_at(root: Path, commit: str, path: str) -> dict[str, Any] | None:
    result = subprocess.run(
        ["git", "-C", str(root), "show", f"{commit}:{path}"],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        return None
    value = json.loads(result.stdout)
    if not isinstance(value, dict):
        raise ValueError(f"{path} at {commit} must contain a JSON object")
    return value


def semver_key(value: str) -> tuple[Any, ...]:
    match = SEMVER_RE.fullmatch(value)
    if not match:
        raise ValueError(f"invalid semantic version: {value!r}")
    major, minor, patch = (int(match.group(i)) for i in range(1, 4))
    prerelease = match.group(4)
    if prerelease is None:
        pre_key: tuple[Any, ...] = (1,)
    else:
        parts: list[tuple[int, Any]] = []
        for identifier in prerelease.split("."):
            parts.append((0, int(identifier)) if identifier.isdigit() else (1, identifier))
        pre_key = (0, *parts)
    return major, minor, patch, pre_key


def without_version(value: dict[str, Any] | None) -> dict[str, Any] | None:
    if value is None:
        return None
    result = dict(value)
    result.pop("version", None)
    return result


def marketplace_entries(data: dict[str, Any]) -> dict[str, dict[str, Any]]:
    entries = data.get("plugins")
    if not isinstance(entries, list):
        raise ValueError("marketplace plugins must be an array")
    result: dict[str, dict[str, Any]] = {}
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("name"), str):
            raise ValueError("every marketplace plugin must be an object with a name")
        name = entry["name"]
        if name in result:
            raise ValueError(f"duplicate marketplace plugin: {name}")
        result[name] = entry
    return result


def normalize_target(link_path: str, target: str) -> str | None:
    combined = PurePosixPath(link_path).parent / target
    parts: list[str] = []
    for part in combined.parts:
        if part in ("", "."):
            continue
        if part == "..":
            if not parts:
                return None
            parts.pop()
        else:
            parts.append(part)
    return "/".join(parts)


def bundled_roots_at(root: Path, commit: str, plugin: str) -> set[str]:
    prefix = f"plugins/{plugin}/skills"
    # -z: NUL-separated records with literal (non-C-quoted) paths, so special
    # characters in symlink names cannot break parsing.
    output = git(root, "ls-tree", "-r", "-z", commit, "--", prefix)
    roots: set[str] = set()
    for line in output.split("\0"):
        if not line:
            continue
        metadata, path = line.split("\t", 1)
        mode = metadata.split()[0]
        if mode != "120000":
            continue
        target = git(root, "show", f"{commit}:{path}").strip()
        normalized = normalize_target(path, target)
        if normalized:
            roots.add(normalized.rstrip("/"))
    return roots


def bundled_roots_in_worktree(root: Path, plugin: str) -> set[str]:
    skills_dir = root / "plugins" / plugin / "skills"
    roots: set[str] = set()
    if not skills_dir.is_dir():
        return roots
    for link in skills_dir.iterdir():
        if not link.is_symlink():
            continue
        try:
            target = os.readlink(link)
        except OSError as exc:
            raise ValueError(f"{plugin}: cannot read skill symlink {link.name}: {exc}") from exc
        try:
            roots.add(link.resolve(strict=False).relative_to(root).as_posix().rstrip("/"))
        except ValueError as exc:
            # external symlinks are identity failures, not omit.
            raise ValueError(
                f"{plugin}: skill symlink escapes repository root: {link.name} -> {target}"
            ) from exc
    return roots


def path_under(path: str, root: str) -> bool:
    return path == root or path.startswith(f"{root}/")


def _git_bytes(root: Path, *args: str) -> bytes:
    """Run git and return NUL-separated bytes; raise RuntimeError on failure.

    NUL-separated porcelain paths can contain non-UTF-8 bytes, so this stays in
    bytes (unlike the `git()` helper) and honors the module's validation-error
    contract (a failing git read becomes a clean error entry, never a traceback)
    rather than raising `subprocess.CalledProcessError`.
    """
    result = subprocess.run(
        ["git", "-C", str(root), *args],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(f"git {' '.join(args)} failed: {detail.decode('utf-8', 'replace')}")
    return result.stdout


def changed_paths(root: Path, base_oid: str, head_oid: str) -> list[str]:
    merge_base = git(root, "merge-base", base_oid, head_oid).strip()
    committed = _git_bytes(root, "diff", "--name-only", "-z", merge_base, head_oid)
    worktree = _git_bytes(root, "diff", "--name-only", "-z", "HEAD")
    untracked = _git_bytes(root, "ls-files", "--others", "--exclude-standard", "-z")
    return sorted(
        {
            path.decode("utf-8")
            for raw in (committed, worktree, untracked)
            for path in raw.split(b"\0")
            if path
        }
    )


ZERO_OID_RE = re.compile(r"^0{7,40}$")


def is_zero_oid(value: str) -> bool:
    return bool(ZERO_OID_RE.fullmatch(value.strip()))


def rev_exists(root: Path, ref: str) -> bool:
    result = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "--verify", f"{ref}^{{commit}}"],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return result.returncode == 0


def discover_base_ref(root: Path) -> str | None:
    """Pick a local comparison base when the caller did not supply one.

    Preference order matches this repository's delivery default (`main`) then
    common GitHub defaults. Only refs that already resolve locally are used so
    the command never invents a remote fetch.
    """
    # This repository delivers from main. Prefer its explicit tracking ref over
    # origin/HEAD, which can remain stale after the GitHub default branch moves.
    candidates: list[str] = ["origin/main"]
    origin_head = git(root, "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD", check=False).strip()
    if origin_head.startswith("refs/remotes/"):
        candidates.append(origin_head.removeprefix("refs/remotes/"))
    candidates.extend(
        [
            "origin/master",
            "main",
            "master",
        ]
    )
    seen: set[str] = set()
    for candidate in candidates:
        if not candidate or candidate in seen:
            continue
        seen.add(candidate)
        if rev_exists(root, candidate):
            return candidate
    return None


def resolve_base_ref(root: Path, explicit: str | None) -> tuple[str | None, list[str]]:
    """Return (base_ref, errors). A resolvable base is required for change detection."""
    errors: list[str] = []
    raw = explicit if explicit is not None else os.environ.get("PLUGIN_VERSION_BASE_REF")
    if raw is not None:
        raw = raw.strip()
    if raw:
        if is_zero_oid(raw):
            errors.append(
                "base ref is the zero OID (common on first-push / orphan events); "
                "pass an explicit reachable --base-ref such as origin/main"
            )
            return None, errors
        return raw, errors

    discovered = discover_base_ref(root)
    if discovered:
        return discovered, errors
    errors.append(
        "no comparison base: pass --base-ref (or PLUGIN_VERSION_BASE_REF), "
        "or ensure origin/main|master is available locally"
    )
    return None, errors


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-ref", help="commit/ref used to detect bundled changes")
    parser.add_argument(
        "--initial-publish",
        action="store_true",
        help="validate current metadata/cache identities without a historical release baseline",
    )
    parser.add_argument("--repo-root", type=Path, help="repository root (defaults to git root)")
    parser.add_argument("--json", action="store_true", help="emit deterministic JSON")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.initial_publish and args.base_ref:
        print("validate-plugin-versions: ERROR: --initial-publish cannot be combined with --base-ref", file=sys.stderr)
        return 2
    root = args.repo_root
    if root is None:
        root = Path(git(Path.cwd(), "rev-parse", "--show-toplevel").strip())
    root = root.resolve()

    errors: list[str] = []
    try:
        current_marketplace = load_json(root / ".claude-plugin/marketplace.json")
        current_entries = marketplace_entries(current_marketplace)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"validate-plugin-versions: ERROR: {exc}", file=sys.stderr)
        return 1

    if args.initial_publish:
        base_ref, base_ref_errors = None, []
    else:
        base_ref, base_ref_errors = resolve_base_ref(root, args.base_ref)
    errors.extend(base_ref_errors)
    base_oid: str | None = None
    head_oid = git(root, "rev-parse", "HEAD^{commit}").strip()
    base_marketplace: dict[str, Any] | None = None
    base_entries: dict[str, dict[str, Any]] = {}
    paths: list[str] = []
    if base_ref:
        try:
            base_oid = git(root, "rev-parse", f"{base_ref}^{{commit}}").strip()
            base_marketplace = load_json_at(root, base_oid, ".claude-plugin/marketplace.json")
            if base_marketplace is None:
                errors.append(f"base {base_ref} has no .claude-plugin/marketplace.json")
            else:
                base_entries = marketplace_entries(base_marketplace)
                paths = changed_paths(root, base_oid, head_oid)
        except (RuntimeError, ValueError, json.JSONDecodeError) as exc:
            errors.append(str(exc))

    marketplace_name = current_marketplace.get("name")
    if not isinstance(marketplace_name, str) or not marketplace_name:
        errors.append("marketplace name must be a non-empty string")
        marketplace_name = "<invalid>"

    plugin_results: list[dict[str, Any]] = []
    manifest_plugins = {
        path.parent.parent.name
        for path in (root / "plugins").glob("*/.claude-plugin/plugin.json")
    }
    for name in sorted(manifest_plugins - set(current_entries)):
        errors.append(f"{name}: plugin manifest exists without a marketplace entry")

    for name in sorted(current_entries):
        entry = current_entries[name]
        source = entry.get("source")
        expected_source = f"./plugins/{name}"
        if source != expected_source:
            errors.append(f"{name}: marketplace source must be {expected_source!r}, got {source!r}")
        manifest_path = f"plugins/{name}/.claude-plugin/plugin.json"
        try:
            manifest = load_json(root / manifest_path)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            errors.append(f"{name}: cannot load manifest: {exc}")
            continue

        manifest_name = manifest.get("name")
        manifest_version = manifest.get("version")
        entry_version = entry.get("version")
        if manifest_name != name:
            errors.append(f"{name}: manifest name is {manifest_name!r}")
        if not isinstance(manifest_version, str) or not SEMVER_RE.fullmatch(manifest_version):
            errors.append(f"{name}: manifest version is not SemVer: {manifest_version!r}")
        if entry_version != manifest_version:
            errors.append(
                f"{name}: marketplace version {entry_version!r} does not match manifest {manifest_version!r}"
            )
        if not isinstance(entry_version, str) or not SEMVER_RE.fullmatch(entry_version):
            errors.append(f"{name}: marketplace version is not SemVer: {entry_version!r}")

        previous_entry = base_entries.get(name) if base_oid else None
        previous_manifest: dict[str, Any] | None = None
        roots: set[str] = set()
        if base_oid:
            # Base-commit reads must become clean errors entries, never
            # tracebacks: invalid JSON at the base or a failing git show is a
            # validation failure, not a crash.
            try:
                previous_manifest = load_json_at(root, base_oid, manifest_path)
                roots |= bundled_roots_at(root, base_oid, name)
                roots |= bundled_roots_at(root, head_oid, name)
            except (RuntimeError, ValueError, json.JSONDecodeError) as exc:
                errors.append(f"{name}: cannot inspect base state: {exc}")
                continue
            try:
                roots |= bundled_roots_in_worktree(root, name)
            except ValueError as exc:
                errors.append(str(exc))
        previous_version = previous_manifest.get("version") if previous_manifest else None

        impact_paths = [
            path
            for path in paths
            if path_under(path, f"plugins/{name}")
            or any(path_under(path, bundle_root) for bundle_root in roots)
        ]
        metadata_changed = (
            base_oid is not None
            and (
                without_version(previous_entry) != without_version(entry)
                or without_version(previous_manifest) != without_version(manifest)
            )
        )
        bundle_changed = bool(impact_paths or metadata_changed)

        if base_oid and previous_manifest is None:
            bundle_changed = True
        if base_oid and bundle_changed and manifest_version == previous_version:
            errors.append(
                f"{name}: bundled content changed without a version increment ({manifest_version})"
            )
        if (
            base_oid
            and isinstance(previous_version, str)
            and isinstance(manifest_version, str)
            and manifest_version != previous_version
        ):
            try:
                if semver_key(manifest_version) <= semver_key(previous_version):
                    errors.append(
                        f"{name}: version must increase, got {previous_version} -> {manifest_version}"
                    )
            except ValueError as exc:
                errors.append(f"{name}: {exc}")

        version_for_identity = manifest_version if isinstance(manifest_version, str) else "<invalid>"
        plugin_results.append(
            {
                "bundle_changed": bundle_changed,
                "cache_identity": f"{marketplace_name}/{name}@{version_for_identity}",
                "cache_path": f"~/.claude/plugins/cache/{marketplace_name}/{name}/{version_for_identity}",
                "changed_paths": impact_paths,
                "name": name,
                "previous_version": previous_version,
                "version": manifest_version,
            }
        )

    missing_current = sorted(set(base_entries) - set(current_entries))
    for name in missing_current:
        # Fail closed on marketplace drops: a plugin disappearing from the
        # marketplace without a replacement entry is never intentional.
        base_meta = base_entries.get(name) or {}
        source = base_meta.get("source") if isinstance(base_meta, dict) else None
        if not isinstance(source, str) or not source:
            source = f"./plugins/{name}"
        rel = PurePosixPath(source)
        # normalize ./plugins/foo → plugins/foo
        parts = rel.parts
        if parts and parts[0] == ".":
            rel = PurePosixPath(*parts[1:]) if len(parts) > 1 else PurePosixPath()
        still_on_disk = (root / Path(*rel.parts)).exists() if rel.parts else True
        if still_on_disk:
            errors.append(
                f"{name}: plugin was removed from the marketplace without a replacement entry "
                f"(source path still present: {source})"
            )
        else:
            errors.append(
                f"{name}: plugin was removed from the marketplace and disk without a replacement entry"
            )

    result = {
        "base_oid": base_oid,
        "base_ref": base_ref,
        "errors": sorted(set(errors)),
        "head_oid": head_oid,
        "initial_publish": args.initial_publish,
        "marketplace": marketplace_name,
        "ok": not errors,
        "plugins": plugin_results,
    }
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        for plugin in plugin_results:
            state = "changed" if plugin["bundle_changed"] else "unchanged"
            print(
                f"{plugin['name']}: {plugin['version']} ({state}) "
                f"cache={plugin['cache_path']}"
            )
        for error in result["errors"]:
            print(f"ERROR: {error}", file=sys.stderr)
        print("validate-plugin-versions: OK" if not errors else "validate-plugin-versions: FAILED")
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
