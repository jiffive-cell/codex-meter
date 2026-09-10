import AppKit
import Charts
import CodexMeterShared
import Foundation
import ServiceManagement
import SwiftUI
import UserNotifications
import WidgetKit

// MARK: - Protocol models

struct RateLimitWindow: Codable, Equatable {
    let usedPercent: Int
    let windowDurationMins: Int
    let resetsAt: Int64?
}

struct CreditsSnapshot: Codable, Equatable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
}

struct RateLimitSnapshot: Codable, Equatable {
    let limitId: String?
    let limitName: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let credits: CreditsSnapshot?
    let individualLimit: IndividualLimit?
    let spendControlReached: Bool?
    let planType: String?
    let rateLimitReachedType: String?
}

struct IndividualLimit: Codable, Equatable {
    let limit: Double?
    let used: Double?
}

struct ResetCredit: Codable, Equatable, Identifiable {
    let id: String
    let resetType: String
    let status: String
    let grantedAt: Int64
    let expiresAt: Int64?
    let title: String?
    let description: String?
}

struct ResetCreditSummary: Codable, Equatable {
    let availableCount: Int
    let credits: [ResetCredit]?
}

struct RateLimitsResponse: Codable, Equatable {
    let accountId: String?
    let rateLimits: RateLimitSnapshot
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
    let rateLimitResetCredits: ResetCreditSummary?
}

struct JSONRPCError: Codable {
    let code: Int
    let message: String
}

struct JSONRPCEnvelope: Codable {
    let id: Int?
    let method: String?
    let result: JSONValue?
    let error: JSONRPCError?
}

enum JSONValue: Codable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([String: JSONValue].self) { self = .object(value); return }
        self = .array(try container.decode([JSONValue].self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - Local persistence

struct HistorySample: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let primaryRemaining: Double
    let weeklyRemaining: Double?
}

final class HistoryStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "CodexMeter.history")

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = appSupport.appendingPathComponent("CodexMeter", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("history.json")
    }

    func load() -> [HistorySample] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL),
                  let samples = try? decoder.decode([HistorySample].self, from: data) else { return [] }
            return samples.sorted { $0.date < $1.date }
        }
    }

    func append(_ sample: HistorySample) {
        queue.async { [fileURL, encoder, decoder] in
            var samples: [HistorySample] = []
            if let data = try? Data(contentsOf: fileURL),
               let decoded = try? decoder.decode([HistorySample].self, from: data) {
                samples = decoded
            }
            samples.append(sample)
            let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
            samples = samples.filter { $0.date >= cutoff }.suffix(2000)
            if let data = try? encoder.encode(Array(samples)) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    func removeAll() {
        queue.async { [fileURL] in try? FileManager.default.removeItem(at: fileURL) }
    }
}

// MARK: - Codex app-server client

@MainActor
final class CodexAppServerClient: NSObject {
    enum ClientError: LocalizedError {
        case executableNotFound
        case notRunning
        case server(String)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .executableNotFound: return "找不到 Codex 可执行文件"
            case .notRunning: return "Codex app-server 未运行"
            case .server(let message): return message
            case .malformedResponse: return "Codex 返回了无法识别的数据"
            }
        }
    }

    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var nextID = 1
    private var pending: [Int: (Result<Data, Error>) -> Void] = [:]
    private var initialized = false
    private var configuredPath: String?

    func setExecutablePath(_ path: String?) {
        configuredPath = path?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : path
        stop()
    }

    var activeExecutablePath: String? { configuredPath ?? discoverExecutable() }

    func startIfNeeded(completion: @escaping (Result<Void, Error>) -> Void) {
        guard process?.isRunning != true else { completion(.success(())); return }
        guard let executable = activeExecutablePath else {
            completion(.failure(ClientError.executableNotFound)); return
        }

        let newProcess = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        newProcess.executableURL = URL(fileURLWithPath: executable)
        newProcess.arguments = ["app-server", "--listen", "stdio://"]
        newProcess.standardInput = stdin
        newProcess.standardOutput = stdout
        newProcess.standardError = FileHandle.standardError

        do {
            try newProcess.run()
        } catch {
            completion(.failure(error)); return
        }

        process = newProcess
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        buffer.removeAll(keepingCapacity: true)
        initialized = false
        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in self?.consume(data) }
        }
        newProcess.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.initialized = false
                self.process = nil
                self.input = nil
                self.output?.readabilityHandler = nil
                self.output = nil
            }
        }

        send(method: "initialize", params: [
            "clientInfo": ["name": "codex-meter", "title": "Codex Meter", "version": "0.4.0"],
            "capabilities": ["experimentalApi": true]
        ]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success:
                self.sendNotification(method: "initialized", params: [:])
                self.initialized = true
                completion(.success(()))
            }
        }
    }

    func refresh(completion: @escaping (Result<RateLimitsResponse, Error>) -> Void) {
        startIfNeeded { [weak self] startupResult in
            guard let self else { return }
            switch startupResult {
            case .failure(let error): completion(.failure(error))
            case .success:
                self.send(method: "account/rateLimits/read", params: nil) { result in
                    switch result {
                    case .failure(let error): completion(.failure(error))
                    case .success(let data):
                        do { completion(.success(try JSONDecoder().decode(RateLimitsResponse.self, from: data))) }
                        catch { completion(.failure(ClientError.malformedResponse)) }
                    }
                }
            }
        }
    }

    func stop() {
        output?.readabilityHandler = nil
        process?.terminate()
        process = nil
        input = nil
        output = nil
        initialized = false
        pending.removeAll()
    }

    private func discoverExecutable() -> String? {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return path }
        let which = Process()
        let pipe = Pipe()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["codex"]
        which.standardOutput = pipe
        try? which.run()
        which.waitUntilExit()
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }
    }

    private func sendNotification(method: String, params: [String: Any]) {
        let object: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        write(object: object)
    }

    private func send(method: String, params: [String: Any]?, completion: @escaping (Result<Data, Error>) -> Void) {
        let id = nextID
        nextID += 1
        pending[id] = completion
        var object: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        object["params"] = params ?? NSNull()
        write(object: object)
    }

    private func write(object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object), let input else { return }
        input.write(data + Data([0x0A]))
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let envelope = try? JSONDecoder().decode(JSONRPCEnvelope.self, from: line) else { continue }
            guard let id = envelope.id, let completion = pending.removeValue(forKey: id) else { continue }
            if let error = envelope.error {
                completion(.failure(ClientError.server("Codex: \(error.message) (\(error.code))")))
            } else if let result = envelope.result,
                      let data = try? JSONEncoder().encode(result) {
                completion(.success(data))
            } else {
                completion(.success(Data("null".utf8)))
            }
        }
    }
}

