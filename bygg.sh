#!/bin/bash
# Båtspillet — build & release console (iOS/iPadOS + App Store + Mac).
#
#   ./bygg.sh            — interactive menu (when run in a terminal)
#   ./bygg.sh utgivelse  — THE release: bumps the version once, builds iOS AND
#                          macOS from it, then hands both to Transporter
#   ./bygg.sh ipad       — build + run in the iPad simulator
#   ./bygg.sh iphone     — build + run in the iPhone simulator
#   ./bygg.sh device     — build + install on a plugged-in iPad/iPhone
#   ./bygg.sh archive    — App Store .ipa (version auto-bumps from ios/VERSION)
#   ./bygg.sh love       — just Båtspillet.love (every iOS build starts here)
#   ./bygg.sh dmg        — Båtspillet.app + .dmg to hand out (run `setup` first)
#   ./bygg.sh mac        — Mac App Store .pkg (same app record as iOS)
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
# Our engine customizations: ios/love-ios.plist and mac/love-macosx.plist
# (synced in before every build), mac/love-*.entitlements, and BATSPILLET-marked
# edits in the vendored pbxproj (bundle id skep.batspillet, StoreKit bridge
# ios/storekit/bt_iap.m as a target source — so EVERY build style links it: CLI,
# Xcode GUI, device, archive). Both app targets carry the same three members.
set -euo pipefail
cd "$(dirname "$0")"

NAME="Båtspillet"
# The .love filename is ASCII, and that is NOT cosmetic: `productbuild` — which
# builds the Mac App Store .pkg — writes a non-ASCII resource name into the
# package's BOM and then leaves the file OUT of the payload archive. The result
# installs an app whose signature seals a file that isn't there, and whose
# Resources hold no game. Nothing warns; the .pkg just quietly weighs 5 MB less.
# Both platforms' fused-game lookup takes any *.love in Resources by extension,
# never by name (ios.mm / macos.mm getLoveInResources), so the name is free —
# and the one thing it must not be is "Båtspillet.love".
LOVE="batspillet.love"
ENGINE="${ENGINE:-$PWD/engine}"
SIM_NAME="${SIM_NAME:-iPad Pro 13-inch (M4)}"
PHONE_SIM_NAME="${PHONE_SIM_NAME:-iPhone 15 Pro}"
TEAM_ID="${TEAM_ID:-8K92QASAAM}"   # baked into the vendored project too
BUNDLE_ID=skep.batspillet
XCODEPROJ="$ENGINE/platform/xcode/love.xcodeproj"
# The macOS target's product carries the game's name (it is what a Mac owner
# sees in /Applications), so `setup` builds Båtspillet.app — but a downloaded
# LÖVE is still love.app, and resolve_love takes either.
LOVE_UNIVERSAL="${LOVE_UNIVERSAL:-$ENGINE/build/Build/Products/Release/$NAME.app}"

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
# The App Store entitlements are sandboxed and profile-backed, which would stop
# the handed-out .dmg app launching at all — so `mac` puts them in place and
# this puts the dev set back, however the build ended.
RESTORE_ENTITLEMENTS=0
cleanup() {
    for d in "${TMPDIRS[@]:-}"; do [ -n "${d:-}" ] && rm -rf "$d"; done
    [ "$RESTORE_ENTITLEMENTS" = 1 ] && sync_entitlements mac/love-dev.entitlements
    true
}
trap cleanup EXIT

need_engine() {
    [ -d "$XCODEPROJ" ] || { echo "!! vendored engine missing at $ENGINE"; exit 1; }
}

# Our plist customizations live in this repo — sync before every build.
sync_plist() { cp ios/love-ios.plist "$ENGINE/platform/xcode/ios/love-ios.plist"; }
sync_plist_mac() {
    cp mac/love-macosx.plist "$ENGINE/platform/xcode/macosx/love-macosx.plist"
    cp mac/liblove-macosx.plist "$ENGINE/platform/xcode/macosx/liblove-macosx.plist"
}

