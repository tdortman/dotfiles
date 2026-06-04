"""Environment for Qt/KDE dialogs spawned outside the user's shell."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path
from typing import Callable

# Plasma / KWin processes to copy session env from (theme, color scheme, Qt platform).
_PLASMA_COMM_NAMES = frozenset(
    {
        "plasmashell",
        "kwin_wayland",
        "kwin_x11",
    }
)

_ENV_INHERIT = frozenset(
    {
        "PATH",
        "WAYLAND_DISPLAY",
        "DISPLAY",
        "XDG_RUNTIME_DIR",
        "DBUS_SESSION_BUS_ADDRESS",
        "XDG_CURRENT_DESKTOP",
        "XDG_DATA_DIRS",
        "XDG_CONFIG_DIRS",
        "DESKTOP_SESSION",
        "KDE_FULL_SESSION",
        "KDE_SESSION_VERSION",
        "KDE_APPLICATIONS_AS_SCOPE",
        "QT_QPA_PLATFORM",
        "QT_QPA_PLATFORMTHEME",
        "QT_PLUGIN_PATH",
        "QML2_IMPORT_PATH",
        "QT_STYLE_OVERRIDE",
        "COLORSCHEME",
        "GTK_THEME",
        "GTK2_RC_FILES",
        "XDG_SESSION_TYPE",
        "XDG_SESSION_DESKTOP",
        "LD_LIBRARY_PATH",
    }
)


def _loginctl(tool_path: Callable[[str, str], str | None]) -> str | None:
    return tool_path("AGENT_SANDBOX_LOGINCTL", "loginctl")


def _environ_for_pid(pid: int) -> dict[str, str]:
    raw = Path(f"/proc/{pid}/environ").read_bytes()
    env: dict[str, str] = {}
    for item in raw.split(b"\0"):
        if b"=" not in item:
            continue
        key, value = item.split(b"=", 1)
        try:
            env[key.decode()] = value.decode()
        except UnicodeDecodeError:
            continue
    return env


def inherit_plasma_env(uid: int) -> dict[str, str]:
    """Copy theme-related env from the user's running Plasma shell."""
    for name in sorted(os.listdir("/proc"), key=lambda x: (not x.isdigit(), x)):
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            if os.stat(f"/proc/{pid}").st_uid != uid:
                continue
            comm = Path(f"/proc/{pid}/comm").read_text().strip()
            if comm not in _PLASMA_COMM_NAMES:
                continue
            proc_env = _environ_for_pid(pid)
            return {
                key: proc_env[key]
                for key in _ENV_INHERIT
                if proc_env.get(key)
            }
        except OSError:
            continue
    return {}


def _kde_session_defaults() -> dict[str, str]:
    return {
        "XDG_CURRENT_DESKTOP": "KDE",
        "DESKTOP_SESSION": "plasma",
        "KDE_FULL_SESSION": "true",
        "QT_QPA_PLATFORMTHEME": "kde",
    }


def x11_display_for_uid(uid: int, tool_path: Callable[[str, str], str | None]) -> str | None:
    loginctl = _loginctl(tool_path)
    if not loginctl:
        return None
    try:
        sessions = subprocess.check_output(
            [loginctl, "list-sessions", "--uid", str(uid), "--no-legend"],
            text=True,
            timeout=2.0,
            stderr=subprocess.DEVNULL,
        )
        for line in sessions.splitlines():
            parts = line.split()
            if len(parts) < 2 or "active" not in parts:
                continue
            sid = parts[0]
            display = subprocess.check_output(
                [loginctl, "show-session", sid, "-pDisplay", "--value"],
                text=True,
                timeout=2.0,
                stderr=subprocess.DEVNULL,
            ).strip()
            if not display:
                continue
            if display.isdigit():
                return f":{display}"
            if display.startswith(":") or "." in display:
                return display
            return f":{display}"
    except (OSError, subprocess.SubprocessError):
        pass
    return None


def kde_color_scheme_from_config(home: str | None) -> str | None:
    if not home:
        return None
    path = Path(home) / ".config" / "kdeglobals"
    if not path.is_file():
        return None
    in_general = False
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line == "[General]":
                in_general = True
                continue
            if line.startswith("[") and line.endswith("]"):
                in_general = False
                continue
            if in_general and line.startswith("ColorScheme="):
                return line.split("=", 1)[1].strip()
    except OSError:
        return None
    return None


def graphical_session_env(
    uid: int,
    tool_path: Callable[[str, str], str | None],
    *,
    home: str | None = None,
) -> dict[str, str]:
    """Build Plasma/KDE graphical env (Wayland, D-Bus, theme) for a desktop user."""
    env = _kde_session_defaults()
    env.update(inherit_plasma_env(uid))
    if "COLORSCHEME" not in env:
        scheme = kde_color_scheme_from_config(home)
        if scheme:
            env["COLORSCHEME"] = scheme

    runtime = f"/run/user/{uid}"
    if not os.path.isdir(runtime):
        return env

    env.setdefault("XDG_RUNTIME_DIR", runtime)
    if "WAYLAND_DISPLAY" not in env:
        for name in ("wayland-0", "wayland-1"):
            if os.path.exists(f"{runtime}/{name}"):
                env["WAYLAND_DISPLAY"] = name
                env.setdefault("QT_QPA_PLATFORM", "wayland")
                break
    if "WAYLAND_DISPLAY" not in env and "DISPLAY" not in env:
        display = x11_display_for_uid(uid, tool_path)
        if display:
            env["DISPLAY"] = display
            env.setdefault("QT_QPA_PLATFORM", "xcb")
    env.setdefault("QT_QPA_PLATFORMTHEME", "kde")
    bus = f"{runtime}/bus"
    if os.path.exists(bus):
        env.setdefault("DBUS_SESSION_BUS_ADDRESS", f"unix:path={bus}")
    if "PATH" not in env:
        env["PATH"] = "/run/current-system/sw/bin"
    return env


def _kdialog_in_dir(directory: str) -> str | None:
    candidate = os.path.join(directory, "kdialog")
    if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
        return candidate
    return None


def resolve_kdialog(env: dict[str, str]) -> str | None:
    """Prefer profile kdialog; fall back to AGENT_SANDBOX_KDIALOG from the Nix module."""
    other_dirs: list[str] = []
    for directory in env.get("PATH", "").split(":"):
        if not directory:
            continue
        if "/profiles/per-user/" in directory:
            found = _kdialog_in_dir(directory)
            if found:
                return found
        else:
            other_dirs.append(directory)
    for directory in other_dirs:
        found = _kdialog_in_dir(directory)
        if found:
            return found
    explicit = env.get("AGENT_SANDBOX_KDIALOG") or os.environ.get(
        "AGENT_SANDBOX_KDIALOG"
    )
    if explicit and os.path.isfile(explicit) and os.access(explicit, os.X_OK):
        return explicit
    return shutil.which("kdialog", path=env.get("PATH"))
