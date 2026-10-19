#!/bin/zsh
# Launch AppleTube in the iPhone 18 Pro simulator with launch arguments and save a screenshot.
# Usage: Scripts/screenshot.sh <out.png> <wait-seconds> [launch args...]
set -e
SIM="${APPLETUBE_SIM:-iPhone 18 Pro}"
BUNDLE_ID=$(sed -n 's/^ *APPLETUBE_BUNDLE_ID: *//p' "$(dirname $0)/../Local.yml")
APP="$(dirname $0)/../build/Build/Products/Debug-iphonesimulator/AppleTube.app"
out=$1; wait=$2; shift 2
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl terminate "$SIM" $BUNDLE_ID 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
xcrun simctl launch "$SIM" $BUNDLE_ID "$@" >/dev/null
sleep $wait
xcrun simctl io "$SIM" screenshot "$out" >/dev/null 2>&1
