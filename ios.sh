#!/bin/bash
# Båtspillet — build & release console (iOS/iPadOS + App Store).
#
#   ./ios.sh            — interactive menu (when run in a terminal)
#   ./ios.sh ipad       — build + run in the iPad simulator
#   ./ios.sh iphone     — build + run in the iPhone simulator
#   ./ios.sh device     — build + install on a plugged-in iPad/iPhone
#   ./ios.sh archive    — App Store .ipa (version auto-bumps from ios/VERSION)
#   ./ios.sh setup      — one-time: build the macOS engine app (build.sh packages it)
#   ./ios.sh xcode      — open the vendored engine project (manual device runs)
#
# SIM_NAME / PHONE_SIM_NAME env override the preferred simulators. A bare
# `./ios.sh` outside a terminal (scripts, CI) runs `ipad`, like before.
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
PHONE_SIM_NAME="${PHONE_SIM_NAME:-iPhone 15 Pro}"
TEAM_ID="${TEAM_ID:-8K92QASAAM}"   # baked into the vendored project too
BUNDLE_ID=skep.batspillet
XCODEPROJ="$ENGINE/platform/xcode/love.xcodeproj"

[ -d "$XCODEPROJ" ] || { echo "!! vendored engine missing at $ENGINE"; exit 1; }

# Our plist customizations live in this repo — sync before every build.
sync_plist() { cp ios/love-ios.plist "$ENGINE/platform/xcode/ios/love-ios.plist"; }

# What the next auto-bumped marketing version will be (see do_archive).
next_version() {
    [ -f ios/VERSION ] || { echo "?"; return; }
    awk -F. 'NF==3 {printf "%d.%d.%d", $1,$2,$3+1} NF==2 {printf "%s.%s.1", $1,$2}' ios/VERSION
}

do_setup() {
    sync_plist
    echo ">> building the macOS engine app (build.sh packages it)…"
    xcodebuild -project "$XCODEPROJ" -scheme love-macosx -configuration Release \
        -derivedDataPath "$ENGINE/build" -quiet build
    echo ">> setup complete"
}

do_xcode() { open "$XCODEPROJ"; }

