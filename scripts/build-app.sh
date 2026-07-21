#!/bin/bash
# Builds the executables and wraps them into a double-clickable macOS app
# with LSUIElement (menu-bar app, no Dock icon). Ad-hoc signs it so it launches
# locally without Gatekeeper prompts.
set -euo pipefail

cd "$(dirname "$0")/.."

EXECUTABLE_NAME="ThreadBay"
HELPER_NAME="ThreadBayNotify"
ICON_SOURCE="Assets/AppIcon.icns"
VERSION="0.1.0"
CONFIGURATION="${1:-release}"
PROFILE="${2:-production}"

case "${CONFIGURATION}" in
    debug|release) ;;
    *)
        echo "Usage: $0 [debug|release] [production|dev]" >&2
        exit 2
        ;;
esac

case "${PROFILE}" in
    production)
        APP_NAME="ThreadBay"
        BUNDLE_ID="com.jlex.threadbay.app"
        APP_ENVIRONMENT="production"
        ;;
    dev)
        APP_NAME="ThreadBay Dev"
        BUNDLE_ID="com.jlex.threadbay.app.dev"
        APP_ENVIRONMENT="development"
        ;;
    *)
        echo "Usage: $0 [debug|release] [production|dev]" >&2
        exit 2
        ;;
esac

APP_DIR="${APP_NAME}.app"

echo "→ swift build -c ${CONFIGURATION}"
swift build -c "${CONFIGURATION}"

BIN_DIR="$(swift build -c "${CONFIGURATION}" --show-bin-path)"
BIN_PATH="${BIN_DIR}/${EXECUTABLE_NAME}"
HELPER_PATH="${BIN_DIR}/${HELPER_NAME}"

echo "→ assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources/bin"

cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${EXECUTABLE_NAME}"
cp "${HELPER_PATH}" "${APP_DIR}/Contents/Resources/bin/threadbay-notify"

# SwiftPM keeps localized resources in a sibling bundle. Bundle.module looks
# for it in Contents/Resources when the executable is wrapped as an app.
for resource_bundle in "${BIN_DIR}"/*.bundle; do
    [ -d "${resource_bundle}" ] || continue
    cp -R "${resource_bundle}" "${APP_DIR}/Contents/Resources/"
done

cp "${ICON_SOURCE}" "${APP_DIR}/Contents/Resources/ThreadBay.icns"

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
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>ThreadBay.icns</string>
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
    <key>ThreadBayEnvironment</key>
    <string>${APP_ENVIRONMENT}</string>
</dict>
</plist>
PLIST

echo "→ ad-hoc code signing"
codesign --force --sign - "${APP_DIR}/Contents/Resources/bin/threadbay-notify" >/dev/null 2>&1 || \
    echo "  (helper codesign skipped: $?)"
codesign --force --sign - "${APP_DIR}" >/dev/null 2>&1 || \
    echo "  (codesign skipped: $?)"

echo "✓ Built ${APP_DIR}"
echo "  Run it with:  open ${APP_DIR}"
