#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/Perch.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/Perch" "$APP/Contents/MacOS/Perch"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Perch</string>
    <key>CFBundleIdentifier</key><string>com.rhart.perch</string>
    <key>CFBundleName</key><string>Perch</string>
    <key>CFBundleDisplayName</key><string>Perch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
printf '\nBuilt %s\nLaunch: open "%s"\n' "$APP" "$APP"
