#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
swift build --disable-sandbox --build-system native -c release
BIN="$(swift build --disable-sandbox --build-system native -c release --show-bin-path)/FileTray"
APP="$PWD/dist/Tray.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FileTray"
rm -f "$APP/Contents/Resources/FileTray.icns"
xcrun actool Assets/AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 13.0 --app-icon AppIcon --output-partial-info-plist "$PWD/.build/icon-info.plist"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleIconName</key><string>AppIcon</string>
<key>CFBundleExecutable</key><string>FileTray</string>
<key>CFBundleIdentifier</key><string>local.filetray.mac</string>
<key>CFBundleName</key><string>Tray</string>
<key>CFBundleDisplayName</key><string>Tray</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.28</string>
<key>CFBundleVersion</key><string>33</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf 'Built: %s\n' "$APP"
