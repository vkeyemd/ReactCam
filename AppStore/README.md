# App Store screenshots

How the ReactCam App Store screenshots are produced. Same pipeline as the Catalyst app:

```
developer's raw shots (screenshots/*.jpg)  →  prep to 1320×2868  →  ReactCam.butterkit artboards  →  ButterKit Publish  →  App Store Connect
                                                     ↑
                        generated picture-in-picture art (butterkit-build/pip-options/)
```

The app is **iPhone-only** (`TARGETED_DEVICE_FAMILY = 1`), so only the iPhone 6.9" set is needed.
App Store Connect reuses it for every smaller iPhone size.

## Layout

| Path | What |
| --- | --- |
| `screenshots/` | The raw shots as they came from the developer (five JPGs, 704–768 px wide) |
| `ReactCam.butterkit/` | The ButterKit document: `Document.json` + `Assets/<UUID>.png` (five iPhone 6.9" artboards) |
| `butterkit-build/prep.py` | Turns the raw JPGs into 1320×2868 screen assets and composites the PiP image |
| `butterkit-build/swap_pip.py` | Replaces the picture-in-picture image on screen 4 in place |
| `butterkit-build/build_package.py` | Full rebuild of the package (new asset UUIDs) when a raw shot or caption changes |
| `butterkit-build/gen_pip_candidates.py` | Generates PiP candidates with Z-Image Turbo on a ComfyUI server |
| `butterkit-build/pip-options/` | The four generated bunny reactions (`a`–`d`); `b` is the one in the package |

Scripts need Python 3 with Pillow (`pip3 install pillow`). Run them from inside `butterkit-build/`.

## The five screens

| # | Artboard | Source | Caption |
| --- | --- | --- | --- |
| 1 | Hero (tilted phone) | `react.jpg` home screen | ReactCam / Capture your kid's reaction to anything. |
| 2 | 02-pip-record | `react2.jpg` | Picture-in-picture reactions |
| 3 | 03-pip-swapped | `react3.jpg` | One tap to start recording |
| 4 | 04-export-portrait | `react5.jpg` + generated PiP | Drag, pinch and swap layers |
| 5 | 05-export-landscape | `react7.jpg` | Export portrait or landscape |

### How the raw shots were fixed up

- `react2/3/7.jpg` are 704×1527, the right aspect ratio: plain Lanczos resize to 1320×2868.
- `react.jpg` and `react5.jpg` are 768×1376, too short for the 6.9" screen. The app background is pure black, so
  `prep.py` inserts black rows: in the empty gap between the tagline and the buttons on the home screen, and as a
  status-bar zone (185 px) plus bottom safe area on the export screen, which had been cropped.
- `react5.jpg` had a **real photo** in the picture-in-picture box. No real people or pets in the store listing, so it
  is replaced by a generated bunny. The box is at (880, 1706)–(1141, 2170) on the finished asset, radius 15.
- Every shot is upscaled about 1.9×, so they are soft when zoomed. Native screenshots from a phone would improve them.
- `react5.jpg` is from an older build of the Layout & Export screen (`react7.jpg` shows the current one).

## Common tasks

**Pick a different picture-in-picture image** (fast, keeps every filename so `Document.json` is untouched):

```sh
cd AppStore/butterkit-build
python3 swap_pip.py d          # a | b | c | d, or a path to any PNG
```

**Rebuild everything** after replacing a raw JPG or editing a caption in `build_package.py`:

```sh
python3 build_package.py --pip b --bg preset-bg-7
```

**Generate new PiP candidates**: `gen_pip_candidates.py` posts the Z-Image Turbo graph to a ComfyUI server
(`EP` at the top of the file, 720×1280, 9 steps). Edit the prompts in `CANDS`; keep the character a bunny and the
setting a couch so it reads as the front camera.

## ButterKit notes

- Open `ReactCam.butterkit` in ButterKit, check each artboard, then **Publish** exports the App Store PNGs. There is no CLI.
- ButterKit **caches assets while a document is open**. After any script writes into the package, quit and reopen it.
- Captions have `paddingSides: 0`; a caption that wraps loses its second line off the bottom edge. Measure before
  changing copy: `ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 40, index=1).getlength(text)` must stay
  under about 550 px. `build_package.py` does this and picks the first candidate that fits.
- Background is ButterKit's bundled `preset-bg-7` (blue). Any `preset-bg-1`…`8` works; custom images must be added as
  `{"ref": {"name": "<file>.png", "type": "document"}}` with the file inside `Assets/`.
- Gavi also keeps a copy of the package in his iCloud ButterKit folder; this repo copy is the shared source of truth.
