"""Shared IP→hostname cache populated by the DNS proxy, read by the policy proxy."""

from __future__ import annotations

import json
import os
import tempfile
import time
from pathlib import Path
from typing import Any

DEFAULT_CACHE_PATH = "/run/agent-sandbox/dns-cache.json"
DEFAULT_MAX_TTL = 600


def _now() -> float:
    return time.monotonic()


class DnsCache:
    """In-memory IP→hostname map with TTL; optional JSON file for cross-process sharing."""

    def __init__(
        self,
        path: str | Path | None = DEFAULT_CACHE_PATH,
        *,
        max_ttl: int = DEFAULT_MAX_TTL,
    ) -> None:
        self.path = Path(path) if path else None
        self.max_ttl = max_ttl
        self._entries: dict[str, tuple[str, float]] = {}

    def remember(self, ip: str, hostname: str, ttl: int) -> None:
        host = hostname.strip().lower().rstrip(".")
        if not host or host == ip:
            return
        ttl = max(1, min(int(ttl), self.max_ttl))
        self._entries[ip] = (host, _now() + ttl)
        if self.path:
            self._persist()

    def lookup(self, ip: str) -> str | None:
        if self.path and self.path.is_file():
            self._load()
        entry = self._entries.get(ip)
        if not entry:
            return None
        host, expires = entry
        if _now() >= expires:
            del self._entries[ip]
            if self.path:
                self._persist()
            return None
        return host

    def _snapshot(self) -> dict[str, Any]:
        now = _now()
        entries: dict[str, dict[str, Any]] = {}
        for ip, (host, expires) in list(self._entries.items()):
            if expires <= now:
                del self._entries[ip]
                continue
            entries[ip] = {"host": host, "expires": expires}
        return {"version": 1, "entries": entries}

    def _persist(self) -> None:
        if not self.path:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True)
        data = json.dumps(self._snapshot(), separators=(",", ":")).encode()
        fd, tmp = tempfile.mkstemp(dir=self.path.parent, prefix=".dns-cache-", suffix=".tmp")
        try:
            os.write(fd, data)
            os.fsync(fd)
        finally:
            os.close(fd)
        os.replace(tmp, self.path)

    def _load(self) -> None:
        if not self.path:
            return
        try:
            raw = json.loads(self.path.read_text())
        except (OSError, json.JSONDecodeError):
            return
        if raw.get("version") != 1:
            return
        now = _now()
        for ip, item in (raw.get("entries") or {}).items():
            if not isinstance(item, dict):
                continue
            host = item.get("host")
            expires = item.get("expires")
            if not isinstance(host, str) or not isinstance(expires, (int, float)):
                continue
            if expires <= now:
                continue
            self._entries[ip] = (host, float(expires))


_default_cache: DnsCache | None = None


def get_cache(path: str | Path | None = None) -> DnsCache:
    global _default_cache
    if path is not None:
        return DnsCache(path)
    if _default_cache is None:
        env = os.environ.get("AGENT_SANDBOX_DNS_CACHE")
        _default_cache = DnsCache(env or DEFAULT_CACHE_PATH)
    return _default_cache


def lookup_dns_cache(ip: str, *, cache_path: str | Path | None = None) -> str | None:
    return get_cache(cache_path).lookup(ip)
