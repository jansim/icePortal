#!/usr/bin/env bash
# Builds IcePortalBar.app (a menubar-only app bundle) into ./build.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/IcePortalBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/IcePortalBar" "$APP/Contents/MacOS/IcePortalBar"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>IcePortalBar</string>
    <key>CFBundleDisplayName</key>
    <string>ICE Portal Bar</string>
    <key>CFBundleIdentifier</key>
    <string>io.simson.IcePortalBar</string>
    <key>CFBundleExecutable</key>
    <string>IcePortalBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so Gatekeeper lets the locally built app run.
codesign --force --sign - "$APP"

echo "Built $APP"
