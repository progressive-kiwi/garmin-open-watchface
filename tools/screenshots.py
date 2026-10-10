#!/usr/bin/env python3
"""Render documentation screenshots with the Connect IQ simulator.

For each variant a patched copy of the project is built: property defaults are replaced
with the variant's overrides, the clock is pinned to 10:09:36, and (for always-on shots)
the view starts asleep. The simulator runs under Xvfb; the watch display is cropped from
the window and masked to a circle.

Requirements: Connect IQ SDK, device files and font stand-ins (tools/setup_sdk.sh),
Xvfb, ImageMagick (import, convert).

Usage: tools/screenshots.py --sdk DIR --key developer_key.der --out docs/images [--only slug,...]
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEVICES = os.path.expanduser("~/.Garmin/ConnectIQ/Devices")
MENU_BAR = 24  # simulator menu bar height under Xvfb (no window manager)

# (slug, caption, device, overrides, asleep)
VARIANTS = [
    ("analog-classic", "Analog · Classic layout, baton hands, bar ticks, date window", "fr970", {}, False),
    ("analog-chronograph", "Analog · Chronograph subdials, dauphine hands, bezel, Ocean theme", "fr970",
     {"AnalogLayout": 1, "Theme": 3, "HourHand": 1, "MinuteHand": 1, "HourTicks": 6, "DialRing": 2,
      "Field1": 5, "Field2": 3, "Field3": 11, "Field4": 6, "SecondHand": 3}, False),
    ("analog-pilot", "Analog · Pilot layout, sword hands, full numerals", "fr970",
     {"AnalogLayout": 5, "Numerals": 2, "NumeralFont": 1, "HourHand": 2, "MinuteHand": 2, "SecondHand": 2,
      "HourTicks": 1, "Theme": 9, "Field2": 15}, False),
    ("analog-roman", "Analog · Roman numerals, Breguet hands, railway track, Gold theme", "fr970",
     {"AnalogLayout": 2, "Numerals": 4, "NumeralFont": 5, "Theme": 5, "HourHand": 8, "MinuteHand": 8,
      "MinuteTicks": 3, "HourTicks": 0, "CenterCap": 2, "Field1": 1, "Field2": 11, "Field3": 0, "Field4": 0},
     False),
    ("analog-gauges", "Analog · Gauges layout, skeleton hands, dot-matrix numerals, Neon theme", "fr970",
     {"AnalogLayout": 4, "GaugeLeft": 2, "GaugeRight": 1, "Theme": 7, "HourHand": 4, "MinuteHand": 4,
      "Numerals": 1, "NumeralFont": 10, "HourTicks": 5, "Field1": 2, "Field2": 6}, False),
    ("analog-minimal", "Analog · Minimal layout, rounded hands, dot ticks, Paper theme", "fr970",
     {"AnalogLayout": 3, "HourTicks": 3, "MinuteTicks": 0, "HourHand": 7, "MinuteHand": 7, "Theme": 8,
      "SecondHand": 4, "HandSize": 0, "CenterCap": 3}, False),
    ("analog-forest", "Analog · Arrow and leaf hands, triangle ticks, Forest theme", "fr970",
     {"HourHand": 3, "MinuteHand": 5, "HourTicks": 4, "MinuteTicks": 2, "Theme": 4, "DialRing": 3,
      "Field2": 16, "Field3": 8}, False),
    ("digital-classic", "Digital · Classic layout, condensed bold", "fr970", {"Mode": 1}, False),
    ("digital-quartz", "Digital · Quartz LCD with unlit segments, Sport layout, gauges", "fr970",
     {"Mode": 1, "TimeFont": 7, "DigitalLayout": 3, "Theme": 10, "GaugeLeft": 2, "GaugeRight": 3,
      "FieldFont": 7, "Field4": 12}, False),
    ("digital-dotmatrix", "Digital · Dot matrix, Racing theme", "fr970",
     {"Mode": 1, "TimeFont": 10, "Theme": 2, "FieldFont": 10}, False),
    ("digital-pixel", "Digital · Pixel blocks, Minimal layout, Ice theme", "fr970",
     {"Mode": 1, "TimeFont": 11, "DigitalLayout": 4, "Theme": 6, "TimeSize": 3, "FieldFont": 11}, False),
    ("digital-stacked", "Digital · Stacked layout, Roboto black, two-tone", "fr970",
     {"Mode": 1, "DigitalLayout": 1, "TimeFont": 3, "Theme": 2, "TimeSize": 3}, False),
    ("digital-side", "Digital · Side layout, field column, Ocean theme", "fr970",
     {"Mode": 1, "DigitalLayout": 5, "TimeFont": 1, "Theme": 3, "TimeSize": 3, "Field1": 5, "Field2": 6,
      "Field3": 11, "Field4": 1}, False),
    ("digital-big", "Digital · Big layout, thin quartz, Stealth theme", "fr970",
     {"Mode": 1, "DigitalLayout": 2, "TimeFont": 9, "Theme": 9}, False),
    ("digital-outline", "Digital · Quartz outline, Classic theme, seconds", "fr970",
     {"Mode": 1, "TimeFont": 8, "Theme": 1, "Ghost": False}, False),
    ("digital-serif", "Digital · Serif, Minimal layout, Gold theme", "fr970",
     {"Mode": 1, "TimeFont": 5, "DigitalLayout": 4, "Theme": 5, "TimeSize": 3}, False),
    ("aod-analog", "Always-on · Analog, outline hands, quarter markers, date", "fr970", {}, True),
    ("aod-digital", "Always-on · Digital, quartz outline", "fr970", {"Mode": 1, "TimeFont": 7}, True),
    ("mip-analog", "MIP display (fēnix 8 Solar) · Analog classic", "fenix8solar47mm", {"Theme": 2}, False),
    ("mip-digital", "MIP display (fēnix 8 Solar) · Digital quartz", "fenix8solar47mm",
     {"Mode": 1, "TimeFont": 7, "Theme": 10}, False),
    ("mip-paper-analog", "MIP · White background (Paper theme), Arabic numerals, railway track", "fenix8solar47mm",
     {"Theme": 8, "Numerals": 2, "NumeralFont": 1, "MinuteTicks": 3, "HourTicks": 1, "HourHand": 2,
      "MinuteHand": 2}, False),
    ("mip-paper-digital", "MIP · White background, Quartz LCD with unlit segments", "fenix8solar47mm",
     {"Theme": 8, "Mode": 1, "TimeFont": 7, "GaugeLeft": 2, "GaugeRight": 1}, False),
    ("mip-paper-lowpower", "MIP · Low power, Minimal + date style on white", "fenix8solar47mm",
     {"Theme": 8, "AodStyle": 3}, True),
]


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, **kw)


def patch_project(dst, overrides, asleep):
    shutil.copytree(os.path.join(ROOT, "source"), os.path.join(dst, "source"))
    shutil.copytree(os.path.join(ROOT, "resources"), os.path.join(dst, "resources"))
    shutil.copy(os.path.join(ROOT, "monkey.jungle"), dst)
    manifest = open(os.path.join(ROOT, "manifest.xml")).read()
    # Fresh app id per variant so the simulator never reuses stored properties.
    manifest = re.sub(r'id="[0-9a-f]{32}"', 'id="%s"' % uuid.uuid4().hex, manifest, count=1)
    open(os.path.join(dst, "manifest.xml"), "w").write(manifest)

    pp = os.path.join(dst, "resources/properties/properties.xml")
    props = open(pp).read()
    for key, val in overrides.items():
        v = ("true" if val else "false") if isinstance(val, bool) else str(val)
        props, n = re.subn(r'(<property id="%s" type="\w+">)[^<]*(</property>)' % key, r"\g<1>%s\2" % v, props)
        if n != 1:
            sys.exit("unknown property " + key)
    open(pp, "w").write(props)

    clock = os.path.join(dst, "source/Clock.mc")
    open(clock, "w").write("""import Toybox.Lang;
