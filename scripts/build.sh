#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_dir"

bridge_key_file=Sources/Shared/LocalKey.swift
if [ ! -f "$bridge_key_file" ]; then
    bridge_key=$(/usr/bin/openssl rand -hex 32)
    (
        umask 077
        set -C
        printf 'enum LocalKey {\n    static let value = "%s"\n}\n' "$bridge_key" > "$bridge_key_file"
    )
fi

/usr/bin/xcodebuild -project Wolke.xcodeproj -scheme Wolke -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$repo_dir/.build" build

app="$repo_dir/.build/Build/Products/Release/Wolke.app"
version=$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")
/usr/bin/codesign --verify --deep --strict "$app"
mkdir -p "$repo_dir/dist"
zip="$repo_dir/dist/Wolke-$version.zip"
release_dir=$(mktemp -d "$repo_dir/.build/wolke-release.XXXXXX")
trap 'rm -rf "$release_dir"' EXIT
/usr/bin/ditto --noextattr --norsrc "$app" "$release_dir/Wolke.app"
cp LICENSE NOTICE "$release_dir/"
/usr/bin/ditto -c -k --noextattr --norsrc "$release_dir" "$zip"
printf '\nApp: %s\nZIP: %s\n' "$app" "$zip"
