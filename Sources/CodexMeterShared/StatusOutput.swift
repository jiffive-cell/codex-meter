import Foundation

/// The stable, read-only JSON shape emitted by `codex-meter status --json`.
/// Keeping the mapping next to the snapshot model lets the CLI and its tests
/// use the same serialization contract without launching the app.
public struct CodexMeterStatusOutput: Encodable, Sendable {
    public struct Limit: Encodable, Sendable {
        public struct Window: Encodable, Sendable {
            public let id: String
            public let name: String
            public let usedPercent: Int
            public let remainingPercent: Int
            public let durationMinutes: Int
            public let resetDate: Date?

            public init(
                id: String,
                name: String,
                usedPercent: Int,
                remainingPercent: Int,
                durationMinutes: Int,
                resetDate: Date?
            ) {
                self.id = id
                self.name = name
                self.usedPercent = usedPercent
                self.remainingPercent = remainingPercent
                self.durationMinutes = durationMinutes
                self.resetDate = resetDate
            }
        }

        public let id: String
        public let name: String
        public let windows: [Window]

        public init(id: String, name: String, windows: [Window]) {
            self.id = id
            self.name = name
            self.windows = windows
        }
    }

    public struct ResetCredit: Encodable, Sendable {
        public let id: String
        public let title: String?
        public let expiresAt: Date?

        public init(id: String, title: String?, expiresAt: Date?) {
            self.id = id
            self.title = title
            self.expiresAt = expiresAt
        }
    }

    public let schemaVersion: Int
    public let plan: String
    public let updatedAt: Date?
    public let status: String
    public let stale: Bool
    public let limits: [Limit]
    public let availableResetCount: Int?
    public let resetCredits: [ResetCredit]
    public let consumptionRatePerHour: Double?
    public let estimatedExhaustionAt: Date?

    public init(
        snapshot: WidgetSnapshot,
        now: Date = Date(),
        staleAfter: TimeInterval = 30 * 60
    ) {
        schemaVersion = snapshot.schemaVersion
        plan = snapshot.planName
        updatedAt = snapshot.updatedAt
        status = snapshot.statusMessage
        stale = snapshot.isStale(at: now, threshold: staleAfter)
        limits = snapshot.limits.map { limit in
            Limit(
                id: limit.id,
                name: limit.name,
                windows: limit.windows.map { window in
                    Limit.Window(
                        id: window.id,
                        name: window.name,
                        usedPercent: window.usedPercent,
                        remainingPercent: window.remainingPercent,
                        durationMinutes: window.durationMinutes,
                        resetDate: window.resetDate
                    )
                }
            )
        }
        availableResetCount = snapshot.availableResetCount
        resetCredits = snapshot.resetCredits.map {
            ResetCredit(id: $0.id, title: $0.title, expiresAt: $0.expiresAt)
        }
        consumptionRatePerHour = snapshot.consumptionRatePerHour
        estimatedExhaustionAt = snapshot.estimatedExhaustionAt
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
