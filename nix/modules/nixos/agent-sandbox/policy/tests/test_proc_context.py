#!/usr/bin/env python3
"""Tests for /proc-based sandbox context helpers."""

from __future__ import annotations

import os
import socket
import unittest

from support import load_module

proc_context = load_module("proc_context", "proxy/proc_context.py")


class ProcContextTests(unittest.TestCase):
    def test_context_from_pid_reads_home_env(self) -> None:
        pid = os.getpid()
        cwd, home, project_root = proc_context.context_from_pid(pid)
        self.assertEqual(cwd, os.getcwd())
        self.assertEqual(home, os.environ.get("HOME"))
        self.assertIsNone(project_root)

    def test_peer_cred_tcp_returns_uid(self) -> None:
        import subprocess

        ls = socket.socket()
        ls.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        ls.bind(("127.0.0.1", 0))
        ls.listen(1)
        port = ls.getsockname()[1]
        proc = subprocess.Popen(
            [
                "python3",
                "-c",
                f"import socket,time; s=socket.create_connection(('127.0.0.1',{port})); time.sleep(3)",
            ]
        )
        cs, _addr = ls.accept()
        try:
            cred = proc_context.peer_cred(cs)
            self.assertIsNotNone(cred)
            assert cred is not None
            pid, uid, _gid = cred
            self.assertGreaterEqual(uid, 0)
            self.assertEqual(proc_context.home_from_uid(uid), os.environ.get("HOME"))
            if pid > 0:
                self.assertEqual(pid, proc.pid)
        finally:
            proc.wait(timeout=5)
            cs.close()
            ls.close()


if __name__ == "__main__":
    unittest.main()
