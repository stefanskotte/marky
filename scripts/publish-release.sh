#!/bin/bash
# Publishes a release that installed copies of Marky update to:
#   1. builds the DMG (scripts/release.sh: Developer ID signed, notarized, stapled) and signs it for
#      Sparkle with the "marky" key in the login Keychain,
#   2. tags v<version>, pushes main and the tag, creates the GitHub release with the DMG,
#   3. checks the uploaded DMG, then adds it to appcast.xml on main (the feed in Info.plist).
# The feed is updated last, so the app never sees a release whose download isn't there yet.
#
#   scripts/publish-release.sh <version> <release-notes.md> [--prerelease]
#
# <version> must equal MARKETING_VERSION in project.yml. Run on main with a clean tree.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="stefanskotte/marky"
KEY_ACCOUNT="marky"
SPARKLE_VERSION="2.10.0"
SPARKLE_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"

fail() { echo "publish-release: $*" >&2; exit 1; }

[ $# -ge 2 ] || fail "usage: $0 <version> <release-notes.md> [--prerelease]"
VERSION="$1"
NOTES="$2"
PRERELEASE="${3:-}"
[ -z "$PRERELEASE" ] || [ "$PRERELEASE" = --prerelease ] || fail "unknown option $PRERELEASE"
[ -s "$NOTES" ] || fail "no release notes at $NOTES"
NOTES="$(cd "$(dirname "$NOTES")" && pwd)/$(basename "$NOTES")"

cd "$ROOT"
[ "$(git branch --show-current)" = main ] || fail "not on main"
[ -z "$(git status --porcelain)" ] || fail "uncommitted changes"
git fetch -q origin main
git merge-base --is-ancestor origin/main HEAD || fail "origin/main has commits this main lacks: pull first"
grep -q "MARKETING_VERSION: \"$VERSION\"" project.yml || fail "MARKETING_VERSION in project.yml is not $VERSION"
! git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null || fail "tag v$VERSION exists"
grep -q "<sparkle:version>$VERSION</sparkle:version>" appcast.xml && fail "$VERSION is already in appcast.xml"

# Sparkle's signing tools, pinned to the framework version the app embeds.
TOOLS="$ROOT/build/sparkle-$SPARKLE_VERSION"
if [ ! -x "$TOOLS/bin/sign_update" ]; then
	echo "** Fetching Sparkle $SPARKLE_VERSION tools"
	mkdir -p "$TOOLS"
	curl -fsSL -o "$TOOLS.tar.xz" \
		"https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
	echo "$SPARKLE_SHA256  $TOOLS.tar.xz" | shasum -a 256 -c --quiet || fail "Sparkle tools checksum mismatch"
	tar -xf "$TOOLS.tar.xz" -C "$TOOLS"
fi

# The key that signs must be the one the app trusts, or every installed copy refuses the update.
APP_KEY="$(awk '/SUPublicEDKey:/{print $2}' project.yml)"
KEYCHAIN_KEY="$("$TOOLS/bin/generate_keys" --account "$KEY_ACCOUNT" -p 2>/dev/null)" \
	|| fail "no Sparkle key '$KEY_ACCOUNT' in the login Keychain (restore it with generate_keys -f)"
[ "$APP_KEY" = "$KEYCHAIN_KEY" ] || fail "Keychain key differs from SUPublicEDKey in project.yml"

"$ROOT/scripts/release.sh"
DMG="$ROOT/build/release/Marky-$VERSION.dmg"
[ -f "$DMG" ] || fail "no DMG at $DMG"
# sign_update reading the Keychain itself stops on an access prompt that never goes away, so the
# key is exported by generate_keys (which created it, so has access) to a private temp file that is
# removed straight after signing.
KEYDIR="$(mktemp -d)"
chmod 700 "$KEYDIR"
"$TOOLS/bin/generate_keys" --account "$KEY_ACCOUNT" -x "$KEYDIR/key" >/dev/null || { rm -rf "$KEYDIR"; fail "could not export the Sparkle key"; }
SIGNATURE="$("$TOOLS/bin/sign_update" --ed-key-file "$KEYDIR/key" -p "$DMG")" || SIGNATURE=""
"$TOOLS/bin/sign_update" --ed-key-file "$KEYDIR/key" --verify "$DMG" "$SIGNATURE" >/dev/null 2>&1 && VERIFIED=1 || VERIFIED=0
rm -P "$KEYDIR/key"; rmdir "$KEYDIR"
[ -n "$SIGNATURE" ] && [ "$VERIFIED" = 1 ] || fail "the DMG signature does not verify"
LENGTH="$(stat -f%z "$DMG")"
SHA256="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"

echo "** Tagging and publishing v$VERSION"
git tag -a "v$VERSION" -m "Marky $VERSION"
git push -q origin main "v$VERSION"
NAME="Marky $VERSION"
FLAGS=()
[ -z "$PRERELEASE" ] || FLAGS+=(--prerelease)
gh release create "v$VERSION" "$DMG" -R "$REPO" --title "$NAME" --notes-file "$NOTES" "${FLAGS[@]}" >/dev/null

URL="https://github.com/$REPO/releases/download/v$VERSION/Marky-$VERSION.dmg"
PAGE="https://github.com/$REPO/releases/tag/v$VERSION"
NOTES_HTML="$(mktemp)"
trap 'rm -f "$NOTES_HTML"' EXIT
gh api -X POST /markdown -f mode=gfm -f context="$REPO" -F text=@"$NOTES" >"$NOTES_HTML"

echo "** Checking the uploaded DMG"
[ "$(curl -fsSL "$URL" | shasum -a 256 | cut -d' ' -f1)" = "$SHA256" ] || fail "uploaded DMG differs from $DMG"

echo "** Adding v$VERSION to appcast.xml"
python3 -I "$ROOT/scripts/appcast.py" appcast.xml --version "$VERSION" --url "$URL" --length "$LENGTH" \
	--signature "$SIGNATURE" --notes-html "$NOTES_HTML" --release-page "$PAGE"
git add appcast.xml
git commit -q -m "release: v$VERSION in the update feed"
git push -q origin main

echo "** Done: $PAGE"
echo "   DMG sha256 $SHA256"