import Toybox.System;
module Clock {
    function time() as ClockTime {
        var t = System.getClockTime();
        t.hour = 10;
        t.min = 9;
        t.sec = 36;
        return t;
    }
}
""")
    if asleep:
        fv = os.path.join(dst, "source/FaceView.mc")
        src = open(fv).read().replace("_awake = true;", "_awake = false;")
        src = src.replace("private var _awake as Boolean = true;", "private var _awake as Boolean = false;")
        open(fv, "w").write(src)


def image_signature(path):
    return subprocess.run(["identify", "-format", "%#", path], check=True, capture_output=True, text=True).stdout


def blank(path):
    out = subprocess.run(["convert", path, "-format", "%[fx:standard_deviation]", "info:"], check=True,
                         capture_output=True, text=True).stdout
    return float(out) < 0.01


def display_box(device):
    with open(os.path.join(DEVICES, device, "simulator.json")) as f:
        loc = json.load(f)["display"]["location"]
    return loc["x"], loc["y"] + MENU_BAR, loc["width"], loc["height"]


def write_gallery(rows):
    """docs/gallery.qmd: one section per group, images in a grid."""
    groups = [("analog", "Analog"), ("digital", "Digital"), ("aod", "Always-on (AMOLED)"),
              ("mip", "Memory-in-pixel displays")]
    out = ["---", "title: Gallery", "---", "",
           "Rendered by the Connect IQ simulator (Forerunner 970 unless noted) with the clock pinned to 10:09:36.",
           "Simulated sensor values; weather is unavailable in the simulator. The exact settings behind each image",
           "are listed in `VARIANTS` in `tools/screenshots.py`.", ""]
    for prefix, title in groups:
        out += ["## " + title, "", '::: {.grid}', ""]
        for r in rows:
            if r["slug"].startswith(prefix + "-"):
                out += ['::: {.g-col-12 .g-col-md-6 .g-col-lg-4 .shot}',
                        "![%s](images/%s.png){fig-alt=\"%s\"}" % (r["caption"], r["slug"], r["caption"]),
                        ":::", ""]
        out += [":::", ""]
    with open(os.path.join(ROOT, "docs/gallery.qmd"), "w") as f:
        f.write("\n".join(out))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sdk", required=True)
    ap.add_argument("--key", required=True)
    ap.add_argument("--out", default=os.path.join(ROOT, "docs/images"))
    ap.add_argument("--only", default="")
    ap.add_argument("--wait", type=float, default=9.0)
    args = ap.parse_args()
    only = set(filter(None, args.only.split(",")))
    os.makedirs(args.out, exist_ok=True)
    sdk_bin = os.path.join(args.sdk, "bin")

    display = ":91"
    env = dict(os.environ, DISPLAY=display)
    xvfb = subprocess.Popen(["Xvfb", display, "-screen", "0", "1280x1100x24"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2)
    sim = subprocess.Popen([os.path.join(sdk_bin, "simulator")], env=env,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(15)
    manifest_rows = []
    failures = 0

    try:
        for slug, caption, device, overrides, asleep in VARIANTS:
            if only and slug not in only:
                continue
            work = tempfile.mkdtemp(prefix="shot-")
            try:
                patch_project(work, overrides, asleep)
                prg = os.path.join(work, "app.prg")
                run([os.path.join(sdk_bin, "monkeyc"), "-f", os.path.join(work, "monkey.jungle"), "-d", device,
                     "-o", prg, "-y", args.key], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                x, y, w, h = display_box(device)
                raw = os.path.join(work, "raw.png")
                crop = os.path.join(work, "crop.png")

                def grab():
                    run(["import", "-display", display, "-window", "root", raw])
                    run(["convert", raw, "-crop", "%dx%d+%d+%d" % (w, h, x, y), "+repage", crop])
                    return image_signature(crop)

                before = grab()
                md = subprocess.Popen([os.path.join(sdk_bin, "monkeydo"), prg, device], env=env,
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                # Wait until the display differs from what was shown before launch, then settles.
                prev = before
                deadline = time.time() + args.wait * 6
                while True:
                    time.sleep(args.wait / 3)
                    sig = grab()
                    if sig != before and sig == prev and not blank(crop):
                        break
                    if time.time() > deadline:
                        raise subprocess.CalledProcessError(1, "timeout waiting for " + slug)
                    prev = sig
                md.kill()
                dst = os.path.join(args.out, slug + ".png")
                run(["convert", crop, "-alpha", "set",
                     "(", "-size", "%dx%d" % (w, h), "xc:none", "-fill", "white",
                     "-draw", "circle %d,%d %d,%d" % (w // 2, h // 2, w // 2, 3), ")",
                     "-compose", "DstIn", "-composite", dst])
                manifest_rows.append({"slug": slug, "caption": caption, "device": device})
                print("ok", slug)
            except subprocess.CalledProcessError as e:
                failures += 1
                print("FAILED", slug, e, file=sys.stderr)
            finally:
                shutil.rmtree(work, ignore_errors=True)
    finally:
        sim.kill()
        xvfb.kill()
    if not only:
        with open(os.path.join(args.out, "gallery.json"), "w") as f:
            json.dump(manifest_rows, f, indent=2)
        write_gallery(manifest_rows)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
