#!/bin/bash
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

APP_NAME="MediaTracker Dev"
BUNDLE_ID="com.vara.mediatracker.dev"
EXECUTABLE_NAME="MediaTracker"
INSTALL_DIR="/Applications"
BUILD_CONFIGURATION="debug"

if [[ "${1:-}" == "--release" ]]; then
    BUILD_CONFIGURATION="release"
elif [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: ./Dev/install-dev.sh [--release]"
    echo "Builds and installs a separate MediaTracker Dev.app."
    exit 0
fi

MARKETING_VERSION="$(awk -F': ' '/MARKETING_VERSION/ { gsub(/"/, "", $2); print $2; exit }' project.yml)"
MARKETING_VERSION="${MARKETING_VERSION:-0.0.0}"

echo "Building ${APP_NAME} (${BUILD_CONFIGURATION})..."
swift build -c "$BUILD_CONFIGURATION" --arch arm64

BINARY_PATH="$(swift build -c "$BUILD_CONFIGURATION" --arch arm64 --show-bin-path)/${EXECUTABLE_NAME}"
if [[ ! -f "$BINARY_PATH" ]]; then
    echo "Binary not found: $BINARY_PATH" >&2
    exit 1
fi

APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIRECTORY="${APP_BUNDLE}/Contents"
MACOS_DIRECTORY="${CONTENTS_DIRECTORY}/MacOS"
RESOURCES_DIRECTORY="${CONTENTS_DIRECTORY}/Resources"
INSTALLED_APP="${INSTALL_DIR}/${APP_BUNDLE}"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIRECTORY" "$RESOURCES_DIRECTORY"
cp "$BINARY_PATH" "$MACOS_DIRECTORY/${EXECUTABLE_NAME}"

if [[ -f "AppIcon.icns" ]]; then
    cp "AppIcon.icns" "$RESOURCES_DIRECTORY/AppIcon.icns"
fi

cat > "${CONTENTS_DIRECTORY}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP_BUNDLE"
rm -rf "$INSTALLED_APP"
mv "$APP_BUNDLE" "$INSTALL_DIR/"

echo "Installed ${APP_NAME} at: ${INSTALLED_APP}"
