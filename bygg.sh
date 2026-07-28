#!/bin/bash
# Båtspillet — build & release console (iOS/iPadOS + App Store + Mac).
#
#   ./bygg.sh            — interactive menu (when run in a terminal)
#   ./bygg.sh ipad       — build + run in the iPad simulator
#   ./bygg.sh iphone     — build + run in the iPhone simulator
#   ./bygg.sh device     — build + install on a plugged-in iPad/iPhone
#   ./bygg.sh archive    — App Store .ipa (version auto-bumps from ios/VERSION)
#   ./bygg.sh love       — just Båtspillet.love (every iOS build starts here)
#   ./bygg.sh dmg        — Båtspillet.app + .dmg to hand out (run `setup` first)
#   ./bygg.sh setup      — one-time: build the macOS engine app (dmg packages it)
#   ./bygg.sh xcode      — open the vendored engine project (manual device runs)
#
# SIM_NAME / PHONE_SIM_NAME env override the preferred simulators. A bare
# `./bygg.sh` outside a terminal (scripts, CI) runs `ipad`, like before.
# Only the iOS commands need the vendored Xcode project; `love` and `dmg` run
# on a Mac without Xcode (point LOVE_UNIVERSAL at a downloaded love.app/.zip).
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

NAME="Båtspillet"
LOVE="$NAME.love"
ENGINE="${ENGINE:-$PWD/engine}"
SIM_NAME="${SIM_NAME:-iPad Pro 13-inch (M4)}"
PHONE_SIM_NAME="${PHONE_SIM_NAME:-iPhone 15 Pro}"
TEAM_ID="${TEAM_ID:-8K92QASAAM}"   # baked into the vendored project too
BUNDLE_ID=skep.batspillet
XCODEPROJ="$ENGINE/platform/xcode/love.xcodeproj"
LOVE_UNIVERSAL="${LOVE_UNIVERSAL:-$ENGINE/build/Build/Products/Release/love.app}"

