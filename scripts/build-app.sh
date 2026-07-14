#!/bin/bash
# Builds a release binary and wraps it into a double-clickable ThreadBay.app
# with LSUIElement (menu-bar app, no Dock icon). Ad-hoc signs it so it launches
# locally without Gatekeeper prompts.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="ThreadBay"
APP_DIR="${APP_NAME}.app"
BUNDLE_ID="com.jlex.threadbay.app"
VERSION="0.1.0"

echo "→ swift build -c release"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="${BIN_DIR}/${APP_NAME}"

echo "→ assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# SwiftPM keeps localized resources in a sibling bundle. Bundle.module looks
# for it in Contents/Resources when the executable is wrapped as an app.
for resource_bundle in "${BIN_DIR}"/*.bundle; do
    [ -d "${resource_bundle}" ] || continue
    cp -R "${resource_bundle}" "${APP_DIR}/Contents/Resources/"
done

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "→ ad-hoc code signing"
codesign --force --sign - "${APP_DIR}" >/dev/null 2>&1 || \
    echo "  (codesign skipped: $?)"

echo "✓ Built ${APP_DIR}"
echo "  Run it with:  open ${APP_DIR}"
