import CodexMeterShared
import SwiftUI
import WidgetKit
#if CODEX_METER_APPINTENTS
import AppIntents
#endif

private struct WidgetLanguageKey: EnvironmentKey {
    static let defaultValue = AppLanguage.chinese
}

private struct WidgetAppearanceKey: EnvironmentKey {
    static let defaultValue = WidgetAppearance.system
}

private extension EnvironmentValues {
    var codexLanguage: AppLanguage {
        get { self[WidgetLanguageKey.self] }
        set { self[WidgetLanguageKey.self] = newValue }
    }

    var codexAppearance: WidgetAppearance {
        get { self[WidgetAppearanceKey.self] }
        set { self[WidgetAppearanceKey.self] = newValue }
    }
}

enum WidgetMetric: String, CaseIterable {
    case overview
    case shortWindow
    case weeklyWindow
    case resets
    case trend

    func title(language: AppLanguage) -> String {
        switch self {
        case .overview: return "Codex"
        case .shortWindow: return language.text("5 小时", "5 hours")
        case .weeklyWindow: return language.text("每周", "Weekly")
        case .resets: return language.text("重置次数", "Resets")
        case .trend: return language.text("最近用量", "Recent usage")
        }
    }
}

struct CodexMeterEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let metric: WidgetMetric
}

struct CodexMeterStaticProvider: TimelineProvider {
    typealias Entry = CodexMeterEntry

    let metric: WidgetMetric
    private let store = WidgetSnapshotStore()

    func placeholder(in context: Context) -> CodexMeterEntry {
        CodexMeterEntry(date: Date(), snapshot: .placeholder, metric: metric)
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexMeterEntry) -> Void) {
        completion(entry(snapshot: store.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexMeterEntry>) -> Void) {
        let snapshot = store.load() ?? .placeholder
        let current = entry(snapshot: snapshot)
        // WidgetKit decides the exact delivery time.  Asking for a refresh
        // after fifteen minutes keeps the desktop card fresh without polling
        // Codex from inside the extension.
        let nextRefresh = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [current], policy: .after(nextRefresh)))
    }

    private func entry(snapshot: WidgetSnapshot) -> CodexMeterEntry {
        CodexMeterEntry(date: Date(), snapshot: snapshot, metric: metric)
    }
}

// The configurable WidgetKit path is enabled by the Xcode build described in
// README.  Local SwiftPM builds keep the static cards below because the
// Command Line Tools do not ship Apple's AppIntent metadata processor.
#if CODEX_METER_APPINTENTS
enum WidgetMetricOption: String, AppEnum, CaseIterable, Sendable {
    case overview
    case shortWindow
    case weeklyWindow
    case resets
    case trend

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "显示指标"

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
            .overview: "总览 / Overview",
            .shortWindow: "5 小时 / 5 hours",
            .weeklyWindow: "每周 / Weekly",
            .resets: "重置次数 / Resets",
            .trend: "趋势 / Trend"
        ]

    var metric: WidgetMetric { WidgetMetric(rawValue: rawValue) ?? .overview }
}

struct CodexMeterWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Codex Meter"
    static let description = IntentDescription("Choose which Codex Meter card to show.")

    @Parameter(title: "显示指标", default: .overview)
    var metric: WidgetMetricOption

    init() {
        metric = .overview
    }
}

struct CodexMeterIntentProvider: AppIntentTimelineProvider {
    typealias Entry = CodexMeterEntry
    typealias Intent = CodexMeterWidgetIntent

    private let store = WidgetSnapshotStore()

    func placeholder(in context: Context) -> CodexMeterEntry {
        CodexMeterEntry(date: Date(), snapshot: .placeholder, metric: .overview)
    }

    func snapshot(for configuration: CodexMeterWidgetIntent, in context: Context) async -> CodexMeterEntry {
        CodexMeterEntry(date: Date(), snapshot: store.load() ?? .placeholder, metric: configuration.metric.metric)
    }

    func timeline(for configuration: CodexMeterWidgetIntent, in context: Context) async -> Timeline<CodexMeterEntry> {
        let entry = CodexMeterEntry(date: Date(), snapshot: store.load() ?? .placeholder, metric: configuration.metric.metric)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
    }
}

