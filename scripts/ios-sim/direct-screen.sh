#!/usr/bin/env bash
# Direct iOS Simulator framebuffer preview, independent of headless macOS VNC.
set -euo pipefail
UDID="$(cat "$RUNNER_TEMP/ios-simulator.udid")"
ROOT="$RUNNER_TEMP/iphone-screen"
mkdir -p "$ROOT"
cat > "$ROOT/index.html" <<'HTML'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>iPhone Simulator screen</title>
<style>html,body{margin:0;background:#101116;color:#f9fafb;font:14px system-ui;text-align:center}main{height:100dvh;display:flex;flex-direction:column;align-items:center}img{min-height:0;max-height:calc(100dvh - 38px);max-width:100vw;object-fit:contain}small{padding:8px}</style></head>
<body><main><small>Live Simulator framebuffer · view only</small><img id="display" alt="iOS Simulator"></main>
<script>
const target=document.querySelector('#display');let previous=null;
async function refresh(){try{const response=await fetch('/frame.png?ts='+Date.now(),{cache:'no-store'});if(response.ok){const blob=await response.blob();const next=URL.createObjectURL(blob);target.onload=()=>{if(previous)URL.revokeObjectURL(previous);previous=next};target.src=next;}}catch(e){}setTimeout(refresh,800)}refresh();
</script></body></html>
HTML
(
 while :; do
   if xcrun simctl io "$UDID" screenshot --type=png "$ROOT/next.png" >/dev/null 2>&1; then mv -f "$ROOT/next.png" "$ROOT/frame.png"; fi
   sleep 0.8
 done
) > "$RUNNER_TEMP/iphone-capture.log" 2>&1 &
echo $! > "$RUNNER_TEMP/iphone-capture.pid"
python3 -m http.server 6081 --bind 127.0.0.1 --directory "$ROOT" > "$RUNNER_TEMP/iphone-http.log" 2>&1 &
echo $! > "$RUNNER_TEMP/iphone-http.pid"
for i in {1..45}; do
 if curl -fsS http://127.0.0.1:6081/frame.png -o /dev/null 2>/dev/null; then break; fi
 sleep 2
done
curl -fsS http://127.0.0.1:6081/frame.png -o /dev/null
cloudflared tunnel --no-autoupdate --url http://127.0.0.1:6081 > "$RUNNER_TEMP/iphone-cloudflared.log" 2>&1 &
echo $! > "$RUNNER_TEMP/iphone-cloudflared.pid"
URL=""
for i in {1..45}; do
 URL="$(grep -Eo 'https://[a-zA-Z0-9-]+[.]trycloudflare[.]com' "$RUNNER_TEMP/iphone-cloudflared.log" | head -1 || true)"
 test -n "$URL" && break
 sleep 2
done
if test -z "$URL"; then cat "$RUNNER_TEMP/iphone-cloudflared.log"; exit 1; fi
echo "### iPhone framebuffer preview (not macOS desktop)" >> "$GITHUB_STEP_SUMMARY"
echo "View-only Safari URL: $URL" >> "$GITHUB_STEP_SUMMARY"
echo "::warning::This temporary preview is view-only, and anyone with its unguessable link can see the simulator. Do not use with sensitive data."
