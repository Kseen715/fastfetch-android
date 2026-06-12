#!/usr/bin/env python3
"""
Quiet an Android-cross-compiled ELF for old Bionic linkers.

Two cleanups, both safe on Android (where Bionic resolves symbols by name only
and ignores ELF symbol versioning / rpath):

1. Clear DF_1_PIE from DT_FLAGS_1.
   lld 14+ sets DF_1_PIE (0x08000000); Android <= 7 linkers print
     WARNING: linker: <bin>: unsupported flags DT_FLAGS_1=0x8000001
   Clearing the bit silences it; the binary is still a PIE.

2. Remove unused dynamic entries that make Android 5.x linkers warn
     WARNING: linker: <bin>: unused DT entry: type 0x1d  arg ...   (DT_RUNPATH)
     WARNING: linker: <bin>: unused DT entry: type 0x6ffffffe ...  (DT_VERNEED)
     WARNING: linker: <bin>: unused DT entry: type 0x6fffffff ...  (DT_VERNEEDNUM)
   We strip rpath/runpath and the whole symbol-versioning family, compacting the
   dynamic table and padding the tail with DT_NULL.
"""
import struct
import sys

DT_NULL    = 0
DT_FLAGS_1 = 0x6ffffffb
DF_1_PIE   = 0x08000000
PT_DYNAMIC = 2

# dynamic entries to drop entirely (Bionic never consumes these)
DT_REMOVE = {
    0x0000000f,  # DT_RPATH
    0x0000001d,  # DT_RUNPATH
    0x6ffffff0,  # DT_VERSYM
    0x6ffffffc,  # DT_VERDEF
    0x6ffffffd,  # DT_VERDEFNUM
    0x6ffffffe,  # DT_VERNEED
    0x6fffffff,  # DT_VERNEEDNUM
}


def patch(path: str) -> None:
    with open(path, "r+b") as f:
        data = bytearray(f.read())

    if data[:4] != b"\x7fELF":
        print(f"{path}: not an ELF file, skipping")
        return

    bits   = 64 if data[4] == 2 else 32
    endian = "<" if data[5] == 1 else ">"

    if bits == 64:
        e_phoff     = struct.unpack_from(endian + "Q", data, 32)[0]
        e_phentsize = struct.unpack_from(endian + "H", data, 54)[0]
        e_phnum     = struct.unpack_from(endian + "H", data, 56)[0]
        tag_fmt, val_fmt, ent_size = endian + "q", endian + "Q", 16
    else:
        e_phoff     = struct.unpack_from(endian + "I", data, 28)[0]
        e_phentsize = struct.unpack_from(endian + "H", data, 42)[0]
        e_phnum     = struct.unpack_from(endian + "H", data, 44)[0]
        tag_fmt, val_fmt, ent_size = endian + "i", endian + "I", 8

    # locate PT_DYNAMIC
    dyn_off = dyn_size = None
    for i in range(e_phnum):
        phdr = e_phoff + i * e_phentsize
        if struct.unpack_from(endian + "I", data, phdr)[0] != PT_DYNAMIC:
            continue
        if bits == 64:
            dyn_off  = struct.unpack_from(endian + "Q", data, phdr + 8)[0]
            dyn_size = struct.unpack_from(endian + "Q", data, phdr + 32)[0]
        else:
            dyn_off  = struct.unpack_from(endian + "I", data, phdr + 4)[0]
            dyn_size = struct.unpack_from(endian + "I", data, phdr + 16)[0]
        break

    if dyn_off is None:
        print(f"{path}: no PT_DYNAMIC, nothing to do")
        return

    slots = dyn_size // ent_size
    kept = []
    cleared_pie = False
    removed = 0
    for j in range(slots):
        off = dyn_off + j * ent_size
        tag = struct.unpack_from(tag_fmt, data, off)[0]
        val = struct.unpack_from(val_fmt, data, off + (8 if bits == 64 else 4))[0]
        if tag == DT_NULL:
            break
        if (tag & 0xffffffff) in DT_REMOVE:
            removed += 1
            continue
        if tag == DT_FLAGS_1 and (val & DF_1_PIE):
            val &= ~DF_1_PIE
            cleared_pie = True
        kept.append((tag, val))

    # rewrite: kept entries, then DT_NULL padding for the rest of the region
    for idx in range(slots):
        off = dyn_off + idx * ent_size
        if idx < len(kept):
            tag, val = kept[idx]
        else:
            tag, val = DT_NULL, 0
        struct.pack_into(tag_fmt, data, off, tag)
        struct.pack_into(val_fmt, data, off + (8 if bits == 64 else 4), val)

    if removed == 0 and not cleared_pie:
        print(f"{path}: already clean")
        return

    with open(path, "wb") as f:
        f.write(data)
    print(f"{path}: removed {removed} DT entr{'y' if removed == 1 else 'ies'}"
          f"{', cleared DF_1_PIE' if cleared_pie else ''}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"usage: {sys.argv[0]} <elf>...")
        sys.exit(1)
    for p in sys.argv[1:]:
        patch(p)
