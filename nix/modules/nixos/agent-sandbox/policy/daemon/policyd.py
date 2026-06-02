#!/usr/bin/env python3
"""Agent sandbox policy daemon."""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import json
import os
import pwd
import sys
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any

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
    argv: list[str] | None = None
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
        self.ui_clients: set[asyncio.StreamWriter] = set()
        self.ui_session_by_writer: dict[asyncio.StreamWriter, str] = {}
        self.ui_context_by_session: dict[str, UiSessionContext] = {}

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

    async def notify_ui(self, payload: dict[str, Any]) -> None:
        if not self.ui_clients:
            return
        dead: list[asyncio.StreamWriter] = []
        line = (json.dumps(payload) + "\n").encode()
        for writer in list(self.ui_clients):
            try:
                writer.write(line)
                await writer.drain()
            except Exception:
                dead.append(writer)
        for writer in dead:
            self.ui_clients.discard(writer)

    async def flush_pending_to_ui(self) -> None:
        """Re-notify OMP UI for elevation requests still awaiting a decision."""
        for pending in list(self.pending.values()):
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

    async def suggest_approval(
        self,
        host: str,
        port: int,
        scheme: str,
        url: str,
        cwd: str | None,
        home: str | None,
        project_root: str | None = None,
    ) -> None:
        cwd, home, project_root = self.resolve_context(cwd, home, project_root)
        if self._policy_denied(host, port, cwd, home, project_root):
            log(f"check deny {normalize_host(host)}:{port} (project policy)")
            return
        if not self.args.interactive_approval:
            return
        self._audit("suggest", host, port, scheme)
        await self.notify_ui(
            {
                "type": "approval_suggestion",
                "host": host,
                "port": port,
                "scheme": scheme,
                "url": url,
                "cwd": cwd,
                "home": home,
                "project_root": project_root,
            }
        )
        if not self.ui_clients:
            log(
                f"approval suggestion {normalize_host(host)}:{port} "
                "(no OMP UI connected)"
            )

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
                    "agent-sandbox: no OMP UI registered "
                    "(is agent-sandbox extension loaded?)"
                ),
            }
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
                    "(no response from OMP; is agent-sandbox extension loaded?)"
                ),
            }

    def _persist_json_rule(self, path: Path, host: str, port: int, label: str) -> None:
        current = load_policy(path)
        allow = {rule_key(r): r for r in current.get("allow", []) if isinstance(r, dict)}
        allow[(host.lower(), port)] = {"host": normalize_host(host), "port": port, "comment": label}
        current["allow"] = sorted(allow.values(), key=lambda r: (r["host"], r["port"]))
        atomic_write_policy(path, current)

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
            self._persist_json_rule(path, host, port, scope)
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
            self._persist_json_rule(project, host, port, scope)
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
    ) -> dict[str, Any]:
        pending = self.pending.get(pending_id)
        if pending is None:
            return {"ok": False, "error": "unknown pending id"}
        pending = self.pending.pop(pending_id)
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
                {
                    "id": p.id,
                    "kind": "elevation",
                    "argv": p.argv or [],
                    "cwd": p.cwd,
                    "home": p.home,
                }
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
                await self._reply(writer, await self._dispatch(req, writer))
        finally:
            self.store.end_ui_session(writer)
            writer.close()
            with contextlib.suppress(Exception):
                await writer.wait_closed()

    async def _reply(self, writer: asyncio.StreamWriter, payload: dict[str, Any]) -> None:
        writer.write((json.dumps(payload) + "\n").encode())
        await writer.drain()

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
            await self.store.flush_pending_to_ui()
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
            await self.store.suggest_approval(
                policy_host, port, scheme, url, cwd, home, project_root
            )
            log(
                f"check blocked {policy_host}:{port} "
                "(not in policy; approve in OMP or via agent-sandbox-approve and retry)"
            )
            return {"ok": True, "allowed": False, "source": "blocked"}
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
        help="Emit OMP approval suggestions for blocked hosts (non-blocking)",
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
