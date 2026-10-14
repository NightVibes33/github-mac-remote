#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-periodic}"
UDID=$(cat "$RUNNER_TEMP/ios-simulator.udid")
if [ "$MODE" != "final" ]; then
  trap 'bash scripts/ios-sim/boot.sh || echo "::warning::Simulator reboot after snapshot failed"' EXIT
fi
echo "Checkpoint: $MODE"
xcrun simctl shutdown "$UDID" 2>/dev/null || true
for i in {1..30}; do
  STATUS=$(xcrun simctl list devices -j | python3 -c 'import json,sys; a=json.load(sys.stdin)["devices"]; u=sys.argv[1]; print(next((x["state"] for v in a.values() for x in v if x["udid"]==u),"unknown"))' "$UDID")
  [ "$STATUS" = "Shutdown" ] && break
  sleep 1
done
[ "$STATUS" = "Shutdown" ] || { echo "::error::Simulator would not shut down"; exit 1; }
node scripts/ios-sim/state-store.cjs save