struct CodexMeterConfigurableWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "CodexMeterWidgetConfigurable",
            intent: CodexMeterWidgetIntent.self,
            provider: CodexMeterIntentProvider()
        ) { entry in
            CodexMeterWidgetView(entry: entry)
        }
        .configurationDisplayName("Codex Meter")
        .description("选择显示 5 小时、每周、重置次数或趋势。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
#endif

@MainActor
private func makeStaticConfiguration(
    kind: String,
    metric: WidgetMetric,
    displayName: String,
    widgetDescription: String
) -> some WidgetConfiguration {
    StaticConfiguration(
        kind: kind,
        provider: CodexMeterStaticProvider(metric: metric)
    ) { entry in
        CodexMeterWidgetView(entry: entry)
    }
    .configurationDisplayName(displayName)
    .description(widgetDescription)
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
}

struct CodexMeterOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        makeStaticConfiguration(
            kind: "CodexMeterWidget",
            metric: .overview,
            displayName: "Codex Meter",
            widgetDescription: "显示 5 小时与每周额度。"
        )
    }
}

struct CodexMeterShortWidget: Widget {
    var body: some WidgetConfiguration {
        makeStaticConfiguration(
            kind: "CodexMeterWidgetShort",
            metric: .shortWindow,
            displayName: "Codex Meter · 5 小时",
            widgetDescription: "显示短周期额度和重置倒计时。"
        )
    }
}

struct CodexMeterWeeklyWidget: Widget {
    var body: some WidgetConfiguration {
        makeStaticConfiguration(
            kind: "CodexMeterWidgetWeekly",
            metric: .weeklyWindow,
            displayName: "Codex Meter · 每周",
            widgetDescription: "显示每周额度和重置倒计时。"
        )
    }
}

struct CodexMeterResetsWidget: Widget {
    var body: some WidgetConfiguration {
        makeStaticConfiguration(
            kind: "CodexMeterWidgetResets",
            metric: .resets,
            displayName: "Codex Meter · 重置次数",
            widgetDescription: "显示可用重置次数和最近到期时间。"
        )
    }
}

struct CodexMeterTrendWidget: Widget {
    var body: some WidgetConfiguration {
        makeStaticConfiguration(
            kind: "CodexMeterWidgetTrend",
            metric: .trend,
            displayName: "Codex Meter · 用量趋势",
            widgetDescription: "显示最近用量趋势。"
        )
    }
}

@main
struct CodexMeterWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodexMeterOverviewWidget()
        CodexMeterShortWidget()
        CodexMeterWeeklyWidget()
        CodexMeterResetsWidget()
        CodexMeterTrendWidget()
#if CODEX_METER_APPINTENTS
        CodexMeterConfigurableWidget()
#endif
    }
}

struct CodexMeterWidgetView: View {
    let entry: CodexMeterEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let language = AppLanguage(rawValue: entry.snapshot.languageCode ?? "") ?? .chinese
        let appearance = WidgetAppearance(rawValue: entry.snapshot.appearance ?? "") ?? .system
        Group {
            switch family {
            case .systemSmall:
                SmallWidget(snapshot: entry.snapshot, metric: entry.metric)
            case .systemMedium:
                MediumWidget(snapshot: entry.snapshot, metric: entry.metric)
            default:
                LargeWidget(snapshot: entry.snapshot, metric: entry.metric)
            }
        }
        .containerBackground(for: .widget) {
            WidgetBackground(appearance: appearance)
        }
        .environment(\.codexLanguage, language)
        .environment(\.codexAppearance, appearance)
        .preferredColorScheme(appearance == .system ? nil : .dark)
        .widgetURL(URL(string: "codex-meter://open"))
    }
}

private struct WidgetBackground: View {
    let appearance: WidgetAppearance

