#!/bin/bash
# Builds build/MySideNotes.app. Pass --install to copy it into /Applications and launch it.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="MySideNotes"
APP="build/${APP_NAME}.app"

fail() {
    echo "❌ $1" >&2
    exit 1
}

macos_major=$(sw_vers -productVersion | cut -d. -f1)
if (( macos_major < 14 )); then
    fail "ต้องใช้ macOS 14 ขึ้นไป (เครื่องนี้เป็น $(sw_vers -productVersion))"
fi

if ! xcrun --find swift >/dev/null 2>&1; then
    fail "ไม่พบ Swift — ติดตั้ง Command Line Tools ก่อนด้วยคำสั่ง: xcode-select --install"
fi

echo "▶︎ Building ($(swift --version 2>/dev/null | head -1))"
swift build -c release || fail "Build ไม่ผ่าน — ดู error ด้านบน (ลองอัปเดต Command Line Tools ผ่าน Software Update)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/${APP_NAME}" "$APP/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "✅ Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x "$APP_NAME" 2>/dev/null && sleep 1 || true
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "$APP" /Applications/ || fail "คัดลอกไป /Applications ไม่ได้ (ลองรันด้วย sudo)"
    echo "✅ Installed to /Applications/${APP_NAME}.app"

    open "/Applications/${APP_NAME}.app" --args --show
    sleep 2
    if pgrep -x "$APP_NAME" >/dev/null; then
        echo ""
        echo "🎉 My SideNotes กำลังทำงานแล้ว — แผงโน้ตจะเลื่อนออกมาที่ขอบขวาของจอ"
        echo "   • เปิด/ปิดแผง: ⌃⌥N  หรือคลิกแถบเล็ก ๆ ที่ขอบขวาของจอ"
        echo "   • ไอคอนอยู่บนแถบเมนูด้านบน (ไม่มีไอคอนใน Dock)"
        echo "   • ถ้าปิดแผงไปแล้วหาไม่เจอ เปิดแอปจาก Launchpad/Spotlight อีกครั้ง แผงจะเด้งขึ้นมา"
    else
        fail "แอปเปิดไม่ขึ้น — ลองรัน /Applications/${APP_NAME}.app/Contents/MacOS/${APP_NAME} ใน Terminal เพื่อดู error"
    fi
fi
