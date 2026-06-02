"""Shared helpers for loading runtime modules from the source tree."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

ROOT = Path(__file__).resolve().parent.parent


def _ensure_import_paths() -> None:
    for sub in ("daemon", "proxy", "dns", "cli"):
        path = str(ROOT / sub)
        if path not in sys.path:
            sys.path.insert(0, path)


def load_module(module_name: str, relpath: str) -> ModuleType:
    _ensure_import_paths()
    path = ROOT / relpath
    spec = importlib.util.spec_from_file_location(f"agent_sandbox_{module_name}", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module
