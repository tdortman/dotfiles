#!/usr/bin/env python3
"""Tests for the shared DNS answer cache."""

from __future__ import annotations

import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

from support import load_module

dns_cache = load_module("dns_cache", "dns/dns_cache.py")


class DnsCacheTests(unittest.TestCase):
    def test_remember_and_lookup(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "dns-cache.json"
            cache = dns_cache.DnsCache(path, max_ttl=600)
            cache.remember("93.184.216.34", "example.com", 300)
            self.assertEqual(cache.lookup("93.184.216.34"), "example.com")

    def test_ttl_expiry(self) -> None:
        cache = dns_cache.DnsCache(path=None, max_ttl=60)
        t0 = 1000.0
        with mock.patch.object(dns_cache, "_now", return_value=t0):
            cache.remember("1.2.3.4", "expired.example", 10)
        with mock.patch.object(dns_cache, "_now", return_value=t0 + 11):
            self.assertIsNone(cache.lookup("1.2.3.4"))

    def test_persist_and_reload(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "dns-cache.json"
            writer = dns_cache.DnsCache(path)
            writer.remember("10.0.0.1", "api.example.com", 120)
            reader = dns_cache.DnsCache(path)
            self.assertEqual(reader.lookup("10.0.0.1"), "api.example.com")

    def test_max_ttl_cap(self) -> None:
        cache = dns_cache.DnsCache(path=None, max_ttl=100)
        t0 = time.monotonic()
        cache.remember("1.2.3.4", "big-ttl.example", 9999)
        entry = cache._entries["1.2.3.4"]
        self.assertLessEqual(entry[1] - t0, 100.1)


if __name__ == "__main__":
    unittest.main()
