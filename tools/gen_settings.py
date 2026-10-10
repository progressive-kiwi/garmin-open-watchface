#!/usr/bin/env python3
"""Generate settings artefacts from one schema.

Outputs:
  resources/properties/properties.xml   property defaults
  resources/settings/settings.xml       Garmin Connect / Express settings UI
  resources/strings/settings_strings.xml titles and option labels
  source/gen/ConfigBase.mc              typed property cache (ConfigBase)
  source/gen/Schema.mc                  on-device settings menu schema
  docs/settings.qmd                     settings reference page
  source/gen/Themes.mc                  theme color table
  docs/configurator/schema.json         schema for the web configurator

Run from the repository root:  python3 tools/gen_settings.py
"""

import os
import re
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---------------------------------------------------------------- enums ----
# Every enum is a list of (value, label). Labels become string resources.

PALETTE = [
    (0x000000, "Black"), (0x000055, "Midnight"), (0x0000AA, "Navy"),
    (0x005555, "Deep teal"), (0x555555, "Dark gray"), (0xAAAAAA, "Light gray"),
    (0xFFFFFF, "White"), (0xFFFFAA, "Cream"), (0xFF0000, "Red"),
    (0xAA0000, "Dark red"), (0xFF5500, "Orange"), (0xFFAA00, "Amber"),
    (0xFFFF00, "Yellow"), (0xAAFF00, "Lime"), (0x00FF00, "Green"),
    (0x00AA00, "Forest"), (0x00AA55, "Emerald"), (0x00FFAA, "Mint"),
    (0x00FFFF, "Cyan"), (0x00AAFF, "Sky"), (0x0055FF, "Blue"),
    (0x5500FF, "Indigo"), (0xAA00FF, "Purple"), (0xFF00FF, "Magenta"),
    (0xFF55AA, "Pink"), (0xFFAA55, "Peach"), (0xAA5500, "Bronze"),
    (0x55AAAA, "Steel"),
]

AUTO = [(-1, "Auto (theme)")]

# Theme colors [background, primary, secondary, accent]; index = Theme value, 0 = custom (from settings).
THEMES = [
    [0x000000, 0xFFFFFF, 0xAAAAAA, 0xFF5500],  # custom placeholder
    [0x000000, 0xFFFFFF, 0xAAAAAA, 0xFF0000],  # classic
    [0x000000, 0xFFFFFF, 0xAAAAAA, 0xFF5500],  # racing
    [0x000055, 0xFFFFFF, 0x55AAAA, 0x00FFFF],  # ocean
    [0x000000, 0xFFFFAA, 0x00AA55, 0xAAFF00],  # forest
    [0x000000, 0xFFAA00, 0xAA5500, 0xFFFFAA],  # gold
    [0x000000, 0xFFFFFF, 0x55AAAA, 0x00AAFF],  # ice
    [0x000000, 0x00FFFF, 0xAA00FF, 0xFF00FF],  # neon
    [0xFFFFFF, 0x000000, 0x555555, 0xFF0000],  # paper
    [0x000000, 0xAAAAAA, 0x555555, 0xFFFFFF],  # stealth
    [0x000000, 0x00FF00, 0x00AA00, 0xFFAA00],  # tactical
]

# Settings that only matter on one display technology (used by the web configurator).
AMOLED_ONLY = {"AodColor", "AodOutline", "AodShift"}

FONTS = [
    (0, "System"), (1, "Condensed bold"), (2, "Roboto"), (3, "Roboto black"),
    (4, "Bionic"), (5, "Serif"), (6, "Condensed italic"),
    (7, "Quartz LCD"), (8, "Quartz outline"), (9, "Quartz thin"),
    (10, "Dot matrix"), (11, "Pixel blocks"), (12, "Dotted fine"),
    (13, "Segment upright"),
]

FIELDS = [
    (0, "Off"), (1, "Date"), (2, "Weekday + day"), (3, "Battery %"),
    (4, "Battery days"), (5, "Steps"), (6, "Heart rate"), (7, "Calories"),
    (8, "Distance"), (9, "Floors"), (10, "Active minutes"),
    (11, "Body Battery"), (12, "Stress"), (13, "Notifications"),
    (14, "Altitude"), (15, "Temperature"), (16, "Sunrise / sunset"),
    (17, "Week number"), (18, "Digital time"), (19, "Seconds"),
    (20, "Respiration"), (21, "Recovery time"), (22, "Day progress"),
]