# ── simulator: build + install + launch ────────────────────────────────────
do_sim() {
    local sim="$1"
    sync_plist
    ./build.sh love    # fresh Båtspillet.love
    echo ">> building engine (love-ios → simulator, cached after the first run)…"
    xcodebuild -project "$XCODEPROJ" -scheme love-ios -configuration Debug \
        -destination "generic/platform=iOS Simulator" \
        -derivedDataPath "$ENGINE/build" -quiet build
    local app
    app="$(find "$ENGINE/build/Build/Products" -name love.app -path '*iphonesimulator*' -print -quit)"
    [ -n "$app" ] || { echo "!! built love.app not found under $ENGINE/build"; exit 1; }
    # The game is fused as a target RESOURCE (Båtspillet.love in the pbxproj),
    # so the build above already contains it — nothing to copy.
    local udid
    udid="$(xcrun simctl list devices available | grep -F "$sim (" | head -1 \
            | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
    [ -n "$udid" ] || { echo "!! no simulator named '$sim' (xcrun simctl list devices)"; exit 1; }
    xcrun simctl bootstatus "$udid" -b >/dev/null    # boot if needed, wait until ready
    open -a Simulator
    xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl install "$udid" "$app"
    xcrun simctl launch "$udid" "$BUNDLE_ID" >/dev/null
    echo ">> Båtspillet running on '$sim'"
}

# ── real device: build + install on a connected iPad/iPhone ────────────────
# Needs a signing team: TEAM_ID=XXXXXXXXXX ./ios.sh device
# (free personal team works — the id is in Xcode ▸ Settings ▸ Accounts).
do_device() {
    sync_plist
    ./build.sh love
    echo ">> building for device (automatic signing, team $TEAM_ID)…"
    xcodebuild -project "$XCODEPROJ" -scheme love-ios -configuration Release         -destination "generic/platform=iOS" -derivedDataPath "$ENGINE/build"         -allowProvisioningUpdates CODE_SIGN_STYLE=Automatic         DEVELOPMENT_TEAM="$TEAM_ID" -quiet build
    local app
    app="$(find "$ENGINE/build/Build/Products" -name love.app -path '*Release-iphoneos*' -print -quit)"
    [ -n "$app" ] || { echo "!! device build not found"; exit 1; }
    echo ">> installing on the connected device…"
    xcrun devicectl device install app --device "$(xcrun devicectl list devices --json-output - 2>/dev/null         | python3 -c 'import json,sys; d=[x for x in json.load(sys.stdin)["result"]["devices"] if x.get("connectionProperties",{}).get("tunnelState")!="unavailable"]; print(d[0]["identifier"] if d else "")')"         "$app" || { echo "!! plug in the iPad (and trust this Mac), then re-run"; exit 1; }
    echo ">> installed — tap Båtspillet on the device"
}

# ── App Store archive + export (needs the paid developer account) ──────────
# ./ios.sh archive → .ipa under engine/build/export
#
# Versioning (Apple has TWO numbers):
#   CFBundleVersion (build number)  = timestamp below: unique + increasing on
#     every archive automatically — required per TestFlight upload. Never set
#     by hand.
#   CFBundleShortVersionString (marketing version, what users/review see) =
#     ios/VERSION, committed to git. Auto-bumps its patch digit on every
#     archive (1.0 → 1.0.1 → 1.0.2 …) so a duplicate version can never ship.
#     Deliberate minor/major releases override it — the override becomes the
#     new baseline in the file:
#       APP_VERSION=1.1 ./ios.sh archive
#     Commit ios/VERSION together with the release.
do_archive() {
    sync_plist
    ./build.sh love
    local build_no
    build_no="$(date +%Y%m%d%H%M)"   # unique, increasing — Apple requires it per upload
    if [ -z "${APP_VERSION:-}" ]; then
        [ -f ios/VERSION ] || { echo "!! ios/VERSION missing — seed it: echo 1.0 > ios/VERSION"; exit 1; }
        APP_VERSION="$(next_version)"
    fi
    echo "$APP_VERSION" | grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$' >/dev/null \
        || { echo "!! bad version '$APP_VERSION' (want e.g. 1.0.1)"; exit 1; }
    echo "$APP_VERSION" > ios/VERSION
    echo ">> ios/VERSION → $APP_VERSION (commit it with this release)"
    echo ">> archiving (version $APP_VERSION, build $build_no)…"
    # Manual DISTRIBUTION signing: works with zero registered devices.
    # STRIP_STYLE=non-global: the archive's post-processing strip defaults to
    # "all symbols", which empties the export trie — and LuaJIT's FFI finds the
    # StoreKit bridge (bt_iap_*) via dlsym, so a fully stripped binary silently
    # kills IAP in production (fails closed: "Kjøp er ikke tilgjengelig her").
    # non-global strips only local symbols; the handful of bt_* globals stay.
    xcodebuild -project "$XCODEPROJ" -scheme love-ios -configuration Release         -destination "generic/platform=iOS" -derivedDataPath "$ENGINE/build"         -archivePath "$ENGINE/build/Batspillet.xcarchive"         CODE_SIGN_STYLE=Manual         CODE_SIGN_IDENTITY="Apple Distribution"         PROVISIONING_PROFILE_SPECIFIER="Batspillet AppStore"         CURRENT_PROJECT_VERSION="$build_no"         MARKETING_VERSION="$APP_VERSION"         STRIP_STYLE=non-global         DEVELOPMENT_TEAM="$TEAM_ID" -quiet archive
    # Guard: never ship a binary the FFI can't see the bridge in.
    # (plain grep, not -q: -q exits at first match and SIGPIPEs dyld_info,
    # which pipefail then reports as failure — a false alarm)
    local arcbin="$ENGINE/build/Batspillet.xcarchive/Products/Applications/love.app/love"
    if ! xcrun dyld_info -exports "$arcbin" 2>/dev/null | grep bt_iap_init >/dev/null; then
        echo "!! bt_iap_* not exported from the archived binary — IAP would be dead in production. NOT exporting."
        exit 1
    fi
    echo ">> bridge check OK (bt_iap_* exported)"
    echo ">> exporting .ipa for App Store Connect…"
    # xcodebuild polls every Xcode-known Apple ID and whines about stale ones;
    # with manual signing none are needed — filter that noise, keep real errors
    local explog="$ENGINE/build/export-log.txt"
    if ! xcodebuild -exportArchive -archivePath "$ENGINE/build/Batspillet.xcarchive"         -exportOptionsPlist ios/ExportOptions.plist         -exportPath "$ENGINE/build/export" > "$explog" 2>&1; then
        cat "$explog"; exit 1
    fi
    grep -vE "IDEDistribution|DVTServices|DVTPortal|DVTDeveloper|DVTAppleID|session has expired|Failed to log in|creationTimestamp|httpCode|protocolVersion|requestUrl|responseId|resultCode|resultString|userLocale|userString|payload = |NSLocalized|NSUnderlying|^\}|^    \}" "$explog" || true
    mv -f "$ENGINE/build/export/love.ipa" "$ENGINE/build/export/Batspillet.ipa" 2>/dev/null || true
    local ipa="$ENGINE/build/export/Batspillet.ipa"
    echo ">> $ipa — deliver via Transporter"
    if [ -t 0 ]; then
        local a=""
        read -rn1 -p ">> open Transporter with the .ipa now? [Y/n] " a; echo
        case "$a" in n|N) ;; *) open -a Transporter "$ipa" || echo "!! Transporter not installed (App Store)";; esac
    fi
}

