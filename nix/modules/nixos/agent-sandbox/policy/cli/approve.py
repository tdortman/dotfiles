#!/usr/bin/env python3
"""Manage agent-sandbox policy approvals from the host CLI."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from typing import Any

DEFAULT_SOCKET = "/run/agent-sandbox/policy.sock"


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


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Manage pending agent-sandbox policy approvals")
    p.add_argument("--socket", default=DEFAULT_SOCKET)
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("pending", help="List pending elevation requests")

    approve_p = sub.add_parser(
        "approve",
        help="Approve a pending elevation request by id",
    )
    approve_p.add_argument("id", help="Pending id from `pending` or policyd logs")
    approve_p.add_argument(
        "scope",
        choices=["once"],
        help="Elevation approvals always run once",
    )
    approve_p.add_argument("--home", default=None)
    approve_p.add_argument("--cwd", default=None)
    approve_p.add_argument("--project-root", default=None)

    approve_host_p = sub.add_parser(
        "approve-host",
        help="Approve a host+port directly (fail-fast network flow)",
    )
    approve_host_p.add_argument("host")
    approve_host_p.add_argument("port", type=int)
    approve_host_p.add_argument(
        "scope",
        choices=["once", "session", "global", "project"],
        help="Approval scope",
    )
    approve_host_p.add_argument("--home", default=None)
    approve_host_p.add_argument("--cwd", default=None)
    approve_host_p.add_argument("--project-root", default=None)
    approve_host_p.add_argument("--session-id", default=None)

    deny_p = sub.add_parser("deny", help="Deny a pending request by id")
    deny_p.add_argument("id")

    args = p.parse_args(argv)
    base: dict[str, Any] = {}
    if hasattr(args, "home") and args.home:
        base["home"] = args.home
    if hasattr(args, "cwd") and args.cwd:
        base["cwd"] = args.cwd
    if hasattr(args, "project_root") and args.project_root:
        base["project_root"] = args.project_root

    if args.cmd == "pending":
        resp = asyncio.run(
            policy_rpc({"op": "status", **base}, args.socket)
        )
        if not resp.get("ok"):
            print(resp.get("error", resp), file=sys.stderr)
            return 1
        pending = resp.get("pending") or []
        if not pending:
            print("No pending approvals.")
            return 0
        for item in pending:
            if not isinstance(item, dict):
                continue
            argv_list = item.get("argv") or []
            print(f"{item.get('id')}\televation\t{' '.join(argv_list)}")
        return 0

    if args.cmd == "approve":
        resp = asyncio.run(
            policy_rpc(
                {"op": "approve", "id": args.id, "scope": args.scope, **base},
                args.socket,
            )
        )
    elif args.cmd == "approve-host":
        payload = {
            "op": "approve_host",
            "host": args.host,
            "port": args.port,
            "scope": args.scope,
            **base,
        }
        if args.session_id:
            payload["session_id"] = args.session_id
        resp = asyncio.run(policy_rpc(payload, args.socket))
    else:
        resp = asyncio.run(
            policy_rpc({"op": "deny", "id": args.id, **base}, args.socket)
        )

    print(json.dumps(resp, indent=2))
    return 0 if resp.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
