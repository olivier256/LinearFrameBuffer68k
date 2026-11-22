#!/usr/bin/env python3
"""Génère les données de la ROM de test Linear Frame Buffer (LFB).

  vstable.bin  : 112 lignes x 16 mots VSRAM (colonnes 2-cell 6..13, A/B entrelacés)
  tilemapA.bin : 112 lignes x 32 cellules (plan A, 32x128)
  tilemapB.bin : idem plan B
  bg.bin       : image de fond 128x112 4bpp, LINÉAIRE (64 octets par ligne)
  palette.bin  : 16 couleurs
"""
import struct, sys, os

OUT = sys.argv[1] if len(sys.argv) > 1 else "."

FB_W, FB_H = 128, 112
FB_TOP = 56          # première ligne écran du frame buffer
TILE0 = 400          # premier tile du frame buffer (VRAM 0x3200)
VIS_COLS = int(os.environ.get("VIS_COLS", 7))  # colonnes 2-cell mises à jour par ligne
VIS = 2 * VIS_COLS   # groupes de 8 px visibles (12 -> 96 px)
COL0 = (20 - VIS_COLS) // 2   # première colonne 2-cell (H40 = 20 colonnes)
CELL0 = 2 * COL0
PLANE_H = 1024       # plan 32x128 cellules -> 1024 lignes

def w(path, data):
    with open(os.path.join(OUT, path), "wb") as f:
        f.write(data)

# --- VSRAM : v = 8*y + r - L  avec L = FB_TOP + y  ->  v = 7*y + r - 56
vs = bytearray()
for y in range(FB_H):
    for m in range(VIS_COLS):
        for plane_r in ((2 * m) & 7, (2 * m + 1) & 7):  # A puis B
            v = (7 * y + plane_r - FB_TOP) % PLANE_H
            vs += struct.pack(">H", v)
w("vstable.bin", vs)

# --- Tilemaps : rangée y du plan = ligne y du frame buffer
ta, tb = bytearray(), bytearray()
for y in range(FB_H):
    for cell in range(32):
        a = b = 0
        k = cell - CELL0
        if 0 <= k < VIS:
            t = TILE0 + 2 * y + (k >> 3)
            if k & 1:
                b = t
            else:
                a = t
        ta += struct.pack(">H", a)
        tb += struct.pack(">H", b)
w("tilemapA.bin", ta)
w("tilemapB.bin", tb)

# --- Image de fond, en pixels (sert aussi à la vérification)
def bg_pixel(x, y):
    if x in (0, FB_W - 1) or y in (0, FB_H - 1):
        return 15
    dx, dy = x - 64, y - 56
    if abs(dx * dx + dy * dy - 40 * 40) < 40:
        return 15
    return 1 + ((x + y) >> 3) % 14

pix = [[bg_pixel(x, y) for x in range(FB_W)] for y in range(FB_H)]
bg = bytearray()
for y in range(FB_H):
    for x in range(0, FB_W, 2):
        bg.append((pix[y][x] << 4) | pix[y][x + 1])
w("bg.bin", bg)

# --- Palette (format MD : 0000 BBB0 GGG0 RRR0)
rgb = [(0, 0, 0),
       (7, 0, 0), (7, 3, 0), (7, 5, 0), (7, 7, 0), (4, 7, 0), (0, 7, 0), (0, 7, 4),
       (0, 7, 7), (0, 4, 7), (0, 0, 7), (3, 0, 7), (5, 0, 7), (7, 0, 7), (7, 0, 4),
       (7, 7, 7)]
pal = bytearray()
for r, g, b in rgb:
    pal += struct.pack(">H", (b << 9) | (g << 5) | (r << 1))
w("palette.bin", pal)

# --- constantes pour l'assembleur
addr = 4 * COL0
cmd = 0x40000010 | (addr << 16)
w("config.inc", (f"        .equ VIS_COLS, {VIS_COLS}\n"
                 f"        .equ VIS_W, {VIS * 8}\n"
                 f"        .equ VSRAM_CMD, 0x{cmd:08X}\n").encode())
