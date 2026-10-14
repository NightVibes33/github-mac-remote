#!/usr/bin/env bash
set -euo pipefail
HOURS="${SIM_SESSION_HOURS:-2}"
[[ "$HOURS" =~ ^[1-6]$ ]] || { echo "::error::Invalid duration"; exit 1; }
DURATION=$((HOURS*3600))
# GitHub-hosted macOS jobs stop at six hours including setup/archiving.
[ "$DURATION" -le 18900 ] || DURATION=18900
INTERVAL=$(((DURATION/60+7)/8))
[ "$INTERVAL" -ge 30 ] || INTERVAL=30
START=$(date +%s)
END=$((START+DURATION))
NEXT=$((START+INTERVAL*60))
echo "Remote control available for up to $((DURATION/60)) minutes."
echo "Checkpoint frequency: ~$INTERVAL min (simulator temporarily shuts down)."
while :; do
 NOW=$(date +%s)
 [ "$NOW" -lt "$END" ] || break
 if [ "$NOW" -ge "$NEXT" ] && [ "$((END-NOW))" -ge 180 ]; then
   bash scripts/ios-sim/checkpoint.sh periodic || echo "::warning::Checkpoint failed"
   NEXT=$(( $(date +%s) + INTERVAL*60 ))
 else
   sleep 20
 fi
done
echo "Remote session finished; final checkpoint follows."
