#!/usr/bin/env python3
"""Tests for policyd allow-once and per-UI session semantics."""

from __future__ import annotations

import argparse
import asyncio
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from support import load_module

policyd = load_module("policyd", "daemon/policyd.py")


class PolicyStoreOnceTests(unittest.TestCase):
    def _store(self) -> policyd.PolicyStore:
        with tempfile.TemporaryDirectory() as tmp:
            args = argparse.Namespace(
                declarative=str(Path(tmp) / "declarative.json"),
                export_json=str(Path(tmp) / "export.json"),
                export_nix="",
                approval_timeout=30.0,
                interactive_approval=True,
            )
            Path(args.declarative).write_text(
                '{"network":{"allow":[],"deny":[]},"sudo":{"allow":[],"deny":[]}}\n', encoding="utf-8"
            )
            return policyd.PolicyStore(args)

    def test_allow_once_consumed_after_first_check(self) -> None:
        store = self._store()
        store.once_allow.add(("example.com", 443))
        self.assertTrue(
            store.is_allowed("example.com", 443, "/tmp", "/home/user", consume_once=True)
        )
        self.assertFalse(store.is_allowed("example.com", 443, "/tmp", "/home/user"))
        self.assertIsNone(store.allow_source("example.com", 443, "/tmp", "/home/user"))

    def test_session_allow_scoped_to_ui_connection(self) -> None:
        store = self._store()
        writer = mock.Mock()
        session_id = store.start_ui_session(writer)
        store.session_allow[session_id] = {("example.com", 443)}
        for _ in range(3):
            self.assertTrue(store.is_allowed("example.com", 443, "/tmp", "/home/user"))
        store.end_ui_session(writer)
        self.assertFalse(store.is_allowed("example.com", 443, "/tmp", "/home/user"))
        self.assertIsNone(store.allow_source("example.com", 443, "/tmp", "/home/user"))

    def test_approve_host_session_requires_session_id(self) -> None:
        store = self._store()
        resp = asyncio.run(
            store.approve_host(
                "example.com",
                443,
                "session",
                "/tmp",
                "/home/user",
            )
        )
        self.assertFalse(resp["ok"])


    def test_project_approve_host_uses_project_root(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / "dotfiles"
            repo.mkdir()
            ephemeral = repo / "omp-python-runner"
            ephemeral.mkdir()
            args = argparse.Namespace(
                declarative=str(Path(tmp) / "declarative.json"),
                export_json=str(Path(tmp) / "export.json"),
                export_nix="",
                approval_timeout=30.0,
                interactive_approval=True,
            )
            Path(args.declarative).write_text(
                '{"network":{"allow":[],"deny":[]},"sudo":{"allow":[],"deny":[]}}\n', encoding="utf-8"
            )
            store = policyd.PolicyStore(args)
            resp = asyncio.run(
                store.approve_host(
                    "example.com",
                    443,
                    "project",
                    str(ephemeral),
                    "/home/user",
                    project_root=str(repo),
                )
            )
            self.assertTrue(resp["ok"])
            policy_file = repo / ".agent-sandbox" / "policy.json"
            self.assertTrue(policy_file.is_file())
            data = json.loads(policy_file.read_text(encoding="utf-8"))
            self.assertEqual(data["network"]["allow"][0]["host"], "example.com")

    def test_approve_host_once_consumes_after_single_check(self) -> None:
        store = self._store()
        resp = asyncio.run(
            store.approve_host("example.com", 443, "once", "/tmp", "/home/user")
        )
        self.assertTrue(resp["ok"])
        self.assertEqual(
            store.allow_source("example.com", 443, "/tmp", "/home/user"),
            "once",
        )
        self.assertTrue(
            store.is_allowed(
                "example.com",
                443,
                "/tmp",
                "/home/user",
                consume_once=True,
            )
        )
        self.assertFalse(store.is_allowed("example.com", 443, "/tmp", "/home/user"))

    def test_approve_host_rejects_project_deny(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            declarative = tmp_path / "declarative.json"
            declarative.write_text(
                '{"network":{"allow":[],"deny":[]},"sudo":{"allow":[],"deny":[]}}\n', encoding="utf-8"
            )
            project_dir = tmp_path / "proj"
            project_dir.mkdir()
            project_policy = project_dir / ".agent-sandbox" / "policy.json"
            project_policy.parent.mkdir(parents=True)
            project_policy.write_text(
                json.dumps({
                        "network": {
                                                "allow": [],
                                                "deny": [
                                                                        {
                                                                                                "host": "blocked.example",
                                                                                                "port": 443
                                                                        }
                                                ]
                        },
                        "sudo": {
                                                "allow": [],
                                                "deny": []
                        }
})
                + "\n",
                encoding="utf-8",
            )
            store = policyd.PolicyStore(
                argparse.Namespace(
                    declarative=str(declarative),
                    export_json=str(tmp_path / "export.json"),
                    export_nix="",
                    approval_timeout=30.0,
                    interactive_approval=True,
                )
            )
            resp = asyncio.run(
                store.approve_host(
                    "blocked.example",
                    443,
                    "once",
                    str(project_dir),
                    "/home/user",
                    project_root=str(project_dir),
                )
            )
            self.assertFalse(resp["ok"])
            self.assertIn("denied", resp["error"])

    def test_merged_for_deny_beats_allow(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            declarative = tmp_path / "declarative.json"
            declarative.write_text(
                json.dumps({
                        "network": {
                                                "allow": [
                                                                        {
                                                                                                "host": "example.com",
                                                                                                "port": 443
                                                                        }
                                                ],
                                                "deny": []
                        },
                        "sudo": {
                                                "allow": [],
                                                "deny": []
                        }
})
                + "\n",
                encoding="utf-8",
            )
            project_dir = tmp_path / "proj"
            project_dir.mkdir()
            project_policy = project_dir / ".agent-sandbox" / "policy.json"
            project_policy.parent.mkdir(parents=True)
            project_policy.write_text(
                json.dumps({
                        "network": {
                                                "allow": [],
                                                "deny": [
                                                                        {
                                                                                                "host": "example.com",
                                                                                                "port": 443
                                                                        }
                                                ]
                        },
                        "sudo": {
                                                "allow": [],
                                                "deny": []
                        }
})
                + "\n",
                encoding="utf-8",
            )
            args = argparse.Namespace(
                declarative=str(declarative),
                export_json=str(tmp_path / "export.json"),
                export_nix="",
                approval_timeout=30.0,
                interactive_approval=True,
            )
            store = policyd.PolicyStore(args)
            merged = store.merged_for(str(project_dir), None, project_root=str(project_dir))
            self.assertEqual(merged["network"]["allow"], [])
            self.assertEqual(len(merged["network"]["deny"]), 1)
            self.assertFalse(
                store.is_allowed("example.com", 443, str(project_dir), None, project_root=str(project_dir))
            )
            self.assertEqual(
                store.allow_source("example.com", 443, str(project_dir), None, project_root=str(project_dir)),
                "deny",
            )

    def test_deny_beats_session_and_once(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            declarative = tmp_path / "declarative.json"
            declarative.write_text(
                '{"network":{"allow":[],"deny":[]},"sudo":{"allow":[],"deny":[]}}\n', encoding="utf-8"
            )
            project_dir = tmp_path / "proj"
            project_dir.mkdir()
            project_policy = project_dir / ".agent-sandbox" / "policy.json"
            project_policy.parent.mkdir(parents=True)
            project_policy.write_text(
                json.dumps({
                        "network": {
                                                "allow": [],
                                                "deny": [
                                                                        {
                                                                                                "host": "blocked.example",
                                                                                                "port": 443
                                                                        }
                                                ]
                        },
                        "sudo": {
                                                "allow": [],
                                                "deny": []
                        }
})
                + "\n",
                encoding="utf-8",
            )
            store = policyd.PolicyStore(
                argparse.Namespace(
                    declarative=str(declarative),
                    export_json=str(tmp_path / "export.json"),
                    export_nix="",
                    approval_timeout=30.0,
                    interactive_approval=True,
                )
            )
            store.once_allow.add(("blocked.example", 443))
            writer = mock.Mock()
            session_id = store.start_ui_session(writer)
            store.session_allow[session_id] = {("blocked.example", 443)}
            self.assertEqual(
                store.allow_source(
                    "blocked.example",
                    443,
                    str(project_dir),
                    None,
                    project_root=str(project_dir),
                ),
                "deny",
            )
            self.assertFalse(
                store.is_allowed(
                    "blocked.example",
                    443,
                    str(project_dir),
                    None,
                    project_root=str(project_dir),
                )
            )

    def test_request_network_approval_not_sent_when_denied(self) -> None:
        async def run() -> None:
            with tempfile.TemporaryDirectory() as tmp:
                tmp_path = Path(tmp)
                declarative = tmp_path / "declarative.json"
                declarative.write_text(
                    '{"network":{"allow":[],"deny":[]},"sudo":{"allow":[],"deny":[]}}\n', encoding="utf-8"
                )
                project_dir = tmp_path / "proj"
                project_dir.mkdir()
                project_policy = project_dir / ".agent-sandbox" / "policy.json"
                project_policy.parent.mkdir(parents=True)
                project_policy.write_text(
                    json.dumps({
                        "network": {
                                                "allow": [],
                                                "deny": [
                                                                        {
                                                                                                "host": "blocked.example",
                                                                                                "port": 443
                                                                        }
                                                ]
                        },
                        "sudo": {
                                                "allow": [],
                                                "deny": []
                        }
})
                    + "\n",
                    encoding="utf-8",
                )
                store = policyd.PolicyStore(
                    argparse.Namespace(
                        declarative=str(declarative),
                        export_json=str(tmp_path / "export.json"),
                        export_nix="",
                        approval_timeout=30.0,
                        interactive_approval=True,
                    )
                )
                notify = mock.AsyncMock()
                with mock.patch.object(store, "notify_ui", notify):
                    resp = await store.request_network_approval(
                        "blocked.example",
                        443,
                        "https",
                        "https://blocked.example:443",
                        str(project_dir),
                        "/home/user",
                        project_root=str(project_dir),
                    )
                notify.assert_not_awaited()
                self.assertFalse(resp["allowed"])
                self.assertEqual(resp["source"], "deny")
                self.assertEqual(store.pending, {})

        asyncio.run(run())

    def test_project_approve_host_rejects_without_project_root(self) -> None:
        store = self._store()
        resp = asyncio.run(
            store.approve_host("example.com", 443, "project", "/", "/home/user")
        )
        self.assertFalse(resp["ok"])
        self.assertIn("project_root", resp["error"])

    def test_resolve_context_uses_ui_session_for_project_deny(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            declarative = tmp_path / "declarative.json"
            declarative.write_text(
                '{"network":{"allow":[],"deny":[]},"sudo":{"allow":[],"deny":[]}}\n', encoding="utf-8"
            )
            project_dir = tmp_path / "proj"
            project_dir.mkdir()
            project_policy = project_dir / ".agent-sandbox" / "policy.json"
            project_policy.parent.mkdir(parents=True)
            project_policy.write_text(
                json.dumps({
                        "network": {
                                                "allow": [],
                                                "deny": [
                                                                        {
                                                                                                "host": "api.xiaomimimo.com",
                                                                                                "port": 443
                                                                        }
                                                ]
                        },
                        "sudo": {
                                                "allow": [],
                                                "deny": []
                        }
})
                + "\n",
                encoding="utf-8",
            )
            store = policyd.PolicyStore(
                argparse.Namespace(
                    declarative=str(declarative),
                    export_json=str(tmp_path / "export.json"),
                    export_nix="",
                    approval_timeout=30.0,
                    interactive_approval=True,
                )
            )
            writer = mock.Mock()
            store.start_ui_session(
                writer,
                cwd=str(project_dir),
                home="/home/user",
                project_root=str(project_dir),
            )
            self.assertEqual(
                store.allow_source(
                    "api.xiaomimimo.com", 443, None, None, None
                ),
                "deny",
            )

    def test_resolve_context_reads_session_context_file(self) -> None:
        import session_context as sc

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            declarative = tmp_path / "declarative.json"
            declarative.write_text(
                '{"network":{"allow":[],"deny":[]},"sudo":{"allow":[],"deny":[]}}\n', encoding="utf-8"
            )
            project_dir = tmp_path / "proj"
            project_dir.mkdir()
            project_policy = project_dir / ".agent-sandbox" / "policy.json"
            project_policy.parent.mkdir(parents=True)
            project_policy.write_text(
                json.dumps({
                        "network": {
                                                "allow": [],
                                                "deny": [
                                                                        {
                                                                                                "host": "api.xiaomimimo.com",
                                                                                                "port": 443
                                                                        }
                                                ]
                        },
                        "sudo": {
                                                "allow": [],
                                                "deny": []
                        }
})
                + "\n",
                encoding="utf-8",
            )
            old_path = sc.SESSION_CONTEXT_PATH
            sc.SESSION_CONTEXT_PATH = tmp_path / "session-context.json"
            self.addCleanup(lambda: setattr(sc, "SESSION_CONTEXT_PATH", old_path))
            sc.write_session_context(
                cwd=str(project_dir),
                home="/home/user",
                project_root=str(project_dir),
            )
            store = policyd.PolicyStore(
                argparse.Namespace(
                    declarative=str(declarative),
                    export_json=str(tmp_path / "export.json"),
                    export_nix="",
                    approval_timeout=30.0,
                    interactive_approval=True,
                )
            )
            self.assertEqual(
                store.allow_source("api.xiaomimimo.com", 443, None, None, None),
                "deny",
            )
            sc.clear_session_context()

    def test_global_allow_without_home_infers_from_project_root(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / "home" / "tim"
            config = home / ".config" / "agent-sandbox"
            config.mkdir(parents=True)
            (config / "policy.json").write_text(
                json.dumps({
                        "network": {
                                                "allow": [
                                                                        {
                                                                                                "host": "api.xiaomimimo.com",
                                                                                                "port": 443
                                                                        }
                                                ],
                                                "deny": []
                        },
                        "sudo": {
                                                "allow": [],
                                                "deny": []
                        }
})
                + "\n",
                encoding="utf-8",
            )
            repo = home / "dotfiles"
            repo.mkdir()
            args = argparse.Namespace(
                declarative=str(Path(tmp) / "declarative.json"),
                export_json=str(Path(tmp) / "export.json"),
                export_nix="",
                approval_timeout=30.0,
                interactive_approval=True,
            )
            Path(args.declarative).write_text(
                '{"network":{"allow":[],"deny":[]},"sudo":{"allow":[],"deny":[]}}\n', encoding="utf-8"
            )
            store = policyd.PolicyStore(args)
            self.assertEqual(
                store.allow_source(
                    "api.xiaomimimo.com", 443, None, None, str(repo)
                ),
                "allow",
            )

    def test_global_allow_from_uid_when_paths_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / "home" / "tim"
            config = home / ".config" / "agent-sandbox"
            config.mkdir(parents=True)
            (config / "policy.json").write_text(
                json.dumps({
                        "network": {
                                                "allow": [
                                                                        {
                                                                                                "host": "api.xiaomimimo.com",
                                                                                                "port": 443
                                                                        }
                                                ],
                                                "deny": []
                        },
                        "sudo": {
                                                "allow": [],
                                                "deny": []
                        }
})
                + "\n",
                encoding="utf-8",
            )
            args = argparse.Namespace(
                declarative=str(Path(tmp) / "declarative.json"),
                export_json=str(Path(tmp) / "export.json"),
                export_nix="",
                approval_timeout=30.0,
                interactive_approval=True,
            )
            Path(args.declarative).write_text(
                '{"network":{"allow":[],"deny":[]},"sudo":{"allow":[],"deny":[]}}\n', encoding="utf-8"
            )
            store = policyd.PolicyStore(args)
            with mock.patch.object(
                policyd, "home_from_uid", return_value=str(home)
            ):
                cwd, resolved_home, project_root = store.resolve_context(
                    None, None, None, uid=1000
                )
                self.assertEqual(resolved_home, str(home))
                self.assertEqual(
                    store.allow_source(
                        "api.xiaomimimo.com", 443, cwd, resolved_home, project_root
                    ),
                    "allow",
                )

    def test_project_deny_with_home_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / "home" / "tim"
            repo = home / "dotfiles"
            policy_dir = repo / ".agent-sandbox"
            policy_dir.mkdir(parents=True)
            (policy_dir / "policy.json").write_text(
                json.dumps({
                        "network": {
                                                "allow": [],
                                                "deny": [
                                                                        {
                                                                                                "host": "chatgpt.com",
                                                                                                "port": 443
                                                                        }
                                                ]
                        },
                        "sudo": {
                                                "allow": [],
                                                "deny": []
                        }
})
                + "\n",
                encoding="utf-8",
            )
            config = home / ".config" / "agent-sandbox"
            config.mkdir(parents=True)
            (config / "policy.json").write_text(
                json.dumps({
                        "network": {
                                                "allow": [
                                                                        {
                                                                                                "host": "chatgpt.com",
                                                                                                "port": 443,
                                                                                                "comment": "global"
                                                                        }
                                                ],
                                                "deny": []
                        },
                        "sudo": {
                                                "allow": [],
                                                "deny": []
                        }
})
                + "\n",
                encoding="utf-8",
            )
            args = argparse.Namespace(
                declarative=str(Path(tmp) / "declarative.json"),
                export_json=str(Path(tmp) / "export.json"),
                export_nix="",
                approval_timeout=30.0,
                interactive_approval=True,
            )
            Path(args.declarative).write_text(
                json.dumps({
                        "network": {
                                                "allow": [
                                                                        {
                                                                                                "host": "chatgpt.com",
                                                                                                "port": 443
                                                                        }
                                                ],
                                                "deny": []
                        },
                        "sudo": {
                                                "allow": [],
                                                "deny": []
                        }
})
                + "\n",
                encoding="utf-8",
            )
            store = policyd.PolicyStore(args)
            with mock.patch.object(
                policyd, "home_from_uid", return_value=str(home)
            ):
                self.assertEqual(
                    store.allow_source("chatgpt.com", 443, None, str(home), None),
                    "deny",
                )

    def test_project_deny_persists_via_session_context(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / "home" / "tim"
            repo = home / "dotfiles"
            policy_dir = repo / ".agent-sandbox"
            policy_dir.mkdir(parents=True)
            (policy_dir / "policy.json").write_text(
                json.dumps({
                        "network": {
                                                "allow": [],
                                                "deny": [
                                                                        {
                                                                                                "host": "chatgpt.com",
                                                                                                "port": 443
                                                                        }
                                                ]
                        },
                        "sudo": {
                                                "allow": [],
                                                "deny": []
                        }
})
                + "\n",
                encoding="utf-8",
            )
            args = argparse.Namespace(
                declarative=str(Path(tmp) / "declarative.json"),
                export_json=str(Path(tmp) / "export.json"),
                export_nix="",
                approval_timeout=30.0,
                interactive_approval=True,
            )
            Path(args.declarative).write_text(
                json.dumps({
                        "network": {
                                                "allow": [
                                                                        {
                                                                                                "host": "chatgpt.com",
                                                                                                "port": 443
                                                                        }
                                                ],
                                                "deny": []
                        },
                        "sudo": {
                                                "allow": [],
                                                "deny": []
                        }
})
                + "\n",
                encoding="utf-8",
            )
            store = policyd.PolicyStore(args)
            import session_context as sc

            sc.SESSION_CONTEXT_PATH = Path(tmp) / "session-context.json"
            sc.write_session_context(home=str(home))
            self.assertEqual(
                store.allow_source("chatgpt.com", 443, None, None, None),
                "deny",
            )
            sc.clear_session_context()

    def test_proxy_check_disconnect_does_not_clear_session_context(self) -> None:
        store = self._store()
        import session_context as sc

        with tempfile.TemporaryDirectory() as tmp:
            sc.SESSION_CONTEXT_PATH = Path(tmp) / "session-context.json"
            sc.write_session_context(home="/home/tim")
            store.end_ui_session(mock.Mock())
            ctx = sc.read_session_context()
            self.assertEqual(ctx["home"], "/home/tim")
            sc.clear_session_context()

    def test_blocking_approve_once_does_not_auto_allow_next_check(self) -> None:
        async def run() -> None:
            with tempfile.TemporaryDirectory() as tmp:
                tmp_path = Path(tmp)
                declarative = tmp_path / "declarative.json"
                declarative.write_text(
                    '{"network":{"allow":[],"deny":[]},"sudo":{"allow":[],"deny":[]}}\n', encoding="utf-8"
                )
                store = policyd.PolicyStore(
                    argparse.Namespace(
                        declarative=str(declarative),
                        export_json=str(tmp_path / "export.json"),
                        export_nix="",
                        approval_timeout=30.0,
                        interactive_approval=True,
                    )
                )
                server = policyd.PolicyServer(store, Path("/tmp/policyd-test.sock"))
                writer = mock.Mock()
                writer.write = mock.Mock()
                writer.drain = mock.AsyncMock(return_value=None)
                store.start_ui_session(writer)
                host = "once-race.test"

                with mock.patch.object(policyd, "write_session_context"):
                    first = asyncio.create_task(
                        server._dispatch(
                            {
                                "op": "check",
                                "host": host,
                                "connect_host": host,
                                "port": 443,
                                "scheme": "https",
                                "url": f"https://{host}:443",
                                "cwd": "/tmp",
                                "home": "/home/user",
                            },
                            mock.Mock(),
                        )
                    )
                    await asyncio.sleep(0.05)
                    pending_id = next(iter(store.pending))
                    await store.approve(pending_id, "once", "/tmp", "/home/user")
                    first_resp = await asyncio.wait_for(first, timeout=1.0)
                    self.assertTrue(first_resp["allowed"])
                    self.assertEqual(store.once_allow, set())

                    second = asyncio.create_task(
                        server._dispatch(
                            {
                                "op": "check",
                                "host": host,
                                "connect_host": host,
                                "port": 443,
                                "scheme": "https",
                                "url": f"https://{host}:443",
                                "cwd": "/tmp",
                                "home": "/home/user",
                            },
                            mock.Mock(),
                        )
                    )
                    await asyncio.sleep(0.05)
                    self.assertEqual(len(store.pending), 1)
                    second_id = next(iter(store.pending))
                    store.deny(second_id)
                    second_resp = await asyncio.wait_for(second, timeout=1.0)
                    self.assertFalse(second_resp["allowed"])

        asyncio.run(run())

    def test_request_network_approval_waits_for_ui_connect(self) -> None:
        async def run() -> None:
            store = self._store()
            host = "ui-wait.test"

            async def register_and_approve() -> None:
                await asyncio.sleep(0.15)
                writer = mock.Mock()
                writer.write = mock.Mock()
                writer.drain = mock.AsyncMock(return_value=None)
                store.start_ui_session(writer)
                pending_id = next(iter(store.pending))
                await store.approve(pending_id, "once", "/tmp", "/home/user")

            ui_task = asyncio.create_task(register_and_approve())
            resp = await store.request_network_approval(
                host,
                443,
                "https",
                f"https://{host}:443",
                "/tmp",
                "/home/user",
            )
            await ui_task
            self.assertTrue(resp["allowed"])
            self.assertEqual(resp.get("source"), "once")

        asyncio.run(run())

    def test_unknown_host_check_blocks_until_approved(self) -> None:
        async def run() -> None:
            store = self._store()
            server = policyd.PolicyServer(store, Path("/tmp/policyd-test.sock"))
            writer = mock.Mock()
            writer.write = mock.Mock()
            writer.drain = mock.AsyncMock(return_value=None)
            store.start_ui_session(writer)

            with mock.patch.object(policyd, "write_session_context"):
                check_task = asyncio.create_task(
                    server._dispatch(
                        {
                            "op": "check",
                            "host": "example.com",
                            "connect_host": "example.com",
                            "port": 443,
                            "scheme": "https",
                            "url": "https://example.com:443",
                            "cwd": "/tmp",
                            "home": "/home/user",
                        },
                        mock.Mock(),
                    )
                )
                await asyncio.sleep(0.05)
                pending_id = next(iter(store.pending))
                self.assertTrue(pending_id.startswith("net:"))
                approve_resp = await store.approve(
                    pending_id,
                    "once",
                    "/tmp",
                    "/home/user",
                )
                self.assertTrue(approve_resp["ok"])
                resp = await asyncio.wait_for(check_task, timeout=1.0)
                self.assertTrue(resp["ok"])
                self.assertTrue(resp["allowed"])
                self.assertEqual(resp["source"], "once")
                self.assertEqual(store.pending, {})

        asyncio.run(run())

    def test_flush_pending_to_ui_on_register(self) -> None:
        async def run() -> None:
            store = self._store()
            store.args.approval_timeout = 2.0
            pending_id = "elev:123"
            store.pending[pending_id] = policyd.Pending(
                pending_id,
                0.0,
                argv=["id"],
                cwd="/tmp",
                home="/home/user",
            )
            writer = mock.Mock()
            writer.write = mock.Mock()
            writer.drain = mock.AsyncMock()
            store.start_ui_session(writer)
            await store.flush_pending_to_ui()
            writer.write.assert_called()
            store.end_ui_session(writer)

        asyncio.run(run())

    def test_export_json_not_in_merge_stack(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            declarative = tmp_path / "declarative.json"
            declarative.write_text(
                '{"network":{"allow":[],"deny":[]},"sudo":{"allow":[],"deny":[]}}\n', encoding="utf-8"
            )
            export = tmp_path / "export.json"
            export.write_text(
                json.dumps(
                    {
                        "network": {
                            "allow": [{"host": "stale.example", "port": 443}],
                            "deny": [],
                        },
                        "sudo": {"allow": [], "deny": []},
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            args = argparse.Namespace(
                declarative=str(declarative),
                export_json=str(export),
                export_nix="",
                approval_timeout=30.0,
                interactive_approval=True,
            )
            store = policyd.PolicyStore(args)
            merged = store.merged_for(None, None)
            self.assertEqual(merged["network"]["allow"], [])
            self.assertFalse(store.is_allowed("stale.example", 443, None, None))


class PolicyStoreElevationTests(unittest.IsolatedAsyncioTestCase):
    def _store(self) -> policyd.PolicyStore:
        tmp = tempfile.mkdtemp()
        self.addCleanup(lambda: __import__("shutil").rmtree(tmp, ignore_errors=True))
        args = argparse.Namespace(
            declarative=str(Path(tmp) / "declarative.json"),
            export_json=str(Path(tmp) / "export.json"),
            export_nix="",
            approval_timeout=0.5,
            interactive_approval=True,
        )
        Path(args.declarative).write_text(
            '{"network":{"allow":[],"deny":[]},"sudo":{"allow":[],"deny":[]}}\n', encoding="utf-8"
        )
        return policyd.PolicyStore(args)

    def _register_ui(
        self, store: policyd.PolicyStore, *, ui_client: str = "standalone"
    ) -> mock.Mock:
        writer = mock.Mock()
        writer.write = mock.Mock()
        writer.drain = mock.AsyncMock(return_value=None)
        store.start_ui_session(writer, ui_client=ui_client)
        return writer

    def test_omp_ui_disconnects_standalone(self) -> None:
        store = self._store()
        standalone = self._register_ui(store, ui_client="standalone")
        omp = self._register_ui(store, ui_client="omp")
        self.assertNotIn(standalone, store.ui_clients)
        self.assertEqual(store._ui_notification_targets(), [omp])

    @mock.patch("asyncio.create_subprocess_exec")
    async def test_sudo_allow_in_policy_auto_executes(self, mock_exec: mock.Mock) -> None:
        store = self._store()
        proc = mock.Mock()
        proc.returncode = 0
        proc.communicate = mock.AsyncMock(return_value=(b"ok\n", b""))
        mock_exec.return_value = proc
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            policy = project / ".agent-sandbox" / "policy.json"
            policy.parent.mkdir(parents=True)
            policy.write_text(
                json.dumps(
                    {
                        "network": {"allow": [], "deny": []},
                        "sudo": {"allow": [{"argv": ["whoami"]}], "deny": []},
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            result = await store.request_elevation(
                ["whoami"],
                str(project),
                "/home/user",
                project_root=str(project),
            )
        self.assertTrue(result["allowed"])
        self.assertEqual(result["exit_code"], 0)
        mock_exec.assert_called_once()

    async def test_sudo_deny_in_policy_blocks_without_ui(self) -> None:
        store = self._store()
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            policy = project / ".agent-sandbox" / "policy.json"
            policy.parent.mkdir(parents=True)
            policy.write_text(
                json.dumps(
                    {
                        "network": {"allow": [], "deny": []},
                        "sudo": {"allow": [], "deny": [{"argv": ["rm"]}]},
                    }
                )
                + "\n",
                encoding="utf-8",
            )
            result = await store.request_elevation(
                ["rm", "-rf", "/"],
                str(project),
                "/home/user",
                project_root=str(project),
            )
        self.assertFalse(result["allowed"])
        self.assertEqual(store.pending, {})

    @mock.patch("asyncio.create_subprocess_exec")
    async def test_elevation_approve_runs_subprocess(self, mock_exec: mock.Mock) -> None:
        store = self._store()
        self._register_ui(store)
        proc = mock.Mock()
        proc.returncode = 0
        proc.communicate = mock.AsyncMock(return_value=(b"uid=0\n", b""))
        mock_exec.return_value = proc

        task = asyncio.create_task(
            store.request_elevation(["id"], "/tmp/ws", "/home/user")
        )
        await asyncio.sleep(0.05)
        pending_id = next(iter(store.pending))
        resp = await store.approve(pending_id, "once", "/tmp/ws", "/home/user")
        self.assertTrue(resp["ok"])
        result = await task
        self.assertTrue(result["allowed"])
        self.assertEqual(result["exit_code"], 0)
        self.assertEqual(result["stdout"], "uid=0\n")
        mock_exec.assert_called_once()

    async def test_elevation_deny_not_allowed(self) -> None:
        store = self._store()
        self._register_ui(store)
        task = asyncio.create_task(
            store.request_elevation(["false"], "/tmp", "/home/user")
        )
        await asyncio.sleep(0.05)
        pending_id = next(iter(store.pending))
        store.deny(pending_id)
        result = await task
        self.assertFalse(result["allowed"])
        self.assertEqual(result["exit_code"], 1)

    async def test_elevation_timeout(self) -> None:
        store = self._store()
        self._register_ui(store)
        result = await store.request_elevation(["id"], "/tmp", "/home/user")
        self.assertFalse(result["allowed"])
        self.assertIn("timed out", result["stderr"])

    async def test_elevation_approve_unknown_id(self) -> None:
        store = self._store()
        resp = await store.approve("missing", "once", "/tmp", "/home/user")
        self.assertFalse(resp["ok"])

    async def test_elevation_no_ui_fails_fast(self) -> None:
        store = self._store()
        result = await store.request_elevation(["id"], "/tmp", "/home/user")
        self.assertFalse(result["allowed"])
        self.assertIn("no policy UI registered", result["stderr"])


if __name__ == "__main__":
    unittest.main()
