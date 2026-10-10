#!/usr/bin/env python3
"""Bake a configurator preset into the property defaults, for side-loaded builds.

    python3 tools/apply_preset.py openface-preset.json
    tools/build.sh "$SDK" developer_key.der build prg

The preset comes from the web configurator ("Download preset"). Only resources/properties/properties.xml
changes; revert it with `git checkout resources/properties/properties.xml`.
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    preset = json.load(open(sys.argv[1]))
    schema = json.load(open(os.path.join(ROOT, "docs/configurator/schema.json")))
    kinds = {s["key"]: s["kind"] for g in schema["groups"] for s in g["settings"]}
    path = os.path.join(ROOT, "resources/properties/properties.xml")
    xml = open(path).read()
    for key, val in preset.get("values", {}).items():
        kind = kinds.get(key)
        if kind is None:
            sys.exit("unknown setting: %s" % key)
        if kind == "bool":
            if not isinstance(val, bool):
                sys.exit("%s must be true or false" % key)
            text = "true" if val else "false"
        else:
            allowed = [v for v, _ in schema["enums"][kind]]
            if val not in allowed:
                sys.exit("%s: %r is not one of %s" % (key, val, allowed))
            text = str(val)
        xml, n = re.subn(r'(<property id="%s" type="\w+">)[^<]*(</property>)' % key, r"\g<1>%s\2" % text, xml)
        if n != 1:
            sys.exit("property %s not found" % key)
        print("%s = %s" % (key, text))
    open(path, "w").write(xml)
    print("updated", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
