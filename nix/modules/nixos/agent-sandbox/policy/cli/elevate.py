#!/usr/bin/env python3
"""Request host-side root execution via agent-sandbox policyd."""

from __future__ import annotations

import json
import os
import socket
import sys

DEFAULT_SOCKET = "/run/agent-sandbox/policy.sock"


def policy_socket() -> str:
    return os.environ.get("AGENT_SANDBOX_POLICY_SOCKET", DEFAULT_SOCKET)


def rpc(req: dict) -> dict:
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.connect(policy_socket())
        sock.sendall((json.dumps(req) + "\n").encode())
        buf = b""
        while b"\n" not in buf:
            chunk = sock.recv(65536)
            if not chunk:
                break
            buf += chunk
        line, _, _ = buf.partition(b"\n")
        if not line:
            return {"ok": False, "error": "no response from policyd"}
        return json.loads(line.decode())
    finally:
        sock.close()


def main() -> int:
    argv = sys.argv[1:]
    if not argv:
        print("agent-sandbox: usage: sudo <command>", file=sys.stderr)
        return 1

    resp = rpc(
        {
            "op": "elevate",
            "argv": argv,
            "cwd": os.environ.get("AGENT_SANDBOX_CWD"),
            "home": os.environ.get("AGENT_SANDBOX_HOME"),
            "project_root": os.environ.get("AGENT_SANDBOX_PROJECT_ROOT"),
        }
    )

    if not resp.get("ok"):
        err = str(resp.get("error", "policyd error"))
        print(f"agent-sandbox: {err}", file=sys.stderr)
        return 1

    if not resp.get("allowed"):
        msg = str(resp.get("stderr") or "agent-sandbox: elevation denied").strip()
        print(msg, file=sys.stderr)
        return int(resp.get("exit_code", 1))

    stdout = resp.get("stdout") or ""
    stderr = resp.get("stderr") or ""
    if stdout:
        sys.stdout.write(stdout if stdout.endswith("\n") else stdout + "\n")
    if stderr:
        sys.stderr.write(stderr if stderr.endswith("\n") else stderr + "\n")

    return int(resp.get("exit_code", 0))


if __name__ == "__main__":
    raise SystemExit(main())
