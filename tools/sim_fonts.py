#!/usr/bin/env python3
"""Populate ~/.Garmin/ConnectIQ/Fonts with open-licensed stand-ins for device TTF fonts.

The Connect IQ simulator loads device fonts from the Fonts folder that the SDK Manager
normally downloads (Garmin login required). For headless CI screenshots, this maps every
TTF font a device declares to a font from Debian/Ubuntu packages:
fonts-roboto-unhinted fonts-nanum fonts-noto-core.

Garmin's proprietary faces (Bionic, Kosugi, Pridi) get visually similar substitutes, so
screenshots are representative, not pixel-exact.

Usage: sim_fonts.py [devices_dir] [fonts_dir]
"""

import json
import os
import shutil
import sys

ROBOTO = "/usr/share/fonts/truetype/roboto/unhinted/"
NOTO = "/usr/share/fonts/truetype/noto/"
NANUM = "/usr/share/fonts/truetype/nanum/"


def source_for(name):
    n = name.lower()
    rules = [
        ("robotocondensed-bold", ROBOTO + "RobotoCondensed-Bold.ttf"),
        ("robotocondensed-regularitalic", ROBOTO + "RobotoCondensed-Italic.ttf"),
        ("robotocondensed-regular", ROBOTO + "RobotoCondensed-Regular.ttf"),
        ("roboto-condensed", ROBOTO + "RobotoCondensed-Regular.ttf"),
        ("bionic", ROBOTO + "RobotoCondensed-Bold.ttf"),
        ("roboto-black", ROBOTO + "RobotoTTF/Roboto-Black.ttf"),
        ("roboto-italic", ROBOTO + "RobotoTTF/Roboto-Italic.ttf"),
        ("roboto-medium", ROBOTO + "RobotoTTF/Roboto-Medium.ttf"),
        ("roboto-bold", ROBOTO + "RobotoTTF/Roboto-Bold.ttf"),
        ("nanumgothic", NANUM + "NanumGothicBold.ttf"),
        ("pridi-semibold", NOTO + "NotoSerif-Bold.ttf"),
        ("pridi", NOTO + "NotoSerif-Regular.ttf"),
        ("notonaskharabic-bold", NOTO + "NotoNaskhArabic-Bold.ttf"),
        ("notonaskharabic", NOTO + "NotoNaskhArabic-Regular.ttf"),
        ("notosansarmenian-bold", NOTO + "NotoSansArmenian-Bold.ttf"),
        ("notosansarmenian", NOTO + "NotoSansArmenian-Regular.ttf"),
        ("notosanshebrew-bold", NOTO + "NotoSansHebrew-Bold.ttf"),
        ("notosanshebrew", NOTO + "NotoSansHebrew-Regular.ttf"),
    ]
    for key, path in rules:
        if n.startswith(key):
            return path
    if n.startswith("kosugi") or n.startswith("notosans"):
        return NOTO + "NotoSans-Regular.ttf"
    return ROBOTO + "RobotoTTF/Roboto-Regular.ttf"


def main():
    home = os.path.expanduser("~/.Garmin/ConnectIQ")
    devices = sys.argv[1] if len(sys.argv) > 1 else os.path.join(home, "Devices")
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(home, "Fonts")
    os.makedirs(out, exist_ok=True)
    names = set()
    for dev in os.listdir(devices):
        p = os.path.join(devices, dev, "simulator.json")
        if not os.path.exists(p):
            continue
        with open(p) as f:
            sim = json.load(f)
        for fs in sim.get("fonts", []):
            for font in fs.get("fonts", []):
                if font.get("type") in ("ttf", "system_ttf"):
                    names.add(font["filename"])
    for name in sorted(names):
        src = source_for(name)
        if os.path.exists(src):
            shutil.copyfile(src, os.path.join(out, name + ".ttf"))
    print("installed %d font stand-ins into %s" % (len(names), out))


if __name__ == "__main__":
    main()
