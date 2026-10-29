#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
CONFIGURATION=release

# Shortcuts only finds App Intents through Metadata.appintents, which Xcode makes from the
# compile-time values the compiler records for these protocols. SwiftPM doesn't, so ask the
# compiler for them here (the same list Xcode uses) and run Xcode's extractor below, as
# Granular does. Release builds are whole-module, so each module writes one file.
INTENTS_DIR="$PWD/.build/appintents"
mkdir -p "$INTENTS_DIR"
print -r -- '["AppIntent","EntityQuery","AppEntity","TransientEntity","AppEnum","AppShortcutProviding","AppShortcutsProvider","AnyResolverProviding","AppIntentsPackage","DynamicOptionsProvider","_IntentValueRepresentable","_AssistantIntentsProvider","_GenerativeFunctionExtractable"]' \
    > "$INTENTS_DIR/protocols.json"
swift build -c "$CONFIGURATION" --disable-sandbox --product Glamshot \
    -Xswiftc -emit-const-values-path -Xswiftc "$INTENTS_DIR/Glamshot.swiftconstvalues" \
    -Xswiftc -Xfrontend -Xswiftc -const-gather-protocols-file \
    -Xswiftc -Xfrontend -Xswiftc "$INTENTS_DIR/protocols.json"

APP="$PWD/build/Glamshot.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build
cp ".build/$CONFIGURATION/Glamshot" "$APP/Contents/MacOS/Glamshot"

print -rl -- "$PWD"/Sources/Glamshot/**/*.swift > "$INTENTS_DIR/sources.txt"
print -r -- "$INTENTS_DIR/Glamshot.swiftconstvalues" > "$INTENTS_DIR/constvalues.txt"
xcrun appintentsmetadataprocessor \
    --toolchain-dir "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" \
    --module-name Glamshot \
    --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
    --xcode-version "$(xcodebuild -version | awk '/Build version/ { print $3 }')" \
    --platform-family macOS \
    --deployment-target 26.0 \
    --bundle-identifier "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PWD/Resources/Info.plist")" \
    --target-triple "$(uname -m)-apple-macos26.0" \
    --binary-file "$APP/Contents/MacOS/Glamshot" \
    --source-file-list "$INTENTS_DIR/sources.txt" \
    --swift-const-vals-list "$INTENTS_DIR/constvalues.txt" \
    --output "$APP/Contents/Resources" \
    --compile-time-extraction \
    --deployment-aware-processing \
    --no-app-shortcuts-localization >/dev/null
if [[ ! -f "$APP/Contents/Resources/Metadata.appintents/extract.actionsdata" ]]; then
    echo "App Intents metadata wasn’t generated; Shortcuts won’t see Glamshot’s action." >&2
    exit 70
fi
# SwiftPM resource bundles sit next to the binary; test bundles stay behind.
for bundle in .build/$CONFIGURATION/*.bundle(N); do
    [[ "$bundle" == *Tests* ]] || cp -R "$bundle" "$APP/Contents/Resources/"
done

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
