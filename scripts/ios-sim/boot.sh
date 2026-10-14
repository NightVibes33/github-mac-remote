#!/usr/bin/env bash
set -euo pipefail
UDID=$(cat "$RUNNER_TEMP/ios-simulator.udid")
CURRENT=$(xcrun simctl list devices -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; u=sys.argv[1]; print(next((x["state"] for a in d.values() for x in a if x["udid"]==u),"unknown"))' "$UDID")
if [ "$CURRENT" != "Booted" ]; then
  xcrun simctl boot "$UDID"
fi
xcrun simctl bootstatus "$UDID" -b
# The xcode-27 preview runner does not register Simulator.app by the short name.
APP="$(xcode-select -p)/Applications/Simulator.app"
if [ -d "$APP" ]; then
  open -a "$APP" --args -CurrentDeviceUDID "$UDID" || echo "::warning::GUI Simulator launch not available, trying simctl screenshot"
else
  echo "::warning::Simulator GUI bundle not found at $APP; using simctl directly"
fi
sleep 4
xcrun simctl io "$UDID" screenshot "$RUNNER_TEMP/ios-simulator-last.png"
test -s "$RUNNER_TEMP/ios-simulator-last.png" || { echo "::error::Screenshot file is empty"; exit 1; }
echo "Simulator screenshot captured on iOS 27."
if [ -x /opt/simject/resim ]; then
  /opt/simject/resim || echo "::warning::resim failed; tweak injection is not validated"
elif command -v resim >/dev/null 2>&1; then
  resim || echo "::warning::resim failed; tweak injection is not validated"
fi
echo "Boot complete. Screenshot: $RUNNER_TEMP/ios-simulator-last.png"
