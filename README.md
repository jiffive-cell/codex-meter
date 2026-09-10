# Codex Meter

原生 macOS 菜单栏与桌面 WidgetKit 额度监控器。它读取 Codex 服务端实际返回的额度、重置次数和最近用量，让你在菜单栏、桌面组件或命令行快速看到“还剩多少”。

> 当前版本：`0.4.0` · macOS 14+ · 只读监控

## 你会得到什么

| 入口 | 适合查看 | 交互 |
| --- | --- | --- |
| 菜单栏 Popover | 当前额度、计划、重置、消耗速度 | 点击菜单栏图标直接展开 |
| 原生桌面 Widget | 一眼看 5 小时、每周、重置次数或趋势 | Control 点按 → 编辑小组件 |
| `codex-meter status --json` | 脚本、自动化和 Skill | 读取本机只读快照 |
| Codex Meter Status Skill | 直接问“我还有多少额度？” | 自动调用上面的 JSON 命令 |

## 功能

- 以服务端返回为准，自动识别 Plus、Pro、Team、Business、Enterprise、Edu 及未来会员等级；不要求手动填写会员类型。
- 展示 5 小时、每日、每周以及服务端返回的其他额度窗口，并显示已用/剩余百分比、准确重置时间和倒计时。
- 展示可用重置次数、重置券标题与到期时间；监控工具保持只读，不提供“一键使用重置”。
- 额度低于 20% / 10% / 5% 时分级通知，每个额度窗口独立去重，可在设置中关闭通知。
- 根据最近采样计算消耗速度，并估算按当前速度耗尽的时间；不估算“还能发多少条消息”。
- 保存本地 30 天趋势，支持中文/英文界面和系统、全彩、深色三种 Widget 外观。
- 菜单栏点击直接展开精简 Popover；不自动弹出大型悬浮仪表盘，也不会在登录后打扰桌面。
- 刷新间隔可选 1 / 5 / 15 / 30 分钟，可选登录时启动。

## 安装（本地构建版）

需要 macOS 14+、Swift 6 / Xcode Command Line Tools，以及已登录的 Codex 桌面应用。

```bash
./scripts/build-app.sh
./scripts/install-app.sh
```

安装脚本会把应用复制到 `/Applications/Codex Meter.app`、注册 WidgetKit 扩展并启动菜单栏应用，同时在 `~/bin/codex-meter` 创建安全的符号链接（已有普通文件时不会覆盖）。如果 `~/bin` 不在 `PATH`，也可以直接运行：

```bash
"/Applications/Codex Meter.app/Contents/Helpers/codex-meter" status --json
```

首次运行如被 Gatekeeper 拦截，在 Finder 中右键应用并选择“打开”。当前包使用本地临时签名，正式分发仍需要 Developer ID 签名与公证。

## 菜单栏用法

1. 启动 **Codex Meter**，菜单栏会出现状态图标。
2. 点击图标，Popover 会显示会员计划、额度卡片、重置次数、消耗速度和最近更新时间。
3. 点击“刷新”立即从本机 `codex app-server` 请求只读额度；点击“设置”调整语言、外观、刷新间隔、通知和登录启动。
4. 点击“退出”可以停止菜单栏宿主；重新打开应用即可恢复监控。

应用只调用 `account/rateLimits/read`，不读取 `auth.json`，不读取对话内容，不执行 Codex 任务，也不兑换重置次数。

## 桌面 Widget 用法

桌面显示由真正的 WidgetKit 扩展负责，不是覆盖桌面的自绘窗口：

1. 在桌面按住 Control 点按，选择“编辑小组件”。
2. 搜索 **Codex Meter**，选择小号、中号或大号组件，拖到时钟、天气、日历等原生组件附近。
3. 组件库提供五个静态指标变体：总览、5 小时、每周、可用重置次数、最近用量趋势。
4. 在应用设置中切换系统、全彩或深色外观；组件的位置、尺寸和排列由 macOS 的“编辑小组件”管理。

