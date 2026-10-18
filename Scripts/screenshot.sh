#!/bin/zsh
# Launch AppleTube in the iPhone 18 Pro simulator with launch arguments and save a screenshot.
# Usage: Scripts/screenshot.sh <out.png> <wait-seconds> [launch args...]
set -e
SIM=6E7F9105-63C0-4533-8414-B7F9A2881A41
APP="$(dirname $0)/../build/Build/Products/Debug-iphonesimulator/AppleTube.app"
out=$1; wait=$2; shift 2
xcrun simctl boot $SIM 2>/dev/null || true
xcrun simctl terminate $SIM dev.saurabhk.AppleTube 2>/dev/null || true
xcrun simctl install $SIM "$APP"
xcrun simctl launch $SIM dev.saurabhk.AppleTube "$@" >/dev/null
sleep $wait
xcrun simctl io $SIM screenshot "$out" >/dev/null 2>&1
