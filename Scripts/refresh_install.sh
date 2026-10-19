#!/bin/bash
# Rebuilds AppleTube with a fresh free-account provisioning profile and installs it on the iPhone over Wi-Fi,
# before the 7-day signature runs out. Run hourly by launchd (Scripts/install_refresh_agent.sh); it does
# nothing until the installed build is within RENEW_DAYS of expiring, then retries every run until it lands.
#
#   Scripts/refresh_install.sh           install only if due
#   Scripts/refresh_install.sh --force   build and install now (use this for manual installs too, so the
#                                        expiry it records stays right)
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# The bundle ID from Local.yml; the device from APPLETUBE_DEVICE or the first paired iPhone.
BUNDLE_ID=$(sed -n 's/^ *APPLETUBE_BUNDLE_ID: *//p' "$REPO/Local.yml" 2>/dev/null)
DEVICE="${APPLETUBE_DEVICE:-}"
RENEW_DAYS=3
WORK="$HOME/Library/Caches/AppleTubeRefresh"
STATE="$WORK/installed-expiry"   # epoch seconds when the installed build's profile expires
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

log() { echo "$(date '+%F %T') $*"; }
notify() { osascript -e "display notification \"$1\" with title \"AppleTube\"" >/dev/null 2>&1 || true; }
fail() { log "FAILED: $1"; [ "$quiet_failures" = 1 ] || notify "Reinstall failed: $1"; exit 1; }
profile_expiry() { security cms -D -i "$1" 2>/dev/null | plutil -extract ExpirationDate raw -o - - 2>/dev/null; }
to_epoch() { date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s; }

mkdir -p "$WORK"
[ -n "$BUNDLE_ID" ] || { echo "Set APPLETUBE_BUNDLE_ID in Local.yml (see Local.example.yml)"; exit 1; }
if [ -z "$DEVICE" ]; then
    xcrun devicectl list devices --json-output "$WORK/devices.json" >/dev/null 2>&1
    DEVICE=$(python3 -c 'import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
print(next((d["hardwareProperties"]["udid"] for d in devices
            if d["hardwareProperties"].get("reality") == "physical" and d["hardwareProperties"].get("deviceType") == "iPhone"), ""))' "$WORK/devices.json" 2>/dev/null)
fi
now=$(date +%s)
expiry=$(cat "$STATE" 2>/dev/null || echo 0)
if [ "${1:-}" != "--force" ] && [ $((expiry - now)) -gt $((RENEW_DAYS * 86400)) ]; then
    exit 0
fi
# Only shout about failures once the signature is about to lapse; before that, hourly retries are routine.
quiet_failures=0
[ "${1:-}" != "--force" ] && [ $((expiry - now)) -gt 86400 ] && quiet_failures=1

log "Refreshing (installed build expires $( [ "$expiry" -gt 0 ] && date -r "$expiry" '+%F %T' || echo 'unknown'))"

# Is the phone reachable (Wi-Fi or cable)? Cheap check before a full build.
xcrun devicectl device info details --device "$DEVICE" --timeout 30 >/dev/null 2>&1 || fail "iPhone not reachable"

# Drop a cached profile that's close to expiring so Xcode fetches a fresh 7-day one.
for dir in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles"; do
    for file in "$dir"/*.mobileprovision; do
        [ -e "$file" ] || continue
        security cms -D -i "$file" 2>/dev/null | grep -q "$BUNDLE_ID" || continue
        ends=$(to_epoch "$(profile_expiry "$file")")
        if [ $((ends - now)) -lt $(((RENEW_DAYS + 1) * 86400)) ]; then
            log "Removing profile expiring $(date -r "$ends" '+%F'): $(basename "$file")"
            rm -f "$file"
        fi
    done
done

# Build the last commit, not whatever is half-edited in the working tree.
rm -rf "$WORK/src" && mkdir -p "$WORK/src"
git -C "$REPO" archive HEAD | tar -x -C "$WORK/src" || fail "couldn't export source"
cp "$REPO/Local.yml" "$WORK/src/"
(cd "$WORK/src" && xcodegen generate --quiet) || fail "xcodegen failed"
xcodebuild -project "$WORK/src/AppleTube.xcodeproj" -scheme AppleTube -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath "$WORK/DerivedData" \
    -allowProvisioningUpdates build > "$WORK/build.log" 2>&1 \
    || { grep -q "No Accounts" "$WORK/build.log" && fail "add your Apple ID in Xcode → Settings → Accounts"; \
         fail "build failed (see $WORK/build.log)"; }

app="$WORK/DerivedData/Build/Products/Debug-iphoneos/AppleTube.app"
new_expiry=$(to_epoch "$(profile_expiry "$app/embedded.mobileprovision")") || fail "no embedded profile"
log "Built $(git -C "$REPO" rev-parse --short HEAD), profile valid until $(date -r "$new_expiry" '+%F %T')"

xcrun devicectl device install app --device "$DEVICE" "$app" > "$WORK/install.log" 2>&1 \
    || fail "install failed — is the iPhone unlocked and on the same Wi-Fi? (see $WORK/install.log)"

echo "$new_expiry" > "$STATE"
log "Installed; next refresh after $(date -r $((new_expiry - RENEW_DAYS * 86400)) '+%F %T')"
notify "Reinstalled — good until $(date -r "$new_expiry" '+%a %e %b')"
