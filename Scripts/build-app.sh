#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
CONFIGURATION="${1:-release}"
swift build -c "$CONFIGURATION" --disable-sandbox --product Glamshot
APP="$PWD/build/Glamshot.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build
cp ".build/$CONFIGURATION/Glamshot" "$APP/Contents/MacOS/Glamshot"
# SwiftPM resource bundles (gradient recipes, Looks) sit next to the binary.
for bundle in .build/$CONFIGURATION/*.bundle(N); do cp -R "$bundle" "$APP/Contents/Resources/"; done

# SwiftPM stamps the binary's SDK version with the deployment target (26.0), so AppKit treats the
# app as built against the 26 SDK and withholds behavior that newer SDKs opt into. Record the real
# SDK instead; the minimum OS stays 26.0.
vtool -set-build-version macos 26.0 "$(xcrun --sdk macosx --show-sdk-version)" -replace \
    -output "$APP/Contents/MacOS/Glamshot" "$APP/Contents/MacOS/Glamshot"

# Compile the Icon Composer icon and the asset catalog (the AccentColor colorset) into one
# Assets.car, plus Glamshot.icns. actool's icon exporter needs absolute paths.
ICON_ARGS=()
if [[ -d "$PWD/Icon/Glamshot.icon" ]]; then
    ICON_ARGS=("$PWD/Icon/Glamshot.icon" --app-icon "Glamshot")
fi
xcrun actool "${ICON_ARGS[@]}" "$PWD/Resources/Assets.xcassets" \
    --compile "$APP/Contents/Resources" \
    --accent-color "AccentColor" \
    --output-partial-info-plist "$PWD/build/icon-partial.plist" \
    --platform macosx --minimum-deployment-target 26.0 \
    --errors --warnings >/dev/null

cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "$APP"
