#!/usr/bin/env python3
"""Agent sandbox policy daemon."""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import json
import os
import pwd
import shutil
import subprocess
import sys
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from graphical_env import graphical_session_env
from hosts import allow_keys, is_ipv4_literal, normalize_host, policy_host_for_connect
from merge_policy import (
    atomic_write_policy,
    infer_home_from_paths,
    load_policy,
    merge_layers,
    project_policy_paths,
    resolve_project_policy_path,
    rule_key,
)
from proc_context import context_from_pid, home_from_uid
from session_context import read_session_context, write_session_context


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def _tool_path(env_key: str, binary: str) -> str | None:
    explicit = os.environ.get(env_key)
    if explicit and os.path.isfile(explicit) and os.access(explicit, os.X_OK):
        return explicit
    return shutil.which(binary)


def _opt_int(value: Any) -> int | None:
    if isinstance(value, int):
        return value if value > 0 else None
    return None


def _opt_uid(value: Any) -> int | None:
    if isinstance(value, int) and value >= 0:
        return value
    return None


@dataclass
class Pending:
    id: str
    created_at: float
    kind: str = "elevation"
    argv: list[str] | None = None
    host: str | None = None
    port: int | None = None
    scheme: str | None = None
    url: str | None = None
    cwd: str | None = None
    home: str | None = None
    project_root: str | None = None


@dataclass
class UiSessionContext:
    cwd: str | None = None
    home: str | None = None
    project_root: str | None = None


