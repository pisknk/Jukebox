#!/usr/bin/env bash
# Installs the app on iOS simulators, opens each tab in each design, and fails if the
# app crashes. Simulators have no music library, so this checks start-up, both designs
# and the empty states, not playback.
#
#   iOS 26: Native Glass (default) and Amity 1.0
#   iOS 18: Amity 1.0 (Native Glass isn't available there)
set -euo pipefail

APP_PATH="$1"
BUNDLE_ID="ph.neilbayron.Jukebox"
OUT="smoke-test"
mkdir -p "$OUT"
status=0

# newest iPhone simulator whose runtime starts with the given iOS major version
find_device() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
major = sys.argv[1]
data = json.load(sys.stdin)["devices"]
runtimes = sorted((r for r in data if ".iOS-" + major + "-" in r), reverse=True)
for runtime in runtimes:
    for device in data[runtime]:
        if device["name"].startswith("iPhone"):
            print(device["udid"]); sys.exit(0)
' "$1"
}

is_running() {
  # read the whole list first: piping into `grep -q` can kill launchctl with SIGPIPE
  local services
  services=$(xcrun simctl spawn "$1" launchctl list)
  [[ "$services" == *"$BUNDLE_ID"* ]]
}

# check_screen <udid> <label> <tab> [extra launch args...]
check_screen() {
  local udid="$1" label="$2" tab="$3"
  shift 3
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  # launch arguments override UserDefaults (@AppStorage) for this launch only
  xcrun simctl launch "$udid" "$BUNDLE_ID" -selectedTab "$tab" "$@"
  sleep 12
  xcrun simctl io "$udid" screenshot "$OUT/$label.png"
  if is_running "$udid"; then
    echo "OK: $label"
  else
    echo "FAIL: app is not running ($label)"
    status=1
  fi
}

prepare() {
  local udid="$1"
  xcrun simctl boot "$udid" || true
  xcrun simctl bootstatus "$udid" -b > /dev/null
  # allow media library access so the app doesn't sit on the permission prompt
  xcrun simctl privacy "$udid" grant media-library "$BUNDLE_ID" || echo "could not pre-grant media library access"
  xcrun simctl install "$udid" "$APP_PATH"
}

IOS26=$(find_device 26 || true)
IOS18=$(find_device 18 || true)

if [ -n "$IOS26" ]; then
  echo "== iOS 26 simulator $IOS26"
  prepare "$IOS26"
  check_screen "$IOS26" "ios26-native-glass-jukebox" 0
  check_screen "$IOS26" "ios26-native-glass-collections" 1
  check_screen "$IOS26" "ios26-amity-jukebox" 0 -designLanguage amity
  check_screen "$IOS26" "ios26-amity-collections" 1 -designLanguage amity
  xcrun simctl shutdown "$IOS26" || true
else
  echo "FAIL: no iOS 26 simulator found"
  status=1
fi

if [ -n "$IOS18" ]; then
  echo "== iOS 18 simulator $IOS18"
  prepare "$IOS18"
  check_screen "$IOS18" "ios18-amity-jukebox" 0
  check_screen "$IOS18" "ios18-amity-collections" 1
  xcrun simctl shutdown "$IOS18" || true
else
  echo "note: no iOS 18 simulator on this runner; skipped the iOS 18 check"
fi

# any crash reports for the app?
CRASHES=$(find ~/Library/Logs/DiagnosticReports -name 'Jukebox*' -newer "$APP_PATH" 2>/dev/null || true)
if [ -n "$CRASHES" ]; then
  echo "FAIL: crash reports found:"
  echo "$CRASHES"
  cp $CRASHES "$OUT/" 2>/dev/null || true
  status=1
fi

exit $status
