#!/usr/bin/env python3
"""Paints a timetable over the advert panels baked into the Sketchfab town shelter's texture atlas
(assets/vendor/sketchfab/bus_stop_town.glb, Ottto3ds, CC BY) and rewrites the glb in place.
The game paints the nearest companies' poster over the second panel at runtime (RoadNetwork._poster).

    python3 tools/textures/shelter_board.py [--flip]
"""
import io, json, struct, sys
from PIL import Image, ImageDraw, ImageFont

SRC = "assets/vendor/sketchfab/bus_stop_town.glb"
PANELS = [(595, 690, 800, 1015), (812, 690, 1015, 1015)]   # in the 1024 px atlas
FONT = "/System/Library/Fonts/Helvetica.ttc"


def board(w, h, flip):
    p = Image.new("RGBA", (w, h), (236, 236, 230, 255))
    d = ImageDraw.Draw(p)
    d.rectangle([0, 0, w, int(h * 0.12)], fill=(20, 60, 120, 255))
    try:
        f = ImageFont.truetype(FONT, int(h * 0.06)); f2 = ImageFont.truetype(FONT, int(h * 0.035))
    except OSError:
        f = f2 = ImageFont.load_default()
    d.text((int(w * 0.06), int(h * 0.025)), "SÕIDUPLAAN", fill=(255, 255, 255, 255), font=f)
    y = int(h * 0.17)
    for i, (no, dest) in enumerate([("2", "Kesklinn"), ("5", "Raudteejaam"), ("10", "Annelinn"), ("22", "Lõunakeskus"), ("27", "Ihaste")]):
        d.rectangle([int(w * 0.06), y, int(w * 0.18), y + int(h * 0.05)], fill=(20, 60, 120, 255))
        d.text((int(w * 0.075), y + int(h * 0.005)), no, fill=(255, 255, 255, 255), font=f2)
        d.text((int(w * 0.22), y + int(h * 0.005)), dest, fill=(40, 40, 40, 255), font=f2)
        yy = y + int(h * 0.07)
        for k in range(3):
            d.text((int(w * 0.06), yy), "  ".join(f"{6 + k * 5 + i:02d}:{m:02d}" for m in (5, 25, 45)), fill=(90, 90, 90, 255), font=f2)
            yy += int(h * 0.045)
        y = yy + int(h * 0.02)
    return p.transpose(Image.FLIP_TOP_BOTTOM) if flip else p


def main():
    flip = "--flip" in sys.argv
    b = open(SRC, "rb").read()
    ln = struct.unpack_from("<I", b, 12)[0]
    j = json.loads(b[20:20 + ln])
    off = 20 + ln
    cl = struct.unpack_from("<I", b, off)[0]
    bin_ = bytearray(b[off + 8:off + 8 + cl])
    img0 = j["images"][0]
    bv0 = j["bufferViews"][img0["bufferView"]]
    start = bv0.get("byteOffset", 0)
    im = Image.open(io.BytesIO(bytes(bin_[start:start + bv0["byteLength"]]))).convert("RGBA")
    w, h = im.size
    for box in PANELS:
        x0, y0, x1, y1 = [int(v * w / 1024) for v in box]
        im.paste(board(x1 - x0, y1 - y0, flip), (x0, y0))
    out = io.BytesIO()
    im.save(out, "PNG")
    new = out.getvalue()
    old_end_pad = (start + bv0["byteLength"] + 3) // 4 * 4
    new_padded = new + b"\x00" * ((4 - len(new) % 4) % 4)
    delta = (start + len(new_padded)) - old_end_pad
    newbin = bytes(bin_[:start]) + new_padded + bytes(bin_[old_end_pad:])
    for i, bv in enumerate(j["bufferViews"]):
        if i == img0["bufferView"]:
            bv["byteLength"] = len(new)
        elif bv.get("byteOffset", 0) > start:
            bv["byteOffset"] = bv.get("byteOffset", 0) + delta
    j["buffers"][0]["byteLength"] = len(newbin)
    jb = json.dumps(j, separators=(",", ":")).encode()
    jb += b" " * ((4 - len(jb) % 4) % 4)
    glb = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(jb) + 8 + len(newbin)) + struct.pack("<II", len(jb), 0x4E4F534A) + jb + struct.pack("<II", len(newbin), 0x004E4942) + newbin
    open(SRC, "wb").write(glb)
    print(f"[shelter_board] rewrote {SRC} ({len(glb)} bytes, flip={flip})")


if __name__ == "__main__":
    main()