class PolicyStore:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        # Per OMP UI connection; cleared when that UI disconnects.
        self.session_allow: dict[str, set[tuple[str, int]]] = {}
        self.once_allow: set[tuple[str, int]] = set()
        self.pending: dict[str, Pending] = {}
        self.elevation_futures: dict[str, asyncio.Future[dict[str, Any]]] = {}
        self.network_futures: dict[str, asyncio.Future[dict[str, Any]]] = {}
        self.ui_clients: set[asyncio.StreamWriter] = set()
        self.ui_session_by_writer: dict[asyncio.StreamWriter, str] = {}
        self.ui_context_by_session: dict[str, UiSessionContext] = {}
        self.ui_spawn_last_by_uid: dict[int, float] = {}

    def resolve_context(
        self,
        cwd: str | None,
        home: str | None,
        project_root: str | None,
        *,
        pid: int | None = None,
        uid: int | None = None,
    ) -> tuple[str | None, str | None, str | None]:
        """Fill missing sandbox paths from /proc, OMP UI, or session context file."""
        file_ctx = read_session_context()
        cwd = cwd or file_ctx.get("cwd")
        home = home or file_ctx.get("home")
        project_root = project_root or file_ctx.get("project_root")
        if pid and pid > 0:
            proc_cwd, proc_home, proc_project = context_from_pid(pid)
            cwd = cwd or proc_cwd
            home = home or proc_home
            project_root = project_root or proc_project
        home = home or home_from_uid(uid)
        if cwd and home and project_root:
            return cwd, home, project_root
        for session_id in self.ui_session_by_writer.values():
            ctx = self.ui_context_by_session.get(session_id)
            if ctx is None:
                continue
            cwd = cwd or ctx.cwd
            home = home or ctx.home
            project_root = project_root or ctx.project_root
            if cwd and home and project_root:
                break
        home = home or infer_home_from_paths(project_root, cwd)
        return cwd, home, project_root

    def _user_global_path(self, home: str | None) -> Path | None:
        if not home:
            return None
        return Path(home) / ".config" / "agent-sandbox" / "policy.json"

    def _project_policy_paths(
        self,
        cwd: str | None,
        home: str | None,
        project_root: str | None,
    ) -> list[Path]:
        return project_policy_paths(
            home=home,
            cwd=cwd,
            project_root=project_root,
        )

    def merged_for(
        self,
        cwd: str | None,
        home: str | None,
        project_root: str | None = None,
        *,
        pid: int | None = None,
        uid: int | None = None,
    ) -> dict[str, Any]:
        cwd, home, project_root = self.resolve_context(
            cwd, home, project_root, pid=pid, uid=uid
        )
        layers = [load_policy(Path(self.args.declarative))]
        user_global = self._user_global_path(home)
        if user_global and user_global.is_file():
            layers.append(load_policy(user_global))
        for project_path in self._project_policy_paths(cwd, home, project_root):
            layers.append(load_policy(project_path))
        return merge_layers(*layers)

    def export_policy_files(
        self,
        cwd: str | None = None,
        home: str | None = None,
        project_root: str | None = None,
    ) -> None:
        merged = self.merged_for(cwd, home, project_root)
        export_path = Path(self.args.export_json)
        export_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = export_path.with_suffix(".tmp")
        tmp.write_text(json.dumps(merged, indent=2) + "\n", encoding="utf-8")
        tmp.replace(export_path)
        if self.args.export_nix:
            nix_path = Path(self.args.export_nix)
            nix_path.parent.mkdir(parents=True, exist_ok=True)
            lines = [
                "# Generated by agent-sandbox-policyd.",
                "{",
                "  version = 1;",
                "  allow = [",
            ]
            for rule in merged.get("allow", []):
                host = str(rule["host"]).replace('"', '\\"')
                port = int(rule["port"])
                lines.append(f'    {{ host = "{host}"; port = {port}; }}')
            lines.extend(["  ];", "  deny = ["])
            for rule in merged.get("deny", []):
                host = str(rule["host"]).replace('"', '\\"')
                port = int(rule["port"])
                lines.append(f'    {{ host = "{host}"; port = {port}; }}')
            lines.extend(["  ];", "}", ""])
            nix_tmp = nix_path.with_suffix(".tmp")
            nix_tmp.write_text("\n".join(lines), encoding="utf-8")
            nix_tmp.replace(nix_path)

    def _audit(self, action: str, host: str | None = None, port: int | None = None, detail: str = "") -> None:
        msg = f"audit {action}"
        if host is not None:
            msg += f" {host}"
            if port is not None:
                msg += f":{port}"
        if detail:
            msg += f" {detail}"
        log(msg)

    def _host_matches(self, pattern: str, host: str) -> bool:
        pattern = pattern.lower()
        host = host.lower()
        if pattern.startswith("*."):
            suffix = pattern[1:]
            return host == pattern[2:] or host.endswith(suffix)
        return pattern == host

    def _once_allowed(self, host: str, port: int, *, consume: bool = False) -> bool:
        keys = allow_keys(host, port)
        matched = any(key in self.once_allow for key in keys)
        if matched and consume:
            for key in keys:
                self.once_allow.discard(key)
        return matched

    def _session_allowed(self, host: str, port: int) -> bool:
        active = set(self.ui_session_by_writer.values())
        if not active:
            return False
        keys = allow_keys(host, port)
        for session_id in active:
            bucket = self.session_allow.get(session_id)
            if bucket and any(key in bucket for key in keys):
                return True
        return False

    def start_ui_session(
        self,
        writer: asyncio.StreamWriter,
        *,
        cwd: str | None = None,
        home: str | None = None,
        project_root: str | None = None,
    ) -> str:
        session_id = uuid.uuid4().hex
        self.ui_clients.add(writer)
        self.ui_session_by_writer[writer] = session_id
        self.ui_context_by_session[session_id] = UiSessionContext(
            cwd=cwd,
            home=home,
            project_root=project_root,
        )
        return session_id

    def end_ui_session(self, writer: asyncio.StreamWriter) -> None:
        self.ui_clients.discard(writer)
        session_id = self.ui_session_by_writer.pop(writer, None)
        if session_id:
            self.session_allow.pop(session_id, None)
            self.ui_context_by_session.pop(session_id, None)

    def _policy_denied(
        self,
        host: str,
        port: int,
        cwd: str | None,
        home: str | None,
        project_root: str | None = None,
        *,
        pid: int | None = None,
        uid: int | None = None,
    ) -> bool:
        host = normalize_host(host)
        merged = self.merged_for(
            cwd, home, project_root, pid=pid, uid=uid
        )
        for rule in merged.get("deny", []):
            if self._host_matches(str(rule["host"]), host) and int(rule["port"]) == port:
                return True
        return False

    def allow_source(
        self,
        host: str,
        port: int,
        cwd: str | None,
        home: str | None,
        project_root: str | None = None,
        *,
        pid: int | None = None,
        uid: int | None = None,
    ) -> str | None:
        host = normalize_host(host)
        cwd, home, project_root = self.resolve_context(
            cwd, home, project_root, pid=pid, uid=uid
        )
        if self._policy_denied(
            host, port, cwd, home, project_root, pid=pid, uid=uid
        ):
            return "deny"
        if self._once_allowed(host, port):
            return "once"
        if self._session_allowed(host, port):
            return "session"
        merged = self.merged_for(
            cwd, home, project_root, pid=pid, uid=uid
        )
        for rule in merged.get("allow", []):
            if self._host_matches(str(rule["host"]), host) and int(rule["port"]) == port:
                comment = str(rule.get("comment", ""))
                return f"allow:{comment}" if comment else "allow"
        return None

    def is_allowed(
        self,
        host: str,
        port: int,
        cwd: str | None,
        home: str | None,
        project_root: str | None = None,
        *,
        consume_once: bool = False,
        pid: int | None = None,
        uid: int | None = None,
    ) -> bool:
        host = normalize_host(host)
        cwd, home, project_root = self.resolve_context(
            cwd, home, project_root, pid=pid, uid=uid
        )
        if self._policy_denied(
            host, port, cwd, home, project_root, pid=pid, uid=uid
        ):
            return False
        if self._once_allowed(host, port, consume=consume_once):
            return True
        if self._session_allowed(host, port):
            return True
        merged = self.merged_for(
            cwd, home, project_root, pid=pid, uid=uid
        )
        for rule in merged.get("allow", []):
            if self._host_matches(str(rule["host"]), host) and int(rule["port"]) == port:
                return True
        return False

    async def _wait_for_ui_client(self, timeout: float) -> bool:
        if self.ui_clients:
            return True
        loop = asyncio.get_running_loop()
        deadline = loop.time() + timeout
        while loop.time() < deadline:
            if self.ui_clients:
                return True
            await asyncio.sleep(0.05)
        return False

    def _ui_spawn_env(
        self,
        user: pwd.struct_passwd,
        uid: int,
        *,
        home: str | None,
        cwd: str | None,
        project_root: str | None,
    ) -> dict[str, str]:
        env: dict[str, str] = {
            "HOME": home or user.pw_dir,
            "USER": user.pw_name,
            "LOGNAME": user.pw_name,
            "AGENT_SANDBOX_POLICY_SOCKET": str(self.args.socket),
        }
        if cwd:
            env["AGENT_SANDBOX_CWD"] = cwd
        if project_root:
            env["AGENT_SANDBOX_PROJECT_ROOT"] = project_root
        env.update(
            graphical_session_env(uid, _tool_path, home=home or user.pw_dir)
        )
        env["AGENT_SANDBOX_UI_PREFER_GRAPHICAL"] = "1"
        profile_bin = f"/etc/profiles/per-user/{user.pw_name}/bin"
        if os.path.isdir(profile_bin):
            env["PATH"] = f"{profile_bin}:{env.get('PATH', '')}"
        kdialog = _tool_path("AGENT_SANDBOX_KDIALOG", "kdialog")
        if kdialog:
            env["AGENT_SANDBOX_KDIALOG"] = kdialog
            kdialog_dir = os.path.dirname(kdialog)
            if kdialog_dir not in env.get("PATH", "").split(":"):
                env["PATH"] = f"{kdialog_dir}:{env.get('PATH', '')}"
        return env

    def _maybe_spawn_ui(
        self,
        *,
        uid: int | None,
        home: str | None,
        cwd: str | None,
        project_root: str | None,
    ) -> None:
        cmd = getattr(self.args, "ui_spawn_cmd", None)
        if not cmd or self.ui_clients:
            return
        if uid is None or uid <= 0:
            return
        now = time.time()
        if now - self.ui_spawn_last_by_uid.get(uid, 0.0) < 10.0:
            return
        self.ui_spawn_last_by_uid[uid] = now
        try:
            user = pwd.getpwuid(uid)
        except KeyError:
            return
        runuser = _tool_path("AGENT_SANDBOX_RUNUSER", "runuser")
        if not runuser:
            log("agent-sandbox: cannot spawn UI (runuser not found)")
            return
        env = self._ui_spawn_env(
            user, uid, home=home, cwd=cwd, project_root=project_root
        )
        # -p keeps Wayland/D-Bus env; plain runuser clears it and Qt dies immediately.
        spawn_cmd = [runuser, "-p", "-u", user.pw_name, "--", cmd]
        ui_log_path = f"/run/user/{uid}/agent-sandbox-ui.log"
        try:
            ui_log_file = open(ui_log_path, "a", encoding="utf-8")
        except OSError:
            ui_log_file = subprocess.DEVNULL  # type: ignore[assignment]
        try:
            proc = subprocess.Popen(
                spawn_cmd,
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=ui_log_file,
                start_new_session=True,
            )
        except OSError as err:
            log(f"agent-sandbox: UI spawn failed for uid={uid}: {err}")
            if ui_log_file not in (subprocess.DEVNULL, None):
                ui_log_file.close()
            return
        if ui_log_file not in (subprocess.DEVNULL, None):
            ui_log_file.close()
        time.sleep(0.25)
        if proc.poll() is not None:
            log(
                f"agent-sandbox: UI spawn exited {proc.returncode} "
                f"(see {ui_log_path})"
            )
            return
        log(
            f"spawned policy UI for uid={uid} ({user.pw_name}); "
            f"log {ui_log_path}"
        )
        notify = _tool_path("AGENT_SANDBOX_NOTIFY_SEND", "notify-send")
        if notify:
            with contextlib.suppress(OSError):
                subprocess.Popen(
                    [
                        runuser,
                        "-p",
                        "-u",
                        user.pw_name,
                        "--",
                        notify,
                        "agent-sandbox",
                        "Network approval needed — respond to the KDE prompt.",
                    ],
                    env=env,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )

    async def notify_ui(self, payload: dict[str, Any]) -> None:
        if not self.ui_clients:
            return
        dead: list[asyncio.StreamWriter] = []
        line = (json.dumps(payload) + "\n").encode()
        for writer in list(self.ui_clients):
            try:
                writer.write(line)
                await writer.drain()
            except (ConnectionResetError, BrokenPipeError, ConnectionError, OSError):
                dead.append(writer)
        for writer in dead:
            self.end_ui_session(writer)

    async def flush_pending_to_ui(self) -> None:
        """Re-notify OMP UI for pending elevation/network requests."""
        for pending in list(self.pending.values()):
            if pending.kind == "network":
                await self.notify_ui(
                    {
                        "type": "network_request",
                        "id": pending.id,
                        "host": pending.host,
                        "port": pending.port,
                        "scheme": pending.scheme,
                        "url": pending.url,
                        "cwd": pending.cwd,
                        "home": pending.home,
                        "project_root": pending.project_root,
                    }
                )
            else:
                await self.notify_ui(
                    {
                        "type": "elevation_request",
                        "id": pending.id,
                        "argv": pending.argv or [],
                        "cwd": pending.cwd,
                        "home": pending.home,
                        "project_root": pending.project_root,
                    }
                )

    def _finish_network(
        self,
        pending_id: str,
        *,
        allowed: bool,
        source: str,
    ) -> None:
        fut = self.network_futures.pop(pending_id, None)
        if fut and not fut.done():
            fut.set_result({"ok": True, "allowed": allowed, "source": source})

    async def request_network_approval(
        self,
        host: str,
        port: int,
        scheme: str,
        url: str,
        cwd: str | None,
        home: str | None,
        project_root: str | None = None,
        *,
        pid: int | None = None,
        uid: int | None = None,
    ) -> dict[str, Any]:
        policy_host = normalize_host(host)
        cwd, home, project_root = self.resolve_context(
            cwd, home, project_root, pid=pid, uid=uid
        )
        if self._policy_denied(
            policy_host, port, cwd, home, project_root, pid=pid, uid=uid
        ):
            log(f"check deny {policy_host}:{port} (project policy)")
            return {"ok": True, "allowed": False, "source": "deny"}
        if not self.args.interactive_approval:
            return {"ok": True, "allowed": False, "source": "blocked"}

        pending_id = f"net:{uuid.uuid4().hex}"
        loop = asyncio.get_running_loop()
        fut: asyncio.Future[dict[str, Any]] = loop.create_future()
        self.network_futures[pending_id] = fut
        self.pending[pending_id] = Pending(
            pending_id,
            time.time(),
            kind="network",
            host=policy_host,
            port=port,
            scheme=scheme,
            url=url,
            cwd=cwd,
            home=home,
            project_root=project_root,
        )
        self._audit("pending", policy_host, port, scheme)
        await self.notify_ui(
            {
                "type": "network_request",
                "id": pending_id,
                "host": policy_host,
                "port": port,
                "scheme": scheme,
                "url": url,
                "cwd": cwd,
                "home": home,
                "project_root": project_root,
            }
        )
        if not self.ui_clients:
            self._maybe_spawn_ui(
                uid=uid, home=home, cwd=cwd, project_root=project_root
            )
        if not self.ui_clients:
            ui_wait = min(60.0, self.args.approval_timeout)
            if not await self._wait_for_ui_client(ui_wait):
                self.pending.pop(pending_id, None)
                self.network_futures.pop(pending_id, None)
                if not fut.done():
                    fut.cancel()
                log(
                    f"network approval {policy_host}:{port} "
                    "(no policy UI connected)"
                )
                return {
                    "ok": True,
                    "allowed": False,
                    "source": "blocked",
                    "error": (
                        "agent-sandbox: no policy UI registered "
                        "(OMP extension, agent-sandbox-ui, or auto-spawn)"
                    ),
                }
            await self.notify_ui(
                {
                    "type": "network_request",
                    "id": pending_id,
                    "host": policy_host,
                    "port": port,
                    "scheme": scheme,
                    "url": url,
                    "cwd": cwd,
                    "home": home,
                    "project_root": project_root,
                }
            )
        try:
            return await asyncio.wait_for(fut, timeout=self.args.approval_timeout)
        except asyncio.TimeoutError:
            self.pending.pop(pending_id, None)
            self.network_futures.pop(pending_id, None)
            if not fut.done():
                fut.cancel()
            self._audit("timeout", policy_host, port, scheme)
            log(
                f"check blocked {policy_host}:{port} "
                "(approval timed out; is policy UI loaded?)"
            )
            return {
                "ok": True,
                "allowed": False,
                "source": "blocked",
                "error": (
                    "agent-sandbox: network approval timed out "
                    "(no response from policy UI)"
                ),
            }

    def _user_for_home(self, home: str | None) -> str:
        if not home:
            return "root"
        try:
            for pw in pwd.getpwall():
                if pw.pw_dir == home:
                    return pw.pw_name
        except Exception:
            pass
        return os.path.basename(home.rstrip("/")) or "nobody"

    def _elevation_env(self, home: str | None) -> dict[str, str]:
        user = self._user_for_home(home)
        return {
            "HOME": home or "/root",
            "USER": user,
            "LOGNAME": user,
            "PATH": (
                "/run/wrappers:/nix/var/nix/profiles/default/bin:"
                "/run/current-system/sw/bin:/usr/bin:/bin"
            ),
        }

    async def _exec_elevation(
        self,
        argv: list[str],
        cwd: str | None,
        home: str | None,
    ) -> dict[str, Any]:
        work_dir = cwd or "/"
        proc = await asyncio.create_subprocess_exec(
            *argv,
            cwd=work_dir,
            env=self._elevation_env(home),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout_b, stderr_b = await proc.communicate()
        exit_code = proc.returncode if proc.returncode is not None else 1
        detail = json.dumps({"argv": argv, "exit_code": exit_code})
        self._audit("exec", detail=detail)
        return {
            "ok": True,
            "allowed": True,
            "exit_code": exit_code,
            "stdout": stdout_b.decode(errors="replace"),
            "stderr": stderr_b.decode(errors="replace"),
        }

    def _finish_elevation(self, pending_id: str, result: dict[str, Any]) -> None:
        fut = self.elevation_futures.pop(pending_id, None)
        if fut and not fut.done():
            fut.set_result(result)

    def _elevation_denied(self) -> dict[str, Any]:
        return {
            "ok": True,
            "allowed": False,
            "exit_code": 1,
            "stdout": "",
            "stderr": "agent-sandbox: elevation denied",
        }

    async def request_elevation(
        self,
        argv: list[str],
        cwd: str | None,
        home: str | None,
        project_root: str | None = None,
    ) -> dict[str, Any]:
        pending_id = f"elev:{uuid.uuid4().hex}"
        loop = asyncio.get_running_loop()
        fut: asyncio.Future[dict[str, Any]] = loop.create_future()
        self.elevation_futures[pending_id] = fut
        self.pending[pending_id] = Pending(
            pending_id,
            time.time(),
            argv=list(argv),
            cwd=cwd,
            home=home,
            project_root=project_root,
        )
        self._audit("pending", detail=json.dumps({"id": pending_id, "argv": argv}))
        await self.notify_ui(
            {
                "type": "elevation_request",
                "id": pending_id,
                "argv": argv,
                "cwd": cwd,
                "home": home,
                "project_root": project_root,
            }
        )
        if not self.ui_clients:
            uid: int | None = None
            if home:
                try:
                    uid = pwd.getpwnam(self._user_for_home(home)).pw_uid
                except KeyError:
                    uid = None
            self._maybe_spawn_ui(
                uid=uid, home=home, cwd=cwd, project_root=project_root
            )
        if not self.ui_clients:
            ui_wait = min(60.0, self.args.approval_timeout)
            if not await self._wait_for_ui_client(ui_wait):
                self.pending.pop(pending_id, None)
                self.elevation_futures.pop(pending_id, None)
                if not fut.done():
                    fut.cancel()
                return {
                    "ok": True,
                    "allowed": False,
                    "exit_code": 1,
                    "stdout": "",
                    "stderr": (
                        "agent-sandbox: no policy UI registered "
                        "(OMP extension, agent-sandbox-ui, or auto-spawn)"
                    ),
                }
            await self.notify_ui(
                {
                    "type": "elevation_request",
                    "id": pending_id,
                    "argv": argv,
                    "cwd": cwd,
                    "home": home,
                    "project_root": project_root,
                }
            )
        try:
            return await asyncio.wait_for(fut, timeout=self.args.approval_timeout)
        except asyncio.TimeoutError:
            self.pending.pop(pending_id, None)
            self.elevation_futures.pop(pending_id, None)
            if not fut.done():
                fut.cancel()
            self._audit("timeout", detail=pending_id)
            return {
                "ok": True,
                "allowed": False,
                "exit_code": 1,
                "stdout": "",
                "stderr": (
                    "agent-sandbox: elevation timed out "
                    "(no response from policy UI)"
                ),
            }

    def _persist_json_rule(
        self,
        path: Path,
        host: str,
        port: int,
        label: str,
        *,
        home: str | None = None,
        owner_uid: int | None = None,
    ) -> None:
        current = load_policy(path)
        allow = {rule_key(r): r for r in current.get("allow", []) if isinstance(r, dict)}
        allow[(host.lower(), port)] = {"host": normalize_host(host), "port": port, "comment": label}
        current["allow"] = sorted(allow.values(), key=lambda r: (r["host"], r["port"]))
        atomic_write_policy(path, current, home=home, owner_uid=owner_uid)

    def _approve_network_scope(
        self,
        host: str,
        port: int,
        scope: str,
        cwd: str | None,
        home: str | None,
        *,
        session_id: str | None = None,
        project_root: str | None = None,
        owner_uid: int | None = None,
    ) -> dict[str, Any]:
        keys = allow_keys(host, port)
        if scope == "once":
            for key in keys:
                self.once_allow.add(key)
        elif scope == "session":
            if not session_id or session_id not in set(self.ui_session_by_writer.values()):
                return {
                    "ok": False,
                    "error": "session_id required (OMP UI must be connected)",
                }
            bucket = self.session_allow.setdefault(session_id, set())
            for key in keys:
                bucket.add(key)
        elif scope == "global":
            if not home:
                return {"ok": False, "error": "home required for global scope"}
            path = self._user_global_path(home)
            assert path is not None
            self._persist_json_rule(
                path, host, port, scope, home=home, owner_uid=owner_uid
            )
        elif scope == "project":
            if not project_root:
                return {
                    "ok": False,
                    "error": "project_root required (set AGENT_SANDBOX_PROJECT_ROOT)",
                }
            try:
                project = resolve_project_policy_path(project_root=project_root)
            except ValueError as exc:
                return {"ok": False, "error": str(exc)}
            self._persist_json_rule(
                project,
                host,
                port,
                scope,
                home=home,
                owner_uid=owner_uid,
            )
            log(f"project policy saved {project}")
        else:
            return {"ok": False, "error": f"invalid scope: {scope}"}
        self.export_policy_files(cwd, home, project_root)
        self._audit("approve", host, port, scope)
        result: dict[str, Any] = {
            "ok": True,
            "host": host,
            "port": port,
            "scope": scope,
        }
        if scope == "project" and project_root:
            try:
                result["path"] = str(
                    resolve_project_policy_path(project_root=project_root)
                )
            except ValueError:
                pass
        return result

    async def approve_host(
        self,
        host: str,
        port: int,
        scope: str,
        cwd: str | None,
        home: str | None,
        *,
        session_id: str | None = None,
        project_root: str | None = None,
        pid: int | None = None,
        uid: int | None = None,
    ) -> dict[str, Any]:
        policy_host = normalize_host(host)
        if not policy_host:
            return {"ok": False, "error": "host required"}
        if port <= 0 or port > 65535:
            return {"ok": False, "error": "invalid port"}
        cwd, home, project_root = self.resolve_context(
            cwd, home, project_root, pid=pid, uid=uid
        )
        if self._policy_denied(
            policy_host, port, cwd, home, project_root, pid=pid, uid=uid
        ):
            return {
                "ok": False,
                "error": "host denied by policy deny rules",
            }
        return self._approve_network_scope(
            policy_host,
            port,
            scope,
            cwd,
            home,
            session_id=session_id,
            project_root=project_root,
            owner_uid=uid,
        )

    async def approve(
        self,
        pending_id: str,
        scope: str,
        cwd: str | None,
        home: str | None,
        *,
        session_id: str | None = None,
        project_root: str | None = None,
        owner_uid: int | None = None,
    ) -> dict[str, Any]:
        pending = self.pending.get(pending_id)
        if pending is None:
            return {"ok": False, "error": "unknown pending id"}
        pending = self.pending.pop(pending_id)
        if pending.kind == "network":
            host = pending.host or ""
            port = pending.port or 0
            # Blocking UI "once" only unblocks this pending check. Do not add to
            # once_allow — that would let the next connection auto-allow without a prompt.
            if scope == "once":
                self._audit("approve", host, port, scope)
                self._finish_network(pending_id, allowed=True, source="once")
                return {"ok": True, "host": host, "port": port, "scope": scope}
            result = self._approve_network_scope(
                host,
                port,
                scope,
                pending.cwd or cwd,
                pending.home or home,
                session_id=session_id,
                project_root=pending.project_root or project_root,
                owner_uid=owner_uid,
            )
            if result.get("ok"):
                self._finish_network(
                    pending_id, allowed=True, source=str(result.get("scope", scope))
                )
            else:
                self._finish_network(pending_id, allowed=False, source="blocked")
            return result

        if scope != "once":
            self.pending[pending.id] = pending
            return {"ok": False, "error": "elevation only supports scope once"}
        argv = pending.argv or []
        self._audit("approve", detail=json.dumps({"id": pending_id, "argv": argv}))
        result = await self._exec_elevation(
            argv, pending.cwd or cwd, pending.home or home
        )
        self._finish_elevation(pending_id, result)
        return {"ok": True, "allowed": True, "scope": scope}

    def deny(self, pending_id: str) -> dict[str, Any]:
        pending = self.pending.pop(pending_id, None)
        if pending is None:
            return {"ok": False, "error": "unknown pending id"}
        if pending.kind == "network":
            host = pending.host or ""
            port = pending.port or 0
            self._audit("deny", host, port, pending.scheme or "")
            self._finish_network(pending_id, allowed=False, source="denied")
            return {"ok": True}
        argv = pending.argv or []
        self._audit("deny", detail=json.dumps({"id": pending_id, "argv": argv}))
        self._finish_elevation(pending_id, self._elevation_denied())
        return {"ok": True}

    def status(
        self, cwd: str | None, home: str | None, project_root: str | None = None
    ) -> dict[str, Any]:
        return {
            "merged": self.merged_for(cwd, home, project_root),
            "pending": [
                (
                    {
                        "id": p.id,
                        "kind": "network",
                        "host": p.host,
                        "port": p.port,
                        "scheme": p.scheme,
                        "url": p.url,
                        "cwd": p.cwd,
                        "home": p.home,
                    }
                    if p.kind == "network"
                    else {
                        "id": p.id,
                        "kind": "elevation",
                        "argv": p.argv or [],
                        "cwd": p.cwd,
                        "home": p.home,
                    }
                )
                for p in self.pending.values()
            ],
        }


class PolicyServer:
    def __init__(self, store: PolicyStore, socket_path: Path) -> None:
        self.store = store
        self.socket_path = socket_path

    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            while True:
                line = await reader.readline()
                if not line:
                    break
                try:
                    req = json.loads(line.decode())
                except json.JSONDecodeError:
                    await self._reply(writer, {"ok": False, "error": "invalid json"})
                    continue
                try:
                    resp = await self._dispatch(req, writer)
                except Exception as err:
                    log(f"dispatch error op={req.get('op')}: {err}")
                    resp = {"ok": False, "error": str(err)}
                await self._reply(writer, resp)
                if req.get("op") == "register_ui" and resp.get("ok"):
                    await self.store.flush_pending_to_ui()
        finally:
            self.store.end_ui_session(writer)
            with contextlib.suppress(
                BrokenPipeError,
                ConnectionResetError,
                ConnectionError,
                OSError,
            ):
                writer.close()
                await writer.wait_closed()

    async def _reply(self, writer: asyncio.StreamWriter, payload: dict[str, Any]) -> None:
        try:
            writer.write((json.dumps(payload) + "\n").encode())
            await writer.drain()
        except (ConnectionResetError, BrokenPipeError, ConnectionError):
            self.store.end_ui_session(writer)

    async def _dispatch(self, req: dict[str, Any], writer: asyncio.StreamWriter) -> dict[str, Any]:
        op = req.get("op")
        cwd, home, project_root = self.store.resolve_context(
            req.get("cwd"),
            req.get("home"),
            req.get("project_root"),
            pid=_opt_int(req.get("pid")),
            uid=_opt_uid(req.get("uid")),
        )
        if op == "register_ui":
            session_id = self.store.start_ui_session(
                writer,
                cwd=req.get("cwd") or cwd,
                home=req.get("home") or home,
                project_root=req.get("project_root") or project_root,
            )
            ctx = self.store.ui_context_by_session.get(session_id)
            if ctx:
                write_session_context(
                    cwd=ctx.cwd,
                    home=ctx.home,
                    project_root=ctx.project_root,
                )
            if ctx and ctx.project_root:
                log(f"ui registered project_root={ctx.project_root}")
            # Pending notifications are sent after the register_ui reply (handle_client).
            return {"ok": True, "role": "ui", "session_id": session_id}
        if op == "unregister_ui":
            self.store.end_ui_session(writer)
            return {"ok": True}
        if op == "check":
            connect_host = str(req.get("connect_host", req.get("host", "")))
            port = int(req.get("port", 0))
            scheme = str(req.get("scheme", "https"))
            policy_host = normalize_host(str(req.get("host", "")))
            if not policy_host:
                policy_host, _ = policy_host_for_connect(connect_host)
            elif is_ipv4_literal(policy_host):
                policy_host, _ = policy_host_for_connect(connect_host)
            url = str(req.get("url", f"{scheme}://{policy_host}:{port}"))
            pid = _opt_int(req.get("pid"))
            uid = _opt_uid(req.get("uid"))
            if home:
                write_session_context(cwd=cwd, home=home, project_root=project_root)
            source = self.store.allow_source(
                policy_host, port, cwd, home, project_root, pid=pid, uid=uid
            )
            if source == "deny":
                log(f"check deny {policy_host}:{port} (project policy)")
                return {"ok": True, "allowed": False, "source": source}
            if source is not None:
                allowed = self.store.is_allowed(
                    policy_host,
                    port,
                    cwd,
                    home,
                    project_root,
                    consume_once=(source == "once"),
                    pid=pid,
                    uid=uid,
                )
                if allowed:
                    log(f"check allow {policy_host}:{port} ({source})")
                return {"ok": True, "allowed": allowed, "source": source}
            return await self.store.request_network_approval(
                policy_host,
                port,
                scheme,
                url,
                cwd,
                home,
                project_root,
                pid=pid,
                uid=uid,
            )
        if op == "elevate":
            argv = req.get("argv")
            if not isinstance(argv, list) or not argv:
                return {"ok": False, "error": "argv required (non-empty list of strings)"}
            if not all(isinstance(arg, str) for arg in argv):
                return {"ok": False, "error": "argv must be strings"}
            return await self.store.request_elevation(argv, cwd, home, project_root)
        if op == "approve":
            return await self.store.approve(
                str(req.get("id", "")),
                str(req.get("scope", "")),
                cwd,
                home,
                session_id=req.get("session_id"),
                project_root=project_root,
                owner_uid=_opt_uid(req.get("uid")),
            )
        if op == "approve_host":
            port_value = _opt_int(req.get("port"))
            if port_value is None:
                return {"ok": False, "error": "port required (1-65535)"}
            return await self.store.approve_host(
                str(req.get("host", "")),
                port_value,
                str(req.get("scope", "")),
                cwd,
                home,
                session_id=req.get("session_id"),
                project_root=project_root,
                pid=_opt_int(req.get("pid")),
                uid=_opt_uid(req.get("uid")),
            )
        if op == "deny":
            return self.store.deny(str(req.get("id", "")))
        if op == "status":
            return {"ok": True, **self.store.status(cwd, home, project_root)}
        if op == "reload":
            self.store.export_policy_files(cwd, home, project_root)
            return {"ok": True}
        return {"ok": False, "error": f"unknown op: {op}"}

    async def run(self) -> None:
        if self.socket_path.exists():
            self.socket_path.unlink()
        self.socket_path.parent.mkdir(parents=True, exist_ok=True)
        server = await asyncio.start_unix_server(self.handle_client, path=str(self.socket_path))
        os.chmod(self.socket_path, 0o666)
        log(f"policyd listening on {self.socket_path}")
        async with server:
            await server.serve_forever()


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--socket", default="/run/agent-sandbox/policy.sock")
    p.add_argument("--declarative", default="/etc/agent-sandbox/declarative.json")
    p.add_argument("--export-json", default="/var/lib/agent-sandbox/exported-policy.json")
    p.add_argument("--export-nix", default="")
    p.add_argument(
        "--approval-timeout",
        type=float,
        default=300.0,
        help="Max seconds to wait for elevation approvals from OMP UI",
    )
    p.add_argument(
        "--interactive-approval",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Block on OMP approval for blocked hosts until allow/deny/timeout",
    )
    p.add_argument(
        "--ui-spawn-cmd",
        default=os.environ.get("AGENT_SANDBOX_UI_SPAWN_CMD", ""),
        metavar="PATH",
        help="Executable to run as the sandbox user when no policy UI is connected",
    )
    return p.parse_args()


def main():
    args = parse_args()
    store = PolicyStore(args)
    store.export_policy_files()
    try:
        asyncio.run(PolicyServer(store, Path(args.socket)).run())
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
