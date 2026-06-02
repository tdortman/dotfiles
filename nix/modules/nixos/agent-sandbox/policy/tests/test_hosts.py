#!/usr/bin/env python3
"""Tests for hostname / SNI helpers."""

from __future__ import annotations

import struct
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from support import load_module

hosts = load_module("hosts", "proxy/hosts.py")


def _client_hello_with_sni(hostname: str) -> bytes:
    name = hostname.encode()
    sni_list = b"\x00" + struct.pack("!H", len(name)) + name
    sni_ext = b"\x00\x00" + struct.pack("!H", len(sni_list) + 2)
    sni_ext += struct.pack("!H", len(sni_list)) + sni_list
    extensions = sni_ext
    ext_block = struct.pack("!H", len(extensions)) + extensions
    session_id = b""
    cipher_suites = struct.pack("!H", 2) + b"\x00\x2f"
    compression = b"\x01\x00"
    body = (
        b"\x03\x03" + b"\x00" * 32
        + bytes([len(session_id)]) + session_id
        + cipher_suites + compression + ext_block
    )
    handshake = b"\x01" + struct.pack("!I", len(body))[1:4] + body
    return b"\x16\x03\x01" + struct.pack("!H", len(handshake)) + handshake


class HostHelperTests(unittest.TestCase):
    def test_parse_tls_sni(self) -> None:
        pkt = _client_hello_with_sni("api.openai.com")
        self.assertEqual(hosts.parse_tls_sni(pkt), "api.openai.com")

    def test_policy_host_prefers_sni(self) -> None:
        pkt = _client_hello_with_sni("chatgpt.com")
        with mock.patch("socket.gethostbyaddr", side_effect=OSError):
            policy_host, connect = hosts.policy_host_for_connect(
                "52.54.28.178", initial_data=pkt
            )
        self.assertEqual(policy_host, "chatgpt.com")
        self.assertEqual(connect, "52.54.28.178")

    def test_policy_host_prefers_dns_cache_over_sni(self) -> None:
        import dns_cache

        pkt = _client_hello_with_sni("other.example")
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "dns-cache.json"
            cache = dns_cache.DnsCache(path)
            cache.remember("52.54.28.178", "api.openai.com", 300)
            with mock.patch("socket.gethostbyaddr", side_effect=OSError):
                policy_host, connect = hosts.policy_host_for_connect(
                    "52.54.28.178",
                    initial_data=pkt,
                    cache_path=path,
                )
        self.assertEqual(policy_host, "api.openai.com")
        self.assertEqual(connect, "52.54.28.178")

    def test_policy_host_sni_when_cache_miss(self) -> None:
        pkt = _client_hello_with_sni("cached-miss.example")
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "dns-cache.json"
            with mock.patch("socket.gethostbyaddr", side_effect=OSError):
                policy_host, _connect = hosts.policy_host_for_connect(
                    "10.0.0.9",
                    initial_data=pkt,
                    cache_path=path,
                )
        self.assertEqual(policy_host, "cached-miss.example")


if __name__ == "__main__":
    unittest.main()
