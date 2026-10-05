#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
configuration="${1:-debug}"
swift build --disable-sandbox --cache-path .build/swift-cache -c "$configuration" --product Phelsuma
bin_path="$(swift build --disable-sandbox --cache-path .build/swift-cache -c "$configuration" --show-bin-path)"
app_path="$PWD/build/Phelsuma.app"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_path/Phelsuma" "$app_path/Contents/MacOS/Phelsuma"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
if [[ -n "${PHELSUMA_VERSION:-}" ]]; then
    plutil -replace CFBundleShortVersionString -string "$PHELSUMA_VERSION" "$app_path/Contents/Info.plist"
fi
if [[ -n "${PHELSUMA_BUILD_NUMBER:-}" ]]; then
    plutil -replace CFBundleVersion -string "$PHELSUMA_BUILD_NUMBER" "$app_path/Contents/Info.plist"
fi
codesign --force --sign - "$app_path"
printf '%s\n' "$app_path"
