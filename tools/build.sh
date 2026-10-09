#!/usr/bin/env bash
# Build Open Face.
#
#   tools/build.sh <sdk_dir> <developer_key.der> <out_dir> [check|iq|prg|all]
#
#   check  type-check (-l 3) a representative device set
#   iq     store package (.iq) for every product in manifest.xml
#   prg    one side-loadable .prg per product, zipped
#   all    iq + prg (default)
set -euo pipefail

SDK="$1"
KEY="$2"
OUT="$3"
WHAT="${4:-all}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MONKEYC="$SDK/bin/monkeyc"
mkdir -p "$OUT"

python3 "$ROOT/tools/gen_settings.py" >/dev/null

products() {
    grep -o '<iq:product id="[^"]*"' "$ROOT/manifest.xml" | cut -d'"' -f2
}

if [ "$WHAT" = "check" ]; then
    for d in fr970 fr965 fenix8solar47mm venu3 fr265s vivoactive6 fenix7pro; do
        echo "== $d"
        "$MONKEYC" -f "$ROOT/monkey.jungle" -d "$d" -o "$OUT/check-$d.prg" -y "$KEY" -l 3 -w
    done
    exit 0
fi

if [ "$WHAT" = "iq" ] || [ "$WHAT" = "all" ]; then
    "$MONKEYC" -f "$ROOT/monkey.jungle" -e -r -o "$OUT/OpenFace.iq" -y "$KEY"
fi

if [ "$WHAT" = "prg" ] || [ "$WHAT" = "all" ]; then
    mkdir -p "$OUT/prg"
    for d in $(products); do
        "$MONKEYC" -f "$ROOT/monkey.jungle" -d "$d" -r -o "$OUT/prg/OpenFace-$d.prg" -y "$KEY" >/dev/null
        echo "built $d"
    done
    rm -f "$OUT"/prg/*.debug.xml "$OUT"/prg/*-settings.json
    (cd "$OUT/prg" && zip -q -r ../OpenFace-prg.zip .)
fi