// MARK: - View model and formatting

struct DisplayWindow: Identifiable, Equatable {
    let id: String
    let name: String
    let usedPercent: Int
    let durationMinutes: Int
    let resetDate: Date?
    var remainingPercent: Int { max(0, min(100, 100 - usedPercent)) }
}

struct DisplayLimit: Identifiable, Equatable {
    let id: String
    let name: String
    let windows: [DisplayWindow]
}

enum MeterLayoutStyle: String, CaseIterable, Identifiable {
    case widget
    case list

    var id: String { rawValue }
    var title: String {
        switch self {
        case .widget: return "组件网格"
        case .list: return "纵向列表"
        }
    }
}

@MainActor
final class MeterViewModel: ObservableObject {
    @Published var limits: [DisplayLimit] = []
    @Published var planName = "未知会员"
    @Published var resetCredits: [ResetCredit] = []
    @Published var availableResetCount: Int?
    @Published var lastUpdated: Date?
    @Published var statusMessage = "正在连接 Codex…"
    @Published var isRefreshing = false
    @Published var history: [HistorySample] = []
    @Published var executablePath: String?
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "language")
            persistWidgetSnapshot()
        }
    }
    @Published var widgetAppearance: WidgetAppearance {
        didSet {
            UserDefaults.standard.set(widgetAppearance.rawValue, forKey: "widgetAppearance")
            persistWidgetSnapshot()
        }
    }
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }
    @Published var layoutStyle: MeterLayoutStyle {
        didSet {
            UserDefaults.standard.set(layoutStyle.rawValue, forKey: "layoutStyle")
            NotificationCenter.default.post(name: .codexMeterLayoutChanged, object: nil)
        }
    }
    @Published var widgetWidth: Double {
        didSet {
            UserDefaults.standard.set(widgetWidth, forKey: "widgetWidth")
            NotificationCenter.default.post(name: .codexMeterLayoutChanged, object: nil)
        }
    }
    @Published var showsHistory: Bool {
        didSet { UserDefaults.standard.set(showsHistory, forKey: "showsHistory") }
    }
    @Published var showsResetCredits: Bool {
        didSet { UserDefaults.standard.set(showsResetCredits, forKey: "showsResetCredits") }
    }
    @Published var showsOtherLimits: Bool {
        didSet { UserDefaults.standard.set(showsOtherLimits, forKey: "showsOtherLimits") }
    }
    @Published var alwaysOnTop: Bool {
        didSet {
            UserDefaults.standard.set(alwaysOnTop, forKey: "alwaysOnTop")
            NotificationCenter.default.post(name: .codexMeterWindowLevelChanged, object: alwaysOnTop)
        }
    }
    @Published var refreshInterval: Double {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval") }
    }

    /// Percentage points consumed per hour, calculated from the oldest and
    /// newest recent samples.  A minimum interval and positive drop prevent a
    /// reset or a single noisy sample from producing a misleading estimate.
    var consumptionRatePerHour: Double? {
        let samples = Array(history.suffix(24))
        guard let first = samples.first, let last = samples.last,
              last.date.timeIntervalSince(first.date) >= 15 * 60 else { return nil }
        let consumed = first.primaryRemaining - last.primaryRemaining
        guard consumed > 0.5 else { return nil }
        let hours = last.date.timeIntervalSince(first.date) / 3600
        guard hours > 0 else { return nil }
        return min(100, consumed / hours)
    }

    var estimatedExhaustionAt: Date? {
        guard let rate = consumptionRatePerHour, rate > 0,
              let remaining = limits.first?.windows.first?.remainingPercent else { return nil }
        return Date().addingTimeInterval(Double(remaining) / rate * 3600)
    }

    let client = CodexAppServerClient()
    private let historyStore = HistoryStore()
    private let widgetSnapshotStore = WidgetSnapshotStore()
    private let widgetContainerSnapshotStore = WidgetSnapshotStore(directory: WidgetSnapshotStore.localWidgetContainerDirectory())
    private var timer: Timer?
    private var previousNotificationKeys = Set<String>()

    init() {
        let storedInterval = UserDefaults.standard.double(forKey: "refreshInterval")
        refreshInterval = storedInterval > 0 ? storedInterval : 300
        layoutStyle = MeterLayoutStyle(rawValue: UserDefaults.standard.string(forKey: "layoutStyle") ?? "widget") ?? .widget
        let storedWidth = UserDefaults.standard.double(forKey: "widgetWidth")
        widgetWidth = storedWidth >= 420 && storedWidth <= 620 ? storedWidth : 460
        showsHistory = UserDefaults.standard.object(forKey: "showsHistory") as? Bool ?? true
        showsResetCredits = UserDefaults.standard.object(forKey: "showsResetCredits") as? Bool ?? true
        showsOtherLimits = UserDefaults.standard.object(forKey: "showsOtherLimits") as? Bool ?? true
        if UserDefaults.standard.object(forKey: "alwaysOnTop") == nil {
            alwaysOnTop = false
        } else {
            alwaysOnTop = UserDefaults.standard.bool(forKey: "alwaysOnTop")
        }
        let path = UserDefaults.standard.string(forKey: "codexPath")
        executablePath = path
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .chinese
        widgetAppearance = WidgetAppearance(rawValue: UserDefaults.standard.string(forKey: "widgetAppearance") ?? "") ?? .system
        notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        client.setExecutablePath(path)
        history = historyStore.load()
        startTimer()
        refresh()
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        statusMessage = language.text("正在刷新…", "Refreshing…")
        client.refresh { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRefreshing = false
                switch result {
                case .failure(let error):
                    self.statusMessage = error.localizedDescription
                    self.lastUpdated = nil
                case .success(let response):
                    self.apply(response)
                }
            }
        }
    }

    func updateSettings(path: String?, interval: Double) {
        executablePath = path
        UserDefaults.standard.set(path, forKey: "codexPath")
        client.setExecutablePath(path)
        refreshInterval = interval
        startTimer()
        refresh()
    }

    func setAlwaysOnTop(_ value: Bool) {
        alwaysOnTop = value
    }

    func updateLayout(style: MeterLayoutStyle, width: Double) {
        layoutStyle = style
        widgetWidth = min(620, max(420, width))
    }

    func clearHistory() {
        history.removeAll()
        historyStore.removeAll()
        persistWidgetSnapshot()
    }

    private func apply(_ response: RateLimitsResponse) {
        let snapshots = response.rateLimitsByLimitId ?? [response.rateLimits.limitId ?? "codex": response.rateLimits]
        let displayLimits = snapshots.compactMap { key, snapshot -> DisplayLimit? in
            let windows = [snapshot.primary, snapshot.secondary].enumerated().compactMap { index, window -> DisplayWindow? in
                guard let window else { return nil }
                let id = "\(key)-\(index)-\(window.windowDurationMins)"
                return DisplayWindow(id: id, name: windowName(window.windowDurationMins), usedPercent: window.usedPercent, durationMinutes: window.windowDurationMins, resetDate: date(from: window.resetsAt))
            }.sorted { $0.durationMinutes < $1.durationMinutes }
            guard !windows.isEmpty else { return nil }
            return DisplayLimit(id: key, name: snapshot.limitName ?? humanize(key), windows: windows)
        }.sorted { $0.id == "codex" && $1.id != "codex" }

        limits = displayLimits
        planName = planDisplayName(response.rateLimits.planType)
        availableResetCount = response.rateLimitResetCredits?.availableCount
        resetCredits = response.rateLimitResetCredits?.credits?.filter { $0.status == "available" }.sorted { ($0.expiresAt ?? Int64.max) < ($1.expiresAt ?? Int64.max) } ?? []
        lastUpdated = Date()
        statusMessage = language.text("数据正常", "Data OK")

        if let primary = displayLimits.first?.windows.first {
            let sample = HistorySample(id: UUID(), date: Date(), primaryRemaining: Double(primary.remainingPercent), weeklyRemaining: displayLimits.first?.windows.dropFirst().first.map { Double($0.remainingPercent) })
            history.append(sample)
            history = Array(history.suffix(2000))
            historyStore.append(sample)
        }
        persistWidgetSnapshot()
        notifyIfNeeded()
    }

    private func persistWidgetSnapshot() {
        let widgetLimits = limits.map { limit in
            WidgetLimit(
                id: limit.id,
                name: limit.name,
                windows: limit.windows.map { window in
                    WidgetWindow(
                        id: window.id,
                        name: window.name,
                        usedPercent: window.usedPercent,
                        durationMinutes: window.durationMinutes,
                        resetDate: window.resetDate
                    )
                }
            )
        }
        let widgetCredits = resetCredits.map {
            WidgetResetCredit(id: $0.id, title: $0.title, expiresAt: $0.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) })
        }
        let widgetHistory = history.suffix(240).map {
            WidgetHistoryPoint(id: $0.id, date: $0.date, primaryRemaining: $0.primaryRemaining, weeklyRemaining: $0.weeklyRemaining)
        }
        let snapshot = WidgetSnapshot(
            planName: planName,
            limits: widgetLimits,
            availableResetCount: availableResetCount,
            resetCredits: widgetCredits,
            history: widgetHistory,
            updatedAt: lastUpdated,
            statusMessage: statusMessage,
            languageCode: language.rawValue,
            appearance: widgetAppearance.rawValue,
            consumptionRatePerHour: consumptionRatePerHour,
            estimatedExhaustionAt: estimatedExhaustionAt
        )
        widgetSnapshotStore.save(snapshot)
        widgetContainerSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func notifyIfNeeded() {
        guard notificationsEnabled else { return }
        let center = UNUserNotificationCenter.current()
        for limit in limits {
            for window in limit.windows {
                guard let threshold = [5, 10, 20].first(where: { window.remainingPercent <= $0 }) else { continue }
                let resetToken = Int(window.resetDate?.timeIntervalSince1970 ?? 0)
                let key = "quota-\(limit.id)-\(window.id)-\(threshold)-\(resetToken)"
                if previousNotificationKeys.insert(key).inserted {
                    let content = UNMutableNotificationContent()
                    content.title = language.text("Codex 额度提醒", "Codex quota alert")
                    let displayName = localizedWindowName(window.name, language: language)
                    content.body = language.text(
                        "\(displayName)额度剩余 \(window.remainingPercent)%（低于 \(threshold)%）",
                        "\(displayName) quota is at \(window.remainingPercent)% (below \(threshold)%)"
                    )
                    center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
                }
            }
        }
        for credit in resetCredits {
            guard let expiry = credit.expiresAt else { continue }
            let hours = Date(timeIntervalSince1970: TimeInterval(expiry)).timeIntervalSinceNow / 3600
            if hours > 0 && hours <= 24 {
                let key = "reset-\(credit.id)-24"
                if previousNotificationKeys.insert(key).inserted {
                    let content = UNMutableNotificationContent()
                    content.title = language.text("Codex 重置次数即将到期", "Codex reset credit expiring")
                    content.body = language.text("有一张重置券将在 24 小时内到期", "A reset credit expires within 24 hours")
                    center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
                }
            }
        }
    }

    private func date(from timestamp: Int64?) -> Date? {
        timestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    private func windowName(_ minutes: Int) -> String {
        if minutes <= 360 { return "5 小时" }
        if minutes <= 24 * 60 { return "每日" }
        if minutes <= 8 * 24 * 60 { return "每周" }
        return "\(minutes / (24 * 60)) 天"
    }

    private func humanize(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").split(separator: " ").map { $0.capitalized }.joined(separator: " ")
    }

    private func planDisplayName(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "未知会员" }
        let normalized = raw.lowercased()
        let known: [String: String] = [
            "free": "Free", "go": "Go", "plus": "Plus", "pro": "Pro", "prolite": "Pro Lite",
            "team": "Team", "business": "Business", "edu": "Edu", "edu_plus": "Edu Plus", "edu_pro": "Edu Pro",
            "enterprise": "Enterprise", "ent26": "Enterprise", "self_serve_business_prolite": "Business Pro Lite",
            "self_serve_business_usage_based": "Business Usage Based", "enterprise_cbp_automation": "Enterprise Automation",
            "enterprise_cbp_usage_based": "Enterprise Usage Based"
        ]
        return known[normalized] ?? humanize(raw)
    }
}