GAUGES = [
    (0, "Off"), (1, "Battery"), (2, "Steps goal"), (3, "Body Battery"),
    (4, "Stress"), (5, "Active minutes goal"), (6, "Floors goal"),
    (7, "Seconds"), (8, "Heart rate"), (9, "Day progress"),
]

HANDS = [
    (0, "Baton"), (1, "Dauphine"), (2, "Sword"), (3, "Leaf"),
    (4, "Skeleton"), (5, "Arrow"), (6, "Needle"), (7, "Rounded"),
    (8, "Breguet"),
]

SECOND_HANDS = [
    (0, "Needle"), (1, "Lollipop"), (2, "Counterweight"), (3, "Arrow tip"),
    (4, "Square tip"),
]

SIZES3 = [(0, "Small"), (1, "Medium"), (2, "Large")]

ENUMS = {
    "mode": [(0, "Analog"), (1, "Digital")],
    "theme": [
        (0, "Custom"), (1, "Classic"), (2, "Racing"), (3, "Ocean"),
        (4, "Forest"), (5, "Gold"), (6, "Ice"), (7, "Neon"), (8, "Paper"),
        (9, "Stealth"), (10, "Tactical"),
    ],
    "palette": PALETTE,
    "palauto": AUTO + PALETTE,
    "fonts": FONTS,
    "aodfont": [(99, "Same as time")] + FONTS,
    "alayout": [
        (0, "Classic"), (1, "Chronograph"), (2, "Top + bottom"),
        (3, "Minimal"), (4, "Gauges"), (5, "Pilot"),
    ],
    "dlayout": [
        (0, "Classic"), (1, "Stacked"), (2, "Big"), (3, "Sport"),
        (4, "Minimal"), (5, "Side"),
    ],
    "hands": HANDS,
    "shand": SECOND_HANDS,
    "secmode": [(0, "Off"), (1, "Awake only"), (2, "Always (MIP)")],
    "handsize": [(0, "Slim"), (1, "Regular"), (2, "Bold")],
    "handlen": [(0, "Short"), (1, "Regular"), (2, "Long")],
    "cap": [(0, "None"), (1, "Dot"), (2, "Ring"), (3, "Large")],
    "hticks": [
        (0, "None"), (1, "Line"), (2, "Bar"), (3, "Dot"), (4, "Triangle"),
        (5, "Double line"), (6, "Diamond"),
    ],
    "mticks": [(0, "None"), (1, "Line"), (2, "Dot"), (3, "Railway")],
    "size3": SIZES3,
    "size4": SIZES3 + [(3, "Extra large")],
    "numerals": [
        (0, "None"), (1, "Quarters"), (2, "All"), (3, "Roman quarters"),
        (4, "Roman all"), (5, "12 only"),
    ],
    "ring": [(0, "None"), (1, "Thin"), (2, "Bezel"), (3, "Double")],
    "hourfmt": [(0, "System"), (1, "12 hour"), (2, "24 hour")],
    "sep": [(0, "Colon"), (1, "None"), (2, "Space")],
    "fields": FIELDS,
    "labels": [(0, "None"), (1, "Text")],
    "gauges": GAUGES,
    "datefmt": [
        (0, "FRI 9"), (1, "9 OCT"), (2, "FRI 9 OCT"), (3, "2026-10-09"),
        (4, "09.10"), (5, "10/09"),
    ],
    "aodstyle": [
        (0, "Auto"), (1, "Full face"), (2, "Minimal"), (3, "Minimal + date"),
        (4, "Time only"),
    ],
    "aodmarks": [(0, "None"), (1, "Quarters"), (2, "Hours")],
    "nighttrig": [(0, "Off"), (1, "Do Not Disturb / sleep mode"), (2, "Sleep schedule"), (3, "Either")],
    "fade": [(p, "%d%%" % p) for p in range(10, 100, 10)],
}

# --------------------------------------------------------------- schema ----
# (key, title, kind, default) ; kind = enum name or "bool".

