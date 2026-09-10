#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build dist
python3 Tools/fetch-dependencies.py
stage="$(mktemp -d "${TMPDIR:-/tmp}/motif-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/Motif.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Tools"
xcrun swiftc -swift-version 5 -O -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path .build/ModuleCache Sources/*.swift \
  -o "$app/Contents/MacOS/Motif"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/MenuBarIcon.png "$app/Contents/Resources/"
cp .deps/yt-dlp .deps/deno "$app/Contents/Resources/Tools/"
cp ../LICENSE "$app/Contents/Resources/LICENSE"
cp Resources/Third-party-notices.txt "$app/Contents/Resources/"
cp -R Resources/Licenses "$app/Contents/Resources/"
xcrun swift -module-cache-path .build/ModuleCache Tools/Icon.swift .build/AppIcon.iconset Resources/AppIcon.png "$app/Contents/Resources/AppIcon.icns"
# Keep the vendors' signatures on their executables. Sign our enclosing bundle.
# Finder may attach metadata to bundles built in an iCloud Documents folder.
xattr -dr com.apple.FinderInfo "$app" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$app" 2>/dev/null || true
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
ditto --noextattr --norsrc "$app" "$PWD/dist/Motif.app"
printf 'Built %s\n' "$PWD/dist/Motif.app"
