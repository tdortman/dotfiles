#!/usr/bin/env python3
"""Policy proxy for agent-sandbox: explicit HTTP CONNECT and transparent TCP redirect."""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import json
import os
import socket
import struct
import sys
from pathlib import Path
from typing import Any

from hosts import policy_host_for_connect
from merge_policy import discover_project_policy, infer_home_from_paths
from proc_context import context_from_pid, home_from_uid, peer_cred
from session_context import read_session_context, write_session_context

# Linux netfilter SO_ORIGINAL_DST (see linux/netfilter_ipv4.h)
SO_ORIGINAL_DST = 80

# Read enough for TLS ClientHello + SNI before policy check (keeps handshake alive).
CLIENT_PEEK_BYTES = 16 * 1024
CLIENT_PEEK_TIMEOUT = 5.0


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def get_original_dst(sock: socket.socket) -> tuple[str, int] | None:
    """Return the pre-DNAT destination for a redirected connection, if available."""
    try:
        raw = sock.getsockopt(socket.SOL_IP, SO_ORIGINAL_DST, 16)
    except OSError:
        return None
    if len(raw) < 16:
        return None
    _, port, raw_ip = struct.unpack("!HH4s8x", raw[:16])
    return socket.inet_ntoa(raw_ip), port


async def policy_request(
    socket_path: str,
    payload: dict[str, Any],
    *,
    timeout: float = 30.0,
) -> dict[str, Any]:
    async def _run() -> dict[str, Any]:
        reader, writer = await asyncio.open_unix_connection(socket_path)
        try:
            writer.write((json.dumps(payload) + "\n").encode())
            await writer.drain()
            line = await reader.readline()
            return json.loads(line.decode())
        finally:
            writer.close()
            await writer.wait_closed()

    return await asyncio.wait_for(_run(), timeout=timeout)


def peer_sandbox_context(sock: socket.socket | None) -> tuple[str | None, str | None, str | None]:
    """Read sandbox paths from the TCP client that connected to the proxy."""
    cred = peer_cred(sock)
    if cred is None:
        return None, None, None
    pid, uid, _gid = cred
    cwd: str | None = None
    home: str | None = None
    project_root: str | None = None
    if pid > 0:
        cwd, home, project_root = context_from_pid(pid)
    home = home or home_from_uid(uid)
    return cwd, home, project_root


def sandbox_context(client_sock: socket.socket | None = None) -> tuple[str | None, str | None, str | None, int | None, int | None]:
    peer_cwd, peer_home, peer_project = peer_sandbox_context(client_sock)
    cred = peer_cred(client_sock)
    pid = cred[0] if cred else None
    uid = cred[1] if cred else None
    file_ctx = read_session_context()
    # Do not fall back to os.getcwd() — the proxy often runs with cwd=/, which would
    # mis-resolve project policy to /.agent-sandbox/policy.json.
    cwd = (
        peer_cwd
        or file_ctx.get("cwd")
        or os.environ.get("AGENT_SANDBOX_CWD")
    )
    home = (
        peer_home
        or file_ctx.get("home")
        or home_from_uid(uid)
        or os.environ.get("AGENT_SANDBOX_HOME")
        or os.environ.get("HOME")
    )
    project_root = (
        peer_project
        or file_ctx.get("project_root")
        or os.environ.get("AGENT_SANDBOX_PROJECT_ROOT")
    )
    if cwd and not project_root:
        try:
            cwd_path = Path(cwd).resolve()
            existing = discover_project_policy(cwd_path)
            if existing:
                project_root = str(existing.parent.parent)
        except OSError:
            pass
    home = home or infer_home_from_paths(project_root, cwd)
    return cwd, home, project_root, pid, uid


async def open_upstream(host: str, port: int) -> tuple[asyncio.StreamReader, asyncio.StreamWriter]:
    """Outbound connect from the sandbox netns (IPv4 only — no v6 route)."""
    return await asyncio.wait_for(
        asyncio.open_connection(host, port, family=socket.AF_INET),
        timeout=30.0,
    )


async def read_client_peek(reader: asyncio.StreamReader) -> bytes:
    try:
        return await asyncio.wait_for(
            reader.read(CLIENT_PEEK_BYTES), CLIENT_PEEK_TIMEOUT
        )
    except TimeoutError:
        return b""


