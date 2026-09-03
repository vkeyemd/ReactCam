#!/usr/bin/env python3
"""Rebuild ReactCam.butterkit from scratch (new asset UUIDs) from ../screenshots/*.jpg.

usage: python3 build_package.py [--pip b] [--bg preset-bg-7] [--out ../ReactCam.butterkit]

Only needed when a raw screenshot or a caption changes; for a new PiP image use swap_pip.py instead.
Captions are measured with Helvetica Bold 40 as a proxy for ButterKit's System Default heavy: keep them under ~550px
or the second line falls off the bottom of the artboard.
"""
import argparse, json, os, shutil, uuid
from PIL import ImageFont
import prep

ap = argparse.ArgumentParser()
ap.add_argument("--pip", default="b"); ap.add_argument("--bg", default="preset-bg-7")
ap.add_argument("--out", default=os.path.join(prep.HERE, "..", "ReactCam.butterkit"))
args = ap.parse_args()

CAPTIONS = {   # first candidate that fits wins
    "02-pip-record": ["Picture-in-picture reactions"],
    "03-pip-swapped": ["One tap to start recording", "Record with a single tap"],
    "04-export-portrait": ["Drag, pinch and swap layers", "Drag and pinch to lay it out"],
    "05-export-landscape": ["Export portrait or landscape"],
}
TITLE, SUBTITLE, LIMIT = "ReactCam", "Capture your kid's reaction to anything.", 550
FONT = "/System/Library/Fonts/Helvetica.ttc"

def width(text, pt, bold=True):
    return ImageFont.truetype(FONT, pt, index=1 if bold else 0).getlength(text)

def pick(name):
    for s in CAPTIONS[name]:
        if width(s, 40) <= LIMIT: return s
    raise SystemExit(f"no caption fits for {name}")

sub_pt = next(pt for pt in (36, 34, 32, 30, 28) if width(SUBTITLE, pt, bold=False) <= LIMIT)
U = lambda: str(uuid.uuid4()).upper()
BG = {"image": {"fill": "fill", "ref": {"name": args.bg, "type": "bundle"}}}

screens = prep.all_screens(args.pip)
if os.path.exists(args.out): shutil.rmtree(args.out)
os.makedirs(os.path.join(args.out, "Assets"))
step, n = 1.7328, len(screens)
arts = []
for i, (name, im) in enumerate(screens):
    asset = U() + ".png"; im.save(os.path.join(args.out, "Assets", asset), optimize=True)
    hero = (name == "Hero"); mid = U()
    model = {"id": mid, "sourceModelID": mid, "assetName": "iPhone17ProMax", "instanceLabel": "iPhone16", "deviceStyle": "realistic",
             "clayColorHex": "#CCCCCCFF", "rotationEuler": [0, -0.46381047, -0.66531944] if hero else [0, 0, 0],
             "scale": [1.09] * 3 if hero else [1, 1, 1], "positionOffset": [0.0, 0.012, 0] if hero else [0, 0, 0],
             "uiOnlyOverlayCornerRadiusFactor": 0, "screenImageFilename": asset}
    base_tb = {"alignment": "center", "isItalic": False, "isUnderlined": False}
    if hero:
        tbs = [dict(base_tb, id=U(), index=0, string=TITLE, role="Title", fontFamily="Avenir Next", sizePt=44, weight="heavy", colorHex="#F5FCFFFF",
                    horizontalAlignment="leading", paddingTop=80.8, paddingSides=24.898407794676803),
               dict(base_tb, id=U(), index=1, string=SUBTITLE, role="SubTitle", fontFamily="System Default", sizePt=sub_pt, weight="regular",
                    colorHex="#E3F0FFFF", horizontalAlignment="center", paddingTop=89.53035884030417, paddingSides=0.0)]
    else:
        tbs = [dict(base_tb, id=U(), index=0, string=pick(name), role="Text1", fontFamily="System Default", sizePt=40, weight="heavy",
                    colorHex="#FFFFFFFF", horizontalAlignment="center", paddingTop=93.38908032319392, paddingSides=0.0)]
    arts.append({"id": U(), "name": name, "sequenceIndex": i + 1, "sizePresetID": "app_store_iphone", "size": [1.6125, 3.495],
                 "position": [round((i - (n - 1) / 2) * step, 4), 0.0, 0], "cameraProjection": "perspective", "perspectiveFOVDeg": 35,
                 "orthoHeight": 0.18917927, "background": BG, "models": [model], "textBlocks": tbs, "imageBlocks": []})
    print(f"{i+1} {name}: {[t['string'] for t in tbs]}")
json.dump({"schemaVersion": 1, "baseLanguageCode": "en", "artboards": arts}, open(os.path.join(args.out, "Document.json"), "w"), indent=1)
print("wrote", os.path.abspath(args.out))
