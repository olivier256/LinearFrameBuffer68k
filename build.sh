#!/bin/sh
# Construit la ROM dans roms/lfb.bin
# Prérequis : binutils m68k (m68k-linux-gnu-as / ld) et python3
# Largeur visible : VIS_COLS=6 (96 px), 7 (112 px, défaut) ou 8 (128 px)
set -e
cd "$(dirname "$0")"
mkdir -p build roms
python3 tools/gen_data.py build
m68k-linux-gnu-as -m68000 --register-prefix-optional -o build/lfb.o src/lfb.s
m68k-linux-gnu-ld -Ttext=0 --oformat binary -e 0 -o build/lfb.bin build/lfb.o
# checksum de l'en-tête (0x18E)
python3 - <<'PY'
import struct
d = bytearray(open("build/lfb.bin", "rb").read())
if len(d) & 1: d.append(0)
s = sum(struct.unpack(">%dH" % ((len(d) - 0x200) // 2), d[0x200:])) & 0xFFFF
d[0x18E:0x190] = struct.pack(">H", s)
open("roms/lfb.bin", "wb").write(d)
print("roms/lfb.bin : %d octets, checksum %04X" % (len(d), s))
PY
