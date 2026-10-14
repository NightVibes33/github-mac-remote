#!/usr/bin/env bash
set -euo pipefail
# Experimental. simject may require iOS Development signing and full-disk access
# that GitHub-hosted macOS machines cannot supply.
STATUS="$RUNNER_TEMP/simject-status.txt"
echo "simject: attempting installation" > "$STATUS"
trap 'echo "simject: unavailable (setup failure)" > "$STATUS"' ERR
ROOT="$RUNNER_TEMP/simject-source"
git init "$ROOT"
git -C "$ROOT" remote add origin https://github.com/akemin-dayo/simject.git
git -C "$ROOT" fetch --depth 1 origin 0a8ec581d813c570a2dc5e7e5113a08b12dcc803
git -C "$ROOT" -c advice.detachedHead=false checkout --detach 0a8ec581d813c570a2dc5e7e5113a08b12dcc803
(
  cd "$ROOT"
  make setup
  ./installsubstrate.sh subst
  ./installsubstrate.sh link
)
if [ ! -d /opt/simject ]; then
  echo "simject: no /opt/simject after setup" | tee "$STATUS"
  exit 1
fi
# Restore custom, simulator-compatible dylib and filter plist pairs.
mkdir -p "$HOME/.remote-ios-simulator/tweaks"
for file in "$HOME/.remote-ios-simulator/tweaks/"*.dylib "$HOME/.remote-ios-simulator/tweaks/"*.plist; do
  [ -f "$file" ] || continue
  sudo cp "$file" /opt/simject/
done
for file in /opt/simject/*.dylib; do
  [ -f "$file" ] || continue
  sudo codesign --force -s - "$file"
done
echo "simject: installed; hooks still require runtime verification" | tee "$STATUS"
echo "simject installed; iOS 27 injection compatibility is NOT guaranteed." >> "$GITHUB_STEP_SUMMARY"