// MARK: - SwiftUI views

private func localizedWindowName(_ name: String, language: AppLanguage) -> String {
    guard language == .english else { return name }
    switch name {
    case "5 小时": return "5 hours"
    case "每日": return "Daily"
    case "每周": return "Weekly"
    default: return name.replacingOccurrences(of: "天", with: " days")
    }
}

private func appearanceTitle(_ appearance: WidgetAppearance, language: AppLanguage) -> String {
    switch appearance {
    case .system: return language.text("跟随系统", "System")
    case .colorful: return language.text("全彩", "Colorful")
    case .dark: return language.text("深色", "Dark")
    }
}

private func rateText(_ rate: Double, language: AppLanguage) -> String {
    let value = String(format: "%.1f", rate)
    return language.text("\(value)% / 小时", "\(value)% / hour")
}

private func estimateText(_ date: Date, language: AppLanguage) -> String {
    let formatted = date.formatted(date: .abbreviated, time: .shortened)
    return language.text("预计 \(formatted) 耗尽", "Estimated empty \(formatted)")
}

private struct ProjectionCard: View {
    @ObservedObject var model: MeterViewModel

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "speedometer")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.language.text("消耗速度", "Consumption rate"))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                if let rate = model.consumptionRatePerHour {
                    Text(rateText(rate, language: model.language))
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                    if let estimate = model.estimatedExhaustionAt {
                        Text(estimateText(estimate, language: model.language))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(model.language.text("继续刷新后显示预计耗尽时间", "Refresh a little longer to estimate"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Text(model.language.text("按最近数据估算", "Based on recent data"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.trailing)
        }
        .padding(12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct WidgetMaterialView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .hudWindow
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

struct ContentView: View {
    @ObservedObject var model: MeterViewModel
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            WidgetMaterialView().ignoresSafeArea()
            // A restrained tint gives the panel the soft glass quality of
            // macOS widgets while allowing the desktop to remain visible.
            Color.green.opacity(0.08).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if model.limits.isEmpty {
                        emptyState
                    } else {
                        ForEach(model.limits.filter { model.showsOtherLimits || $0.id == "codex" }) { limit in
                            LimitSection(limit: limit, layoutStyle: model.layoutStyle, language: model.language)
                        }
                        if model.showsResetCredits, let count = model.availableResetCount { resetCard(count: count) }
                        if model.showsHistory, !model.history.isEmpty { historyCard }
                        if !model.limits.isEmpty { ProjectionCard(model: model) }
                    }
                    footer
                }
                .padding(20)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.32), lineWidth: 0.7) }
        .frame(minWidth: CGFloat(model.widgetWidth), idealWidth: CGFloat(model.widgetWidth), maxWidth: CGFloat(model.widgetWidth), minHeight: 560, idealHeight: 650, maxHeight: 760)
        .sheet(isPresented: $showingSettings) { SettingsView(model: model) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.tint.opacity(0.14))
                Image(systemName: "chart.bar.xaxis").font(.system(size: 18, weight: .semibold)).foregroundStyle(.tint)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex Meter").font(.system(.title3, design: .rounded, weight: .semibold))
                Text(model.language.text("实时额度与重置状态", "Live quota and reset status")).font(.system(.caption, design: .rounded)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.setAlwaysOnTop(!model.alwaysOnTop) } label: {
                Image(systemName: model.alwaysOnTop ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(model.alwaysOnTop ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(model.alwaysOnTop ? model.language.text("取消固定", "Unpin") : model.language.text("固定在桌面", "Keep on desktop"))
            HStack(spacing: 6) {
                Circle().fill(model.lastUpdated == nil ? .orange : .green).frame(width: 6, height: 6)
                Text(model.planName).font(.system(.caption, design: .rounded, weight: .semibold))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.primary.opacity(0.08), lineWidth: 0.5))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.language.text("暂时无法读取额度", "Unable to read quota"), systemImage: "exclamationmark.triangle")
                .font(.system(.headline, design: .rounded, weight: .semibold)).foregroundStyle(.orange)
            Text(model.statusMessage).font(.system(.subheadline, design: .rounded))
            Text(model.language.text("请确认 Codex 已登录，或在设置中指定 Codex 可执行文件。应用只读取本地 app-server 的额度数据。", "Confirm Codex is signed in, or choose its executable in Settings. The app only reads local app-server quota data."))
                .font(.system(.caption, design: .rounded)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(model.language.text("立即重试", "Retry now")) { model.refresh() }.buttonStyle(.borderedProminent).controlSize(.small)
        }
        .meterCard()
    }

    private func resetCard(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(model.language.text("可用重置次数", "Available resets"), systemImage: "arrow.clockwise.circle")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Spacer()
                Text("\(count)").font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(.tint)
            }
            ForEach(model.resetCredits.prefix(4)) { credit in
                HStack {
                    Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.secondary)
                    Text(credit.title ?? model.language.text("Codex 重置", "Codex reset"))
                    Spacer()
                    Text(expiryText(credit.expiresAt)).foregroundStyle(.secondary)
                }.font(.system(.caption, design: .rounded))
            }
            if model.resetCredits.isEmpty {
                Text(model.language.text("服务端未返回每张重置券的到期明细", "The service did not return credit expiry details")).font(.system(.caption, design: .rounded)).foregroundStyle(.secondary)
            }
        }
        .meterCard()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.language.text("最近用量", "Recent usage")).font(.system(.subheadline, design: .rounded, weight: .semibold))
                Spacer()
                Text(model.language.text("过去 30 天", "Last 30 days")).font(.system(.caption2, design: .rounded)).foregroundStyle(.secondary)
            }
            Chart(model.history.suffix(60)) { sample in
                LineMark(x: .value("时间", sample.date), y: .value("短周期剩余", sample.primaryRemaining))
                    .foregroundStyle(.tint).interpolationMethod(.catmullRom)
                if let weekly = sample.weeklyRemaining {
                    LineMark(x: .value("时间", sample.date), y: .value("周剩余", weekly))
                        .foregroundStyle(.secondary).interpolationMethod(.catmullRom)
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(values: [0, 50, 100]) }
            .chartPlotStyle { plot in plot.background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous)) }
            .frame(height: 110)
        }
        .meterCard()
    }

    private var footer: some View {
        HStack {
            Circle().fill(model.lastUpdated == nil ? .orange : .green).frame(width: 7, height: 7)
            Text(model.lastUpdated.map { "\(model.statusMessage) · \(relative($0))" } ?? model.statusMessage)
                .font(.system(.caption2, design: .rounded)).foregroundStyle(.secondary)
            Spacer()
                Button { model.refresh() } label: { Image(systemName: model.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise") }
                .buttonStyle(.borderless).controlSize(.small).help(model.language.text("立即刷新", "Refresh now"))
            Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless).controlSize(.small).help(model.language.text("设置", "Settings"))
        }
        .padding(.horizontal, 2)
    }

    private func expiryText(_ timestamp: Int64?) -> String {
        guard let timestamp else { return model.language.text("无到期时间", "No expiry") }
        return Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(date: .abbreviated, time: .shortened)
    }

    private func relative(_ date: Date) -> String { date.formatted(.relative(presentation: .named)) }
}