    var body: some View {
        switch appearance {
        case .system:
            Color.clear
        case .colorful:
            LinearGradient(
                colors: [Color.blue.opacity(0.82), Color.indigo.opacity(0.74), Color.purple.opacity(0.68)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dark:
            LinearGradient(
                colors: [Color.black.opacity(0.94), Color(red: 0.10, green: 0.12, blue: 0.16).opacity(0.98)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct SmallWidget: View {
    let snapshot: WidgetSnapshot
    let metric: WidgetMetric
    @Environment(\.codexLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: metric.title(language: language), plan: snapshot.planName)
            switch metric {
            case .resets:
                ResetSummary(snapshot: snapshot, compact: true)
            case .trend:
                TrendSummary(snapshot: snapshot, compact: true)
            default:
                QuotaSummary(window: selectedWindow, compact: true)
            }
            Spacer(minLength: 0)
            UpdatedLabel(snapshot: snapshot)
        }
        .padding(2)
    }

    private var selectedWindow: WidgetWindow? {
        switch metric {
        case .weeklyWindow: return snapshot.weeklyWindow ?? snapshot.primaryWindow
        default: return snapshot.primaryWindow
        }
    }
}

private struct MediumWidget: View {
    let snapshot: WidgetSnapshot
    let metric: WidgetMetric
    @Environment(\.codexLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(title: metric == .overview ? "Codex" : metric.title(language: language), plan: snapshot.planName)
            switch metric {
            case .resets:
                ResetSummary(snapshot: snapshot, compact: false)
            case .trend:
                TrendSummary(snapshot: snapshot, compact: false)
            case .shortWindow:
                HStack(spacing: 18) {
                    QuotaSummary(window: snapshot.primaryWindow, compact: false)
                    ResetSummary(snapshot: snapshot, compact: true)
                }
            case .weeklyWindow:
                HStack(spacing: 18) {
                    QuotaSummary(window: snapshot.weeklyWindow ?? snapshot.primaryWindow, compact: false)
                    ResetSummary(snapshot: snapshot, compact: true)
                }
            case .overview:
                HStack(spacing: 18) {
                    QuotaSummary(window: snapshot.primaryWindow, compact: false)
                    QuotaSummary(window: snapshot.weeklyWindow, compact: false)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(2)
    }
}

private struct LargeWidget: View {
    let snapshot: WidgetSnapshot
    let metric: WidgetMetric
    @Environment(\.codexLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WidgetHeader(title: metric == .overview ? "Codex" : metric.title(language: language), plan: snapshot.planName)
            switch metric {
            case .resets:
                ResetSummary(snapshot: snapshot, compact: false)
                    .frame(maxHeight: .infinity, alignment: .top)
            case .trend:
                TrendSummary(snapshot: snapshot, compact: false)
                    .frame(maxHeight: .infinity, alignment: .top)
            default:
                HStack(alignment: .top, spacing: 14) {
                    QuotaSummary(window: snapshot.primaryWindow, compact: false)
                    QuotaSummary(window: snapshot.weeklyWindow, compact: false)
                }
                ResetSummary(snapshot: snapshot, compact: false)
                TrendSummary(snapshot: snapshot, compact: false)
            }
            Spacer(minLength: 0)
            UpdatedLabel(snapshot: snapshot)
        }
        .padding(2)
    }
}

private struct WidgetHeader: View {
    let title: String
    let plan: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tint)
                .widgetAccentable()
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(plan)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct QuotaSummary: View {
    let window: WidgetWindow?
    let compact: Bool
    @Environment(\.codexLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            if let window {
                HStack(alignment: .firstTextBaseline) {
                    Text(localizedWindowName(window.name, language: language))
                        .font(.system(compact ? .caption : .subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text("\(window.remainingPercent)%")
                        .font(.system(size: compact ? 31 : 38, weight: .bold, design: .rounded))
                        .foregroundStyle(quotaColor(for: window.remainingPercent))
                        .widgetAccentable()
                        .minimumScaleFactor(0.7)
                }
                ProgressView(value: Double(window.remainingPercent), total: 100)
                    .tint(quotaColor(for: window.remainingPercent))
                Text(window.resetDate.map { "\(countdown(to: $0, language: language))\(language.text(" 后重置", " until reset"))" } ?? language.text("重置时间未知", "Reset time unknown"))
                    .font(.system(compact ? .caption2 : .caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } else {
                Text(language.text("暂无额度数据", "No quota data"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ResetSummary: View {
    let snapshot: WidgetSnapshot
    let compact: Bool
    @Environment(\.codexLanguage) private var language

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(language.text("可用重置次数", "Available resets"))
                    .font(.system(compact ? .caption : .subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let credit = snapshot.resetCredits.first, let expiry = credit.expiresAt {
                    Text(language.text("下次 ", "Next ") + expiry.formatted(.relative(presentation: .named)))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(snapshot.availableResetCount == nil ? language.text("等待服务端数据", "Waiting for service data") : language.text("暂无到期明细", "No expiry details"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text(snapshot.availableResetCount.map(String.init) ?? "—")
                .font(.system(size: compact ? 31 : 42, weight: .bold, design: .rounded))
                .foregroundStyle(.tint)
                .widgetAccentable()
        }
    }
}

private struct TrendSummary: View {
    let snapshot: WidgetSnapshot
    let compact: Bool
    @Environment(\.codexLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(language.text("最近用量", "Recent usage"))
                    .font(.system(compact ? .caption : .subheadline, design: .rounded, weight: .semibold))
                Spacer(minLength: 4)
                Text(language.text("30 天", "30 days"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Sparkline(values: snapshot.history.suffix(60).map(\.primaryRemaining))
                .frame(height: compact ? 36 : 62)
            if snapshot.history.isEmpty {
                Text(language.text("刷新后显示趋势", "Trend appears after refresh"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if let rate = snapshot.consumptionRatePerHour {
                let value = String(format: "%.1f", rate)
                Text(language.text("消耗 \(value)% / 小时", "Consuming \(value)% / hour"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                guard values.count > 1 else { return }
                let width = proxy.size.width
                let height = proxy.size.height
                for (index, value) in values.enumerated() {
                    let x = width * CGFloat(index) / CGFloat(values.count - 1)
                    let y = height * (1 - CGFloat(max(0, min(100, value))) / 100)
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .widgetAccentable()
            .overlay(alignment: .bottom) {
                Rectangle().fill(.secondary.opacity(0.18)).frame(height: 1)
            }
        }
    }
}

private struct UpdatedLabel: View {
    let snapshot: WidgetSnapshot
    @Environment(\.codexLanguage) private var language

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(snapshot.updatedAt == nil ? .orange : .green)
                .frame(width: 6, height: 6)
            Text(verbatim: snapshot.updatedAt.map { language.text("更新 ", "Updated ") + $0.formatted(.relative(presentation: .named)) } ?? snapshot.statusMessage)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private extension WidgetSnapshot {
    static let placeholder: WidgetSnapshot = {
        let now = Date()
        let short = WidgetWindow(id: "short", name: "5 小时", usedPercent: 7, durationMinutes: 300, resetDate: now.addingTimeInterval(3 * 3600))
        let weekly = WidgetWindow(id: "weekly", name: "每周", usedPercent: 60, durationMinutes: 10080, resetDate: now.addingTimeInterval(5 * 24 * 3600))
        let limit = WidgetLimit(id: "codex", name: "Codex", windows: [short, weekly])
        var history: [WidgetHistoryPoint] = []
        for index in 0..<18 {
            let date = now.addingTimeInterval(TimeInterval(-index * 3600))
            let remaining = Double(74 + (index % 5) * 4)
            history.append(WidgetHistoryPoint(id: UUID(), date: date, primaryRemaining: remaining, weeklyRemaining: nil))
        }
        return WidgetSnapshot(
            planName: "Plus",
            limits: [limit],
            availableResetCount: 3,
            resetCredits: [],
            history: history,
            updatedAt: now,
            statusMessage: "示例数据"
        )
    }()
}

private func localizedWindowName(_ name: String, language: AppLanguage) -> String {
    guard language == .english else { return name }
    switch name {
    case "5 小时": return "5 hours"
    case "每日": return "Daily"
    case "每周": return "Weekly"
    default: return name.replacingOccurrences(of: "天", with: " days")
    }
}

private func quotaColor(for remaining: Int) -> Color {
    if remaining <= 20 { return .red }
    if remaining <= 50 { return .orange }
    return .green
}

private func countdown(to date: Date, language: AppLanguage) -> String {
    let seconds = max(0, Int(date.timeIntervalSinceNow))
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    if hours >= 24 {
        return language.text("\(hours / 24)天 \(hours % 24)小时", "\(hours / 24)d \(hours % 24)h")
    }
    if hours > 0 { return language.text("\(hours)小时 \(minutes)分", "\(hours)h \(minutes)m") }
    return language.text("\(minutes)分", "\(minutes)m")
}
