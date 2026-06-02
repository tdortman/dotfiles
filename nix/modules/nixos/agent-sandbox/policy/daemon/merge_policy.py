#!/usr/bin/env python3
"""Merge agent-sandbox policy layers (later layers win for duplicate host:port)."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

# Paths where a cwd does not identify a durable project (omp ! runner, nix-shell, etc.).
_EPHEMERAL_MARKERS = (
    "omp-python-runner",
    "nix-build-",
    "/tmp/tmp",  # Python tempfile.TemporaryDirectory
)


def _empty() -> dict[str, Any]:
    return {
        "version": 1,
        "allow": [],
        "deny": [],
    }


def load_policy(path: Path | None) -> dict[str, Any]:
    if path is None:
        return _empty()
    read_path = resolve_policy_write_path(path)
    if not read_path.is_file():
        return _empty()
    data = json.loads(read_path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"{read_path}: policy root must be an object")
    data.setdefault("version", 1)
    data.setdefault("allow", [])
    data.setdefault("deny", [])
    return data


def resolve_policy_write_path(path: Path) -> Path:
    """Follow symlinks so atomic writes update the target without replacing the link."""
    if path.is_symlink():
        return path.resolve()
    return path


def atomic_write_policy(path: Path, data: dict[str, Any]) -> None:
    """Atomically write policy JSON, preserving symlinks (e.g. chezmoi-managed paths)."""
    target = resolve_policy_write_path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(f"{target.name}.tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    tmp.replace(target)


def rule_key(rule: dict[str, Any]) -> tuple[str, int]:
    host = str(rule.get("host", "")).lower()
    port = int(rule["port"])
    return host, port


def merge_layers(*layers: dict[str, Any]) -> dict[str, Any]:
    allow: dict[tuple[str, int], dict[str, Any]] = {}
    deny: dict[tuple[str, int], dict[str, Any]] = {}

    for layer in layers:
        for rule in layer.get("deny", []):
            if isinstance(rule, dict) and "host" in rule and "port" in rule:
                key = rule_key(rule)
                allow.pop(key, None)
                deny[key] = rule
        for rule in layer.get("allow", []):
            if isinstance(rule, dict) and "host" in rule and "port" in rule:
                key = rule_key(rule)
                deny.pop(key, None)
                allow[key] = rule

    return {
        "version": 1,
        "allow": sorted(allow.values(), key=lambda r: (r["host"], r["port"])),
        "deny": sorted(deny.values(), key=lambda r: (r["host"], r["port"])),
    }


def is_ephemeral_cwd(path: Path) -> bool:
    """True when cwd is a short-lived runner dir (omp !, nix-shell build, etc.)."""
    s = str(path.resolve())
    return any(marker in s for marker in _EPHEMERAL_MARKERS)


def is_valid_project_root(path: Path) -> bool:
    """Reject / and other paths that are not a real project checkout."""
    root = path.resolve()
    return root != Path("/") and root.name != ""


def infer_home_from_paths(*paths: str | Path | None) -> str | None:
    """Derive /home/<user> from project_root or cwd when AGENT_SANDBOX_HOME is missing."""
    for path_str in paths:
        if not path_str:
            continue
        try:
            parts = Path(path_str).resolve().parts
        except OSError:
            continue
        for idx, part in enumerate(parts[:-1]):
            if part != "home":
                continue
            user = parts[idx + 1]
            if not user:
                continue
            candidate = Path(*parts[: idx + 2])
            if candidate.is_dir():
                return str(candidate)
    return None


def discover_project_policy(start: Path) -> Path | None:
    """Return existing project policy file by walking parents of start (not past /)."""
    cur = start.resolve()
    if not is_valid_project_root(cur):
        return None
    for parent in [cur, *cur.parents]:
        if parent == Path("/"):
            break
        candidate = parent / ".agent-sandbox" / "policy.json"
        if candidate.is_file():
            return candidate
        if parent == parent.parent:
            break
    return None


def project_policy_paths(
    *,
    home: str | Path | None = None,
    cwd: str | Path | None = None,
    project_root: str | Path | None = None,
) -> list[Path]:
    """Return project policy files to merge, most specific first."""
    paths: list[Path] = []
    seen: set[Path] = set()

    def add(path: Path | None) -> None:
        if path is None or not path.is_file():
            return
        resolved = path.resolve()
        if resolved in seen:
            return
        seen.add(resolved)
        paths.append(resolved)

    if project_root:
        try:
            add(resolve_project_policy_path(project_root=project_root))
        except ValueError:
            pass
    if cwd:
        cwd_path = Path(cwd).resolve()
        if is_valid_project_root(cwd_path) and not is_ephemeral_cwd(cwd_path):
            add(discover_project_policy(cwd_path))
    if home:
        home_path = Path(home).resolve()
        add(home_path / ".agent-sandbox" / "policy.json")
        for candidate in sorted(home_path.glob("*/.agent-sandbox/policy.json")):
            add(candidate)
    return paths


def resolve_project_policy_path(
    *,
    cwd: str | Path | None = None,
    project_root: str | Path | None = None,
) -> Path:
    """
    Path to <project>/.agent-sandbox/policy.json (file may not exist yet).

    Prefer AGENT_SANDBOX_PROJECT_ROOT (git root at agent launch). Fall back to cwd
    only when it is not an ephemeral runner directory (never walk from /tmp runners).
    """
    if project_root:
        root = Path(project_root).resolve()
        if not is_valid_project_root(root):
            raise ValueError(
                f"invalid project_root ({root}); set AGENT_SANDBOX_PROJECT_ROOT to the git root"
            )
        return root / ".agent-sandbox" / "policy.json"

    if cwd:
        cwd_path = Path(cwd).resolve()
        if not is_valid_project_root(cwd_path):
            raise ValueError(
                f"cannot resolve project policy from cwd ({cwd_path}); "
                "set AGENT_SANDBOX_PROJECT_ROOT"
            )
        if is_ephemeral_cwd(cwd_path):
            raise ValueError(
                "cannot resolve project policy path from ephemeral cwd "
                f"({cwd_path}); set AGENT_SANDBOX_PROJECT_ROOT"
            )
        existing = discover_project_policy(cwd_path)
        if existing:
            return existing
        return cwd_path / ".agent-sandbox" / "policy.json"

    raise ValueError(
        "cannot resolve project policy path "
        "(set AGENT_SANDBOX_PROJECT_ROOT or run the agent from a git checkout)"
    )


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: merge_policy.py <layer.json> [layer.json ...]", file=sys.stderr)
        return 2

    layers = [load_policy(Path(p)) for p in argv[1:]]
    merged = merge_layers(*layers)
    json.dump(merged, sys.stdout, indent=2, sort_keys=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
