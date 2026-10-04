"""Patch the Tern binary for the Nix package.

Usage: patch-binary.py BINARY [POSTSCRIPT_NAME=FONT_FILE...]

- Desktop integration: every launch links ~/.local/bin/tern and writes a
  desktop file pointing at the running store path. The function spawning that
  thread (found through its "cannot start desktop integration" error string)
  is made to return immediately.
- Fonts: Tern lists its embedded fonts in a static table whose
  `data: &[u8]` pointers are R_X86_64_RELATIVE relocations, each followed by
  the slice length. Replacement fonts are appended in a new read-only segment
  (reusing the PT_NOTE program header, since the header table has no spare
  slot) and every table entry for a replaced font is pointed at its
  replacement.
"""

import bisect
import re
import struct
import sys
from pathlib import Path

PT_LOAD, PT_DYNAMIC, PT_NOTE, PT_GNU_EH_FRAME = 1, 2, 4, 0x6474E550
PF_X, PF_R = 1, 4
DT_NULL, DT_RELA, DT_RELASZ = 0, 7, 8
R_X86_64_RELATIVE = 8
PAGE = 0x1000
PHDR = "<IIQQQQQQ"
INTEGRATION_ERROR = b"cannot start desktop integration"


class Elf:
    def __init__(self, data):
        assert data[:6] == b"\x7fELF\x02\x01", "Expected a little-endian ELF64 file"
        self.data = data
        (phoff,) = struct.unpack_from("<Q", data, 0x20)
        phentsize, phnum = struct.unpack_from("<HH", data, 0x36)
        # (header offset, p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align)
        self.phdrs = [
            (
                phoff + i * phentsize,
                *struct.unpack_from(PHDR, data, phoff + i * phentsize),
            )
            for i in range(phnum)
        ]
        self.loads = [p for p in self.phdrs if p[1] == PT_LOAD]

    def segment(self, p_type):
        return next(p for p in self.phdrs if p[1] == p_type)

    def offset(self, vaddr):
        for _, _, _, offset, start, _, filesz, _, _ in self.loads:
            if start <= vaddr < start + filesz:
                return offset + vaddr - start
        return None

    def vaddr(self, offset):
        for _, _, _, start, vaddr, _, filesz, _, _ in self.loads:
            if start <= offset < start + filesz:
                return vaddr + offset - start
        return None

    def relative_relocations(self):
        """Yields (entry offset, r_offset, addend) for each R_X86_64_RELATIVE."""
        dynamic = self.segment(PT_DYNAMIC)
        tags = {}
        for i in range(dynamic[6] // 16):
            tag, value = struct.unpack_from("<qQ", self.data, dynamic[3] + 16 * i)
            if tag == DT_NULL:
                break
            tags[tag] = value
        rela = self.offset(tags[DT_RELA])
        for entry in range(rela, rela + tags[DT_RELASZ], 24):
            r_offset, r_info, addend = struct.unpack_from("<QQq", self.data, entry)
            if r_info & 0xFFFFFFFF == R_X86_64_RELATIVE:
                yield entry, r_offset, addend

    def function_starts(self):
        """Sorted function start addresses from the .eh_frame_hdr search table."""
        hdr = self.segment(PT_GNU_EH_FRAME)
        base = hdr[3]
        version, ptr_enc, count_enc, table_enc = self.data[base : base + 4]
        # pcrel|sdata4 frame pointer, udata4 count, datarel|sdata4 table
        assert (version, ptr_enc, count_enc, table_enc) == (1, 0x1B, 0x03, 0x3B), (
            "Unexpected .eh_frame_hdr encoding"
        )
        (count,) = struct.unpack_from("<I", self.data, base + 8)
        table = struct.unpack_from(f"<{2 * count}i", self.data, base + 12)
        return sorted(hdr[4] + start for start in table[::2])


def disable_integration(elf):
    data = elf.data
    assert data.count(INTEGRATION_ERROR) == 1, (
        "Expected one desktop integration error string"
    )
    string = elf.vaddr(data.find(INTEGRATION_ERROR))
    text = next(p for p in elf.loads if p[2] & PF_X)
    starts = elf.function_starts()
    functions = set()
    # lea r64, [rip + disp32]
    for match in re.finditer(
        rb"[\x48\x4c]\x8d[\x05\x0d\x15\x1d\x25\x2d\x35\x3d]",
        data[text[3] : text[3] + text[6]],
    ):
        instruction = text[4] + match.start()
        (disp,) = struct.unpack_from("<i", data, text[3] + match.start() + 3)
        if instruction + 7 + disp == string:
            functions.add(starts[bisect.bisect_right(starts, instruction) - 1])
    assert len(functions) == 1, (
        f"Expected one function reporting {INTEGRATION_ERROR.decode()}, found {len(functions)}"
    )
    (function,) = functions
    data[elf.offset(function)] = 0xC3  # ret
    print(f"desktop integration: disabled spawn at {function:#x}")


def postscript_name(data, off):
    """PostScript name (name ID 6) of the sfnt font at `off`, if any."""
    if data[off : off + 4] not in (b"\x00\x01\x00\x00", b"OTTO", b"true"):
        return None
    (tables,) = struct.unpack_from(">H", data, off + 4)
    for i in range(tables):
        tag, _, table, _ = struct.unpack_from(">4sIII", data, off + 12 + 16 * i)
        if tag != b"name":
            continue
        base = off + table
        _, records, strings = struct.unpack_from(">HHH", data, base)
        for j in range(records):
            platform, _, _, name_id, length, start = struct.unpack_from(
                ">6H", data, base + 6 + 12 * j
            )
            if platform == 3 and name_id == 6:
                start += base + strings
                return data[start : start + length].decode("utf-16-be")
    return None


def replace_fonts(elf, replacements):
    data = elf.data
    note = next(p for p in reversed(elf.phdrs) if p[1] == PT_NOTE)
    # The loader expects PT_LOAD headers sorted by address; the new segment is the highest.
    assert note[0] > elf.loads[-1][0], (
        "Expected a PT_NOTE header after the last PT_LOAD"
    )

    # PostScript name -> [(relocation entry, slice length offset)]
    embedded = {}
    for entry, r_offset, addend in elf.relative_relocations():
        font, slot = elf.offset(addend), elf.offset(r_offset)
        if (
            font is not None
            and slot is not None
            and (name := postscript_name(data, font))
        ):
            embedded.setdefault(name, []).append((entry, slot + 8))

    missing = sorted(replacements.keys() - embedded.keys())
    if missing:
        sys.exit(
            f"tern embeds no font named {', '.join(missing)}; it embeds {', '.join(sorted(embedded))}"
        )

    segment_offset = len(data) + -len(data) % PAGE
    end = max(p[4] + p[7] for p in elf.loads)
    segment_vaddr = end + -end % PAGE
    data.extend(bytes(segment_offset - len(data)))

    for name, file in replacements.items():
        font = Path(file).read_bytes()
        vaddr = segment_vaddr + len(data) - segment_offset
        data += font + bytes(-len(font) % 8)
        for entry, length in embedded[name]:
            struct.pack_into("<q", data, entry + 16, vaddr)
            struct.pack_into("<Q", data, length, len(font))
        print(f"{name}: replaced {len(embedded[name])} copies with {file}")

    size = len(data) - segment_offset
    struct.pack_into(
        PHDR,
        data,
        note[0],
        PT_LOAD,
        PF_R,
        segment_offset,
        segment_vaddr,
        segment_vaddr,
        size,
        size,
        PAGE,
    )


def main(binary, *specs):
    path = Path(binary)
    elf = Elf(bytearray(path.read_bytes()))
    disable_integration(elf)
    if specs:
        replace_fonts(elf, dict(spec.split("=", 1) for spec in specs))
    path.write_bytes(elf.data)


if __name__ == "__main__":
    main(*sys.argv[1:])
