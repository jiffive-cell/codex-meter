import Foundation

/// The two languages exposed by the app and its widgets.  Keeping this small
/// value in the shared target means the host and the WidgetKit extension use
/// the same persisted representation without depending on AppKit or SwiftUI.
public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case chinese = "zh-Hans"
    case english = "en"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    public func text(_ chinese: String, _ english: String) -> String {
        self == .chinese ? chinese : english
    }
}

/// Widget rendering preferences.  `.system` deliberately leaves color
/// treatment to macOS, while the other modes provide predictable surfaces
/// for users who want a stronger visual identity.
public enum WidgetAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case colorful
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "跟随系统"
        case .colorful: return "全彩"
        case .dark: return "深色"
        }
    }
}

/// The small, stable payload shared by the menu-bar host and the WidgetKit
/// extension.  The widget never launches Codex itself; it only renders the
/// last snapshot written by the host.
public struct WidgetWindow: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let usedPercent: Int
    public let durationMinutes: Int
    public let resetDate: Date?

    public init(id: String, name: String, usedPercent: Int, durationMinutes: Int, resetDate: Date?) {
        self.id = id
        self.name = name
        self.usedPercent = usedPercent
        self.durationMinutes = durationMinutes
        self.resetDate = resetDate
    }

    public var remainingPercent: Int {
        max(0, min(100, 100 - usedPercent))
    }
}

public struct WidgetLimit: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let windows: [WidgetWindow]

    public init(id: String, name: String, windows: [WidgetWindow]) {
        self.id = id
        self.name = name
        self.windows = windows
    }
}

public struct WidgetResetCredit: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String?
    public let expiresAt: Date?

    public init(id: String, title: String?, expiresAt: Date?) {
        self.id = id
        self.title = title
        self.expiresAt = expiresAt
    }
}

public struct WidgetHistoryPoint: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let primaryRemaining: Double
    public let weeklyRemaining: Double?

    public init(id: UUID, date: Date, primaryRemaining: Double, weeklyRemaining: Double?) {
        self.id = id
        self.date = date
        self.primaryRemaining = primaryRemaining
        self.weeklyRemaining = weeklyRemaining
    }
}

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let planName: String
    public let limits: [WidgetLimit]
    public let availableResetCount: Int?
    public let resetCredits: [WidgetResetCredit]
    public let history: [WidgetHistoryPoint]
    public let updatedAt: Date?
    public let statusMessage: String
    /// Optional fields keep snapshots written by versions before 0.4.0
    /// readable.  New hosts always write a value for each field.
    public let languageCode: String?
    public let appearance: String?
    public let consumptionRatePerHour: Double?
    public let estimatedExhaustionAt: Date?

    public init(
        schemaVersion: Int = WidgetSnapshot.currentSchemaVersion,
        planName: String,
        limits: [WidgetLimit],
        availableResetCount: Int?,
        resetCredits: [WidgetResetCredit],
        history: [WidgetHistoryPoint],
        updatedAt: Date?,
        statusMessage: String,
        languageCode: String? = AppLanguage.chinese.rawValue,
        appearance: String? = WidgetAppearance.system.rawValue,
        consumptionRatePerHour: Double? = nil,
        estimatedExhaustionAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.planName = planName
        self.limits = limits
        self.availableResetCount = availableResetCount
        self.resetCredits = resetCredits
        self.history = history
        self.updatedAt = updatedAt
        self.statusMessage = statusMessage
        self.languageCode = languageCode
        self.appearance = appearance
        self.consumptionRatePerHour = consumptionRatePerHour
        self.estimatedExhaustionAt = estimatedExhaustionAt
    }

    public static let empty = WidgetSnapshot(
        planName: "未知会员",
        limits: [],
        availableResetCount: nil,
        resetCredits: [],
        history: [],
        updatedAt: nil,
        statusMessage: "等待 Codex 数据"
    )

    public var primaryLimit: WidgetLimit? {
        limits.first(where: { $0.id == "codex" }) ?? limits.first
    }

    public var primaryWindow: WidgetWindow? {
        primaryLimit?.windows.first
    }

    public var weeklyWindow: WidgetWindow? {
        primaryLimit?.windows.dropFirst().first
    }
}

/// Persists the latest account snapshot for the WidgetKit extension.
///
/// A signed distribution can use the App Group container. The local ad-hoc
/// build keeps the host snapshot in the user's Application Support and mirrors
/// it into the WidgetKit extension container, because macOS does not provision
/// arbitrary App Group identifiers for locally signed extensions.
public final class WidgetSnapshotStore: @unchecked Sendable {
    public static let appGroupIdentifier = "group.com.local.codex-meter"
    public static let widgetBundleIdentifier = "com.local.codex-meter.widget"

    public let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    public init(fileManager: FileManager = .default, directory: URL? = nil) {
        // Do not use `.applicationSupportDirectory` here.  Inside a sandboxed
        // Widget extension that URL points at the extension container, while
        // the menu-bar host writes to the user's shared Application Support.
        // An explicit home-relative URL keeps both processes on the same file.
        let directory = directory ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexMeter", isDirectory: true)

        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let snapshotURL = directory.appendingPathComponent("widget-snapshot.json")
        fileURL = snapshotURL

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    /// The path that the sandboxed WidgetKit extension resolves as its home.
    /// The unsandboxed host mirrors each snapshot here so the widget can read
    /// it without relying on an App Group entitlement in a local ad-hoc build.
    public static func localWidgetContainerDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(widgetBundleIdentifier)/Data/Library/Application Support/CodexMeter", isDirectory: true)
    }

    public func load() -> WidgetSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    public func save(_ snapshot: WidgetSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
