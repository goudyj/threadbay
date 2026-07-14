#!/bin/bash
# Rebuilds and launches the isolated development app bundle.
set -euo pipefail

cd "$(dirname "$0")/.."

DEV_EXECUTABLE="${PWD}/ThreadBay Dev.app/Contents/MacOS/ThreadBay"

if /usr/bin/pgrep -f -x "${DEV_EXECUTABLE}" >/dev/null; then
    /usr/bin/osascript -e 'tell application id "com.jlex.threadbay.app.dev" to quit'
    if /usr/bin/pgrep -f -x "${DEV_EXECUTABLE}" >/dev/null; then
        echo "ThreadBay Dev is still running; close it before rebuilding." >&2
        exit 1
    fi
fi

./scripts/build-app.sh debug dev
exec /usr/bin/open "ThreadBay Dev.app"
