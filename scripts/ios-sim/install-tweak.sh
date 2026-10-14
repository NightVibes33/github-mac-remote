#!/usr/bin/env bash
set -euo pipefail
# Run inside the GitHub runner terminal after transferring a simulator-built tweak.
# Usage: bash scripts/ios-sim/install-tweak.sh /path/to/name.dylib /path/to/name.plist
[ "$#" -eq 2 ] || { echo "Usage: $0 tweak.dylib filter.plist"; exit 2; }
[ -f "$1" ] && [ -f "$2" ] || { echo "Tweak files missing"; exit 2; }
[[ "$1" == *.dylib && "$2" == *.plist ]] || { echo "Expected .dylib and .plist"; exit 2; }
[ -d /opt/simject ] || { echo "simject is not installed on this runner"; exit 1; }
DEST="$HOME/.remote-ios-simulator/tweaks"
mkdir -p "$DEST"
cp "$1" "$2" "$DEST/"
sudo cp "$1" "$2" /opt/simject/
sudo codesign --force --sign - "/opt/simject/$(basename "$1")"
if [ -x /opt/simject/resim ]; then
  /opt/simject/resim
else
  command -v resim >/dev/null && resim
fi
echo "Installed simulator tweak; added to next encrypted checkpoint."
