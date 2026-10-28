#!/bin/sh
# Builds .build/Raccoon.app. The icon ships as AppIcon.icns named by Info.plist, so the Dock
# reads it from disk and Raccoon never holds it in memory (design/entry-points/theme.md).
set -eu
cd "$(dirname "$0")/.."

swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP=.build/Raccoon.app
ICONSET=$(mktemp -d)/AppIcon.iconset
trap 'rm -rf "$(dirname "$ICONSET")"' EXIT

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"
cp "$BIN/Raccoon" "$APP/Contents/MacOS/"
# Bundle.module looks in Contents/Resources first.
cp -R "$BIN/Raccoon_Raccoon.bundle" "$APP/Contents/Resources/"

for size in 16 32 128 256 512; do
    sips -z $size $size design/ui/assets/icon/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) design/ui/assets/icon/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# CFBundleIdentifier is the UserDefaults domain swift run uses, so both share one.
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Raccoon</string>
    <key>CFBundleIdentifier</key><string>Raccoon</string>
    <key>CFBundleName</key><string>Raccoon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"

ICON=$(plutil -extract CFBundleIconFile raw "$APP/Contents/Info.plist")
test -s "$APP/Contents/Resources/$ICON.icns" || { echo "Info.plist names $ICON.icns, which is missing" >&2; exit 1; }
codesign --verify --strict "$APP"
echo "wrote $APP"