async def check_destination(
    args: argparse.Namespace,
    policy_host: str,
    connect_host: str,
    port: int,
    scheme: str,
    *,
    client_sock: socket.socket | None = None,
) -> bool:
    cwd, home, project_root, pid, uid = sandbox_context(client_sock)
    if home:
        write_session_context(cwd=cwd, home=home, project_root=project_root)
    url = f"{scheme}://{policy_host}:{port}"
    payload: dict[str, Any] = {
        "op": "check",
        "host": policy_host,
        "port": port,
        "scheme": scheme,
        "url": url,
        "cwd": cwd,
        "home": home,
        "project_root": project_root,
        "connect_host": connect_host,
    }
    if pid is not None:
        payload["pid"] = pid
    if uid is not None:
        payload["uid"] = uid
    resp = await policy_request(
        args.policy_socket,
        payload,
        timeout=args.policy_timeout,
    )
    allowed = bool(resp.get("allowed"))
    source = resp.get("source")
    if allowed and source:
        log(f"policy allow {policy_host}:{port} ({source})")
    elif allowed:
        log(f"policy allow {policy_host}:{port}")
    elif resp.get("ok"):
        if source == "deny":
            log(f"policy deny {policy_host}:{port} (project policy)")
        else:
            log(f"policy blocked {policy_host}:{port} (not in allow list)")
    else:
        log(f"policy check error {policy_host}:{port}: {resp.get('error', resp)}")
    return allowed


async def pipe_streams(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    remote_reader: asyncio.StreamReader,
    remote_writer: asyncio.StreamWriter,
    *,
    client_prefix: bytes = b"",
) -> None:
    async def pipe(
        src: asyncio.StreamReader,
        dst: asyncio.StreamWriter,
        prefix: bytes = b"",
    ) -> None:
        try:
            if prefix:
                dst.write(prefix)
                await dst.drain()
            while True:
                chunk = await src.read(65536)
                if not chunk:
                    break
                dst.write(chunk)
                await dst.drain()
        except Exception:
            pass
        finally:
            with contextlib.suppress(Exception):
                dst.close()

    await asyncio.gather(
        pipe(reader, remote_writer, client_prefix),
        pipe(remote_reader, writer),
    )


async def handle_transparent(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    connect_host: str,
    port: int,
    args: argparse.Namespace,
    *,
    client_sock: socket.socket | None = None,
) -> None:
    scheme = "https" if port == 443 else "http"
    initial = await read_client_peek(reader)
    policy_host, upstream_host = policy_host_for_connect(
        connect_host, initial_data=initial or None
    )
    if policy_host != connect_host:
        log(f"transparent policy host {policy_host} (connect {connect_host}:{port})")

    if not await check_destination(
        args, policy_host, upstream_host, port, scheme, client_sock=client_sock
    ):
        log(f"transparent deny {policy_host}:{port}")
        writer.close()
        with contextlib.suppress(Exception):
            await writer.wait_closed()
        return

    # Transparent mode already gives us the real pre-DNAT destination IP.
    # Use it directly so tunnel establishment does not depend on local DNS.
    upstream_target = upstream_host
    try:
        remote_reader, remote_writer = await open_upstream(upstream_target, port)
        log(
            f"transparent upstream {upstream_target}:{port} connected for {policy_host}"
        )
    except OSError as exc:
        log(f"transparent upstream {upstream_host}:{port} failed: {exc}")
        writer.close()
        with contextlib.suppress(Exception):
            await writer.wait_closed()
        return

    await pipe_streams(
        reader,
        writer,
        remote_reader,
        remote_writer,
        client_prefix=initial,
    )


