#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="MemoExport"
APP_BUNDLE="$PROJECT_DIR/build/${APP_NAME}.app"
DMG_DIR="$PROJECT_DIR/build/dmg"
DMG_RW="$PROJECT_DIR/build/${APP_NAME}-rw.dmg"
DMG_OUTPUT="$PROJECT_DIR/build/${APP_NAME}.dmg"
BG_IMAGE="$PROJECT_DIR/Resources/dmg-background.png"
ICON_FILE="$PROJECT_DIR/Resources/AppIcon.icns"
VOL_NAME="$APP_NAME"

echo "=== MemoExport Build & DMG Script ==="

# Step 1: Build release binary
echo "[1/5] Building release binary..."
cd "$PROJECT_DIR"
swift build -c release 2>&1
BINARY="$(swift build -c release --show-bin-path)/${APP_NAME}"

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi
echo "  Binary: $BINARY"

# Step 2: Create .app bundle
echo "[2/5] Creating .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/"

if [ -f "$ICON_FILE" ]; then
    cp "$ICON_FILE" "$APP_BUNDLE/Contents/Resources/"
    echo "  Icon copied"
fi

echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Ad-hoc code sign (prevents "damaged" error on downloaded apps)
echo "  Signing app..."
codesign --force --deep -s - "$APP_BUNDLE"
echo "  App bundle: $APP_BUNDLE"

# Step 3: Prepare DMG staging
echo "[3/5] Preparing DMG staging..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
rm -f "$DMG_RW" "$DMG_OUTPUT"

cp -R "$APP_BUNDLE" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

# Copy background image into hidden .background directory
if [ -f "$BG_IMAGE" ]; then
    mkdir -p "$DMG_DIR/.background"
    cp "$BG_IMAGE" "$DMG_DIR/.background/background.png"
    if [ -f "${BG_IMAGE%.*}@2x.png" ]; then
        cp "${BG_IMAGE%.*}@2x.png" "$DMG_DIR/.background/background@2x.png"
    fi
fi

# Step 4: Create DMG with layout
echo "[4/5] Creating DMG..."

# Calculate DMG size (staging dir size + 10MB padding)
DMG_SIZE_KB=$(du -sk "$DMG_DIR" | cut -f1)
DMG_SIZE_KB=$((DMG_SIZE_KB + 10240))

# Create read-write DMG
hdiutil create -size "${DMG_SIZE_KB}k" \
    -volname "$VOL_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDRW \
    -fs HFS+ \
    "$DMG_RW" 2>&1

# Mount the DMG
MOUNT_OUTPUT=$(hdiutil attach "$DMG_RW" -readwrite -noverify -noautoopen 2>&1)
MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | grep -o '/Volumes/[^	]*' | head -1 | sed 's/[[:space:]]*$//')

if [ -z "$MOUNT_POINT" ]; then
    echo "ERROR: Failed to mount DMG"
    echo "$MOUNT_OUTPUT"
    exit 1
fi
# Extract actual volume name from mount point (may differ from VOL_NAME if duplicates exist)
ACTUAL_VOL_NAME=$(basename "$MOUNT_POINT")
echo "  Mounted at: $MOUNT_POINT (volume: $ACTUAL_VOL_NAME)"

# Set volume icon
if [ -f "$ICON_FILE" ]; then
    cp "$ICON_FILE" "$MOUNT_POINT/.VolumeIcon.icns"
    SetFile -c icnC "$MOUNT_POINT/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$MOUNT_POINT" 2>/dev/null || true
fi

# Use AppleScript to configure Finder view with error handling
echo "  Configuring Finder view..."
osascript <<APPLESCRIPT || true
tell application "Finder"
    try
        tell disk "$ACTUAL_VOL_NAME"
            open
            delay 1

            -- Set icon view
            set current view of container window to icon view
            set theViewOptions to the icon view options of container window

            -- Icon size and arrangement
            set icon size of theViewOptions to 100
            set text size of theViewOptions to 14
            try
                set arrangement of theViewOptions to not arranged
            end try

            -- Background image
            try
                set background picture of theViewOptions to file ".background:background.png"
            end try

            -- Window size and position
            try
                set the bounds of container window to {200, 120, 800, 520}
            end try

            -- Icon positions
            try
                set position of item "${APP_NAME}.app" of container window to {155, 200}
            end try
            try
                set position of item "Applications" of container window to {445, 200}
            end try

            -- Hide toolbar and sidebar
            try
                set toolbar visible of container window to false
            end try

            -- Update and close
            update without registering applications
            delay 0.5
            close
        end tell
    end try
end tell
APPLESCRIPT

# Wait for Finder to process, then detach
sleep 1
sync
hdiutil detach "$MOUNT_POINT" 2>&1 || {
    sleep 3
    hdiutil detach "$MOUNT_POINT" -force 2>&1 || true
}

# Convert to compressed read-only DMG
echo "  Compressing DMG..."
hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -o "$DMG_OUTPUT" 2>&1

if [ ! -f "$DMG_OUTPUT" ]; then
    echo "ERROR: DMG creation failed"
    exit 1
fi

# Step 5: Cleanup
echo "[5/5] Cleanup..."
rm -rf "$DMG_DIR"
rm -f "$DMG_RW"

echo ""
echo "=== Build Complete ==="
echo "  App:  $APP_BUNDLE"
echo "  DMG:  $DMG_OUTPUT"
echo "  Size: $(du -h "$DMG_OUTPUT" | cut -f1)"
echo ""
echo "To install: Open the DMG and drag MemoExport to Applications."
echo "First launch: macOS will ask permission to access Notes app."
