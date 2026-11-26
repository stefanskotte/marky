#!/usr/bin/env bash
# Unregister every Marky copy (app + Quick Look extension) except /Applications/Marky.app.
# Build products get registered with LaunchServices/PlugInKit automatically, so without
# this Finder ends up with several Marky Quick Look extensions.
set -uo pipefail
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -dump 2>/dev/null \
	| sed -n 's/^path: *\(.*Marky\.app\) (0x[0-9a-f]*)$/\1/p' | sort -u \
	| while read -r app; do
		[ "$app" = /Applications/Marky.app ] && continue
		pluginkit -r "$app/Contents/PlugIns/MarkyQuickLook.appex" 2>/dev/null
		"$LSREGISTER" -u "$app" 2>/dev/null
		echo "unregistered $app"
	done
pluginkit -m -v -p com.apple.quicklook.preview 2>/dev/null \
	| awk -F'\t' 'tolower($0) ~ /marky/ {print $NF}' \
	| while read -r ext; do
		case "$ext" in /Applications/Marky.app/*) ;; *) pluginkit -r "$ext" 2>/dev/null; echo "removed $ext" ;; esac
	done
[ -d /Applications/Marky.app ] && "$LSREGISTER" -f /Applications/Marky.app
qlmanage -r >/dev/null 2>&1 || true
