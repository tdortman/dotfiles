#!/usr/bin/env python3
"""Regression tests for agent-sandbox proxy helpers."""

from __future__ import annotations

import socket
import struct
import unittest

from support import load_module

proxy = load_module("proxy", "proxy/proxy.py")


class FakeSocket:
    def __init__(self, payload: bytes = b"", raise_error: bool = False) -> None:
        self.payload = payload
        self.raise_error = raise_error
        self.last_call = None

    def getsockopt(self, level: int, optname: int, buflen: int) -> bytes:
        if self.raise_error:
            raise OSError("boom")
        self.last_call = (level, optname, buflen)
        return self.payload


class ProxyHelperTests(unittest.TestCase):
    def test_get_original_dst_decodes_sockaddr(self) -> None:
        payload = struct.pack("!HH4s8x", socket.AF_INET, 443, socket.inet_aton("1.2.3.4"))
        fake = FakeSocket(payload)
        self.assertEqual(proxy.get_original_dst(fake), ("1.2.3.4", 443))
        self.assertEqual(fake.last_call, (socket.SOL_IP, proxy.SO_ORIGINAL_DST, 16))

    def test_get_original_dst_short_payload_returns_none(self) -> None:
        self.assertIsNone(proxy.get_original_dst(FakeSocket(b"\x00" * 8)))

    def test_get_original_dst_oserror_returns_none(self) -> None:
        self.assertIsNone(proxy.get_original_dst(FakeSocket(raise_error=True)))

    def test_policy_host_for_connect(self) -> None:
        from hosts import policy_host_for_connect

        policy_host, connect = policy_host_for_connect("api.example.com")
        self.assertEqual(policy_host, "api.example.com")
        self.assertEqual(connect, "api.example.com")


if __name__ == "__main__":
    unittest.main()
