#!/bin/bash
# Builds build/MySideNotes.app. Pass --install to copy it into /Applications.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="MySideNotes"
APP="build/${APP_NAME}.app"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/${APP_NAME}" "$APP/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/${APP_NAME}.app"
    open "/Applications/${APP_NAME}.app"
fi
