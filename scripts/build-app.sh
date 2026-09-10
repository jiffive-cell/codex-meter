#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}/.."
cd "$ROOT"

swift build -c release
swift build -c release --product CodexMeterWidget -Xswiftc -application-extension
swift build -c release --product codex-meter
APP="$ROOT/.build/Codex Meter.app"
EXT="$APP/Contents/PlugIns/CodexMeterWidget.appex"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources" "$EXT/Contents/MacOS" "$EXT/Contents/Resources"
cp "$ROOT/.build/release/CodexMeter" "$APP/Contents/MacOS/CodexMeter"
cp "$ROOT/.build/release/codex-meter" "$APP/Contents/Helpers/codex-meter"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/.build/release/CodexMeterWidget" "$EXT/Contents/MacOS/CodexMeterWidget"
cp "$ROOT/Resources/WidgetInfo.plist" "$EXT/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --sign - "$APP/Contents/Helpers/codex-meter" >/dev/null
codesign --force --sign - --entitlements "$ROOT/Resources/CodexMeterWidget.entitlements" "$EXT" >/dev/null
codesign --force --sign - --entitlements "$ROOT/Resources/CodexMeter.entitlements" "$APP" >/dev/null
codesign --verify --deep --strict "$APP"
echo "$APP"
