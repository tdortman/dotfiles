#!/usr/bin/env python3
"""DNS forwarder that records query→A/AAAA answers for transparent proxy hostname correlation."""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import socket
import struct
import sys

from dns_cache import DEFAULT_CACHE_PATH, DnsCache
from dns_wire import mappings_from_response


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def parse_upstream(value: str) -> tuple[str, int]:
    if ":" in value:
        host, port_s = value.rsplit(":", 1)
        return host, int(port_s)
    return value, 53


class DnsProxy:
    def __init__(
        self,
        upstream: tuple[str, int],
        cache: DnsCache,
        *,
        verbose: bool = False,
    ) -> None:
        self.upstream = upstream
        self.cache = cache
        self.verbose = verbose

    def record_response(self, data: bytes) -> None:
        for ip, hostname, ttl in mappings_from_response(data):
            self.cache.remember(ip, hostname, ttl)
            if self.verbose:
                log(f"dns cache {ip} -> {hostname} ttl={ttl}")

    async def forward_udp(self, data: bytes) -> bytes:
        loop = asyncio.get_running_loop()
        upstream = self.upstream

        def _exchange() -> bytes:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            try:
                sock.settimeout(10.0)
                sock.sendto(data, upstream)
                resp, _addr = sock.recvfrom(65535)
                return resp
            finally:
                sock.close()

        return await loop.run_in_executor(None, _exchange)

    async def handle_udp(
        self,
        data: bytes,
        addr: tuple[str, int],
        transport: asyncio.DatagramTransport,
    ) -> None:
        if not data:
            return
        try:
            resp = await self.forward_udp(data)
        except OSError as exc:
            log(f"dns udp upstream {self.upstream} failed from {addr}: {exc}")
            return
        self.record_response(resp)
        transport.sendto(resp, addr)

    async def handle_tcp(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> None:
        peer = writer.get_extra_info("peername")
        try:
            while True:
                len_buf = await reader.readexactly(2)
                (msg_len,) = struct.unpack("!H", len_buf)
                if msg_len == 0:
                    continue
                data = await reader.readexactly(msg_len)
                resp = await self.forward_tcp_message(data)
                self.record_response(resp)
                writer.write(struct.pack("!H", len(resp)) + resp)
                await writer.drain()
        except asyncio.IncompleteReadError:
            pass
        except OSError as exc:
            log(f"dns tcp client {peer} error: {exc}")
        finally:
            writer.close()
            with contextlib.suppress(Exception):
                await writer.wait_closed()

    async def forward_tcp_message(self, data: bytes) -> bytes:
        upstream_host, upstream_port = self.upstream
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(upstream_host, upstream_port, family=socket.AF_INET),
            timeout=10.0,
        )
        try:
            writer.write(struct.pack("!H", len(data)) + data)
            await writer.drain()
            len_buf = await reader.readexactly(2)
            (msg_len,) = struct.unpack("!H", len_buf)
            return await reader.readexactly(msg_len)
        finally:
            writer.close()
            await writer.wait_closed()


class UdpProtocol(asyncio.DatagramProtocol):
    def __init__(self, proxy: DnsProxy) -> None:
        self.proxy = proxy

    def connection_made(self, transport: asyncio.BaseTransport) -> None:
        self.transport = transport

    def datagram_received(self, data: bytes, addr: tuple[str, int]) -> None:
        asyncio.create_task(self.proxy.handle_udp(data, addr, self.transport))


async def main_async(args: argparse.Namespace) -> None:
    upstream = parse_upstream(args.upstream)
    cache = DnsCache(args.cache_path, max_ttl=args.max_ttl)
    proxy = DnsProxy(upstream, cache, verbose=args.verbose)

    loop = asyncio.get_running_loop()
    udp_transport, _protocol = await loop.create_datagram_endpoint(
        lambda: UdpProtocol(proxy),
        local_addr=(args.listen_host, args.listen_port),
        family=socket.AF_INET,
    )
    tcp_server = await asyncio.start_server(
        proxy.handle_tcp,
        host=args.listen_host,
        port=args.listen_port,
        reuse_address=True,
        family=socket.AF_INET,
    )
    log(
        f"dns proxy on {args.listen_host}:{args.listen_port} -> {upstream[0]}:{upstream[1]} "
        f"cache={args.cache_path}"
    )
    async with tcp_server:
        await tcp_server.serve_forever()
    udp_transport.close()


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--listen-host", default="169.254.100.1")
    p.add_argument("--listen-port", type=int, default=53)
    p.add_argument("--upstream", default="127.0.0.53:53")
    p.add_argument("--cache-path", default=DEFAULT_CACHE_PATH)
    p.add_argument("--max-ttl", type=int, default=600)
    p.add_argument("--verbose", action="store_true")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    try:
        asyncio.run(main_async(args))
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
