#!/bin/bash
set -euo pipefail
expanded="$(mktemp -d)/package"
pkgutil --expand-full "$1" "$expanded"
payload="$expanded/Installer.pkg/Payload"
app="$payload/Applications/Background Music.app"
host="$app/Contents/Resources/AudioHub.NativeHost"
test -x "$host"
test -f "$app/Contents/Resources/edge/manifest.json"
test -f "$app/Contents/Resources/AudioHub-使用说明.md"
lipo "$host" -verify_arch x86_64 arm64
lipo "$app/Contents/MacOS/Background Music" -verify_arch x86_64 arm64
lipo "$payload/Library/Audio/Plug-Ins/HAL/Background Music Device.driver/Contents/MacOS/Background Music Device" -verify_arch x86_64 arm64
lipo "$expanded/Installer.pkg/Scripts/BGMXPCHelper.xpc/Contents/MacOS/BGMXPCHelper" -verify_arch x86_64 arm64
lipo "$expanded/Installer.pkg/Scripts/ListInputDevices" -verify_arch x86_64 arm64
codesign --verify --deep --strict "$app"
grep -q 'os-version min="12.0"' "$expanded/Distribution"
echo "PASS installer payload: executable bridge, extension, guide, universal binaries, app signature, minimum OS"