# Placeholder so the Mac App Store release isn't forgotten — not rigged yet.
do_mac() {
    cat <<'EOF'
!! The Mac App Store build isn't rigged yet. Still needed:
   - App Sandbox entitlements for the love-macosx target
   - macOS provisioning profile + distribution signing (archive-style)
   - export as .pkg + the separate macOS app record in App Store Connect
   (./ios.sh setup still builds the desktop engine app for development.)
EOF
}

menu() {
    local B=$'\e[1m' D=$'\e[2m' C=$'\e[36m' R=$'\e[0m' key
    while true; do
        echo ""
        echo "${C}════════════════════════════════════════════════${R}"
        echo "  ⚓  ${B}Båtspillet${R} — bygg & utgivelse"
        echo "${C}════════════════════════════════════════════════${R}"
        echo "   ${B}1${R}  iPad-simulator      ${D}$SIM_NAME${R}"
        echo "   ${B}2${R}  iPhone-simulator    ${D}$PHONE_SIM_NAME${R}"
        echo "   ${B}3${R}  Enhet               ${D}tilkoblet iPad/iPhone${R}"
        echo "   ${B}4${R}  App Store-arkiv     ${D}neste versjon: $(next_version)${R}"
        echo "   ${B}5${R}  Mac App Store       ${D}ikke rigget ennå${R}"
        echo "   ${B}q${R}  Avslutt"
        echo ""
        read -rsn1 -p "  Velg: " key; echo "${key:-}"
        # Re-exec for each action: keeps `set -e` fully armed inside it (a
        # plain `do_x || …` here would disable errexit within the function).
        case "${key:-}" in
            1) "$0" ipad     || echo "!! feilet" ;;
            2) "$0" iphone   || echo "!! feilet" ;;
            3) "$0" device   || echo "!! feilet" ;;
            4) "$0" archive  || echo "!! feilet" ;;
            5) "$0" mac ;;
            q|Q) exit 0 ;;
        esac
    done
}

case "${1:-}" in
    setup)   do_setup ;;
    xcode)   do_xcode ;;
    device)  do_device ;;
    archive) do_archive ;;
    ipad)    do_sim "$SIM_NAME" ;;
    iphone)  do_sim "$PHONE_SIM_NAME" ;;
    mac)     do_mac ;;
    "")      if [ -t 0 ] && [ -t 1 ]; then menu; else do_sim "$SIM_NAME"; fi ;;
    *)       echo "!! unknown command '$1' (ipad|iphone|device|archive|setup|xcode|mac)"; exit 1 ;;
esac