# Signing identity for the handed-out Mac app: "-" = ad-hoc (default). Set
# SIGN_ID to a Developer ID to enable real signing. Notarization runs when
# credentials are present.
SIGN_ID="${SIGN_ID:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
NOTARY_READY=0
if [ -n "$NOTARY_PROFILE" ] || { [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_PASSWORD:-}" ]; }; then
    NOTARY_READY=1
fi

TMPDIRS=()
cleanup() { for d in "${TMPDIRS[@]:-}"; do [ -n "${d:-}" ] && rm -rf "$d"; done; true; }
trap cleanup EXIT

need_engine() {
    [ -d "$XCODEPROJ" ] || { echo "!! vendored engine missing at $ENGINE"; exit 1; }
}

# Our plist customizations live in this repo — sync before every build.
sync_plist() { cp ios/love-ios.plist "$ENGINE/platform/xcode/ios/love-ios.plist"; }

# What the next auto-bumped marketing version will be (see do_archive).
next_version() {
    [ -f ios/VERSION ] || { echo "?"; return; }
    awk -F. 'NF==3 {printf "%d.%d.%d", $1,$2,$3+1} NF==2 {printf "%s.%s.1", $1,$2}' ios/VERSION
}

# The game as one LÖVE file. Every other target packages this.
# Excluded: build-time-only art (assets/icon is source for tools/make_icon.py,
# raw/ is scanned originals) and this script — none of it is read at runtime,
# and it all rides along into the App Store download otherwise.
build_love() {
    rm -f "$LOVE"
    zip -9 -r -X "$LOVE" . \
        -x '.git/*' -x '.claude/*' -x 'raw/*' -x 'tools/*' -x 'save/*' \
        -x 'engine/*' -x 'tests/*' -x 'docs/*' -x 'ios/*' \
        -x 'assets/icon/*' -x 'skjermbilde.png' \
        -x '*.love' -x '*.app' -x '*.app/*' -x '*.dmg' -x '*.zip' \
        -x 'bygg.sh' -x '.gitignore' -x 'CLAUDE.md' -x 'README.md' \
        -x '.DS_Store' -x '*/.DS_Store' -x '*.swp' \
        > /dev/null
    echo ">> built $LOVE  ($(du -h "$LOVE" | cut -f1))"
}

do_setup() {
    need_engine
    sync_plist
    echo ">> building the macOS engine app (./bygg.sh dmg packages it)…"
    xcodebuild -project "$XCODEPROJ" -scheme love-macosx -configuration Release \
        -derivedDataPath "$ENGINE/build" -quiet build
    echo ">> setup complete"
}

do_xcode() { need_engine; open "$XCODEPROJ"; }

# ── simulator: build + install + launch ────────────────────────────────────
do_sim() {
    local sim="$1"
    need_engine
    sync_plist
    build_love
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
# Needs a signing team: TEAM_ID=XXXXXXXXXX ./bygg.sh device
# (free personal team works — the id is in Xcode ▸ Settings ▸ Accounts).
do_device() {
    need_engine
    sync_plist
    build_love
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
# ./bygg.sh archive → .ipa under engine/build/export
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
#       APP_VERSION=1.1 ./bygg.sh archive
#     Commit ios/VERSION together with the release.
do_archive() {
    need_engine
    sync_plist
    build_love
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

# ── the Mac app handed out to family: Båtspillet.app + .dmg ────────────────
# Packages the love.app from `./bygg.sh setup` (LOVE_UNIVERSAL overrides it —
# a path to a .app, a .zip or a folder containing one, e.g. a LÖVE download).
#
# By default the apps are AD-HOC signed (free, no account) — which macOS blocks
# on download ("is damaged"); recipients must run:
#     xattr -dr com.apple.quarantine "/Applications/Båtspillet.app"
#
# To make the DMG open with a plain double-click for everyone, sign + NOTARIZE.
# This needs a paid Apple Developer account. Whoever has one does this ONCE:
#   1. Install their "Developer ID Application" cert into the login keychain
#      (Xcode → Settings → Accounts → Manage Certificates, or developer.apple.com).
#   2. Store a notarytool credential profile once:
#        xcrun notarytool store-credentials batspillet \
#          --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
#   3. Build with:
#        SIGN_ID="Developer ID Application: Your Name (TEAMID)" \
#        NOTARY_PROFILE=batspillet ./bygg.sh dmg
# (Alternatively pass APPLE_ID + APPLE_PASSWORD instead of NOTARY_PROFILE.)

# Resolve a love.app from a path that may be a .app, a .zip, or a folder. Echoes
# the love.app path (nothing if the source isn't there).
resolve_love() {
    local p="$1"
    [ -e "$p" ] || return 0
    if [ -d "$p" ] && [[ "$p" == *.app ]]; then echo "$p"; return 0; fi
    if [[ "$p" == *.zip ]] && [ -f "$p" ]; then
        local d; d="$(mktemp -d)"; TMPDIRS+=("$d")
        unzip -q "$p" -d "$d"
        find "$d" -maxdepth 2 -name love.app -type d -print -quit
        return 0
    fi
    [ -d "$p" ] && find "$p" -maxdepth 2 -name love.app -type d -print -quit
}

plist() { /usr/libexec/PlistBuddy -c "$1" "$2" 2>/dev/null || true; }

# Sign an app bundle. With a real Developer ID (SIGN_ID set) it signs inside-out
# with the hardened runtime + secure timestamp (both required for notarization);
# otherwise it falls back to a free ad-hoc signature (Gatekeeper-blocked).
sign_app() {
    local app="$1"
    if [ "$SIGN_ID" = "-" ]; then
        codesign --force --deep --sign - "$app" 2>/dev/null || true
        return
    fi
    # nested mach-o first (dylibs), then each framework, then the binary + bundle
    find "$app/Contents/Frameworks" -type f \( -name '*.dylib' -o -name '*.so' \) -print0 2>/dev/null \
        | while IFS= read -r -d '' f; do
            codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$f"
        done
    for fw in "$app"/Contents/Frameworks/*; do
        [ -e "$fw" ] && codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$fw"
    done
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$app/Contents/MacOS/love"
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$app"
    codesign --verify --deep --strict "$app" && echo "   signature: $SIGN_ID (verified)"
}

# Submit a .zip/.dmg to Apple and wait for the verdict.
notarize_file() {
    if [ -n "$NOTARY_PROFILE" ]; then
        xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
    else
        xcrun notarytool submit "$1" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" \
            --password "$APPLE_PASSWORD" --wait
    fi
}

# Notarize an .app (zip it, submit, then staple the ticket into the bundle).
notarize_app() {
    local app="$1" d; d="$(mktemp -d)"; TMPDIRS+=("$d")
    /usr/bin/ditto -c -k --keepParent "$app" "$d/app.zip"
    notarize_file "$d/app.zip" && xcrun stapler staple "$app"
}

# Build <appname>.app from a love.app, with our .love inside and our identity.
make_app() {
    local app="$1" loveapp="$2"
    rm -rf "$app"
    cp -R "$loveapp" "$app"
    cp "$LOVE" "$app/Contents/Resources/"
    local pl="$app/Contents/Info.plist"
    plist "Set :CFBundleName $NAME" "$pl"
    plist "Set :CFBundleIdentifier $BUNDLE_ID" "$pl"
    plist "Delete :CFBundleDocumentTypes" "$pl"        # don't pose as a ".love opener"
    plist "Delete :UTExportedTypeDeclarations" "$pl"
    sign_app "$app"
    xattr -cr "$app" 2>/dev/null || true
    echo ">> built $app  (arch: $(lipo -archs "$app/Contents/MacOS/love" 2>/dev/null || echo '?'))"
}

do_dmg() {
    build_love
    local U; U="$(resolve_love "$LOVE_UNIVERSAL")"
    if [ -z "$U" ]; then
        echo "!! no love.app at $LOVE_UNIVERSAL — run ./bygg.sh setup first"
        exit 1
    fi
    make_app "$NAME.app" "$U"
    case "$(lipo -archs "$NAME.app/Contents/MacOS/love" 2>/dev/null)" in
        *arm64*) : ;;
        *) echo "   !! WARNING: $LOVE_UNIVERSAL is not universal — won't run native on Apple Silicon." ;;
    esac
    if [ "$NOTARY_READY" = 1 ]; then
        echo ">> notarizing $NAME.app (this can take a minute)…"
        notarize_app "$NAME.app"
    fi
    local STAGE; STAGE="$(mktemp -d)"; TMPDIRS+=("$STAGE")
    cp -R "$NAME.app" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    # A read-me inside the DMG: the app is unsigned, so macOS blocks it the first
    # time. These are the up-to-date steps (incl. macOS Sequoia/Tahoe, where the
    # old right-click→Open trick is gone).
    cat > "$STAGE/LES MEG – slik åpner du.txt" <<'TXT'
Sånn åpner du Båtspillet
====================================

  1. Dra «Båtspillet» over i Programmer-mappen (Applications) til høyre
  2. Dobbeltklikk på Båtspillet. macOS sier at det ikke kan åpne
  3. Åpne Apple-menyen  → Systeminnstillinger → «Personvern og sikkerhet».
  4. Bla helt ned. Der står det at «Båtspillet» ble blokkert – klikk «Åpne likevel»
  5. Dobbeltklikk på Båtspillet igjen og bekreft med «Åpne»

Etter dette starter spillet som normalt hver gang.

Dette virker antakelig ikke i Tahoe og oppover. Åpne Terminal, lim inn linjen
under og trykk Enter:

    xattr -dr com.apple.quarantine "/Applications/Båtspillet.app"

TXT
    rm -f "$NAME.dmg"
    if hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$NAME.dmg" >/dev/null 2>&1; then
        echo ">> built $NAME.dmg  ($(du -h "$NAME.dmg" | cut -f1))"
        if [ "$NOTARY_READY" = 1 ]; then
            echo ">> notarizing $NAME.dmg (this can take a minute)…"
            notarize_file "$NAME.dmg" && xcrun stapler staple "$NAME.dmg"
        fi
    else
        echo ">> NOTE: hdiutil failed — $NAME.app is ready, but no .dmg."
    fi
    if [ "$NOTARY_READY" = 1 ]; then
        echo ">> $NAME.dmg is signed + NOTARIZED — opens with a normal double-click for everyone. 🎉"
    else
        echo ">> (ad-hoc / unsigned build.)  On another Mac, macOS will say \"is damaged\"."
        echo "   Recipient fix:  xattr -dr com.apple.quarantine \"/Applications/$NAME.app\""
        echo "   To build a clean, double-click DMG, run with a Developer ID + notarization:"
        echo "     SIGN_ID=\"Developer ID Application: NAME (TEAMID)\" NOTARY_PROFILE=batspillet ./bygg.sh dmg"
    fi
}

# Placeholder so the Mac App Store release isn't forgotten — not rigged yet.
do_mac() {
    cat <<'EOF'
!! The Mac App Store build isn't rigged yet. Still needed:
   - App Sandbox entitlements for the love-macosx target
   - macOS provisioning profile + distribution signing (archive-style)
   - export as .pkg + the separate macOS app record in App Store Connect
   (./bygg.sh setup still builds the desktop engine app for development.)
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
        echo "   ${B}5${R}  Mac-app + .dmg      ${D}dele ut til familien${R}"
        echo "   ${B}6${R}  Mac App Store       ${D}ikke rigget ennå${R}"
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
            5) "$0" dmg      || echo "!! feilet" ;;
            6) "$0" mac ;;
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
    love)    build_love ;;
    dmg)     do_dmg ;;
    mac)     do_mac ;;
    "")      if [ -t 0 ] && [ -t 1 ]; then menu; else do_sim "$SIM_NAME"; fi ;;
    *)       echo "!! unknown command '$1' (ipad|iphone|device|archive|love|dmg|setup|xcode|mac)"; exit 1 ;;
esac
