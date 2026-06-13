#!/bin/bash

# Configuration
APP_NAME="MediaTracker"
BUNDLE_ID="com.vara.mediatracker"
EXECUTABLE_NAME="MediaTracker"
INSTALL_DIR="/Applications"

BUILD_MODE="release"
BUILD_CONFIG="release"
DO_CLEAN=false
FORCE=false

# Parse arguments
for arg in "$@"; do
    if [ "$arg" == "--debug" ]; then
        BUILD_MODE="debug"
        BUILD_CONFIG="debug"
    elif [ "$arg" == "--clean" ]; then
        DO_CLEAN=true
        FORCE=true
    elif [ "$arg" == "--force" ] || [ "$arg" == "-f" ]; then
        FORCE=true
    elif [ "$arg" == "--help" ] || [ "$arg" == "-h" ]; then
        echo "Usage: ./install.sh [options]"
        echo ""
        echo "Options:"
        echo "  --clean      Perform a full clean build (removes .build directory)"
        echo "  --debug      Build in debug mode (skips icon/packaging/codesign)"
        echo "  --force,-f   Build and install even if no source changes detected"
        echo "  --help       Show this help message"
        exit 0
    fi
done

# Skip source hash check if --force was passed
if [ "$FORCE" = false ]; then
    HASH_FILE=".build/.source_hash_$BUILD_CONFIG"
    mkdir -p .build
    SOURCE_HASH=$(git ls-files '*.swift' 'Package.swift' 'Package.resolved' 2>/dev/null | sort | xargs shasum -a 256 2>/dev/null | shasum -a 256 | cut -d' ' -f1)

    if [ -f "$HASH_FILE" ] && [ "$(cat "$HASH_FILE")" == "$SOURCE_HASH" ]; then
        echo "✨ No source changes detected. Skipping build."

        BINARY_PATH=$(swift build -c "$BUILD_CONFIG" --arch arm64 --show-bin-path 2>/dev/null)/$EXECUTABLE_NAME
        if [ -f "$BINARY_PATH" ]; then
            echo "📦 Binary is up-to-date. Skipping packaging."
            exit 0
        fi
        echo "⚠️  Binary missing. Forcing rebuild."
    fi
fi

if [ "$DO_CLEAN" = true ]; then
    echo "🧹 Performing full clean build..."
    rm -rf .build
fi

echo "🚀 Building $APP_NAME in $BUILD_MODE mode..."

swift build -c "$BUILD_CONFIG" --arch arm64 -j $(sysctl -n hw.ncpu) -Xswiftc -index-ignore-system-modules

if [ $? -ne 0 ]; then
    echo "❌ Build failed."
    exit 1
fi

# Save source hash for next run
if [ "$FORCE" = false ]; then
    echo "$SOURCE_HASH" > "$HASH_FILE"
fi

# Resolve binary path after a successful build
BINARY_PATH=$(swift build -c "$BUILD_CONFIG" --arch arm64 --show-bin-path 2>/dev/null)/$EXECUTABLE_NAME

if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Binary not found at $BINARY_PATH"
    exit 1
fi

# For debug builds, skip icon generation, packaging, and installation
if [ "$BUILD_CONFIG" == "debug" ]; then
    echo "✅ Debug build complete. Binary at: $BINARY_PATH"
    exit 0
fi

# Optimized Icon Generation (Cached)
if [ ! -f "AppIcon.icns" ] || [ "generate_icon.swift" -nt "AppIcon.icns" ]; then
    echo "🎨 Generating App Icon..."
    swift generate_icon.swift
    iconutil -c icns AppIcon.iconset -o AppIcon.icns
    rm -rf AppIcon.iconset
fi

echo "📦 Packaging into $APP_NAME.app..."

APP_BUNDLE="$APP_NAME.app"
INSTALLED_APP="$INSTALL_DIR/$APP_BUNDLE"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/"
cp AppIcon.icns "$RESOURCES_DIR/"

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
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "🔐 Ad-hoc signing $APP_NAME..."
codesign --force --sign - "$APP_BUNDLE"

echo "🚚 Installing to $INSTALL_DIR..."
rm -rf "$INSTALLED_APP"
mv "$APP_BUNDLE" "$INSTALL_DIR/"

echo "✅ Done! $APP_NAME is now in your Applications folder."
