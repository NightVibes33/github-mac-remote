#!/usr/bin/env bash
set -euo pipefail
# Standard GitHub Actions xcode-27 image, not a jailbroken physical device.
command -v xcrun >/dev/null
RUNTIME=$(xcrun simctl list runtimes -j | python3 -c '
import json,sys
r=json.load(sys.stdin)["runtimes"]
v=[x for x in r if x.get("isAvailable") and x.get("identifier","").startswith("com.apple.CoreSimulator.SimRuntime.iOS-27")]
if not v: raise SystemExit("No available iOS 27 simulator runtime on this runner")
print(sorted(v,key=lambda x:x["identifier"])[-1]["identifier"])
')
DEVICE_TYPE=$(xcrun simctl list devicetypes -j | python3 -c '
import json,sys
a=json.load(sys.stdin)["devicetypes"]
iphone=[x for x in a if x["name"].startswith("iPhone")]
if not iphone: raise SystemExit("No iPhone device types installed")
order=["iPhone 17 Pro","iPhone 17","iPhone 16 Pro","iPhone 16"]
for n in order:
 x=next((x for x in iphone if x["name"]==n),None)
 if x: print(x["identifier"]); break
else: print(iphone[-1]["identifier"])
')
UDID=$(xcrun simctl create "Remote iPhone (GitHub)" "$DEVICE_TYPE" "$RUNTIME")
echo "$UDID" > "$RUNNER_TEMP/ios-simulator.udid"
echo "$RUNTIME" > "$RUNNER_TEMP/ios-simulator.runtime"
echo "$DEVICE_TYPE" > "$RUNNER_TEMP/ios-simulator.type"
mkdir -p "$HOME/.remote-ios-simulator/tweaks"
echo "iOS simulator $UDID, runtime $RUNTIME, device $DEVICE_TYPE"
echo "### Simulator" >> "$GITHUB_STEP_SUMMARY"
echo "Device: \`$UDID\`" >> "$GITHUB_STEP_SUMMARY"
echo "Runtime: \`$RUNTIME\`" >> "$GITHUB_STEP_SUMMARY"
