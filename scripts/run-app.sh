#!/bin/bash
# Launches the real app bundle so macOS services such as notifications work.
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/build-app.sh debug
exec /usr/bin/open "ThreadBay.app"
