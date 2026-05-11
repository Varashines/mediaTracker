#!/bin/bash

# Configuration
APP_NAME="MediaTracker"
BUNDLE_ID="com.vara.mediatracker"
EXECUTABLE_NAME="MediaTracker"
INSTALL_DIR="/Applications"
BUILD_DIR=".build/arm64-apple-macosx/release"

echo "🚀 Building $APP_NAME in Release mode (Incremental)..."

# 1. Build the executable using all available cores
CORES=$(sysctl -n hw.ncpu)
swift build -c release --arch arm64 -j $CORES

if [ $? -ne 0 ]; then
    echo "❌ Build failed."
    exit 1
fi

if [ ! -f "AppIcon.icns" ]; then
    echo "🎨 Generating App Icon..."
    swift generate_icon.swift
    iconutil -c icns AppIcon.iconset -o AppIcon.icns
    rm -rf AppIcon.iconset
fi

echo "📦 Packaging into $APP_NAME.app..."

# 2. Create the .app bundle structure
APP_BUNDLE="$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 3. Copy the executable and icon
cp "$BUILD_DIR/$EXECUTABLE_NAME" "$MACOS_DIR/"
cp AppIcon.icns "$RESOURCES_DIR/"
rm AppIcon.icns

# 4. Create a basic Info.plist
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

# 5. Move to Applications
echo "🚚 Installing to $INSTALL_DIR..."
rm -rf "$INSTALL_DIR/$APP_BUNDLE"
mv "$APP_BUNDLE" "$INSTALL_DIR/"

# 6. Ad-hoc sign the app (Required for Notifications on macOS)
echo "🔐 Ad-hoc signing $APP_NAME..."
codesign --force --deep --sign - "$INSTALL_DIR/$APP_BUNDLE"

echo "✅ Done! $APP_NAME is now in your Applications folder."
