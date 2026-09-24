#!/bin/zsh
set -euo pipefail
BUILD_ROOT="${0:A:h}"
APP_DEST="${1:-$BUILD_ROOT/PowerScope.app}"
mkdir -p "$APP_DEST/Contents/MacOS" "$APP_DEST/Contents/Resources" "$BUILD_ROOT/.build"
xcrun swiftc -O -swift-version 5 -whole-module-optimization -target arm64-apple-macosx14.0 \
  -module-cache-path "$BUILD_ROOT/.build/module-cache" \
  -framework AppKit -framework SwiftUI -framework Charts -framework IOKit \
  "$BUILD_ROOT"/Sources/*.swift -o "$APP_DEST/Contents/MacOS/PowerScope"
cat > "$APP_DEST/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>PowerScope</string>
<key>CFBundleDisplayName</key><string>PowerScope</string>
<key>CFBundleIdentifier</key><string>local.powerscope.mac</string>
<key>CFBundleExecutable</key><string>PowerScope</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHumanReadableCopyright</key><string>Local, private power monitoring.</string>
</dict></plist>
PLIST
if [[ -f "$BUILD_ROOT/Resources/AppIcon.icns" ]]; then
  cp "$BUILD_ROOT/Resources/AppIcon.icns" "$APP_DEST/Contents/Resources/AppIcon.icns"
elif [[ -f "$BUILD_ROOT/.build/AppIcon.icns" ]]; then
  cp "$BUILD_ROOT/.build/AppIcon.icns" "$APP_DEST/Contents/Resources/AppIcon.icns"
fi
/usr/bin/codesign --force --deep --sign - "$APP_DEST"
print "Built: $APP_DEST"
