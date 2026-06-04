#!/usr/bin/env python3
"""Long-lived policyd UI client for non-OMP agents (and manual use)."""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

from graphical_env import (
    _kdialog_lock,
    format_elevation_prompt,
    graphical_session_env,
    kdialog_menu_geometry,
    resolve_kdialog,
)

DEFAULT_SOCKET = "/run/agent-sandbox/policy.sock"


def ui_log(message: str) -> None:
    line = f"agent-sandbox-ui: {message}"
    print(line, file=sys.stderr, flush=True)
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        return
    try:
        with open(
            os.path.join(runtime, "agent-sandbox-ui.log"),
            "a",
            encoding="utf-8",
        ) as log_file:
            log_file.write(line + "\n")
    except OSError:
        pass


def _tool_path(env_key: str, binary: str) -> str | None:
    explicit = os.environ.get(env_key)
    if explicit and os.path.isfile(explicit) and os.access(explicit, os.X_OK):
        return explicit
    return shutil.which(binary)

NETWORK_APPROVAL_OPTIONS = [
    "Allow once (this connection only)",
    "Allow for this session",
    "Allow for this project",
    "Allow globally (user config)",
    "Deny once (this connection only)",
    "Deny for this session",
    "Deny for this project",
    "Deny globally (user config)",
]
SUDO_APPROVAL_OPTIONS = [
    "Allow once (this command only)",
    "Allow for this session",
    "Allow for this project",
    "Allow globally (user config)",
    "Deny once (this command only)",
    "Deny for this session",
    "Deny for this project",
    "Deny globally (user config)",
]
SCOPE_BY_LABEL = {
    "Allow once (this connection only)": "once",
    "Allow once (this command only)": "once",
    "Allow for this session": "session",
    "Allow for this project": "project",
    "Allow globally (user config)": "global",
    "Deny once (this connection only)": "once",
    "Deny once (this command only)": "once",
    "Deny for this session": "session",
    "Deny for this project": "project",
    "Deny globally (user config)": "global",
}
DENY_LABELS = frozenset(
    label
    for label in SCOPE_BY_LABEL
    if label.startswith("Deny ")
)


class TtyUnavailable(Exception):
    """No controlling terminal (background / headless UI client)."""


async def policy_rpc(req: dict[str, Any], socket_path: str) -> dict[str, Any]:
    reader, writer = await asyncio.open_unix_connection(socket_path)
    try:
        writer.write((json.dumps(req) + "\n").encode())
        await writer.drain()
        line = await reader.readline()
        return json.loads(line.decode())
    finally:
        writer.close()
        await writer.wait_closed()


def graphical_select(title: str, options: list[str]) -> str | None:
    """Qt/KDE menu via kdialog (used when /dev/tty is unavailable)."""
    env = os.environ.copy()
    try:
        uid = os.getuid()
        if uid > 0:
            env.update(
                graphical_session_env(
                    uid,
                    _tool_path,
                    home=os.environ.get("HOME"),
                )
            )
    except OSError:
        pass
    kdialog = resolve_kdialog(env)
    if not kdialog:
        ui_log("kdialog not found in PATH")
        return None
    ui_log(f"opening kdialog menu via {kdialog}")
    try:
        menu_args: list[str] = [kdialog]
        geometry = kdialog_menu_geometry(len(options))
        if geometry:
            menu_args.extend(["--geometry", geometry])
        menu_args.extend(
            [
                "--title",
                "agent-sandbox",
                "--menu",
                title,
            ]
        )
        for i, label in enumerate(options, start=1):
            menu_args.extend([str(i), label])
        # Piping stdout breaks GUI on Wayland/Qt; write to a temp file instead.
        fd, out_path = tempfile.mkstemp(prefix="agent-sandbox-kdialog-")
        os.close(fd)
        try:
            with open(out_path, "w", encoding="utf-8") as stdout_file:
                with _kdialog_lock:
                    proc = subprocess.run(
                        menu_args,
                        env=env,
                        stdout=stdout_file,
                        stderr=subprocess.PIPE,
                        timeout=600,
                        check=False,
                    )
            if proc.returncode != 0:
                err = (proc.stderr or b"").decode(errors="replace").strip()
                ui_log(f"kdialog failed (exit {proc.returncode}): {err[:300]}")
                return None
            raw = Path(out_path).read_text(encoding="utf-8").strip()
            if not raw:
                return None
            num = int(raw, 10)
            if 1 <= num <= len(options):
                return options[num - 1]
        finally:
            with contextlib.suppress(OSError):
                os.unlink(out_path)
    except (OSError, subprocess.SubprocessError, ValueError) as err:
        ui_log(f"kdialog error: {err}")
    return None


