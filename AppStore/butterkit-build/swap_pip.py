#!/usr/bin/env python3
"""Swap the picture-in-picture image on artboard 04-export-portrait of ReactCam.butterkit.

usage: python3 swap_pip.py <a|b|c|d | path/to/any.png>
       BUTTERKIT_PKG=/path/to/ReactCam.butterkit python3 swap_pip.py d   # target another copy of the package

Overwrites the artboard's asset in place (same filename, so Document.json is untouched).
Quit and reopen ButterKit afterwards -- it caches assets while the document is open.
"""
import sys, json, os
import prep

PKG = os.environ.get("BUTTERKIT_PKG", os.path.join(prep.HERE, "..", "ReactCam.butterkit"))
choice = sys.argv[1] if len(sys.argv) > 1 else "b"
doc = json.load(open(os.path.join(PKG, "Document.json")))
asset = next(a for a in doc["artboards"] if a["name"] == "04-export-portrait")["models"][0]["screenImageFilename"]
prep.composite_pip(prep.export_portrait_base(), prep.pip_option(choice)).save(os.path.join(PKG, "Assets", asset), optimize=True)
print(f"wrote {asset} from {os.path.basename(prep.pip_option(choice))} -> {PKG}\nnow quit and reopen ButterKit")
