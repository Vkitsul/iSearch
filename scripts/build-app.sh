#!/bin/bash
# Builds build/iSearch.app from the Swift package. With --install, replaces /Applications/iSearch.app and starts it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product ISearchApp

# The icon only needs to be drawn once.
if [ ! -f build/AppIcon.icns ]; then
    mkdir -p build/AppIcon.iconset
    swift scripts/make-icon.swift build/AppIcon.iconset/icon_512x512@2x.png
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" build/AppIcon.iconset/icon_512x512@2x.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        if [ "$size" != 512 ]; then
            sips -z "$double" "$double" build/AppIcon.iconset/icon_512x512@2x.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
        fi
    done
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
    rm -r build/AppIcon.iconset
fi

rm -rf build/iSearch.app
mkdir -p build/iSearch.app/Contents/MacOS build/iSearch.app/Contents/Resources
cp "$(swift build -c release --product ISearchApp --show-bin-path)/ISearchApp" build/iSearch.app/Contents/MacOS/iSearch
cp Resources/Info.plist build/iSearch.app/Contents/Info.plist
cp build/AppIcon.icns build/iSearch.app/Contents/Resources/AppIcon.icns
codesign --force --sign - build/iSearch.app

echo "Built $(pwd)/build/iSearch.app"

if [ "${1:-}" = "--install" ]; then
    pkill -x iSearch || true
    rm -rf /Applications/iSearch.app
    mv build/iSearch.app /Applications/iSearch.app
    open /Applications/iSearch.app
    echo "Installed and started /Applications/iSearch.app"
fi
