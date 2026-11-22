#!/usr/bin/env python3
"""Lance une ROM LFB dans Genesis Plus GX (via stable-retro) et compare
l'écran au buffer attendu, groupe de 8 pixels par groupe de 8 pixels.

    pip install stable-retro pillow numpy
    python3 tools/test_emu.py roms/lfb.bin [--frame 200] [--vis-cols 7] [--png capture.png]

Le carré mobile n'est pas dans l'image de référence : 32 à 48 groupes
« faux » regroupés sur 16 lignes sont donc normaux.
"""
import argparse, os, shutil, sys, tempfile, warnings

import numpy as np

warnings.filterwarnings("ignore")

FB_W, FB_H, FB_TOP = 128, 112, 56


def run(rom, frame):
    import stable_retro as retro
    tmp = tempfile.mkdtemp()
    path = os.path.join(tmp, "lfb.md")          # extension .md -> cœur Genesis
    shutil.copy(rom, path)
    em = retro.RetroEmulator(path)
    for _ in range(frame + 1):
        em.step()
    return em.get_screen().astype(int)


def load_ref(build):
    pal = open(os.path.join(build, "palette.bin"), "rb").read()
    cols = []
    for i in range(16):
        v = pal[2 * i] << 8 | pal[2 * i + 1]
        cols.append([((v >> s) & 7) * 255 / 7 for s in (1, 5, 9)])
    bg = open(os.path.join(build, "bg.bin"), "rb").read()
    fb = [[(bg[y * 64 + x // 2] >> (4 if x % 2 == 0 else 0)) & 15
           for x in range(FB_W)] for y in range(FB_H)]
    return np.array(cols), fb


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rom")
    ap.add_argument("--frame", type=int, default=200)
    ap.add_argument("--vis-cols", type=int, default=7)
    ap.add_argument("--build", default="build")
    ap.add_argument("--png")
    a = ap.parse_args()

    im = run(a.rom, a.frame)
    if a.png:
        from PIL import Image
        Image.fromarray(im.astype(np.uint8)).resize((640, 448), Image.NEAREST).save(a.png)

    cols, fb = load_ref(a.build)
    vis = 2 * a.vis_cols
    x0 = (20 - a.vis_cols) // 2 * 16
    zone = im[:, x0:x0 + 8 * vis]
    idx = ((zone[:, :, None, :] - cols[None, None]) ** 2).sum(-1).argmin(-1)

    lit = [L for L in range(im.shape[0]) if im[L, x0:x0 + 8 * vis].sum() > 0]
    print(f"lignes affichées : {lit[0]} -> {lit[-1]} (attendu {FB_TOP} -> {FB_TOP + FB_H - 1})")
    bad = []
    for y in range(FB_H):
        for k in range(vis):
            if list(idx[FB_TOP + y, 8 * k:8 * k + 8]) != fb[y][8 * k:8 * k + 8]:
                bad.append((FB_TOP + y, k))
    print(f"groupes différents : {len(bad)} / {FB_H * vis}")
    if bad:
        ls = sorted({b[0] for b in bad})
        print(f"  lignes {ls[0]}-{ls[-1]} ({len(ls)}), groupes {sorted({b[1] for b in bad})}")
    ok = lit[0] == FB_TOP and lit[-1] == FB_TOP + FB_H - 1 and len(bad) <= 48 \
        and (not bad or max(b[0] for b in bad) - min(b[0] for b in bad) < 16)
    print("OK" if ok else "ÉCHEC")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
