"""Hostname resolution helpers for agent-sandbox policy (DNS cache, SNI, PTR)."""

from __future__ import annotations

import socket
from pathlib import Path

from dns_cache import lookup_dns_cache


def is_ipv4_literal(host: str) -> bool:
    parts = host.split(".")
    if len(parts) != 4:
        return False
    try:
        return all(0 <= int(p) <= 255 for p in parts)
    except ValueError:
        return False


def normalize_host(host: str) -> str:
    return host.strip().lower().rstrip(".")


def reverse_hostname(ip: str) -> str | None:
    if not is_ipv4_literal(ip):
        return None
    try:
        hostname, _, _ = socket.gethostbyaddr(ip)
        return normalize_host(hostname)
    except OSError:
        return None


def parse_tls_sni(buf: bytes) -> str | None:
    """Extract server_name from a TLS ClientHello (first record may be partial)."""
    if len(buf) < 5 or buf[0] != 0x16:
        return None
    record_len = (buf[3] << 8) | buf[4]
    if len(buf) < 5 + record_len:
        record_len = min(record_len, len(buf) - 5)
    hs = buf[5 : 5 + record_len]
    if len(hs) < 43 or hs[0] != 0x01:
        return None
    pos = 1 + 3 + 2 + 32
    if pos >= len(hs):
        return None
    pos += 1 + hs[pos]
    if pos + 2 > len(hs):
        return None
    cs_len = (hs[pos] << 8) | hs[pos + 1]
    pos += 2 + cs_len
    if pos + 1 > len(hs):
        return None
    pos += 1 + hs[pos]
    if pos + 2 > len(hs):
        return None
    ext_total = (hs[pos] << 8) | hs[pos + 1]
    pos += 2
    ext_end = pos + ext_total
    while pos + 4 <= ext_end and pos + 4 <= len(hs):
        ext_type = (hs[pos] << 8) | hs[pos + 1]
        ext_len = (hs[pos + 2] << 8) | hs[pos + 3]
        pos += 4
        if ext_type == 0 and ext_len >= 5 and pos + ext_len <= len(hs):
            ext = hs[pos : pos + ext_len]
            if len(ext) >= 5:
                name_len = (ext[3] << 8) | ext[4]
                if len(ext) >= 5 + name_len:
                    name = ext[5 : 5 + name_len].decode(errors="ignore")
                    if name:
                        return normalize_host(name)
        pos += ext_len
    return None


def policy_host_for_connect(
    connect_host: str,
    *,
    initial_data: bytes | None = None,
    cache_path: str | Path | None = None,
) -> tuple[str, str]:
    """Return (policy_host, connect_host) — policy uses DNS names, TCP uses original target."""
    connect_host = connect_host.strip()
    if not is_ipv4_literal(connect_host):
        name = normalize_host(connect_host)
        return name, connect_host

    cached = lookup_dns_cache(connect_host, cache_path=cache_path)
    if cached:
        return cached, connect_host

    if initial_data:
        sni = parse_tls_sni(initial_data)
        if sni:
            return sni, connect_host

    ptr = reverse_hostname(connect_host)
    if ptr:
        return ptr, connect_host

    return connect_host, connect_host


def allow_keys(host: str, port: int) -> list[tuple[str, int]]:
    """Keys checked for once/session grants (hostname + optional PTR alias)."""
    host = normalize_host(host)
    keys: list[tuple[str, int]] = [(host, port)]
    if is_ipv4_literal(host):
        ptr = reverse_hostname(host)
        if ptr:
            keys.append((ptr, port))
    return keys