def tty_select(title: str, options: list[str]) -> str | None:
    if not options:
        return None
    try:
        with open("/dev/tty", "r+") as tty:
            lines = "\n".join(f"  {i + 1}) {label}" for i, label in enumerate(options))
            tty.write(
                f"\n\x1b[1m{title}\x1b[0m\n{lines}\n\n"
                f"Choice [1-{len(options)}], Enter=Deny: "
            )
            tty.flush()
            raw = tty.readline().strip()
    except OSError as err:
        raise TtyUnavailable from err
    if not raw:
        return None
    try:
        num = int(raw, 10)
    except ValueError:
        return None
    if num < 1 or num > len(options):
        return None
    return options[num - 1]


def prefer_graphical_prompt() -> bool:
    if os.environ.get("AGENT_SANDBOX_UI_PREFER_GRAPHICAL") == "1":
        return True
    return bool(os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY"))


def pick_option(title: str, options: list[str]) -> str | None:
    if prefer_graphical_prompt():
        choice = graphical_select(title, options)
        if choice is not None:
            return choice
        ui_log("kdialog unavailable; trying /dev/tty")
    try:
        return tty_select(title, options)
    except TtyUnavailable:
        return graphical_select(title, options)


def sandbox_context(
    *,
    cwd: str | None,
    home: str | None,
    project_root: str | None,
    req: dict[str, Any] | None = None,
) -> dict[str, str | None]:
    req = req or {}
    return {
        "cwd": (
            req.get("cwd")
            or cwd
            or os.environ.get("AGENT_SANDBOX_CWD")
            or os.getcwd()
        ),
        "home": req.get("home") or home or os.environ.get("HOME"),
        "project_root": (
            req.get("project_root")
            or project_root
            or os.environ.get("AGENT_SANDBOX_PROJECT_ROOT")
            or None
        ),
    }


class PolicyUiClient:
    def __init__(
        self,
        socket_path: str,
        *,
        cwd: str | None,
        home: str | None,
        project_root: str | None,
    ) -> None:
        self.socket_path = socket_path
        self.cwd = cwd
        self.home = home
        self.project_root = project_root
        self.session_id: str | None = None
        self._prompt_queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue()
        self._prompt_worker: asyncio.Task[None] | None = None

    def _ctx(self, req: dict[str, Any] | None = None) -> dict[str, Any]:
        base = sandbox_context(
            cwd=self.cwd,
            home=self.home,
            project_root=self.project_root,
            req=req,
        )
        out: dict[str, Any] = {"cwd": base["cwd"]}
        if base.get("home"):
            out["home"] = base["home"]
        if base.get("project_root"):
            out["project_root"] = base["project_root"]
        try:
            uid = os.getuid()
            if uid > 0:
                out["uid"] = uid
        except OSError:
            pass
        return out

    async def _deny(self, req: dict[str, Any], scope: str) -> None:
        body: dict[str, Any] = {"op": "deny", "id": req["id"], "scope": scope, **self._ctx(req)}
        if scope == "session" and self.session_id:
            body["session_id"] = self.session_id
        await policy_rpc(body, self.socket_path)

    async def _pick(self, title: str, options: list[str]) -> str | None:
        return await asyncio.to_thread(pick_option, title, options)

    async def _resolve_scoped_choice(
        self, req: dict[str, Any], choice: str | None
    ) -> None:
        if choice is None:
            ui_log("no prompt available; request left pending")
            return
        scope = SCOPE_BY_LABEL.get(choice)
        if choice in DENY_LABELS:
            if scope == "session" and not self.session_id:
                print(
                    "agent-sandbox: session deny unavailable (policy UI not connected).",
                    file=sys.stderr,
                )
                return
            await self._deny(req, scope or "once")
            return
        if scope == "session" and not self.session_id:
            print(
                "agent-sandbox: session approval unavailable (policy UI not connected).",
                file=sys.stderr,
            )
            return
        body: dict[str, Any] = {
            "op": "approve",
            "id": req["id"],
            "scope": scope,
            **self._ctx(req),
        }
        if self.session_id:
            body["session_id"] = self.session_id
        resp = await policy_rpc(body, self.socket_path)
        if not resp.get("ok"):
            print(
                f"agent-sandbox: approval failed ({resp.get('error', 'unknown')}).",
                file=sys.stderr,
            )
        elif scope == "project" and resp.get("path"):
            print(f"Project policy saved to {resp['path']}.", file=sys.stderr)

    async def _handle_network(self, req: dict[str, Any]) -> None:
        host = req.get("host", "")
        port = req.get("port", 0)
        url = req.get("url") or f"{req.get('scheme', 'https')}://{host}:{port}"
        choice = await self._pick(
            f"agent-sandbox: allow {url}?",
            list(NETWORK_APPROVAL_OPTIONS),
        )
        await self._resolve_scoped_choice(req, choice)

    def _graphical_env(self) -> dict[str, str]:
        env = os.environ.copy()
        try:
            uid = os.getuid()
            if uid > 0:
                env.update(
                    graphical_session_env(
                        uid,
                        _tool_path,
                        home=os.environ.get("HOME"),
                    )
                )
        except OSError:
            pass
        return env

    async def _handle_elevation(self, req: dict[str, Any]) -> None:
        argv = req.get("argv") or []
        cwd = str(req.get("cwd") or self.cwd or "?")
        title, _message = format_elevation_prompt(argv, cwd)
        choice = await self._pick(title, list(SUDO_APPROVAL_OPTIONS))
        await self._resolve_scoped_choice(req, choice)

    async def _prompt_worker_loop(self) -> None:
        while True:
            msg = await self._prompt_queue.get()
            try:
                if msg.get("type") == "network_request":
                    await self._handle_network(msg)
                elif msg.get("type") == "elevation_request":
                    await self._handle_elevation(msg)
            except Exception as exc:
                print(f"agent-sandbox-ui: prompt error: {exc}", file=sys.stderr)

    def _enqueue(self, msg: dict[str, Any]) -> None:
        self._prompt_queue.put_nowait(msg)

    async def run(self) -> None:
        self._prompt_worker = asyncio.create_task(self._prompt_worker_loop())
        while True:
            try:
                await self._session()
            except Exception as exc:
                ui_log(f"disconnected ({exc}); retrying…")
            await asyncio.sleep(2)

    async def _session(self) -> None:
        reader, writer = await asyncio.open_unix_connection(self.socket_path)
        try:
            writer.write(
                (
                    json.dumps(
                        {"op": "register_ui", "ui_client": "standalone", **self._ctx()}
                    )
                    + "\n"
                ).encode()
            )
            await writer.drain()
            self.session_id = None
            while self.session_id is None:
                line = await reader.readline()
                if not line:
                    raise RuntimeError("policyd closed before register_ui response")
                try:
                    msg = json.loads(line.decode())
                except json.JSONDecodeError:
                    continue
                if msg.get("ok") and isinstance(msg.get("session_id"), str):
                    self.session_id = msg["session_id"]
                    ui_log("connected to policyd")
                    break
                if msg.get("type") in ("network_request", "elevation_request"):
                    self._enqueue(msg)
                    continue
                err = str(msg.get("error") or "register_ui failed")
                if "OMP policy UI is active" in err:
                    ui_log("OMP extension owns prompts; exiting standalone UI")
                    raise SystemExit(0)
                raise RuntimeError(err)

            while True:
                line = await reader.readline()
                if not line:
                    break
                try:
                    msg = json.loads(line.decode())
                except json.JSONDecodeError:
                    continue
                if msg.get("type") in ("network_request", "elevation_request"):
                    self._enqueue(msg)
        finally:
            self.session_id = None
            try:
                writer.write((json.dumps({"op": "unregister_ui"}) + "\n").encode())
                await writer.drain()
            except OSError:
                pass
            with contextlib.suppress(OSError, BrokenPipeError, ConnectionResetError):
                writer.close()
                await writer.wait_closed()


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Register as agent-sandbox policyd UI (blocking /dev/tty prompts)",
    )
    p.add_argument(
        "--socket",
        default=os.environ.get("AGENT_SANDBOX_POLICY_SOCKET", DEFAULT_SOCKET),
    )
    p.add_argument("--cwd", default=None)
    p.add_argument("--home", default=None)
    p.add_argument("--project-root", default=None)
    args = p.parse_args(argv)

    client = PolicyUiClient(
        args.socket,
        cwd=args.cwd,
        home=args.home,
        project_root=args.project_root,
    )
    try:
        asyncio.run(client.run())
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
