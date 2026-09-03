"""Shared helpers: turn the raw developer JPGs into 1320x2868 screen assets and drop a PiP image into screen 4."""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "..", "screenshots")
W, H = 1320, 2868                      # iPhone 6.9" screen, what ButterKit's iPhone17ProMax model expects
SCALE_768 = W / 768                     # 1.71875
TOP_PAD_EXPORT = 185                    # black status-bar zone added above the cropped react5.jpg
# PiP inner rect on the finished screen-4 asset (react5.jpg x1.71875, +185px top pad), plus corner radius
PIP = (880, 1706, 1141, 2170)
PIP_RADIUS = 15


def _fit_exact(path):
    return Image.open(path).convert("RGB").resize((W, H), Image.LANCZOS)


def home_screen():
    """react.jpg is 768x1376 (too short). Insert black rows in the empty gap between the tagline and the buttons."""
    im = Image.open(os.path.join(RAW, "react.jpg")).convert("RGB")
    im = im.resize((W, round(im.height * SCALE_768)), Image.LANCZOS)
    need, cut = H - im.height, round(640 * SCALE_768)
    band = im.crop((0, cut, W, cut + 1)).resize((W, need))
    out = Image.new("RGB", (W, H))
    out.paste(im.crop((0, 0, W, cut)), (0, 0)); out.paste(band, (0, cut)); out.paste(im.crop((0, cut, W, im.height)), (0, cut + need))
    return out


def export_portrait_base():
    """react5.jpg is 768x1376 and cropped (no status bar / home indicator). Pad top and bottom with black."""
    im = Image.open(os.path.join(RAW, "react5.jpg")).convert("RGB")
    im = im.resize((W, round(im.height * SCALE_768)), Image.LANCZOS)
    need = H - im.height
    row = im.crop((0, round(100 * SCALE_768), W, round(100 * SCALE_768) + 1))
    out = Image.new("RGB", (W, H))
    out.paste(row.resize((W, TOP_PAD_EXPORT)), (0, 0)); out.paste(im, (0, TOP_PAD_EXPORT)); out.paste(row.resize((W, need - TOP_PAD_EXPORT)), (0, TOP_PAD_EXPORT + im.height))
    return out


def composite_pip(base, pip_path):
    """Center-crop pip_path to the PiP box ratio and paste it inside the existing light border with rounded corners."""
    x0, y0, x1, y1 = PIP
    g = Image.open(pip_path).convert("RGB")
    tr = (x1 - x0) / (y1 - y0)
    if g.width / g.height > tr:
        nw = round(g.height * tr); g = g.crop(((g.width - nw) // 2, 0, (g.width - nw) // 2 + nw, g.height))
    else:
        nh = round(g.width / tr); g = g.crop((0, (g.height - nh) // 2, g.width, (g.height - nh) // 2 + nh))
    g = g.resize((x1 - x0, y1 - y0), Image.LANCZOS)
    mask = Image.new("L", g.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, g.width - 1, g.height - 1], radius=PIP_RADIUS, fill=255)
    out = base.copy(); out.paste(g, (x0, y0), mask)
    return out


def pip_option(letter_or_path):
    if letter_or_path.endswith(".png"):
        return letter_or_path
    import glob
    return glob.glob(os.path.join(HERE, "pip-options", f"{letter_or_path}-*.png"))[0]


def all_screens(pip):
    """Ordered (name, image) for the five artboards."""
    return [
        ("Hero", home_screen()),
        ("02-pip-record", _fit_exact(os.path.join(RAW, "react2.jpg"))),
        ("03-pip-swapped", _fit_exact(os.path.join(RAW, "react3.jpg"))),
        ("04-export-portrait", composite_pip(export_portrait_base(), pip_option(pip))),
        ("05-export-landscape", _fit_exact(os.path.join(RAW, "react7.jpg"))),
    ]
