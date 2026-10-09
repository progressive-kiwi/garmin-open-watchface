#!/usr/bin/env bash
# Install the Connect IQ SDK, device definitions and simulator font stand-ins for headless builds.
#
#   tools/setup_sdk.sh [install_dir]
#
# - SDK: public Linux zip listed in Garmin's sdks.json (latest unless CIQ_SDK_VERSION is set).
# - Devices: the SDK Manager download needs a Garmin login, so device definitions are taken from
#   the public ghcr.io/matco/connectiq-tester image (override with CIQ_DEVICES_IMAGE).
# - Fonts: open-licensed stand-ins (tools/sim_fonts.py) so the simulator can render screenshots.
#
# Prints the SDK path on the last line.
set -euo pipefail

DIR="${1:-$HOME/.ciq}"
IMAGE="${CIQ_DEVICES_IMAGE:-matco/connectiq-tester}"
TAG="${CIQ_DEVICES_TAG:-latest}"
GARMIN="$HOME/.Garmin/ConnectIQ"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DIR" "$GARMIN"

# --- SDK -------------------------------------------------------------------------------------
INDEX="https://developer.garmin.com/downloads/connect-iq/sdks/sdks.json"
ZIP=$(curl -fsSL "$INDEX" | python3 -c "
import json, os, sys
sdks = json.load(sys.stdin)
want = os.environ.get('CIQ_SDK_VERSION')
pick = [s for s in sdks if s['version'] == want] if want else sdks
print(pick[-1]['linux'])
")
SDK="$DIR/${ZIP%.zip}"
if [ ! -x "$SDK/bin/monkeyc" ]; then
    echo "Downloading $ZIP" >&2
    curl -fsSL -o "$DIR/sdk.zip" "https://developer.garmin.com/downloads/connect-iq/sdks/$ZIP"
    mkdir -p "$SDK"
    unzip -q -o "$DIR/sdk.zip" -d "$SDK"
    rm -f "$DIR/sdk.zip"
fi

# --- Devices ---------------------------------------------------------------------------------
if [ ! -d "$GARMIN/Devices/fr970" ]; then
    TOKEN=$(curl -fsSL "https://ghcr.io/token?scope=repository:$IMAGE:pull" | python3 -c "import json,sys; print(json.load(sys.stdin)['token'])")
    ACCEPT="application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.manifest.v1+json"
    LAYERS=$(curl -fsSL -H "Authorization: Bearer $TOKEN" -H "Accept: $ACCEPT" \
        "https://ghcr.io/v2/$IMAGE/manifests/$TAG" | python3 -c "
import json, sys
m = json.load(sys.stdin)
# Smallest layers first; device files are a mid-sized layer.
for l in sorted(m['layers'], key=lambda l: l['size']):
    if l['size'] > 10_000_000:
        print(l['digest'])
")
    for DIGEST in $LAYERS; do
        URL="https://ghcr.io/v2/$IMAGE/blobs/$DIGEST"
        # grep exits early, so the pipeline's status must come from grep alone.
        if (set +o pipefail; curl -fsSL -H "Authorization: Bearer $TOKEN" "$URL" 2>/dev/null | tar -tz 2>/dev/null \
                | grep -q -m1 '\.Garmin/ConnectIQ/Devices/'); then
            echo "Extracting device definitions from layer $DIGEST" >&2
            TMP=$(mktemp -d)
            curl -fsSL -H "Authorization: Bearer $TOKEN" "$URL" | tar -xz -C "$TMP" --wildcards '*.Garmin/ConnectIQ/Devices/*'
            cp -r "$(find "$TMP" -type d -path '*.Garmin/ConnectIQ/Devices' | head -n1)" "$GARMIN/"
            rm -rf "$TMP"
            break
        fi
    done
    [ -d "$GARMIN/Devices/fr970" ] || { echo "device definitions not found in $IMAGE" >&2; exit 1; }
fi

# --- Fonts -----------------------------------------------------------------------------------
python3 "$HERE/sim_fonts.py" "$GARMIN/Devices" "$GARMIN/Fonts" >&2 || true

echo "$SDK"
