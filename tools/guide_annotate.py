"""Draws numbered arrows on the guide's screenshots (R14). See guide_annotate.py.md."""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

GREEN = (118, 185, 0)

# name -> (source capture, crop box in the capture, [(x, y, label-less arrow target, text side)]) in capture pixels.
SPECS = {
    "tab_overview": ("shot-03-tab_remix_settings.png", (724, 0, 1280, 500), [
        (855, 9, "up"), (797, 100, "left"), (1060, 45, "right")]),
    "remix_settings": ("shot-03-tab_remix_settings.png", (724, 0, 1280, 500), [
        (885, 89, "left"), (1100, 131, "left"), (1185, 245, "up"), (1100, 335, "left"), (1070, 487, "up")]),
    "glass_settings": ("shot-07-tab_glass_settings.png", (724, 0, 1280, 720), [
        (1056, 199, "up"), (885, 224, "left"), (1085, 372, "up"), (1075, 507, "up")]),
    "remix_menu_marked": ("@remix_menu.jpg", (590, 0, 960, 540), [
        (765, 35, "right"), (700, 75, "down"), (700, 128, "down"), (790, 334, "right"), (790, 462, "right")]),
    "guide_window": ("shot-11-guide_welcome.png", (160, 15, 1120, 330), [
        (400, 60, "up"), (1098, 32, "left"), (650, 200, "up")]),
}


def font(size):
    for name in ("arialbd.ttf", "segoeuib.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def annotate(src, box, marks, scale=2):
    img = Image.open(src).convert("RGB").crop(box)
    img = img.resize((img.width * scale, img.height * scale), Image.LANCZOS)
    d = ImageDraw.Draw(img)
    f = font(22)
    for n, (x, y, side) in enumerate(marks, 1):
        tx, ty = (x - box[0]) * scale, (y - box[1]) * scale
        dx, dy = {"left": (-90, 0), "right": (90, 0), "up": (0, -60), "down": (0, 60)}[side]
        if side == "left" and tx + dx < 40: dx = 90
        if side == "up" and ty + dy < 30: dy = 60
        bx, by = tx + dx, ty + dy
        d.line([(bx, by), (tx, ty)], fill=GREEN, width=4)
        # arrow head
        import math
        a = math.atan2(ty - by, tx - bx)
        for s in (-0.5, 0.5):
            d.line([(tx, ty), (tx - 16 * math.cos(a + s), ty - 16 * math.sin(a + s))], fill=GREEN, width=4)
        d.ellipse([bx - 17, by - 17, bx + 17, by + 17], fill=GREEN, outline=(0, 0, 0), width=2)
        d.text((bx, by), str(n), fill=(0, 0, 0), font=f, anchor="mm")
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shots", required=True, help="folder with the poc_session captures")
    ap.add_argument("--out", required=True, help="folder for the JPEGs")
    a = ap.parse_args()
    Path(a.out).mkdir(parents=True, exist_ok=True)
    for name, (cap, box, marks) in SPECS.items():
        annotate(Path(a.out) / cap[1:] if cap.startswith("@") else Path(a.shots) / cap, box, marks).save(Path(a.out) / f"{name}.jpg", quality=88)
        print("wrote", name)


if __name__ == "__main__":
    main()
