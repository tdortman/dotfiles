"""Minimal DNS wire-format helpers (stdlib only)."""

from __future__ import annotations

import socket
import struct
from dataclasses import dataclass

TYPE_A = 1
TYPE_AAAA = 28
CLASS_IN = 1


@dataclass(frozen=True)
class DnsQuestion:
    name: str
    qtype: int
    qclass: int


@dataclass(frozen=True)
class DnsRecord:
    name: str
    rtype: int
    rclass: int
    ttl: int
    rdata: bytes


def parse_name(data: bytes, offset: int = 0) -> tuple[str, int]:
    labels: list[str] = []
    jumped = False
    end = offset
    max_jumps = 16
    jumps = 0
    while offset < len(data):
        length = data[offset]
        if length == 0:
            offset += 1
            if not jumped:
                end = offset
            break
        if length & 0xC0 == 0xC0:
            if offset + 1 >= len(data):
                raise ValueError("truncated name pointer")
            if jumps >= max_jumps:
                raise ValueError("too many compression pointers")
            ptr = ((length & 0x3F) << 8) | data[offset + 1]
            if not jumped:
                end = offset + 2
            offset = ptr
            jumped = True
            jumps += 1
            continue
        offset += 1
        label = data[offset : offset + length]
        if len(label) != length:
            raise ValueError("truncated label")
        labels.append(label.decode(errors="replace"))
        offset += length
    name = ".".join(labels).lower().rstrip(".")
    return name, end


def skip_name(data: bytes, offset: int) -> int:
    _, end = parse_name(data, offset)
    return end


def parse_header(data: bytes) -> tuple[int, int, int, int, int, int]:
    if len(data) < 12:
        raise ValueError("short DNS header")
    _id, flags, qd, an, ns, ar = struct.unpack("!HHHHHH", data[:12])
    return _id, flags, qd, an, ns, ar


def parse_questions(data: bytes, offset: int, count: int) -> tuple[list[DnsQuestion], int]:
    questions: list[DnsQuestion] = []
    for _ in range(count):
        name, offset = parse_name(data, offset)
        if offset + 4 > len(data):
            raise ValueError("truncated question")
        qtype, qclass = struct.unpack("!HH", data[offset : offset + 4])
        offset += 4
        questions.append(DnsQuestion(name, qtype, qclass))
    return questions, offset


def parse_rr(data: bytes, offset: int) -> tuple[DnsRecord, int]:
    name, offset = parse_name(data, offset)
    if offset + 10 > len(data):
        raise ValueError("truncated RR header")
    rtype, rclass, ttl, rdlen = struct.unpack("!HHIH", data[offset : offset + 10])
    offset += 10
    if offset + rdlen > len(data):
        raise ValueError("truncated RDATA")
    rdata = data[offset : offset + rdlen]
    return DnsRecord(name, rtype, rclass, ttl, rdata), offset + rdlen


def parse_records(data: bytes, offset: int, count: int) -> tuple[list[DnsRecord], int]:
    records: list[DnsRecord] = []
    for _ in range(count):
        rec, offset = parse_rr(data, offset)
        records.append(rec)
    return records, offset


def question_name(data: bytes) -> str | None:
    try:
        _id, _flags, qd, _an, _ns, _ar = parse_header(data)
        if qd < 1:
            return None
        questions, _ = parse_questions(data, 12, qd)
        return questions[0].name
    except ValueError:
        return None


def ip_from_rdata(rtype: int, rdata: bytes) -> str | None:
    if rtype == TYPE_A and len(rdata) == 4:
        return socket.inet_ntoa(rdata)
    if rtype == TYPE_AAAA and len(rdata) == 16:
        return socket.inet_ntop(socket.AF_INET6, rdata)
    return None


def mappings_from_response(data: bytes) -> list[tuple[str, str, int]]:
    """Return (ip, hostname, ttl) tuples from a DNS response."""
    try:
        _id, flags, qd, an, ns, ar = parse_header(data)
    except ValueError:
        return []
    if not (flags & 0x8000):
        return []
    qname = question_name(data)
    if not qname:
        return []
    try:
        offset = 12
        _questions, offset = parse_questions(data, offset, qd)
        answers, offset = parse_records(data, offset, an)
        _authority, offset = parse_records(data, offset, ns)
        _additional, _offset = parse_records(data, offset, ar)
    except ValueError:
        return []
    out: list[tuple[str, str, int]] = []
    for rec in answers:
        ip = ip_from_rdata(rec.rtype, rec.rdata)
        if ip:
            out.append((ip, qname, rec.ttl))
    return out