WidgetKit 的刷新时间由系统调度，不承诺每分钟重绘。菜单栏宿主刷新成功后会请求组件更新；如果组件显示旧数据，先打开应用点击“刷新”，再等待系统刷新周期。

### AppIntent 配置说明

完整 Xcode 构建时，代码已准备好可配置的 **Codex Meter** AppIntent：在“编辑小组件”里选择总览、5 小时、每周、重置次数或趋势。当前仅有 Command Line Tools 的构建保留五个静态变体，避免缺少 Apple 元数据处理器时出现空白组件。拿到完整 Xcode 后，在 Widget target 的 **Active Compilation Conditions** 加入 `CODEX_METER_APPINTENTS`，由 Xcode 的 WidgetKit/AppIntent 构建阶段生成可配置变体。

## 命令行与 Skill

`status --json` 是只读查询，输出计划、所有额度窗口、重置券、消耗速度、预计耗尽时间和快照新鲜度：

```bash
codex-meter status --json
```

CLI 读取应用维护的本地快照；请先启动 Codex Meter，才能获得最新同步数据。快照超过 30 分钟会标记 `stale: true`，不会偷偷猜测额度。

配套 Skill 位于 [`skills/codex-meter-status`](skills/codex-meter-status)：

```bash
cp -R skills/codex-meter-status ~/.codex/skills/
```

安装后可直接询问“我还有多少额度？”或“我的重置次数和预计耗尽时间是什么？”。Skill 只读本地 JSON，不读取凭据、不访问会话、不启动任务、不兑换重置。

## 构建细节

```bash
swift test
./scripts/build-app.sh
./scripts/smoke-test.sh
```

构建脚本会编译主应用、WidgetKit 扩展和 CLI，把扩展嵌入 `.app/Contents/PlugIns/CodexMeterWidget.appex`，先签名扩展再签名宿主并执行严格校验。SwiftPM 没有原生 Widget Extension target，因此脚本使用 `_NSExtensionMain` 入口完成打包；正式发布仍建议使用 Xcode/Developer ID。

本地临时签名版本把最小化快照写入 `~/Library/Application Support/CodexMeter/widget-snapshot.json`，并同步一份到 WidgetKit 自己的沙盒容器；扩展只读快照。正式签名分发时，可将镜像改为受保护的 App Group 容器。

## 隐私与边界

- 数据只在本机快照和 WidgetKit 容器之间流转，不上传到第三方。
- 额度、计划和重置信息以 Codex 服务端实际返回为准；服务端未返回的字段不会被猜测。
- 消耗速度和耗尽时间是基于本地采样的趋势估计，不是官方承诺。
- 不显示消息条数估算，不执行任何写入账户、任务或兑换操作。

## 排查

| 现象 | 处理 |
| --- | --- |
| Popover 显示旧数据 | 确认 Codex 已登录，打开应用点击“刷新”；检查更新时间和 `stale` 字段。 |
| Widget 没出现在组件库 | 确认应用已安装到 `/Applications`，重新运行 `./scripts/install-app.sh`，再打开“编辑小组件”。 |
| CLI 找不到命令 | 将 `~/bin` 加入 `PATH`，或使用应用内的绝对路径。 |
| 显示 `gpt-reserve` 为 0% | 这是服务端返回的独立额度窗口，不等于主 Codex 窗口；请以每张卡片的名称和重置时间为准。 |

## 项目结构

```text
Sources/CodexMeter/          菜单栏宿主与 Popover
Sources/CodexMeterWidget/    WidgetKit 扩展与静态/AppIntent 变体
Sources/CodexMeterShared/    Widget 快照模型
Sources/CodexMeterCLI/       codex-meter status --json
skills/codex-meter-status/   配套只读 Codex Skill
scripts/                     构建、安装、协议冒烟测试
```

欢迎通过 Issue 反馈 macOS 版本、Codex 版本和脱敏后的 `status --json` 结构；不要粘贴凭据、会话内容或完整日志。
