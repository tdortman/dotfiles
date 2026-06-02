"""Read sandbox context from a client process via /proc (host pid namespace)."""

from __future__ import annotations

import os
import pwd
import socket
import struct
from pathlib import Path

SO_PEERCRED = getattr(socket, "SO_PEERCRED", 17)
_TCP_ESTABLISHED = "01"


def read_proc_environ(pid: int) -> dict[str, str]:
    try:
        raw = Path(f"/proc/{pid}/environ").read_bytes()
    except OSError:
        return {}
    env: dict[str, str] = {}
    for item in raw.split(b"\0"):
        if b"=" not in item:
            continue
        key, value = item.split(b"=", 1)
        env[key.decode(errors="replace")] = value.decode(errors="replace")
    return env


def read_proc_cwd(pid: int) -> str | None:
    try:
        cwd = os.readlink(f"/proc/{pid}/cwd")
    except OSError:
        return None
    return cwd or None


def _tcp_addr_field(ip: str, port: int) -> str:
    packed = socket.inet_aton(ip)
    return f"{packed[::-1].hex().upper()}:{port:04X}"


def _parse_tcp_addr(field: str) -> tuple[str, int]:
    ip_hex, port_hex = field.split(":")
    ip = socket.inet_ntoa(bytes.fromhex(ip_hex)[::-1])
    return ip, int(port_hex, 16)


def _find_tcp_entry(
    local: tuple[str, int], peer: tuple[str, int]
) -> tuple[int | None, str | None]:
    """Return uid and socket inode for an established IPv4 TCP connection."""
    local_field = _tcp_addr_field(local[0], local[1])
    peer_field = _tcp_addr_field(peer[0], peer[1])
    try:
        lines = Path("/proc/net/tcp").read_text(encoding="utf-8").splitlines()[1:]
    except OSError:
        return None, None
    for line in lines:
        parts = line.split()
        if len(parts) < 10:
            continue
        if parts[3] != _TCP_ESTABLISHED:
            continue
        if parts[1] == local_field and parts[2] == peer_field:
            try:
                uid = int(parts[7])
            except ValueError:
                uid = None
            return uid, parts[9]
    return None, None


def pid_for_socket_inode(inode: str | None) -> int | None:
    if not inode:
        return None
    needle = f"socket:[{inode}]"
    for pid_dir in Path("/proc").iterdir():
        if not pid_dir.name.isdigit():
            continue
        pid = int(pid_dir.name)
        fd_dir = pid_dir / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    if os.readlink(fd) == needle:
                        return pid
                except OSError:
                    continue
        except OSError:
            continue
    return None


def peer_cred(sock: socket.socket | None) -> tuple[int, int, int] | None:
    """Return pid, uid, gid for the peer of a connected socket."""
    if sock is None:
        return None
    try:
        family = sock.family
    except AttributeError:
        family = socket.AF_INET
    if family == socket.AF_INET:
        try:
            local = sock.getsockname()
            peer = sock.getpeername()
        except OSError:
            local = peer = None
        if local and peer and len(local) == 2 and len(peer) == 2:
            uid, inode = _find_tcp_entry(peer, local)
            if uid is not None and uid >= 0:
                pid = pid_for_socket_inode(inode) or 0
                return pid, uid, -1
    try:
        raw = sock.getsockopt(socket.SOL_SOCKET, SO_PEERCRED, struct.calcsize("3i"))
        pid, uid, gid = struct.unpack("3i", raw)
    except OSError:
        return None
    if pid <= 0 and uid < 0:
        return None
    return pid if pid > 0 else 0, uid, gid


def home_from_uid(uid: int | None) -> str | None:
    if uid is None or uid < 0:
        return None
    try:
        return pwd.getpwuid(uid).pw_dir
    except (KeyError, OSError):
        return None


def context_from_pid(pid: int) -> tuple[str | None, str | None, str | None]:
    """Return cwd, home, project_root from /proc/<pid> when available."""
    if pid <= 0:
        return None, None, None
    env = read_proc_environ(pid)
    cwd = env.get("AGENT_SANDBOX_CWD") or read_proc_cwd(pid)
    home = env.get("AGENT_SANDBOX_HOME") or env.get("HOME")
    project_root = env.get("AGENT_SANDBOX_PROJECT_ROOT")
    return cwd, home, project_root
