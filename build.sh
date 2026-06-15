#!/bin/bash
# Build distributables for Båtspillet:
#   1. Båtspillet.love           — the game as one LÖVE file (needs LÖVE installed)
#   2. Båtspillet.app + .dmg      — UNIVERSAL app (LÖVE 11.5, arm64+Intel) to hand out
#   3. Båtspillet-Yosemite.app    — Intel app (LÖVE 11.3) for the old 2009/Yosemite iMac
#
#   ./build.sh
#
# It finds the two LÖVE builds (a .zip or an unpacked love.app). Defaults look in
# ~/Downloads for the official zips; override with env vars:
#   LOVE_UNIVERSAL=/path/love-11.5  LOVE_YOSEMITE=/path/love-11.3  ./build.sh
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
#        NOTARY_PROFILE=batspillet ./build.sh
# (Alternatively pass APPLE_ID + TEAM_ID + APPLE_PASSWORD instead of NOTARY_PROFILE.)

set -euo pipefail
cd "$(dirname "$0")"

NAME="Båtspillet"
LOVE="$NAME.love"
LOVE_UNIVERSAL="${LOVE_UNIVERSAL:-$HOME/Downloads/love-11.5-macos.zip}"
LOVE_YOSEMITE="${LOVE_YOSEMITE:-$HOME/Downloads/love-11.3-macos.zip}"

# Signing identity: "-" = ad-hoc (default). Set SIGN_ID to a Developer ID to
# enable real signing. Notarization runs when credentials are present.
SIGN_ID="${SIGN_ID:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
NOTARY_READY=0
if [ -n "$NOTARY_PROFILE" ] || { [ -n "${APPLE_ID:-}" ] && [ -n "${TEAM_ID:-}" ] && [ -n "${APPLE_PASSWORD:-}" ]; }; then
    NOTARY_READY=1
fi

TMPDIRS=()
cleanup() { for d in "${TMPDIRS[@]:-}"; do [ -n "${d:-}" ] && rm -rf "$d"; done; }
trap cleanup EXIT

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
    plist "Set :CFBundleIdentifier com.tk.batspillet" "$pl"
    plist "Delete :CFBundleDocumentTypes" "$pl"        # don't pose as a ".love opener"
    plist "Delete :UTExportedTypeDeclarations" "$pl"
    sign_app "$app"
    xattr -cr "$app" 2>/dev/null || true
    echo ">> built $app  (arch: $(lipo -archs "$app/Contents/MacOS/love" 2>/dev/null || echo '?'))"
}

# ── 1) the .love ────────────────────────────────────────────────────────────
rm -f "$LOVE"
zip -9 -r -X "$LOVE" . \
    -x '.git/*' -x '.claude/*' -x 'raw/*' -x 'tools/*' -x 'save/*' \
    -x '*.love' -x '*.app' -x '*.app/*' -x '*.dmg' \
    -x '*.command' -x '*.applescript' \
    -x 'sync.sh' -x 'build.sh' -x 'CLAUDE.md' -x 'README.md' \
    -x '.DS_Store' -x '*/.DS_Store' -x '*.swp' \
    > /dev/null
echo ">> built $LOVE  ($(du -h "$LOVE" | cut -f1))"

# ── 2) universal app + dmg (LÖVE 11.5) ──────────────────────────────────────
U="$(resolve_love "$LOVE_UNIVERSAL")"
if [ -n "$U" ]; then
    make_app "$NAME.app" "$U"
    case "$(lipo -archs "$NAME.app/Contents/MacOS/love" 2>/dev/null)" in
        *arm64*) : ;;
        *) echo "   !! WARNING: $LOVE_UNIVERSAL is not universal — won't run native on Apple Silicon." ;;
    esac
    if [ "$NOTARY_READY" = 1 ]; then
        echo ">> notarizing $NAME.app (this can take a minute)…"
        notarize_app "$NAME.app"
    fi
    STAGE="$(mktemp -d)"; TMPDIRS+=("$STAGE")
    cp -R "$NAME.app" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    # A read-me inside the DMG: the app is unsigned, so macOS blocks it the first
    # time. These are the up-to-date steps (incl. macOS Sequoia/Tahoe, where the
    # old right-click→Open trick is gone).
    cat > "$STAGE/LES MEG – slik åpner du.txt" <<'TXT'
Slik åpner du Båtspillet første gang
====================================

  1. Dra «Båtspillet» over i Programmer-mappa (Applications) til høyre.
  2. Dobbeltklikk på Båtspillet. macOS sier at det ikke kan åpnes – det er OK.
  3. Åpne Apple-menyen  → Systeminnstillinger → «Personvern og sikkerhet».
  4. Bla helt ned. Der står det at «Båtspillet» ble blokkert – klikk «Åpne likevel».
  5. Dobbeltklikk Båtspillet igjen og bekreft med «Åpne».

Etter dette starter spillet som normalt hver gang.

Funker det ikke? Åpne appen Terminal, lim inn linjen under og trykk Enter:

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
else
    echo ">> NOTE: universal LÖVE not found ($LOVE_UNIVERSAL) — skipped $NAME.app/.dmg"
fi

# ── 3) Yosemite app (Intel LÖVE 11.3) ───────────────────────────────────────
Y="$(resolve_love "$LOVE_YOSEMITE")"
if [ -n "$Y" ]; then
    make_app "$NAME-Yosemite.app" "$Y"
else
    echo ">> NOTE: Intel/11.3 LÖVE not found ($LOVE_YOSEMITE) — skipped $NAME-Yosemite.app"
fi

echo ">> done."
if [ "$NOTARY_READY" = 1 ]; then
    echo ">> $NAME.dmg is signed + NOTARIZED — opens with a normal double-click for everyone. 🎉"
else
    echo ">> (ad-hoc / unsigned build.)  On another Mac, macOS will say \"is damaged\"."
    echo "   Recipient fix:  xattr -dr com.apple.quarantine \"/Applications/$NAME.app\""
    echo "   To build a clean, double-click DMG, run with a Developer ID + notarization:"
    echo "     SIGN_ID=\"Developer ID Application: NAME (TEAMID)\" NOTARY_PROFILE=batspillet ./build.sh"
fi
