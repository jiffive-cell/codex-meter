#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}/.."
cd "$ROOT"

APP_SOURCE="$ROOT/.build/Codex Meter.app"
APP_DEST="${1:-/Applications/Codex Meter.app}"

if [[ ! -d "$APP_SOURCE" ]]; then
    "$ROOT/scripts/build-app.sh" >/dev/null
fi

# Reload an already-running copy so an in-place install actually activates the
# new Popover/UI code.  The targeted quit is limited to this app's process.
if pgrep -x CodexMeter >/dev/null 2>&1; then
    osascript -e 'tell application id "com.local.codex-meter" to quit' >/dev/null 2>&1 || true
    sleep 1
fi

mkdir -p "$(dirname "$APP_DEST")"
ditto --rsrc --extattr "$APP_SOURCE" "$APP_DEST"

# Register both the application and its WidgetKit extension so the widget
# gallery can discover a freshly copied local build.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$APP_DEST" || true
fi

WIDGET_APPEX="$APP_DEST/Contents/PlugIns/CodexMeterWidget.appex"
if [[ -d "$WIDGET_APPEX" ]]; then
    /usr/bin/pluginkit -a "$WIDGET_APPEX" || true
    /usr/bin/pluginkit -e use -i com.local.codex-meter.widget || true
fi

# Make the read-only JSON command convenient without requiring administrator
# privileges.  Do not replace an existing regular file in ~/bin.
CLI_SOURCE="$APP_DEST/Contents/Helpers/codex-meter"
CLI_DIR="${CODEX_METER_BIN_DIR:-${HOME}/bin}"
CLI_LINK="$CLI_DIR/codex-meter"
if [[ -x "$CLI_SOURCE" ]]; then
    mkdir -p "$CLI_DIR"
    if [[ ! -e "$CLI_LINK" || -L "$CLI_LINK" ]]; then
        ln -sfn "$CLI_SOURCE" "$CLI_LINK"
        echo "命令行工具：$CLI_LINK"
    else
        echo "跳过已有文件：$CLI_LINK"
    fi
fi

open "$APP_DEST"

echo "Codex Meter 已安装到：$APP_DEST"
echo "添加组件：按住 Control 点按桌面 → 编辑小组件 → 搜索 Codex Meter。"
echo "状态查询：codex-meter status --json（若 ~/bin 不在 PATH，请使用 $CLI_SOURCE status --json）。"
