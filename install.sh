#!/bin/bash

# Configuration
APP_NAME="MediaTracker"
BUNDLE_ID="com.vara.mediatracker"
EXECUTABLE_NAME="MediaTracker"
INSTALL_DIR="/Applications"

BUILD_MODE="release"
BUILD_CONFIG="release"
DO_CLEAN=false

# Parse arguments
for arg in "$@"; do
    if [ "$arg" == "--debug" ]; then
        BUILD_MODE="debug"
        BUILD_CONFIG="debug"
    elif [ "$arg" == "--clean" ]; then
        DO_CLEAN=true
    elif [ "$arg" == "--help" ] || [ "$arg" == "-h" ]; then
        echo "Usage: ./install.sh [options]"
        echo ""
        echo "Options:"
        echo "  --clean    Perform a full clean build (removes .build directory)"
        echo "  --debug    Build in debug mode"
        echo "  --help     Show this help message"
        exit 0
    fi
done

if [ "$DO_CLEAN" = true ]; then
    echo "🧹 Performing full clean build..."
    # Full clean: Swift package clean + remove build directory
    swift package clean
    rm -rf .build
fi

echo "🚀 Building $APP_NAME in $BUILD_MODE mode..."

# 1. Capture binary state before build
# Use --show-bin-path to be robust across Swift versions and platforms
BINARY_PATH=$(swift build -c "$BUILD_CONFIG" --arch arm64 --show-bin-path 2>/dev/null)/$EXECUTABLE_NAME
PRE_BUILD_STAT=$(stat -f "%m%z" "$BINARY_PATH" 2>/dev/null || echo "none")

# 2. Build the executable
# -c release already includes -O optimization
swift build -c "$BUILD_CONFIG" --arch arm64 -j $(sysctl -n hw.ncpu) -Xswiftc -index-ignore-system-modules

if [ $? -ne 0 ]; then
    echo "❌ Build failed."
    exit 1
fi

# 3. Capture binary state after build
POST_BUILD_STAT=$(stat -f "%m%z" "$BINARY_PATH" 2>/dev/null || echo "none")

# 4. Optimized Icon Generation (Cached)
# Only regenerate if missing or if the source script is newer than the icns
if [ ! -f "AppIcon.icns" ] || [ "generate_icon.swift" -nt "AppIcon.icns" ]; then
    echo "🎨 Generating App Icon..."
    swift generate_icon.swift
    iconutil -c icns AppIcon.iconset -o AppIcon.icns
    rm -rf AppIcon.iconset
fi

# 5. Skip packaging if no changes detected
APP_BUNDLE="$APP_NAME.app"
INSTALLED_APP="$INSTALL_DIR/$APP_BUNDLE"

if [ "$PRE_BUILD_STAT" == "$POST_BUILD_STAT" ] && [ -d "$INSTALLED_APP" ]; then
    echo "✨ No changes detected in binary. Skipping packaging."
    exit 0
fi

echo "📦 Packaging into $APP_NAME.app..."

# 6. Create the .app bundle structure
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 7. Copy the executable and icon
cp "$BINARY_PATH" "$MACOS_DIR/"
cp AppIcon.icns "$RESOURCES_DIR/"

# 8. Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.2.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# 9. Ad-hoc sign the app
echo "🔐 Ad-hoc signing $APP_NAME..."
codesign --force --sign - "$APP_BUNDLE"

# 10. Move to Applications
echo "🚚 Installing to $INSTALL_DIR..."
rm -rf "$INSTALLED_APP"
mv "$APP_BUNDLE" "$INSTALL_DIR/"

echo "✅ Done! $APP_NAME is now in your Applications folder."