GROUPS = [
    ("General", "Mode, theme and base colors", [
        ("Mode", "Watch mode", "mode", 0),
        ("Theme", "Color theme", "theme", 1),
        ("BgColor", "Custom background", "palette", 0x000000),
        ("PrimaryColor", "Custom primary", "palette", 0xFFFFFF),
        ("SecondaryColor", "Custom secondary", "palette", 0xAAAAAA),
        ("AccentColor", "Custom accent", "palette", 0xFF5500),
        ("SecondsMode", "Seconds", "secmode", 1),
        ("StatusIcons", "Status icons", "bool", True),
    ]),
    ("Analog", "Layout and hands", [
        ("AnalogLayout", "Analog layout", "alayout", 0),
        ("HourHand", "Hour hand", "hands", 0),
        ("MinuteHand", "Minute hand", "hands", 0),
        ("SecondHand", "Second hand", "shand", 1),
        ("HandSize", "Hand width", "handsize", 1),
        ("HandLength", "Hand length", "handlen", 1),
        ("HandOutline", "Hand outline", "bool", True),
        ("CenterCap", "Center cap", "cap", 1),
        ("HourHandColor", "Hour hand color", "palauto", -1),
        ("MinuteHandColor", "Minute hand color", "palauto", -1),
        ("SecondHandColor", "Second hand color", "palauto", -1),
    ]),
    ("Dial", "Ticks, numerals and ring", [
        ("HourTicks", "Hour ticks", "hticks", 2),
        ("MinuteTicks", "Minute ticks", "mticks", 1),
        ("TickLength", "Tick length", "size3", 1),
        ("QuarterEmphasis", "Emphasize 12/3/6/9", "bool", True),
        ("Numerals", "Numerals", "numerals", 0),
        ("NumeralFont", "Numeral font", "fonts", 1),
        ("NumeralSize", "Numeral size", "size3", 1),
        ("DialRing", "Dial ring", "ring", 0),
        ("HourTickColor", "Hour tick color", "palauto", -1),
        ("MinuteTickColor", "Minute tick color", "palauto", -1),
        ("NumeralColor", "Numeral color", "palauto", -1),
    ]),
    ("Digital", "Time font and layout", [
        ("DigitalLayout", "Digital layout", "dlayout", 0),
        ("TimeFont", "Time font", "fonts", 1),
        ("TimeSize", "Time size", "size4", 2),
        ("HourFormat", "Hour format", "hourfmt", 0),
        ("LeadingZero", "Leading zero", "bool", False),
        ("Separator", "Separator", "sep", 0),
        ("Ghost", "Unlit segments / dots", "bool", True),
        ("GhostColor", "Unlit color", "palauto", -1),
        ("HourDigitColor", "Hours color", "palauto", -1),
        ("MinuteDigitColor", "Minutes color", "palauto", -1),
    ]),
    ("Data", "Fields, gauges and date", [
        ("Field1", "Field 1", "fields", 1),
        ("Field2", "Field 2", "fields", 6),
        ("Field3", "Field 3", "fields", 5),
        ("Field4", "Field 4", "fields", 3),
        ("FieldFont", "Field font", "fonts", 0),
        ("FieldLabels", "Field labels", "labels", 1),
        ("FieldColor", "Field value color", "palauto", -1),
        ("LabelColor", "Field label color", "palauto", -1),
        ("GaugeLeft", "Left gauge", "gauges", 0),
        ("GaugeRight", "Right gauge", "gauges", 0),
        ("DateFormat", "Date format", "datefmt", 0),
    ]),
    ("AlwaysOn", "Low power display. AMOLED: burn-in safe face. MIP: theme colors, any background", [
        ("AodStyle", "AOD style", "aodstyle", 0),
        ("AodColor", "AOD color (AMOLED)", "palette", 0xAAAAAA),
        ("AodFont", "AOD font", "aodfont", 99),
        ("AodOutline", "Outline hands / digits (AMOLED)", "bool", True),
        ("AodMarkers", "AOD markers", "aodmarks", 1),
        ("AodShift", "Pixel shift (AMOLED)", "bool", True),
    ]),
    ("Night", "Fade all colors toward the background while sleeping", [
        ("NightTrigger", "Night dimming", "nighttrig", 0),
        ("NightFade", "Fade amount", "fade", 50),
    ]),
]