# ── vendored frameworks: fill in what Apple insists on ─────────────────────
# Delivery fails with "Missing Bundle Identifier" (409, at Transporter time —
# after a clean build, a clean export and an upload) if ANY embedded framework
# has no CFBundleIdentifier. Several of LÖVE's prebuilt frameworks ship an
# Info.plist without one, and freetype's has no version keys at all. Apple also
# wants versions that parse: at most three dot-separated integers, which
# theora's "1.0d6" / "1.1alpha1svn" are not.
#
# Only ever fills a key that is MISSING or syntactically invalid, so it is
# idempotent and re-vendoring the engine cannot silently undo it. Editing the
# plist breaks that framework's own signature, which does not matter — they are
# copied with CodeSignOnCopy and re-signed with our identity — but re-sign
# ad-hoc anyway so the vendored tree is never internally inconsistent.
fw_plist() {
    local fw="$1"
    for p in "$fw/Resources/Info.plist" "$fw/Versions/A/Resources/Info.plist"; do
        [ -f "$p" ] && { echo "$p"; return; }
    done
}

# Add the key only if absent.
fw_add_missing() {
    local pl="$1" key="$2" val="$3"
    /usr/libexec/PlistBuddy -c "Print :$key" "$pl" >/dev/null 2>&1 && return 0
    /usr/libexec/PlistBuddy -c "Add :$key string $val" "$pl" >/dev/null
    echo "   $(basename "$(dirname "$(dirname "$pl")")"): $key = $val"
}

