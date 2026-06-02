#!/usr/bin/env python3
"""Tests for minimal DNS wire parsing."""

from __future__ import annotations

import socket
import struct
import unittest

from support import load_module

dns_wire = load_module("dns_wire", "dns/dns_wire.py")


def _encode_name(name: str) -> bytes:
    out = bytearray()
    for label in name.split("."):
        out.append(len(label))
        out.extend(label.encode())
    out.append(0)
    return bytes(out)


def _build_a_response(qname: str, ip: str, ttl: int = 300) -> bytes:
    header = struct.pack("!HHHHHH", 0xBEEF, 0x8180, 1, 1, 0, 0)
    question = _encode_name(qname) + struct.pack("!HH", dns_wire.TYPE_A, dns_wire.CLASS_IN)
    answer = (
        b"\xc0\x0c"
        + struct.pack("!HHIH", dns_wire.TYPE_A, dns_wire.CLASS_IN, ttl, 4)
        + socket.inet_aton(ip)
    )
    return header + question + answer


class DnsWireTests(unittest.TestCase):
    def test_mappings_from_response(self) -> None:
        pkt = _build_a_response("api.openai.com", "52.54.28.178", ttl=120)
        maps = dns_wire.mappings_from_response(pkt)
        self.assertEqual(maps, [("52.54.28.178", "api.openai.com", 120)])

    def test_question_name(self) -> None:
        pkt = _build_a_response("Example.COM.", "1.2.3.4")
        self.assertEqual(dns_wire.question_name(pkt), "example.com")


if __name__ == "__main__":
    unittest.main()
