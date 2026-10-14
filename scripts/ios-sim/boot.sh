#!/usr/bin/env bash
set -euo pipefail
UDID=$(cat "$RUNNER_TEMP/ios-simulator.udid")
CURRENT=$(xcrun simctl list devices -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; u=sys.argv[1]; print(next((x["state"] for a in d.values() for x in a if x["udid"]==u),"unknown"))' "$UDID")
if [ "$CURRENT" != "Booted" ]; then
  xcrun simctl boot "$UDID"
fi
xcrun simctl bootstatus "$UDID" -b
open -a Simulator --args -CurrentDeviceUDID "$UDID"
sleep 4
xcrun simctl io "$UDID" screenshot "$RUNNER_TEMP/ios-simulator-last.png"
if [ -x /opt/simject/resim ]; then
  /opt/simject/resim || echo "::warning::resim failed; tweak injection is not validated"
elif command -v resim >/dev/null 2>&1; then
  resim || echo "::warning::resim failed; tweak injection is not validated"
fi
echo "Boot complete. Screenshot: $RUNNER_TEMP/ios-simulator-last.png"
