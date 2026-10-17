#!/bin/bash
set -euo pipefail
app="$1"
resources="$app/Contents/Resources"
clang -Wall -Wextra -Werror -O2 -arch x86_64 -arch arm64 -mmacosx-version-min=12.0 AudioHub/NativeHost.c -o "$resources/AudioHub.NativeHost"
cp -R AudioHub/edge "$resources/edge"
cp AudioHub/使用说明.md "$resources/AudioHub-使用说明.md"
codesign --force --sign - "$resources/AudioHub.NativeHost"
codesign --force --deep --sign - "$app"
lipo -verify_arch x86_64 arm64 "$resources/AudioHub.NativeHost"
lipo -verify_arch x86_64 arm64 "$app/Contents/MacOS/Background Music"
