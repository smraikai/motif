#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ $# -gt 1 || ($# -eq 1 && "$1" != "--open-at-login") ]]; then
  printf 'Usage: %s [--open-at-login]\n' "$0" >&2
  exit 1
fi
source_app="$PWD/dist/Motif.app"
installed_app="/Applications/Motif.app"
[[ -d "$source_app" ]] || { printf 'Run ./macos/build.sh first.\n' >&2; exit 1; }
codesign --verify --deep --strict "$source_app"
if [[ -e "$installed_app" ]]; then
  identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installed_app/Contents/Info.plist")
  [[ "$identifier" == "io.github.itsdotdev.motif" ]] || { printf 'A different app already exists at %s.\n' "$installed_app" >&2; exit 1; }
fi
xcrun swift -module-cache-path .build/ModuleCache Tools/StopPlayer.swift
ditto --noextattr --norsrc "$source_app" "$installed_app"
codesign --verify --deep --strict "$installed_app"
if [[ "${1:-}" == "--open-at-login" ]]; then
  open "$installed_app" --args --enable-login-item
else
  open "$installed_app"
fi
printf 'Installed %s\n' "$installed_app"
