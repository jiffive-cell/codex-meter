import CodexMeterShared
import Darwin
import Foundation

/// A deliberately read-only command-line surface.  It reads the same host
/// snapshot as the app and never starts Codex or mutates account state.
@main
struct CodexMeterCLI {
    private struct StatusOutput: Encodable {
        struct Limit: Encodable {
            struct Window: Encodable {
                let id: String
                let name: String
                let usedPercent: Int
                let remainingPercent: Int
                let durationMinutes: Int
                let resetDate: Date?
            }

            let id: String
            let name: String
            let windows: [Window]
        }

        struct ResetCredit: Encodable {
            let id: String
            let title: String?
            let expiresAt: Date?
        }

        let schemaVersion: Int
        let plan: String
        let updatedAt: Date?
        let status: String
        let stale: Bool
        let limits: [Limit]
        let availableResetCount: Int?
        let resetCredits: [ResetCredit]
        let consumptionRatePerHour: Double?
        let estimatedExhaustionAt: Date?
    }

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2, arguments[0] == "status", arguments[1] == "--json" else {
            FileHandle.standardError.write(Data("Usage: codex-meter status --json\n".utf8))
            Darwin.exit(2)
        }

        let store = WidgetSnapshotStore()
        guard let snapshot = store.load() else {
            print("{\"error\":\"snapshot_unavailable\",\"message\":\"Codex Meter has not written a snapshot yet\"}")
            Darwin.exit(1)
        }

        let stale: Bool = {
            guard let updatedAt = snapshot.updatedAt else { return true }
            return Date().timeIntervalSince(updatedAt) > 30 * 60
        }()

        let output = StatusOutput(
            schemaVersion: snapshot.schemaVersion,
            plan: snapshot.planName,
            updatedAt: snapshot.updatedAt,
            status: snapshot.statusMessage,
            stale: stale,
            limits: snapshot.limits.map { limit in
                StatusOutput.Limit(
                    id: limit.id,
                    name: limit.name,
                    windows: limit.windows.map { window in
                        StatusOutput.Limit.Window(
                            id: window.id,
                            name: window.name,
                            usedPercent: window.usedPercent,
                            remainingPercent: window.remainingPercent,
                            durationMinutes: window.durationMinutes,
                            resetDate: window.resetDate
                        )
                    }
                )
            },
            availableResetCount: snapshot.availableResetCount,
            resetCredits: snapshot.resetCredits.map {
                StatusOutput.ResetCredit(id: $0.id, title: $0.title, expiresAt: $0.expiresAt)
            },
            consumptionRatePerHour: snapshot.consumptionRatePerHour,
            estimatedExhaustionAt: snapshot.estimatedExhaustionAt
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(output) else {
            FileHandle.standardError.write(Data("Unable to encode status JSON\n".utf8))
            Darwin.exit(1)
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}
