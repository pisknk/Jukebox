#!/usr/bin/env bash
# Installs the app on an iOS simulator, opens each tab, and fails if the app crashes.
# Simulators have no music library, so this checks start-up and the empty states,
# not playback.
set -euo pipefail

APP_PATH="$1"
BUNDLE_ID="ph.neilbayron.Jukebox"
OUT="smoke-test"
mkdir -p "$OUT"

# pick the newest available iPhone simulator
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
runtimes = sorted((r for r in data if "iOS" in r), reverse=True)
for runtime in runtimes:
    for device in data[runtime]:
        if device["name"].startswith("iPhone"):
            print(device["udid"]); sys.exit(0)
sys.exit(1)
')
echo "Using simulator $UDID"

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b

# allow media library access so the app doesn't sit on the permission prompt
xcrun simctl privacy "$UDID" grant media-library "$BUNDLE_ID" || echo "could not pre-grant media library access"

xcrun simctl install "$UDID" "$APP_PATH"

# capture the app's log output
xcrun simctl spawn "$UDID" log stream --level debug --style compact \
  --predicate "process == \"Jukebox\"" > "$OUT/app.log" 2>&1 &
LOG_PID=$!

is_running() {
  xcrun simctl spawn "$UDID" launchctl list | grep -q "$BUNDLE_ID"
}

check_tab() {
  local tab="$1" name="$2"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  # -selectedTab overrides the @AppStorage value for this launch
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -selectedTab "$tab"
  sleep 12
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png"
  if ! is_running; then
    echo "FAIL: app is not running after opening the $name tab"
    return 1
  fi
  echo "OK: $name tab launched and is still running"
}

status=0
check_tab 0 "jukebox-tab" || status=1
check_tab 1 "collections-tab" || status=1

kill "$LOG_PID" 2>/dev/null || true

# any crash reports for the app?
CRASHES=$(find ~/Library/Logs/DiagnosticReports -name 'Jukebox*' -newer "$APP_PATH" 2>/dev/null || true)
if [ -n "$CRASHES" ]; then
  echo "FAIL: crash reports found:"
  echo "$CRASHES"
  cp $CRASHES "$OUT/" 2>/dev/null || true
  status=1
fi

exit $status