# Add if absent, replace if it isn't a valid Apple version string.
fw_fix_version() {
    local pl="$1" key="$2" val="$3" cur
    cur="$(/usr/libexec/PlistBuddy -c "Print :$key" "$pl" 2>/dev/null || true)"
    [[ "$cur" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] && return 0
    if [ -z "$cur" ]; then
        /usr/libexec/PlistBuddy -c "Add :$key string $val" "$pl" >/dev/null
    else
        /usr/libexec/PlistBuddy -c "Set :$key $val" "$pl" >/dev/null
    fi
    echo "   $(basename "$(dirname "$(dirname "$pl")")"): $key = $val (was '${cur:-unset}')"
}

stamp_frameworks() {
    local F="$ENGINE/platform/xcode/macosx/Frameworks" fw pl touched=""
    # id, version, short version. An empty field is left alone. freetype's
    # upstream binary declares no version at all, so 1.0.0 is ours — Apple only
    # requires a syntactically valid one, and inventing an upstream release
    # number would be worse than an obviously neutral placeholder.
    local specs=(
        "freetype|org.freetype.freetype|1.0.0|1.0.0"
        "harfbuzz|org.harfbuzz.harfbuzz||"
        "theora||1.1.0|1.1.0"
    )
    for spec in "${specs[@]}"; do
        IFS='|' read -r name id ver sver <<< "$spec"
        fw="$F/$name.framework"
        [ -d "$fw" ] || continue
        pl="$(fw_plist "$fw")"
        [ -n "$pl" ] || continue
        local before; before="$(shasum "$pl" | cut -d' ' -f1)"
        [ -n "$id" ]   && fw_add_missing  "$pl" CFBundleIdentifier "$id"
        [ -n "$ver" ]  && fw_fix_version  "$pl" CFBundleVersion "$ver"
        [ -n "$sver" ] && fw_fix_version  "$pl" CFBundleShortVersionString "$sver"
        if [ "$before" != "$(shasum "$pl" | cut -d' ' -f1)" ]; then
            codesign --force --sign - "$fw" 2>/dev/null || true
            touched="yes"
        fi
    done
    # Apple also requires each framework's CODE SIGNATURE identifier to equal its
    # bundle identifier ("Invalid Code Signature Identifier", another 409 at
    # delivery). codesign REUSES the identifier from a previous signature, so a
    # framework that was once signed while it had no CFBundleIdentifier keeps a
    # synthesized "libmodplug-<sha>" for ever — including through Xcode's
    # re-sign on copy, which is why fixing the plist alone is not enough. Spell
    # the identifier out once here; the archive's re-sign then carries it.
    local id sid
    for fw in "$F"/*.framework; do
        [ -d "$fw" ] || continue
        pl="$(fw_plist "$fw")"
        [ -n "$pl" ] || continue
        id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$pl" 2>/dev/null || true)"
        [ -n "$id" ] || continue
        sid="$(codesign -dvv "$fw" 2>&1 | sed -n 's/^Identifier=//p')"
        [ "$sid" = "$id" ] && continue
        codesign --force --sign - --identifier "$id" "$fw" 2>/dev/null || true
        echo "   $(basename "$fw"): signature identifier → $id (was '${sid:-unsigned}')"
        touched="yes"
    done
    [ -n "$touched" ] && echo ">> stamped vendored frameworks (Apple requires these)"
    true
}

# Same idea for the macOS entitlements: love-macosx signs with one fixed path,
# love.entitlements, and the two Mac builds need different sets. Whoever builds
# puts theirs in place; never leave the wrong one behind (see cleanup).
sync_entitlements() { cp "$1" "$ENGINE/platform/xcode/love.entitlements"; }

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
    sync_plist_mac
    stamp_frameworks
    sync_entitlements mac/love-dev.entitlements
    build_love          # the target fuses it in, so `setup` alone yields a playable app
    echo ">> building the macOS engine app (./bygg.sh dmg packages it)…"
    xcodebuild -project "$XCODEPROJ" -scheme love-macosx -configuration Release \
        -derivedDataPath "$ENGINE/build" -quiet build
    # The product is Båtspillet.app now (the Mac App Store bundle name is what a
    # Mac owner reads in /Applications). `setup` used to make love.app, and the
    # documented desktop workflow — plus any shell alias pointing at it — still
    # says love.app, so leave a symlink rather than break `love .`.
    local rel="$ENGINE/build/Build/Products/Release"
    # Strip the fused game from the DEV app. love-macosx carries the .love as a
    # target resource so the App Store archive contains it — but love.cpp inserts
    # a Resources/*.love at argv[1], BEFORE any path you pass, and adds --fused.
    # A dev app with the game inside would therefore ignore `love .` and run a
    # stale snapshot instead: edits do nothing, F5/F6 do nothing, and nothing
    # says why. `setup` builds the ENGINE; the game is packaged in by `dmg`
    # (make_app) and by `mac` (the archive), which is where it belongs.
    rm -f "$rel/$NAME.app"/Contents/Resources/*.love
    [ -L "$rel/love.app" ] || rm -rf "$rel/love.app"
    ln -sfn "$NAME.app" "$rel/love.app"
    echo ">> setup complete  ($rel/$NAME.app, with love.app → it)"
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
    # BT_RELEASE: `utgivelse` builds both platforms, then offers
    # Transporter ONCE at the end — no prompt half way through.
    if [ -t 0 ] && [ -z "${BT_RELEASE:-}" ]; then
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
        find "$d" -maxdepth 2 \( -name love.app -o -name "$NAME.app" \) -type d -print -quit
        return 0
    fi
    [ -d "$p" ] && find "$p" -maxdepth 2 \( -name love.app -o -name "$NAME.app" \) -type d -print -quit
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
    # Entitlements go on the outermost signature only — a framework carrying
    # them fails notarization. They are not optional here: the hardened runtime
    # this signature turns on refuses executable pages, and LÖVE embeds LuaJIT,
    # so a Developer ID app signed WITHOUT allow-jit dies the moment Lua runs.
    codesign --force --options runtime --timestamp \
        --entitlements mac/love-dev.entitlements --sign "$SIGN_ID" "$app"
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
    cat > "$STAGE/LES MEG - sånn åpner du.txt" <<'TXT'
Sånn åpner du Båtspillet
====================================

  1. Dra «Båtspillet» over i Programmer-mappen (Applications) til høyre
  2. Dobbeltklikk på Båtspillet. macOS sier at det ikke kan åpne
  3. Åpne Apple-menyen  → Systeminnstillinger → «Personvern og sikkerhet».
  4. Bla helt ned. Der står det at «Båtspillet» ble blokkert - klikk «Åpne likevel»
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

# ── Mac App Store: a signed .pkg for App Store Connect ─────────────────────
# Same bundle id as iOS (skep.batspillet) and the SAME App Store Connect record,
# which is what Universal Purchase means — and why Kaptein-pakken needs no work:
# an in-app purchase belongs to the app, not to a platform, so the product the
# iPad build sells is the product the Mac build sells. The StoreKit bridge is a
# member of both targets and guards its only UIKit call with TARGET_OS_IOS, so
# it compiles for macOS unchanged.
#
# TWO certificates are involved and they are NOT interchangeable:
#   Apple Distribution                 signs the .app
#   3rd Party Mac Developer Installer  signs the .pkg  (Xcode's Manage
#                                      Certificates calls it "Mac Installer
#                                      Distribution")
# The App Store takes only a signed .pkg for macOS — no .app, no .zip — so a
# missing installer cert stops the release dead. Preflight says which is absent.
#
# Version: macOS FOLLOWS ios/VERSION and never bumps it. The Mac release is the
# same game as the last iOS release, App Store Connect versions each platform
# separately, and one number for one game is the whole point. A Mac-only fix
# overrides: APP_VERSION=1.0.5 ./bygg.sh mac
#
# The profile name necessarily appears TWICE — on the love-macosx target in the
# pbxproj (a profile is a per-target setting; passing it on the xcodebuild
# command line also hits liblove-macosx, which is a framework and refuses one)
# and in mac/ExportOptions.plist, which re-signs. Neither can be dropped, so
# preflight reads both and insists they agree.

# Is a certificate with this common name in the keychain?
have_cert() { security find-certificate -c "$1" >/dev/null 2>&1; }

mac_profile_name() {
    /usr/libexec/PlistBuddy -c "Print :provisioningProfiles:$BUNDLE_ID" \
        mac/ExportOptions.plist 2>/dev/null
}

# Ask the build system, never grep the file: Xcode rewrites the pbxproj whenever
# the project is opened — the first open added an empty PROVISIONING_PROFILE_
# SPECIFIER to the Debug config, and a plain grep then read THAT and reported a
# mismatch against a perfectly good project. This resolves the same value the
# archive will actually use (~1.5 s).
mac_profile_in_project() {
    xcodebuild -project "$XCODEPROJ" -target love-macosx -configuration Release \
        -showBuildSettings 2>/dev/null \
        | sed -n 's/^ *PROVISIONING_PROFILE_SPECIFIER = //p' | head -1
}

ios_profile_name() {
    /usr/libexec/PlistBuddy -c "Print :provisioningProfiles:$BUNDLE_ID" \
        ios/ExportOptions.plist 2>/dev/null
}

# Is a profile by that name installed? Xcode reads both directories, and macOS
# profiles are .provisionprofile while iOS ones are .mobileprovision.
profile_installed() {
    local want="$1" d f tmp; tmp="$(mktemp)"; TMPDIRS+=("$tmp")
    for d in "$HOME/Library/MobileDevice/Provisioning Profiles" \
             "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
        [ -d "$d" ] || continue
        for f in "$d"/*.provisionprofile "$d"/*.mobileprovision; do
            [ -e "$f" ] || continue
            security cms -D -i "$f" -o "$tmp" 2>/dev/null || continue
            if [ "$(/usr/libexec/PlistBuddy -c 'Print :Name' "$tmp" 2>/dev/null)" = "$want" ]; then
                return 0
            fi
        done
    done
    return 1
}

# Everything signing-related that can be known BEFORE a build, so a missing
# certificate costs a second instead of fifteen minutes and an upload.
# $1: ios | mac | both
signing_preflight() {
    local want="$1" missing=0 prof projprof
    if ! have_cert "Apple Distribution"; then
        echo "!! mangler sertifikat: Apple Distribution — signerer appen"
        echo "   Xcode → Settings → Accounts → Manage Certificates → + → Apple Distribution"
        missing=1
    fi
    if [ "$want" != "mac" ]; then
        prof="$(ios_profile_name)"
        if [ -n "$prof" ] && ! profile_installed "$prof"; then
            echo "!! ingen iOS-profil ved navn '$prof'"
            echo "   developer.apple.com → Profiles → + → App Store,"
            echo "   App ID $BUNDLE_ID — last ned og dobbeltklikk."
            missing=1
        fi
    fi
    if [ "$want" != "ios" ]; then
        if ! have_cert "3rd Party Mac Developer Installer"; then
            echo "!! mangler sertifikat: 3rd Party Mac Developer Installer — signerer .pkg-en"
            echo "   Xcode → Settings → Accounts → Manage Certificates → + → Mac Installer Distribution"
            echo "   (et ANNET sertifikat enn det som signerer appen; macOS lastes"
            echo "    bare opp som .pkg, så ingenting kan sendes uten det)"
            missing=1
        fi
        prof="$(mac_profile_name)"
        if [ -z "$prof" ]; then
            echo "!! mac/ExportOptions.plist oppgir ingen profil for $BUNDLE_ID"
            return 1
        fi
        if ! profile_installed "$prof"; then
            echo "!! ingen macOS-profil ved navn '$prof'"
            echo "   developer.apple.com → Profiles → + → Mac App Store Connect,"
            echo "   App ID $BUNDLE_ID — last ned og dobbeltklikk."
            missing=1
        fi
        projprof="$(mac_profile_in_project)"
        if [ "$projprof" != "$prof" ]; then
            echo "!! profilnavnene er ulike — arkivet og eksporten ville vært uenige:"
            echo "   pbxproj (love-macosx):     '$projprof'"
            echo "   mac/ExportOptions.plist:   '$prof'"
            missing=1
        fi
    fi
    return "$missing"
}

# Apple validates every nested bundle — and only says so at DELIVERY, after a
# full build, export and upload. Same check here, where it costs seconds.
verify_bundles() {
    local app="$1" bad=0 fw pl id sid v k
    while IFS= read -r fw; do
        pl="$fw/Resources/Info.plist"
        [ -f "$pl" ] || pl="$fw/Versions/A/Resources/Info.plist"
        [ -f "$pl" ] || { echo "!! $(basename "$fw"): no Info.plist"; bad=1; continue; }
        id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$pl" 2>/dev/null || true)"
        [ -n "$id" ] || { echo "!! $(basename "$fw"): no CFBundleIdentifier"; bad=1; }
        sid="$(codesign -dvv "$fw" 2>&1 | sed -n 's/^Identifier=//p')"
        if [ -n "$id" ] && [ "$sid" != "$id" ]; then
            echo "!! $(basename "$fw"): signed as '$sid' but bundle id is '$id'"
            bad=1
        fi
        for k in CFBundleVersion CFBundleShortVersionString; do
            v="$(/usr/libexec/PlistBuddy -c "Print :$k" "$pl" 2>/dev/null || true)"
            [[ "$v" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] && continue
            echo "!! $(basename "$fw"): $k = '${v:-unset}' — needs up to three integers"
            bad=1
        done
    done < <(find "$app/Contents/Frameworks" -maxdepth 1 -name "*.framework" 2>/dev/null)
    [ "$bad" = 0 ] && return 0
    echo "   Apple rejects these at delivery, never at build time. Add them to stamp_frameworks."
    return 1
}

do_mac() {
    need_engine
    signing_preflight mac || exit 1

    sync_plist_mac
    stamp_frameworks
    RESTORE_ENTITLEMENTS=1                      # cleanup puts the dev set back
    sync_entitlements mac/love-appstore.entitlements
    build_love

    local build_no
    build_no="$(date +%Y%m%d%H%M)"   # unique, increasing — Apple requires it per upload
    if [ -z "${APP_VERSION:-}" ]; then
        [ -f ios/VERSION ] || { echo "!! ios/VERSION missing — seed it: echo 1.0 > ios/VERSION"; exit 1; }
        APP_VERSION="$(cat ios/VERSION)"
    fi
    echo "$APP_VERSION" | grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$' >/dev/null \
        || { echo "!! bad version '$APP_VERSION' (want e.g. 1.0.4)"; exit 1; }
    echo ">> archiving macOS (version $APP_VERSION, build $build_no)…"
    echo "   the macOS version in App Store Connect must read $APP_VERSION too, or"
    echo "   the upload arrives with no version to attach itself to."
    # Universal on purpose: an Apple-Silicon-only slice quietly drops every Intel
    # Mac, and the vendored frameworks are already x86_64+arm64, so it is free.
    # STRIP_STYLE: see do_archive — LuaJIT's FFI finds bt_iap_* via dlsym, and a
    # fully stripped binary kills IAP silently.
    # NO PROVISIONING_PROFILE_SPECIFIER here, deliberately — it lives on the
    # love-macosx target instead (see mac_profile_in_project). On the command
    # line it also lands on liblove-macosx, which is a framework and errors out
    # with "does not support provisioning profiles". It cannot simply be left to
    # the export either: the entitlements ask for IAP, so Xcode demands a
    # profile granting it before it will archive at all.
    local arch="$ENGINE/build/BatspilletMac.xcarchive"
    rm -rf "$arch"
    xcodebuild -project "$XCODEPROJ" -scheme love-macosx -configuration Release \
        -destination "generic/platform=macOS" -derivedDataPath "$ENGINE/build" \
        -archivePath "$arch" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="Apple Distribution" \
        CURRENT_PROJECT_VERSION="$build_no" \
        MARKETING_VERSION="$APP_VERSION" \
        ARCHS="x86_64 arm64" ONLY_ACTIVE_ARCH=NO \
        STRIP_STYLE=non-global \
        DEVELOPMENT_TEAM="$TEAM_ID" -quiet archive
    local arcapp="$arch/Products/Applications/$NAME.app"
    local arcbin="$arcapp/Contents/MacOS/love"
    if ! xcrun dyld_info -exports "$arcbin" 2>/dev/null | grep bt_iap_init >/dev/null; then
        echo "!! bt_iap_* not exported from the archived binary — IAP would be dead in production. NOT exporting."
        exit 1
    fi
    echo ">> bridge check OK (bt_iap_* exported, arch: $(lipo -archs "$arcbin"))"
    # The game itself must be inside, or the .pkg installs a LÖVE that boots to
    # the no-game screen — which passes review and fails the child.
    [ -n "$(find "$arcapp/Contents/Resources" -name '*.love' -print -quit)" ] \
        || { echo "!! no .love inside the archived app — NOT exporting."; exit 1; }
    verify_bundles "$arcapp" || exit 1
    echo ">> nested bundles OK (identifiers and versions Apple will accept)"

    echo ">> exporting .pkg for App Store Connect…"
    local explog="$ENGINE/build/export-mac-log.txt"
    rm -rf "$ENGINE/build/export-mac"
    if ! xcodebuild -exportArchive -archivePath "$arch" \
        -exportOptionsPlist mac/ExportOptions.plist \
        -exportPath "$ENGINE/build/export-mac" > "$explog" 2>&1; then
        cat "$explog"; exit 1
    fi
    # Same Apple-ID login noise as the iOS export; manual signing needs none of it.
    grep -vE "IDEDistribution|DVTServices|DVTPortal|DVTDeveloper|DVTAppleID|session has expired|Failed to log in|creationTimestamp|httpCode|protocolVersion|requestUrl|responseId|resultCode|resultString|userLocale|userString|payload = |NSLocalized|NSUnderlying|^\}|^    \}" "$explog" || true
    local pkg
    pkg="$(find "$ENGINE/build/export-mac" -name '*.pkg' -print -quit)"
    [ -n "$pkg" ] || { echo "!! no .pkg in the export — see $explog"; exit 1; }
    # Check the PAYLOAD, not the archive: productbuild silently dropped the game
    # once already (a non-ASCII resource name lands in the BOM but not in the
    # payload archive — see $LOVE above). The .pkg looked perfect, installed an
    # app with no game inside, and nothing anywhere said so.
    # (plain grep, not -q, for the same reason as the bridge check above: -q
    # exits at the first match and SIGPIPEs pkgutil, which pipefail then reports
    # as a failure — the guard would fire on a perfectly good .pkg.)
    if ! pkgutil --payload-files "$pkg" 2>/dev/null | grep "Contents/Resources/.*\.love$" >/dev/null; then
        echo "!! the .pkg payload has no .love — the installed app would have NO GAME."
        echo "   productbuild dropped it. Check for non-ASCII in the resource name."
        exit 1
    fi
    echo ">> payload check OK (the game is inside the .pkg)"
    echo ">> $pkg — deliver via Transporter"
    # BT_RELEASE: `utgivelse` builds both platforms, then offers
    # Transporter ONCE at the end — no prompt half way through.
    if [ -t 0 ] && [ -z "${BT_RELEASE:-}" ]; then
        local a=""
        read -rn1 -p ">> open Transporter with the .pkg now? [Y/n] " a; echo
        case "$a" in n|N) ;; *) open -a Transporter "$pkg" || echo "!! Transporter not installed (App Store)";; esac
    fi
}

# ── the whole release, both platforms, one command ─────────────────────────
# One version number for one game: the bump happens HERE, once, and both builds
# inherit it through APP_VERSION — so iOS and macOS can never drift apart by a
# forgotten flag. Signing is checked for BOTH platforms up front, because the
# iOS archive alone is ten minutes and finding out afterwards that a Mac
# certificate is missing is the worst possible moment.
do_release() {
    need_engine
    local B=$'\e[1m' D=$'\e[2m' C=$'\e[36m' R=$'\e[0m'
    local ver="${APP_VERSION:-$(next_version)}"
    echo "$ver" | grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$' >/dev/null \
        || { echo "!! ugyldig versjon '$ver' (vil ha f.eks. 1.0.5)"; exit 1; }

    echo ""
    echo "${C}════════════════════════════════════════════════${R}"
    echo "  ⚓  ${B}Utgivelse $ver${R} — iOS + macOS"
    echo "${C}════════════════════════════════════════════════${R}"
    echo "  Bygger begge, klare for opplasting. Tar 10–20 min"
    echo "  ${D}Du kan gå og ta en kaffe; jeg sier fra når begge er klare.${R}"
    echo ""
    echo "  ${B}Sjekker signering først…${R}"
    signing_preflight both || {
        echo ""
        echo "  Fiks det over og kjør igjen — ingenting er bygget ennå."
        exit 1
    }
    echo "  ${D}sertifikater og profiler OK${R}"
    echo ""
    if [ -t 0 ]; then
        local a=""
        read -rn1 -p "  Bygge $ver for begge plattformer? [Y/n] " a; echo
        case "$a" in n|N) echo "  Avbrutt."; exit 0 ;; esac
    fi

    # Both children inherit the version, so neither bumps on its own; archive
    # writes it to ios/VERSION, which mac then reads back to the same number.
    export APP_VERSION="$ver"
    export BT_RELEASE=1          # no Transporter prompt half way through
    echo ""
    echo "${C}── 1/2  iOS ────────────────────────────────────${R}"
    "$0" archive || { echo "!! iOS-bygget feilet — macOS ikke forsøkt."; exit 1; }
    echo ""
    echo "${C}── 2/2  macOS ──────────────────────────────────${R}"
    "$0" mac || { echo "!! macOS-bygget feilet (iOS-arkivet er ferdig)."; exit 1; }

    local ipa="$ENGINE/build/export/Batspillet.ipa"
    local pkg; pkg="$(find "$ENGINE/build/export-mac" -name '*.pkg' -print -quit)"
    echo ""
    echo "${C}════════════════════════════════════════════════${R}"
    echo "  🎉  ${B}Versjon $ver er bygget — begge plattformer${R}"
    echo "${C}════════════════════════════════════════════════${R}"
    echo "   iOS    ${D}$ipa${R}"
    echo "   macOS  ${D}$pkg${R}"
    echo ""
    echo "  ${B}Slik får du dem ut i verden:${R}"
    echo ""
    echo "   ${B}1.${R} Last opp BEGGE i Transporter (åpnes nå)."
    echo "      Dra inn én, vent til den sier Delivered, så den andre."
    echo "   ${B}2.${R} appstoreconnect.apple.com → Båtspillet"
    echo "      Lag versjon ${B}$ver${R} for ${B}både iOS og macOS${R} — to separate"
    echo "      sider, samme nummer. Byggene dukker opp etter 5–15 min."
    echo "   ${B}3.${R} Skriv hva som er nytt, velg bygget, «Send til vurdering»."
    echo ""
    echo "  ${D}Kaptein-pakken følger med av seg selv: samme app, samme kjøp.${R}"
    echo "  ${D}Husk: git commit -am \"Versjon $ver\" (ios/VERSION er endret).${R}"
    echo ""
    if [ -t 0 ]; then
        local t=""
        read -rn1 -p "  Åpne Transporter med begge nå? [Y/n] " t; echo
        case "$t" in
            n|N) ;;
            *) open -a Transporter "$ipa" "$pkg" 2>/dev/null \
                 || echo "  !! Transporter er ikke installert (hent den i App Store)" ;;
        esac
    fi
}

menu() {
    local B=$'\e[1m' D=$'\e[2m' C=$'\e[36m' R=$'\e[0m' key
    while true; do
        echo ""
        echo "${C}════════════════════════════════════════════════${R}"
        echo "  ⚓  ${B}Båtspillet${R} - fang og slipp ut 🐟"
        echo "${C}════════════════════════════════════════════════${R}"
        echo ""
        echo "  ${B}UTGIVELSE${R}  ${D}- distribusjon${R}"
        echo "   ${B}1${R}  ${B}Slipp ny versjon${R}   ${D}iOS + macOS, klar til opplasting${R}"
        echo "      ${D}$(cat ios/VERSION 2>/dev/null || echo '?') → $(next_version) for begge plattformer, ~10 min${R}"
        echo ""
        echo "  ${B}PRØVE UT${R}"
        echo "   ${B}2${R}  iPad-simulator      ${D}$SIM_NAME${R}"
        echo "   ${B}3${R}  iPhone-simulator    ${D}$PHONE_SIM_NAME${R}"
        echo "   ${B}4${R}  Enhet               ${D}tilkoblet iPad/iPhone${R}"
        echo "   ${B}5${R}  Skjermbilder        ${D}til App Store-siden${R}"
        echo ""
        echo "  ${B}ÉN OM GANGEN${R}  ${D}- hvis noe må gjøres på nytt${R}"
        echo "   ${B}6${R}  Kun iOS  (.ipa)     ${D}neste versjon: $(next_version)${R}"
        echo "   ${B}7${R}  Kun macOS (.pkg)    ${D}versjon: $(cat ios/VERSION 2>/dev/null || echo '?')${R}"
        echo "   ${B}8${R}  Mac-app + .dmg      ${D}dele ut utenom App Store${R}"
        echo ""
        echo "   ${B}q${R}  Avslutt"
        echo ""
        read -rsn1 -p "  Velg: " key; echo "${key:-}"
        # Re-exec for each action: keeps `set -e` fully armed inside it (a
        # plain `do_x || …` here would disable errexit within the function).
        case "${key:-}" in
            1) "$0" utgivelse || echo "!! feilet" ;;
            2) "$0" ipad      || echo "!! feilet" ;;
            3) "$0" iphone    || echo "!! feilet" ;;
            4) "$0" device    || echo "!! feilet" ;;
            5) how_screenshots ;;
            6) "$0" archive   || echo "!! feilet" ;;
            7) "$0" mac       || echo "!! feilet" ;;
            8) "$0" dmg       || echo "!! feilet" ;;
            q|Q) exit 0 ;;
        esac
    done
}

# Screenshots are the one release step no script can do for you, so the menu
# tells you how instead of pretending to.
how_screenshots() {
    local B=$'\e[1m' D=$'\e[2m' C=$'\e[36m' R=$'\e[0m'
    cat <<EOF

${C}════════════════════════════════════════════════${R}
  📸  ${B}Skjermbilder til App Store${R}
${C}════════════════════════════════════════════════${R}

   ${B}1.${R} Kjør spillet i skjermbilde-modus:

        ${B}BATSHOT=retina love .${R}

   ${B}2.${R} Spill deg til noe fint. Trykk ${B}F10${R} for hvert bilde.
      Stien skrives i terminalen (lagremappa).

   ${B}3.${R} Last dem opp i App Store Connect.

   ${D}Hvorfor ikke bare et vanlig skjermbilde: App Store tar KUN${R}
   ${D}1280x800, 1440x900, 2560x1600 eller 2880x1800, og skalerer${R}
   ${D}ingenting. BATSHOT setter vinduet til riktig størrelse, og F10${R}
   ${D}tar bildet inne i spillet — uten musepeker, menylinje og ramme,${R}
   ${D}som alle tre gjør at bildet blir avvist. «retina» gir 2880x1800.${R}

   ${D}Alle bildene i ett sett må ha samme størrelse — bli på «retina».${R}

EOF
    read -rsn1 -p "  Trykk en tast… "; echo
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
    utgivelse|release) do_release ;;
    "")      if [ -t 0 ] && [ -t 1 ]; then menu; else do_sim "$SIM_NAME"; fi ;;
    *)       echo "!! unknown command '$1' (utgivelse|ipad|iphone|device|archive|mac|love|dmg|setup|xcode)"; exit 1 ;;
esac
