#!/usr/bin/env bash
# Build, sign, notarize and staple Marky, and package it as build/release/Marky-<version>.dmg.
#
# Usage: scripts/release.sh [--install] [--skip-notarize]
#   --install        also copy the stapled app to /Applications and register it
#   --skip-notarize  sign only (quick local check)
# Env:   NOTARY_PROFILE  notarytool keychain profile (default: minibro-notary; it is the
#                        team's App Store Connect API key, so it works for any of our apps)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/release"
DD="$OUT/dd"
STAGE="$OUT/stage"
IDENTITY="Developer ID Application: Stefan Skotte (3WT5WSV6B5)"
PROFILE="${NOTARY_PROFILE:-minibro-notary}"
INSTALL=0
NOTARIZE=1
for arg in "$@"; do
	case "$arg" in
		--install) INSTALL=1 ;;
		--skip-notarize) NOTARIZE=0 ;;
		*) echo "usage: $0 [--install] [--skip-notarize]" >&2; exit 2 ;;
	esac
done
fail() { echo "FAILED: $*" >&2; exit 1; }

notarize() { # $1 = file to submit
	local out id
	out="$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait 2>&1)" || true
	echo "$out" | tail -2
	if ! grep -q 'status: Accepted' <<<"$out"; then
		id="$(awk '/^  id:/{print $2; exit}' <<<"$out")"
		[ -z "$id" ] || xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true
		fail "notarization of $(basename "$1") was not accepted"
	fi
}

cd "$ROOT"
command -v xcodegen >/dev/null && xcodegen generate >/dev/null
rm -rf "$DD" "$STAGE"
mkdir -p "$OUT" "$STAGE"

echo "** Release build (signed: $IDENTITY)"
xcodebuild -project Marky.xcodeproj -scheme Marky -configuration Release -derivedDataPath "$DD" build \
	>"$OUT/xcodebuild.log" 2>&1 || { tail -30 "$OUT/xcodebuild.log" >&2; fail "xcodebuild (see $OUT/xcodebuild.log)"; }
APP="$STAGE/Marky.app"
ditto "$DD/Build/Products/Release/Marky.app" "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$OUT/Marky-$VERSION.dmg"

echo "** Signing nested code (inside-out)"
SIGN=(codesign --force --options runtime --timestamp --sign "$IDENTITY")
SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
[ -d "$SPK" ] || fail "Sparkle.framework missing from the app"
"${SIGN[@]}" "$SPK/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$SPK/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$SPK/Autoupdate"
"${SIGN[@]}" "$SPK/Updater.app"
"${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" --entitlements "$ROOT/QuickLook/QuickLook-Release.entitlements" "$APP/Contents/PlugIns/MarkyQuickLook.appex"
"${SIGN[@]}" --entitlements "$ROOT/Marky/Marky-Release.entitlements" "$APP"

echo "** Checking signature"
codesign --verify --deep --strict "$APP" || fail "codesign verify"
for bundle in "$APP" "$APP/Contents/PlugIns/MarkyQuickLook.appex" "$APP/Contents/Frameworks/Sparkle.framework" \
	"$SPK/Autoupdate" "$SPK/Updater.app" "$SPK/XPCServices/Installer.xpc" "$SPK/XPCServices/Downloader.xpc"; do
	info="$(codesign -dvv "$bundle" 2>&1)"
	grep -qF "Authority=$IDENTITY" <<<"$info" || fail "$(basename "$bundle") is not signed by $IDENTITY"
	grep -q 'flags=.*runtime' <<<"$info" || fail "$(basename "$bundle") lacks the hardened runtime"
	grep -q 'Timestamp=' <<<"$info" || fail "$(basename "$bundle") has no secure timestamp"
	! codesign -d --entitlements - "$bundle" 2>/dev/null | grep -q get-task-allow || fail "$(basename "$bundle") has get-task-allow"
done
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q '3WT5WSV6B5.dk.enhance-it.marky' || fail "app lacks the App Group"
codesign -d --entitlements - "$APP/Contents/PlugIns/MarkyQuickLook.appex" 2>/dev/null | grep -q '3WT5WSV6B5.dk.enhance-it.marky' || fail "Quick Look lacks the App Group"
[ -n "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist" 2>/dev/null)" ] || fail "Info.plist has no SUPublicEDKey"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" = "$VERSION" ] || fail "CFBundleVersion differs from $VERSION (Sparkle compares it)"
echo "ok app, Quick Look, Sparkle: Developer ID, hardened runtime, timestamp; App Group; update keys"

if [ "$NOTARIZE" = 1 ]; then
	echo "** Notarizing the app"
	ditto -c -k --keepParent "$APP" "$OUT/Marky.zip"
	notarize "$OUT/Marky.zip"
	rm -f "$OUT/Marky.zip"
	xcrun stapler staple "$APP" >/dev/null || fail "stapler staple app"
	spctl -a -t exec "$APP" 2>&1 || fail "Gatekeeper rejects the app"
	echo "ok app notarized, stapled, accepted by Gatekeeper"
fi

echo "** Creating DMG"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Marky $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
if [ "$NOTARIZE" = 1 ]; then
	echo "** Notarizing the DMG"
	notarize "$DMG"
	xcrun stapler staple "$DMG" >/dev/null || fail "stapler staple dmg"
	spctl -a -t open --context context:primary-signature "$DMG" 2>&1 || fail "Gatekeeper rejects the DMG"
	echo "ok DMG notarized, stapled, accepted by Gatekeeper"
fi
hdiutil verify "$DMG" >/dev/null || fail "hdiutil verify"

if [ "$INSTALL" = 1 ]; then
	echo "** Installing to /Applications"
	osascript -e 'tell application id "dk.enhance-it.marky" to quit' >/dev/null 2>&1 || true
	rm -rf /Applications/Marky.app
	ditto "$APP" /Applications/Marky.app
	echo "ok installed"
fi

# Build copies register their own Quick Look extension; keep only /Applications/Marky.app.
rm -rf "$DD" "$STAGE"
"$ROOT/scripts/clean-registrations.sh" >/dev/null

echo "** Done: $DMG"
shasum -a 256 "$DMG"
