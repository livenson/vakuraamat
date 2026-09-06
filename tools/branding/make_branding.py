#!/usr/bin/env python3
"""The app's icon and boot splash, drawn from the book's own palette and a real plate of parcels.

    python3 tools/branding/make_branding.py

Writes assets/branding/icon.png (1024), icon_512.png, icon.icns (macOS, via iconutil), icon.ico
(Windows) and splash.png (1920x1080). The plate is a window of Kvissentali's cadastral units
(sites/kvissentali/parcels.json, Maa-amet) in the ledger's blue on the page colour, one plot in gold:
the same thing the front page shows. Fonts: EB Garamond (title), IBM Plex Sans (small text), both OFL.
"""
import json, os, shutil, subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "branding")
PAGE, PAGE_LIGHT, PAGE_DARK = (0xDC, 0xD5, 0xC1), (0xEB, 0xE5, 0xD4), (0xCF, 0xC7, 0xB1)
INK, FADED, BLUE, RUBRIC, GOLD = (0x22, 0x1E, 0x19), (0x6B, 0x62, 0x55), (0x2D, 0x5F, 0x8B), (0x8E, 0x3A, 0x2F), (0xC9, 0x9A, 0x2E)
GARAMOND = os.path.join(ROOT, "assets/fonts/EBGaramond[wght].ttf")
PLEX = os.path.join(ROOT, "assets/fonts/IBMPlexSans[wdth,wght].ttf")
WINDOW = (330, 470, 690, 830)   # tile metres: a block of Kvissentali's plots that reads well small
OWNED = ""                      # the plot nearest the plate's centre, filled gold (set below)


def parcels():
    d = json.load(open(os.path.join(ROOT, "sites/kvissentali/parcels.json")))
    out = []
    for u in d["parcels"]:
        poly = u.get("polygon") or []
        if len(poly) < 3:
            continue
        xs = [p[0] for p in poly]; zs = [p[1] for p in poly]
        if max(xs) < WINDOW[0] or min(xs) > WINDOW[2] or max(zs) < WINDOW[1] or min(zs) > WINDOW[3]:
            continue
        out.append((u.get("tunnus"), poly))
    return out


def owned():
    """The plot to fill gold: the one whose centroid lies nearest the plate's centre."""
    cx, cz = (WINDOW[0] + WINDOW[2]) / 2, (WINDOW[1] + WINDOW[3]) / 2
    best = None
    for tunnus, poly in parcels():
        mx = sum(p[0] for p in poly) / len(poly); mz = sum(p[1] for p in poly) / len(poly)
        d = (mx - cx) ** 2 + (mz - cz) ** 2
        if best is None or d < best[0]:
            best = (d, tunnus)
    return best[1] if best else ""


def plate(size, line, scale=4):
    """The parcel plate as an RGBA image of `size` px, drawn at `scale` and downsampled (clean lines)."""
    global OWNED
    OWNED = OWNED or owned()
    s = size * scale
    im = Image.new("RGBA", (s, s), PAGE_LIGHT + (255,))
    d = ImageDraw.Draw(im)
    w = WINDOW[2] - WINDOW[0]
    k = s / w
    for tunnus, poly in parcels():
        pts = [((x - WINDOW[0]) * k, (z - WINDOW[1]) * k) for x, z in poly]
        if tunnus == OWNED:
            d.polygon(pts, fill=GOLD + (255,))
    for tunnus, poly in parcels():
        pts = [((x - WINDOW[0]) * k, (z - WINDOW[1]) * k) for x, z in poly]
        d.line(pts + [pts[0]], fill=BLUE + (255,), width=int(line * scale), joint="curve")
    return im.resize((size, size), Image.LANCZOS)


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m


def icon(size=1024):
    im = Image.new("RGBA", (size, size), PAGE + (255,))
    d = ImageDraw.Draw(im)
    # the page: a rubric rule down the left margin, the plate to its right
    margin = int(size * 0.13)
    d.line([(margin, int(size * 0.08)), (margin, int(size * 0.92))], fill=RUBRIC + (255,), width=max(2, size // 100))
    inset = int(size * 0.2)
    pl = plate(size - inset - int(size * 0.09), line=size / 200)
    im.paste(pl, (inset, int(size * 0.09)))
    d.rectangle([inset, int(size * 0.09), inset + pl.width - 1, int(size * 0.09) + pl.height - 1], outline=INK + (255,), width=max(1, size // 256))
    # a big V in the margin, the book's initial
    font = ImageFont.truetype(GARAMOND, int(size * 0.42))
    try:
        font.set_variation_by_axes([600])
    except Exception:  # noqa: BLE001 - static fallback
        pass
    d.text((int(size * 0.06), int(size * 0.5)), "V", font=font, fill=INK + (255,), anchor="lm")
    im.putalpha(rounded_mask(size, int(size * 0.22)))
    return im


def splash(w=1920, h=1080):
    im = Image.new("RGB", (w, h), PAGE)
    d = ImageDraw.Draw(im)
    d.line([(int(w * 0.045), 0), (int(w * 0.045), h)], fill=RUBRIC, width=3)
    title = ImageFont.truetype(GARAMOND, 150)
    try:
        title.set_variation_by_axes([500])
    except Exception:  # noqa: BLE001
        pass
    sub = ImageFont.truetype(GARAMOND, 44)
    small = ImageFont.truetype(PLEX, 22)
    d.text((int(w * 0.07), int(h * 0.30)), "Vakuraamat", font=title, fill=INK, anchor="ls")
    d.text((int(w * 0.07), int(h * 0.30) + 70), "Real plots, real values.", font=sub, fill=FADED, anchor="ls")
    d.text((int(w * 0.07), int(h * 0.30) + 120), "Päris maa, päris väärtused.", font=sub, fill=FADED, anchor="ls")
    d.line([(int(w * 0.07), int(h * 0.30) + 160), (int(w * 0.40), int(h * 0.30) + 160)], fill=PAGE_DARK, width=2)
    d.text((int(w * 0.07), int(h * 0.30) + 200), "Loading the ground…", font=small, fill=FADED, anchor="ls")
    side = int(h * 0.78)
    pl = plate(side, line=2.2).convert("RGB")
    x0, y0 = w - side - int(w * 0.06), (h - side) // 2
    im.paste(pl, (x0, y0))
    d.rectangle([x0, y0, x0 + side - 1, y0 + side - 1], outline=INK, width=2)
    d.text((x0, y0 + side + 30), "Kvissentali   L-EST97 657600 6477150   1024 m", font=small, fill=FADED, anchor="ls")
    d.text((w - int(w * 0.06), h - 28), "Map data: Maa- ja Ruumiamet 2026", font=small, fill=FADED, anchor="rs")
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    big = icon(1024)
    big.save(os.path.join(OUT, "icon.png"))
    big.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, "icon_512.png"))
    big.save(os.path.join(OUT, "icon.ico"), sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    if shutil.which("iconutil"):
        iset = os.path.join(OUT, "icon.iconset")
        os.makedirs(iset, exist_ok=True)
        for px in (16, 32, 128, 256, 512):
            big.resize((px, px), Image.LANCZOS).save(os.path.join(iset, f"icon_{px}x{px}.png"))
            big.resize((px * 2, px * 2), Image.LANCZOS).save(os.path.join(iset, f"icon_{px}x{px}@2x.png"))
        subprocess.run(["iconutil", "-c", "icns", iset, "-o", os.path.join(OUT, "icon.icns")], check=True)
        shutil.rmtree(iset)
    splash().save(os.path.join(OUT, "splash.png"))
    print("[branding] wrote", sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()