private struct MeterCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.primary.opacity(0.08), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

private extension View {
    func meterCard() -> some View { modifier(MeterCardModifier()) }
}

struct LimitSection: View {
    let limit: DisplayLimit
    let layoutStyle: MeterLayoutStyle
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(limit.id == "codex" ? "Codex" : limit.name)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    if limit.id != "codex" {
                        Text(language.text("服务端返回的其他额度", "Other limits from the service"))
                            .font(.system(.caption2, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "ellipsis.circle").foregroundStyle(.tertiary).font(.caption)
            }
            LazyVGrid(columns: layoutStyle == .widget
                ? [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                : [GridItem(.flexible())], spacing: 10) {
                ForEach(limit.windows) { window in WindowTile(window: window, language: language) }
            }
        }
        .meterCard()
    }
}

private struct WindowTile: View {
    let window: DisplayWindow
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(localizedWindowName(window.name, language: language)).font(.system(.caption, design: .rounded, weight: .medium))
                Spacer()
                Text("\(window.remainingPercent)%")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(color(for: window.remainingPercent))
            }
            ProgressView(value: Double(window.remainingPercent), total: 100).tint(color(for: window.remainingPercent))
            VStack(alignment: .leading, spacing: 2) {
                Text(language.text("剩余额度", "Remaining quota"))
                Text(window.resetDate.map { countdown(to: $0) + language.text(" 后重置", " until reset") } ?? language.text("重置时间未知", "Reset time unknown"))
            }
            .font(.system(.caption2, design: .rounded)).foregroundStyle(.secondary)
        }
        .padding(11)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.primary.opacity(0.06), lineWidth: 0.5) }
    }

    private func color(for remaining: Int) -> Color { remaining <= 20 ? .red : remaining <= 50 ? .orange : .green }
    private func countdown(to date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 24 { return "\(hours / 24)d \(hours % 24)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

struct SettingsView: View {
    @ObservedObject var model: MeterViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var path: String
    @State private var interval: Double
    @State private var launchAtLogin = false

    init(model: MeterViewModel) {
        self.model = model
        _path = State(initialValue: model.executablePath ?? "")
        _interval = State(initialValue: model.refreshInterval)
    }

    var body: some View {
        Form {
            Section {
                TextField(model.language.text("Codex 路径", "Codex path"), text: $path, prompt: Text(model.language.text("自动发现", "Auto-discover")))
                Text(model.language.text("当前环境会优先使用 ChatGPT.app 内置的 Codex。留空即可自动发现。", "This environment prefers the Codex bundled in ChatGPT.app. Leave blank to auto-discover."))
                    .font(.system(.caption, design: .rounded)).foregroundStyle(.secondary)
            } header: {
                Label(model.language.text("连接", "Connection"), systemImage: "link")
            }
            Section {
                Picker(model.language.text("刷新间隔", "Refresh interval"), selection: $interval) {
                    Text(model.language.text("1 分钟", "1 minute")).tag(60.0)
                    Text(model.language.text("5 分钟", "5 minutes")).tag(300.0)
                    Text(model.language.text("15 分钟", "15 minutes")).tag(900.0)
                    Text(model.language.text("30 分钟", "30 minutes")).tag(1800.0)
                }
                Toggle(model.language.text("登录时启动", "Launch at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, value in LoginItemManager.setEnabled(value) }
            } header: {
                Label(model.language.text("更新", "Updates"), systemImage: "arrow.clockwise")
            }
            Section {
                Picker(model.language.text("语言", "Language"), selection: $model.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                Picker(model.language.text("组件外观", "Widget appearance"), selection: $model.widgetAppearance) {
                    ForEach(WidgetAppearance.allCases) { appearance in
                        Text(appearanceTitle(appearance, language: model.language)).tag(appearance)
                    }
                }
                Toggle(model.language.text("启用分级通知（20% / 10% / 5%）", "Tiered alerts (20% / 10% / 5%)"), isOn: $model.notificationsEnabled)
            } header: {
                Label(model.language.text("偏好", "Preferences"), systemImage: "slider.horizontal.3")
            }
            Section {
                Label(model.language.text("桌面组件", "Desktop widgets"), systemImage: "rectangle.3.group")
                Text(model.language.text("尺寸和位置由 macOS 的“编辑小组件”管理。组件库提供 Codex Meter 总览、5 小时、每周、重置次数和趋势五个变体，选择需要的变体添加即可。", "macOS controls widget size and placement. The gallery provides Overview, 5-hour, Weekly, Resets, and Trend variants."))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(model.language.text("组件", "Widgets"))
            }
            Section {
                Button(model.language.text("清除历史记录", "Clear history"), role: .destructive) { model.clearHistory() }
            } header: {
                Label(model.language.text("隐私", "Privacy"), systemImage: "hand.raised")
            } footer: {
                Text(model.language.text("历史数据只保存在这台 Mac 上；应用不会读取对话内容或上传项目文件。", "History stays on this Mac; the app does not read conversations or upload project files."))
            }
            Section {
                HStack {
                    Spacer()
                    Button(model.language.text("取消", "Cancel")) { dismiss() }
                    Button(model.language.text("保存", "Save")) {
                        model.updateSettings(path: path.isEmpty ? nil : path, interval: interval)
                        dismiss()
                    }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 580)
        .onAppear { launchAtLogin = LoginItemManager.isEnabled }
    }
}

/// The host app is intentionally small.  The desktop surface belongs to
/// WidgetKit; this window only explains how to add the widget and exposes
/// connection/refresh settings.
struct HostStatusView: View {
    @ObservedObject var model: MeterViewModel
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.tint)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex Meter")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                    Text(model.language.text("桌面组件与实时额度", "Desktop widgets and live quota"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(model.planName)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
            }

            VStack(alignment: .leading, spacing: 10) {
                Label(model.language.text("组件已随应用安装", "Widget installed with the app"), systemImage: "checkmark.circle.fill")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.green)
                Text(model.language.text("在桌面按住 Control 点按，选择“编辑小组件”，搜索 Codex Meter，然后把需要的变体放在系统组件下面。组件库提供总览、5 小时、每周、重置次数和趋势五种卡片。", "Control-click the desktop, choose Edit Widgets, search for Codex Meter, and place a variant below the system widgets. The gallery provides Overview, 5-hour, Weekly, Resets, and Trend cards."))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(.quaternary.opacity(0.34), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if let primary = model.limits.first?.windows.first {
                HStack(spacing: 10) {
                        HostMetric(title: localizedWindowName(primary.name, language: model.language), value: "\(primary.remainingPercent)%", color: quotaColor(primary.remainingPercent))
                    if let weekly = model.limits.first?.windows.dropFirst().first {
                        HostMetric(title: localizedWindowName(weekly.name, language: model.language), value: "\(weekly.remainingPercent)%", color: quotaColor(weekly.remainingPercent))
                    }
                    if let resets = model.availableResetCount {
                        HostMetric(title: model.language.text("重置", "Resets"), value: model.language.text("\(resets) 次", "\(resets)"), color: .accentColor)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Circle().fill(.orange).frame(width: 7, height: 7)
                    Text(model.statusMessage)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            if !model.limits.isEmpty {
                ProjectionCard(model: model)
            }

            HStack(spacing: 10) {
                Button {
                    model.refresh()
                } label: {
                    Label(model.isRefreshing ? model.language.text("刷新中…", "Refreshing…") : model.language.text("刷新", "Refresh"), systemImage: model.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(model.isRefreshing)
                Button {
                    showingSettings = true
                } label: {
                    Label(model.language.text("设置", "Settings"), systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label(model.language.text("退出", "Quit"), systemImage: "power")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                Spacer()
                if let updated = model.lastUpdated {
                    Text(model.language.text("已更新 ", "Updated ") + updated.formatted(.relative(presentation: .named)))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.tertiary)
                } else {
                    Text(model.statusMessage)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(22)
        .frame(width: 430)
        .sheet(isPresented: $showingSettings) { SettingsView(model: model) }
    }

    private func quotaColor(_ remaining: Int) -> Color {
        if remaining <= 20 { return .red }
        if remaining <= 50 { return .orange }
        return .green
    }
}

private struct HostMetric: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

enum LoginItemManager {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { NSLog("Codex Meter login item: \(error.localizedDescription)") }
    }
}

private extension Notification.Name {
    static let codexMeterWindowLevelChanged = Notification.Name("CodexMeter.windowLevelChanged")
    static let codexMeterLayoutChanged = Notification.Name("CodexMeter.layoutChanged")
    static let codexMeterShowMainWindow = Notification.Name("CodexMeter.showMainWindow")
}

// MARK: - App lifecycle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = MeterViewModel()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusItem.button?.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "Codex Meter")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.toolTip = "Codex Meter"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: HostStatusView(model: viewModel))
        popover.contentSize = NSSize(width: 430, height: 500)
        viewModel.$limits.combineLatest(viewModel.$statusMessage).sink { [weak self] _, _ in self?.updateStatusItem() }.store(in: &cancellables)
        viewModel.$availableResetCount.sink { [weak self] _ in self?.updateStatusItem() }.store(in: &cancellables)
        viewModel.$alwaysOnTop.sink { [weak self] value in self?.applyWindowLevel(value) }.store(in: &cancellables)
        viewModel.$widgetWidth.sink { [weak self] value in self?.resizeMainWindow(width: value) }.store(in: &cancellables)
        NotificationCenter.default.addObserver(forName: .codexMeterShowMainWindow, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.showMainWindow() }
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        updateStatusItem()
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        if let main = viewModel.limits.first {
            let values = main.windows.map {
                let shortName = $0.durationMinutes <= 360 ? "5h" : $0.durationMinutes <= 8 * 24 * 60 ? "W" : "D"
                return "\(shortName) \($0.remainingPercent)%"
            }
            button.title = values.joined(separator: " · ")
        } else { button.title = "Codex —" }
    }

    private func showMainWindow() {
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 390),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Meter"
        window.isReleasedWhenClosed = false
        window.hasShadow = true
        window.minSize = NSSize(width: 380, height: 340)
        window.maxSize = NSSize(width: 620, height: 620)
        window.setFrameAutosaveName("CodexMeterHost")
        window.contentViewController = NSHostingController(rootView: HostStatusView(model: viewModel))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow = window
        applyWindowLevel(viewModel.alwaysOnTop)
    }

    private func applyWindowLevel(_ pinned: Bool) {
        guard let mainWindow else { return }
        mainWindow.level = pinned ? .floating : .normal
        mainWindow.collectionBehavior = pinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.managed]
    }

    private func resizeMainWindow(width: Double) {
        guard let mainWindow else { return }
        var frame = mainWindow.frame
        let newWidth = CGFloat(min(620, max(380, width)))
        frame.origin.x += (frame.width - newWidth) / 2
        frame.size.width = newWidth
        mainWindow.setFrame(frame, display: true, animate: true)
    }

    private var cancellables = Set<AnyCancellable>()
}

// Tiny local publisher subscription helper to avoid pulling in Combine explicitly in every file.
import Combine

@main
struct CodexMeterMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
