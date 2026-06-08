#!/usr/bin/env python3
"""
Clear DF_1_PIE from DT_FLAGS_1 in an ELF binary.

lld 14+ sets DF_1_PIE (0x08000000) in DT_FLAGS_1 to mark PIE executables.
Android <= 7 linkers don't recognise this bit and print:
  WARNING: linker: <binary>: unsupported flags DT_FLAGS_1=0x8000001
Clearing the bit suppresses the warning; the binary is still a PIE.
"""
import struct
import sys

DF_1_PIE  = 0x08000000
DT_FLAGS_1 = 0x6ffffffb
PT_DYNAMIC = 2


def patch(path: str) -> None:
    with open(path, "r+b") as f:
        data = bytearray(f.read())

    if data[:4] != b"\x7fELF":
        print(f"{path}: not an ELF file, skipping")
        return

    bits    = 64 if data[4] == 2 else 32
    endian  = "<" if data[5] == 1 else ">"

    if bits == 64:
        e_phoff     = struct.unpack_from(endian + "Q", data, 32)[0]
        e_phentsize = struct.unpack_from(endian + "H", data, 54)[0]
        e_phnum     = struct.unpack_from(endian + "H", data, 56)[0]
        phdr_fmt    = endian + "IIQQQQQQ"   # type flags offset vaddr paddr filesz memsz align
        dyn_tag_fmt = endian + "q"
        dyn_val_fmt = endian + "Q"
        dyn_entry   = 16
    else:
        e_phoff     = struct.unpack_from(endian + "I", data, 28)[0]
        e_phentsize = struct.unpack_from(endian + "H", data, 42)[0]
        e_phnum     = struct.unpack_from(endian + "H", data, 44)[0]
        phdr_fmt    = endian + "IIIIIIII"   # type offset vaddr paddr filesz memsz flags align
        dyn_tag_fmt = endian + "i"
        dyn_val_fmt = endian + "I"
        dyn_entry   = 8

    for i in range(e_phnum):
        phdr_off = e_phoff + i * e_phentsize
        p_type = struct.unpack_from(endian + "I", data, phdr_off)[0]
        if p_type != PT_DYNAMIC:
            continue

        if bits == 64:
            p_offset = struct.unpack_from(endian + "Q", data, phdr_off + 8)[0]
            p_filesz = struct.unpack_from(endian + "Q", data, phdr_off + 32)[0]
        else:
            p_offset = struct.unpack_from(endian + "I", data, phdr_off + 4)[0]
            p_filesz = struct.unpack_from(endian + "I", data, phdr_off + 16)[0]

        for j in range(0, p_filesz, dyn_entry):
            tag = struct.unpack_from(dyn_tag_fmt, data, p_offset + j)[0]
            if tag != DT_FLAGS_1:
                continue
            val_off = p_offset + j + (8 if bits == 64 else 4)
            val = struct.unpack_from(dyn_val_fmt, data, val_off)[0]
            if not (val & DF_1_PIE):
                print(f"{path}: DF_1_PIE not set, nothing to do")
                return
            new_val = val & ~DF_1_PIE
            struct.pack_into(dyn_val_fmt, data, val_off, new_val)
            with open(path, "wb") as f:
                f.write(data)
            print(f"{path}: DT_FLAGS_1  0x{val:x} -> 0x{new_val:x}")
            return

    print(f"{path}: DT_FLAGS_1 entry not found")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"usage: {sys.argv[0]} <elf>...")
        sys.exit(1)
    for path in sys.argv[1:]:
        patch(path)