def sid(text):
    text = text.replace("%", " Pct").replace("+", " Plus").replace("/", " Slash").replace("-", " Dash").replace(".", " Dot")
    return re.sub(r"[^A-Za-z0-9]", "", text.title())


def enum_string_id(enum, idx):
    return "e_%s_%d" % (enum, idx)


def label_ids():
    """Map (enum, index) to a shared string id; identical labels share ids."""
    out = {}
    for enum, entries in ENUMS.items():
        for i, (_, label) in enumerate(entries):
            out[(enum, i)] = "o_" + sid(label)[:40] + ("N" if label[0].isdigit() else "")
    return out


def xml_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v)


def write(path, text):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as f:
        f.write(text)
    print("wrote", path)


def main():
    lid = label_ids()
    strings = {}
    for (enum, i), s in lid.items():
        label = ENUMS[enum][i][1]
        assert strings.get(s, label) == label, "string id collision: " + s
        strings[s] = label

    # ---- properties.xml
    props = ["<properties>"]
    for _, _, settings in GROUPS:
        for key, _, kind, default in settings:
            t = "boolean" if kind == "bool" else "number"
            props.append('    <property id="%s" type="%s">%s</property>' % (key, t, xml_value(default)))
    props.append("</properties>\n")
    write("resources/properties/properties.xml", "\n".join(props))

    # ---- settings.xml
    st = ["<settings>"]
    for gname, gdesc, settings in GROUPS:
        strings["g_" + gname] = re.sub(r"(?<!^)(?=[A-Z])", " ", gname).replace("Always On", "Always on")
        strings["gd_" + gname] = gdesc
        st.append('    <group id="%s" title="@Strings.g_%s" description="@Strings.gd_%s">' % (gname, gname, gname))
        for key, title, kind, _ in settings:
            strings["t_" + key] = title
            st.append('        <setting propertyKey="@Properties.%s" title="@Strings.t_%s">' % (key, key))
            if kind == "bool":
                st.append('            <settingConfig type="boolean" />')
            else:
                st.append('            <settingConfig type="list">')
                for i, (v, _) in enumerate(ENUMS[kind]):
                    st.append('                <listEntry value="%d">@Strings.%s</listEntry>' % (v, lid[(kind, i)]))
                st.append("            </settingConfig>")
            st.append("        </setting>")
        st.append("    </group>")
    st.append("</settings>\n")
    write("resources/settings/settings.xml", "\n".join(st))

    # ---- strings
    sx = ["<strings>"]
    for k in sorted(strings):
        sx.append('    <string id="%s">%s</string>' % (k, escape(strings[k])))
    sx.append("</strings>\n")
    write("resources/strings/settings_strings.xml", "\n".join(sx))

    header = "// GENERATED by tools/gen_settings.py. Do not edit by hand.\n\n"

    # ---- ConfigBase.mc
    cb = [header + "import Toybox.Application;\nimport Toybox.Lang;\n",
          "//! Raw property cache. Field names match property ids.",
          "class ConfigBase {"]
    for _, _, settings in GROUPS:
        for key, _, kind, default in settings:
            if kind == "bool":
                cb.append("    var %s as Boolean = %s;" % (key, xml_value(default)))
            else:
                cb.append("    var %s as Number = %s;" % (key, xml_value(default)))
    cb.append("")
    cb.append("    function initialize() {")
    cb.append("    }")
    cb.append("")
    cb.append("    function loadProperties() as Void {")
    for _, _, settings in GROUPS:
        for key, _, kind, default in settings:
            fn = "readBool" if kind == "bool" else "readNum"
            cb.append('        %s = %s("%s", %s);' % (key, fn, key, xml_value(default)))
    cb.append("    }")
    cb.append("""
    static function readNum(key as String, def as Number) as Number {
        var v = null;
        try {
            v = Properties.getValue(key);
        } catch (e) {
            v = null;
        }
        if (v instanceof Number) {
            return v;
        }
        if (v instanceof Long or v instanceof Float or v instanceof Double) {
            return v.toNumber();
        }
        return def;
    }

    static function readBool(key as String, def as Boolean) as Boolean {
        var v = null;
        try {
            v = Properties.getValue(key);
        } catch (e) {
            v = null;
        }
        if (v instanceof Boolean) {
            return v;
        }
        return def;
    }
}
""")
    write("source/gen/ConfigBase.mc", "\n".join(cb))

    # ---- Schema.mc
    sc = [header + "import Toybox.Lang;\nimport Toybox.WatchUi;\n",
          "//! On-device settings schema. Built lazily: only the settings menu calls it.",
          "module Schema {",
          "",
          "    //! Option list for an enum: Array of [value, label].",
          "    function options(e as Number) as Array<Array> {",
          "        switch (e) {"]
    enum_names = list(ENUMS.keys())
    for ei, enum in enumerate(enum_names):
        sc.append("            case %d:" % ei)
        items = ", ".join("[%d, Rez.Strings.%s]" % (v, lid[(enum, i)]) for i, (v, _) in enumerate(ENUMS[enum]))
        sc.append("                return [%s];" % items)
    sc.append("        }")
    sc.append("        return [];")
    sc.append("    }")
    sc.append("")
    sc.append("    //! Groups: Array of [title, Array of [key, title, enumIndex or -1 for boolean]].")
    sc.append("    function groups() as Array<Array> {")
    sc.append("        return [")
    for gname, _, settings in GROUPS:
        rows = []
        for key, _, kind, _ in settings:
            ei = -1 if kind == "bool" else enum_names.index(kind)
            rows.append('                ["%s", Rez.Strings.t_%s, %d]' % (key, key, ei))
        sc.append("            [Rez.Strings.g_%s, [\n%s\n            ]]," % (gname, ",\n".join(rows)))
    sc[-1] = sc[-1].rstrip(",")
    sc.append("        ];")
    sc.append("    }")
    sc.append("}\n")
    write("source/gen/Schema.mc", "\n".join(sc))

    # ---- docs
    md = ["---", "title: Settings reference", "---", "",
          "Every setting is available in the Garmin Connect app, Garmin Express, and on the watch",
          "(hold the menu button on the watch face → **Watch Face** → **Customize**).",
          "Colors set to **Auto (theme)** follow the selected color theme.", "",
          "This page is generated from `tools/gen_settings.py`.", ""]
    for gname, gdesc, settings in GROUPS:
        md.append("## %s" % strings["g_" + gname])
        md.append("")
        md.append(gdesc + ".")
        md.append("")
        md.append("| Key | Setting | Default | Options |")
        md.append("|---|---|---|---|")
        for key, title, kind, default in settings:
            if kind == "bool":
                opts, d = "on / off", ("on" if default else "off")
            else:
                entries = ENUMS[kind]
                d = next(l for v, l in entries if v == default)
                if kind in ("palette", "palauto"):
                    opts = "%d colors%s" % (len(PALETTE), " + Auto" if kind == "palauto" else "")
                else:
                    opts = ", ".join(l for _, l in entries)
            md.append("| `%s` | %s | %s | %s |" % (key, title, d, opts))
        md.append("")
    md.append("## Color palette")
    md.append("")
    md.append("Values come from the 64-color MIP palette, so they render identically on MIP and AMOLED.")
    md.append("")
    md.append("| Color | Hex |")
    md.append("|---|---|")
    for v, label in PALETTE:
        md.append('| <span style="display:inline-block;width:1em;height:1em;border:1px solid #888;background:#%06X"></span> %s | `#%06X` |' % (v, label, v))
    md.append("")
    write("docs/settings.qmd", "\n".join(md))

    # ---- Themes.mc
    rows = ",\n".join("        [%s]" % ", ".join("0x%06X" % c for c in t) for t in THEMES)
    write("source/gen/Themes.mc", header + "import Toybox.Lang;\n\nmodule Themes {\n"
          "    //! [background, primary, secondary, accent] per Theme value; 0 = custom.\n"
          "    const TABLE = [\n%s\n    ];\n}\n" % rows)

    # ---- configurator schema
    import json
    schema = {
        "themes": THEMES,
        "palette": PALETTE,
        "enums": {k: v for k, v in ENUMS.items()},
        "amoledOnly": sorted(AMOLED_ONLY),
        "groups": [
            {"id": g, "title": strings["g_" + g], "description": d,
             "settings": [{"key": k, "title": t, "kind": kind, "default": dflt} for k, t, kind, dflt in settings]}
            for g, d, settings in GROUPS
        ],
    }
    write("docs/configurator/schema.json", json.dumps(schema, indent=1, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
