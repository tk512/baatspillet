#!/bin/bash
# Run Båtspillet on iOS/iPadOS.
#
#   ./ios.sh                             — build + install + launch in the iPad simulator
#   SIM_NAME="iPhone 15 Pro" ./ios.sh    — same, on an iPhone simulator
#   ./ios.sh setup                       — one-time: build the macOS engine app
#                                          (build.sh packages it)
#   ./ios.sh xcode                       — open the engine Xcode project (real-device
#                                          runs: pick your iPad + personal team there)
#
# The engine is VENDORED at ./engine (LÖVE 12-dev + Apple deps; see
# engine/VENDORED.md), so this repo builds forever with no network. LÖVE 12's
# Metal renderer is required: LÖVE 11's OpenGL ES crashes in Apple-Silicon
# simulators (Apple bug).
#
# Our engine customizations: ios/love-ios.plist (synced in before every build)
# and BATSPILLET-marked edits in the vendored pbxproj (bundle id
# skep.batspillet, StoreKit bridge ios/storekit/bt_iap.m as a target source —
# so EVERY build style links it: CLI, Xcode GUI, device, archive).
set -euo pipefail
cd "$(dirname "$0")"

ENGINE="${ENGINE:-$PWD/engine}"
SIM_NAME="${SIM_NAME:-iPad Pro 13-inch (M4)}"
TEAM_ID="${TEAM_ID:-8K92QASAAM}"   # baked into the vendored project too
BUNDLE_ID=skep.batspillet
XCODEPROJ="$ENGINE/platform/xcode/love.xcodeproj"

[ -d "$XCODEPROJ" ] || { echo "!! vendored engine missing at $ENGINE"; exit 1; }

if [ "${1:-}" = "setup" ]; then
    cp ios/love-ios.plist "$ENGINE/platform/xcode/ios/love-ios.plist"
    echo ">> building the macOS engine app (build.sh packages it)…"
    xcodebuild -project "$XCODEPROJ" -scheme love-macosx -configuration Release \
        -derivedDataPath "$ENGINE/build" -quiet build
    echo ">> setup complete"
    exit 0
fi

if [ "${1:-}" = "xcode" ]; then
    open "$XCODEPROJ"
    exit 0
fi

# ── real device: build + install on a connected iPad/iPhone ────────────────
# Needs a signing team: TEAM_ID=XXXXXXXXXX ./ios.sh device
# (free personal team works — the id is in Xcode ▸ Settings ▸ Accounts).
if [ "${1:-}" = "device" ]; then
    cp ios/love-ios.plist "$ENGINE/platform/xcode/ios/love-ios.plist"
    ./build.sh love
    echo ">> building for device (automatic signing, team $TEAM_ID)…"
    xcodebuild -project "$XCODEPROJ" -scheme love-ios -configuration Release         -destination "generic/platform=iOS" -derivedDataPath "$ENGINE/build"         -allowProvisioningUpdates CODE_SIGN_STYLE=Automatic         DEVELOPMENT_TEAM="$TEAM_ID" -quiet build
    APP="$(find "$ENGINE/build/Build/Products" -name love.app -path '*Release-iphoneos*' -print -quit)"
    [ -n "$APP" ] || { echo "!! device build not found"; exit 1; }
    echo ">> installing on the connected device…"
    xcrun devicectl device install app --device "$(xcrun devicectl list devices --json-output - 2>/dev/null         | python3 -c 'import json,sys; d=[x for x in json.load(sys.stdin)["result"]["devices"] if x.get("connectionProperties",{}).get("tunnelState")!="unavailable"]; print(d[0]["identifier"] if d else "")')"         "$APP" || { echo "!! plug in the iPad (and trust this Mac), then re-run"; exit 1; }
    echo ">> installed — tap Båtspillet on the device"
    exit 0
fi

# ── App Store archive + export (needs the paid developer account) ──────────
# TEAM_ID=XXXXXXXXXX ./ios.sh archive → .ipa under engine/build/export
if [ "${1:-}" = "archive" ]; then
    cp ios/love-ios.plist "$ENGINE/platform/xcode/ios/love-ios.plist"
    ./build.sh love
    BUILD_NO="$(date +%Y%m%d%H%M)"   # unique, increasing — Apple requires it per upload
    echo ">> archiving (build $BUILD_NO)…"
    # Manual DISTRIBUTION signing: works with zero registered devices
    xcodebuild -project "$XCODEPROJ" -scheme love-ios -configuration Release         -destination "generic/platform=iOS" -derivedDataPath "$ENGINE/build"         -archivePath "$ENGINE/build/Batspillet.xcarchive"         CODE_SIGN_STYLE=Manual         CODE_SIGN_IDENTITY="Apple Distribution"         PROVISIONING_PROFILE_SPECIFIER="Batspillet AppStore"         CURRENT_PROJECT_VERSION="$BUILD_NO"         DEVELOPMENT_TEAM="$TEAM_ID" -quiet archive
    echo ">> exporting .ipa for App Store Connect…"
    xcodebuild -exportArchive -archivePath "$ENGINE/build/Batspillet.xcarchive"         -exportOptionsPlist ios/ExportOptions.plist         -exportPath "$ENGINE/build/export"
    echo ">> upload with: xcrun altool --upload-app … or Xcode Organizer / Transporter"
    exit 0
fi

# Our plist customizations live in this repo — sync before building.
cp ios/love-ios.plist "$ENGINE/platform/xcode/ios/love-ios.plist"

./build.sh love    # fresh Båtspillet.love

echo ">> building engine (love-ios → simulator, cached after the first run)…"
xcodebuild -project "$XCODEPROJ" -scheme love-ios -configuration Debug \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$ENGINE/build" -quiet build

APP="$(find "$ENGINE/build/Build/Products" -name love.app -path '*iphonesimulator*' -print -quit)"
[ -n "$APP" ] || { echo "!! built love.app not found under $ENGINE/build"; exit 1; }

# The game is fused as a target RESOURCE (Båtspillet.love in the pbxproj),
# so the build above already contains it — nothing to copy.

UDID="$(xcrun simctl list devices available | grep -F "$SIM_NAME (" | head -1 \
        | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
[ -n "$UDID" ] || { echo "!! no simulator named '$SIM_NAME' (xcrun simctl list devices)"; exit 1; }

xcrun simctl bootstatus "$UDID" -b >/dev/null    # boot if needed, wait until ready
open -a Simulator
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
echo ">> Båtspillet running on '$SIM_NAME'"
