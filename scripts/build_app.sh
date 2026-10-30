#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "Building OrientApp..."
swift build -c debug --product OrientApp

BIN_PATH="$(swift build -c debug --show-bin-path)/OrientApp"
TMP_BUILD_DIR="/tmp/OrientAppBuild"
APP_DIR="$TMP_BUILD_DIR/Orient.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$TMP_BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/OrientApp"
chmod +x "$MACOS_DIR/OrientApp"

cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>OrientApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.orient.cursorlab</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Orient</string>
    <key>CFBundleDisplayName</key>
    <string>Orient</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>ApplePersistenceIgnoreState</key>
    <true/>
    <key>NSQuitAlwaysKeepsWindows</key>
    <false/>
    <key>NSMotionUsageDescription</key>
    <string>Orient uses your AirPods motion sensors (gyroscope and accelerometer) for ultra-low-latency cursor and gaming control.</string>
</dict>
</plist>
EOF

echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

find "$APP_DIR" -exec xattr -c {} + 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR"

mkdir -p "$ROOT_DIR/build"
rm -rf "$ROOT_DIR/build/Orient.app"
cp -R "$APP_DIR" "$ROOT_DIR/build/Orient.app"
echo "Packaged and signed: $APP_DIR"
