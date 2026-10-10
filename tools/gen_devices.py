#!/usr/bin/env python3
"""Write docs/configurator/devices.json (name, id, display, resolution) for every product in manifest.xml.

Needs device definitions in ~/.Garmin/ConnectIQ/Devices (tools/setup_sdk.sh).
"""

import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEVICES = os.path.expanduser("~/.Garmin/ConnectIQ/Devices")


def main():
    ids = re.findall(r'<iq:product id="([^"]+)"', open(os.path.join(ROOT, "manifest.xml")).read())
    out = []
    for i in ids:
        with open(os.path.join(DEVICES, i, "compiler.json")) as f:
            c = json.load(f)
        out.append({"id": i, "name": c["displayName"], "display": "amoled" if c["displayType"] == "amoled" else "mip",
                    "size": c["resolution"]["width"]})
    out.sort(key=lambda d: d["name"])
    path = os.path.join(ROOT, "docs/configurator/devices.json")
    with open(path, "w") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print("wrote", path, len(out))


if __name__ == "__main__":
    main()
