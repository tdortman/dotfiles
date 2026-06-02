"""Shared OMP session paths for policyd and the proxy."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

SESSION_CONTEXT_PATH = Path(
    os.environ.get(
        "AGENT_SANDBOX_SESSION_CONTEXT_PATH",
        "/run/agent-sandbox/session-context.json",
    )
)


def read_session_context() -> dict[str, str | None]:
    try:
        data = json.loads(SESSION_CONTEXT_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"cwd": None, "home": None, "project_root": None}
    if not isinstance(data, dict):
        return {"cwd": None, "home": None, "project_root": None}
    return {
        "cwd": _opt_str(data.get("cwd")),
        "home": _opt_str(data.get("home")),
        "project_root": _opt_str(data.get("project_root")),
    }


def write_session_context(
    *,
    cwd: str | None = None,
    home: str | None = None,
    project_root: str | None = None,
) -> None:
    payload: dict[str, Any] = {
        "cwd": cwd,
        "home": home,
        "project_root": project_root,
    }
    SESSION_CONTEXT_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = SESSION_CONTEXT_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    tmp.replace(SESSION_CONTEXT_PATH)


def clear_session_context() -> None:
    try:
        SESSION_CONTEXT_PATH.unlink()
    except FileNotFoundError:
        pass
    except OSError:
        pass


def _opt_str(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None
