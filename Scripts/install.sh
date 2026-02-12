#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Activity Tracker"
APP_BUNDLE="/Applications/${APP_NAME}.app"

# Check prerequisites
if ! command -v swift &> /dev/null; then
    echo "Error: Swift not found. Install Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi

echo "Building Activity Tracker (release)..."
cd "$PROJECT_DIR"
swift build -c release

BINARY="$PROJECT_DIR/.build/release/ActivityTracker"

if [ ! -f "$BINARY" ]; then
    echo "Error: Build failed."
    exit 1
fi

# --- Create .app bundle ---
echo "Creating ${APP_BUNDLE}..."
rm -rf "$APP_BUNDLE"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "$BINARY" "${APP_BUNDLE}/Contents/MacOS/ActivityTracker"
chmod +x "${APP_BUNDLE}/Contents/MacOS/ActivityTracker"

# Generate icon
echo "Generating app icon..."
ICON_SCRIPT="$SCRIPT_DIR/generate_icon.swift"
if [ -f "$ICON_SCRIPT" ]; then
    swiftc -framework AppKit -framework CoreGraphics -o /tmp/generate_icon "$ICON_SCRIPT"
    /tmp/generate_icon
    iconutil -c icns /tmp/ActivityTracker.iconset -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
    rm -rf /tmp/ActivityTracker.iconset /tmp/generate_icon
fi

cat > "${APP_BUNDLE}/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ActivityTracker</string>
    <key>CFBundleIdentifier</key>
    <string>com.alpgiraykelem.activity-tracker</string>
    <key>CFBundleName</key>
    <string>Activity Tracker</string>
    <key>CFBundleDisplayName</key>
    <string>Activity Tracker</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Activity Tracker needs access to read window details from Safari, Terminal, Spotify and other apps.</string>
</dict>
</plist>
PLIST

echo ""
echo "=== Installation complete! ==="
echo ""
echo "  App: ${APP_BUNDLE}"
echo ""
echo "Open '${APP_NAME}' from Spotlight (Cmd+Space) or Applications folder."
echo "For auto-start: System Settings > General > Login Items > add '${APP_NAME}'"