async def handle_connect(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    host: str,
    port: int,
    args: argparse.Namespace,
    *,
    client_sock: socket.socket | None = None,
) -> None:
    policy_host, connect_host = policy_host_for_connect(host)
    if not await check_destination(
        args, policy_host, connect_host, port, "https", client_sock=client_sock
    ):
        writer.write(
            b"HTTP/1.1 403 Forbidden\r\nContent-Type: text/plain\r\n\r\nDenied by agent-sandbox policy\n"
        )
        await writer.drain()
        return

    try:
        remote_reader, remote_writer = await open_upstream(connect_host, port)
        log(f"connect upstream {connect_host}:{port} connected (policy {policy_host})")
    except TimeoutError as exc:
        detail = str(exc).strip() or repr(exc)
        log(
            f"connect upstream {connect_host}:{port} timed out "
            f"(policy {policy_host}): {detail}"
        )
        writer.write(
            (
                "HTTP/1.1 504 Gateway Timeout\r\n"
                "Content-Type: text/plain\r\n\r\n"
                f"{detail}\n"
            ).encode()
        )
        await writer.drain()
        return
    except OSError as exc:
        detail = str(exc).strip() or repr(exc)
        log(
            f"connect upstream {connect_host}:{port} failed "
            f"(policy {policy_host}): {detail}"
        )
        writer.write(
            (
                "HTTP/1.1 502 Bad Gateway\r\n"
                "Content-Type: text/plain\r\n\r\n"
                f"{detail}\n"
            ).encode()
        )
        await writer.drain()
        return
    except Exception as exc:
        detail = str(exc).strip() or repr(exc)
        log(
            f"connect upstream {connect_host}:{port} unexpected error "
            f"(policy {policy_host}): {detail}"
        )
        writer.write(
            (
                "HTTP/1.1 502 Bad Gateway\r\n"
                "Content-Type: text/plain\r\n\r\n"
                f"{detail}\n"
            ).encode()
        )
        await writer.drain()
        return

    writer.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
    await writer.drain()
    await pipe_streams(reader, writer, remote_reader, remote_writer)


async def handle_client(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    args: argparse.Namespace,
) -> None:
    peer = writer.get_extra_info("peername")
    sock = writer.get_extra_info("socket")
    try:
        orig: tuple[str, int] | None = None
        if args.transparent and sock is not None:
            orig = get_original_dst(sock)

        listen_host = args.listen_host
        if orig is not None:
            orig_host, orig_port = orig
            redirected = orig_port in (80, 443) and not (
                orig_host == listen_host and orig_port == args.listen_port
            )
            if redirected:
                log(f"transparent {peer} -> {orig_host}:{orig_port}")
                await handle_transparent(
                    reader,
                    writer,
                    orig_host,
                    orig_port,
                    args,
                    client_sock=sock,
                )
                return

        header = await reader.readline()
        if not header:
            return
        line = header.decode(errors="replace").strip()
        parts = line.split()
        if len(parts) < 2:
            writer.write(b"HTTP/1.1 400 Bad Request\r\n\r\n")
            await writer.drain()
            return
        method, target = parts[0].upper(), parts[1]
        while True:
            h = await reader.readline()
            if h in (b"\r\n", b"\n", b""):
                break
        if method != "CONNECT":
            writer.write(b"HTTP/1.1 405 Method Not Allowed\r\n\r\n")
            await writer.drain()
            return
        if ":" in target:
            host, port_s = target.rsplit(":", 1)
            port = int(port_s)
        else:
            host, port = target, 443
        log(f"connect {peer} -> {host}:{port}")
        await handle_connect(
            reader, writer, host, port, args, client_sock=sock
        )
    except Exception as exc:
        log(f"proxy client {peer} error: {exc}")
    finally:
        writer.close()
        with contextlib.suppress(Exception):
            await writer.wait_closed()


async def main_async(args: argparse.Namespace) -> None:
    server = await asyncio.start_server(
        lambda r, w: handle_client(r, w, args),
        host=args.listen_host,
        port=args.listen_port,
        reuse_address=True,
    )
    addrs = ", ".join(str(s.getsockname()) for s in server.sockets or [])
    modes = ["explicit CONNECT"]
    if args.transparent:
        modes.append("transparent")
    log(f"proxy listening on {addrs} ({', '.join(modes)})")
    async with server:
        await server.serve_forever()


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--listen-host", default="127.0.0.1")
    p.add_argument("--listen-port", type=int, default=17888)
    p.add_argument("--policy-socket", default="/run/agent-sandbox/policy.sock")
    p.add_argument(
        "--policy-timeout",
        type=float,
        default=35.0,
        help="Max seconds to wait for policyd RPCs (daemon health safety cap)",
    )
    p.add_argument(
        "--transparent",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Handle nftables-DNATed TCP 80/443 using SO_ORIGINAL_DST",
    )
    return p.parse_args()


def main():
    args = parse_args()
    try:
        asyncio.run(main_async(args))
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
