import XCTest
import CodexMeterShared
@testable import CodexMeter

final class CodexMeterTests: XCTestCase {
    func testRateLimitResponseDecodesResetCreditsAndPlan() throws {
        let data = Data(#"{"accountId":"a","rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":57,"windowDurationMins":300,"resetsAt":1788966999},"secondary":{"usedPercent":51,"windowDurationMins":10080,"resetsAt":1789445362},"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"individualLimit":null,"spendControlReached":false,"planType":"plus","rateLimitReachedType":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":{"availableCount":3,"credits":[{"id":"r1","resetType":"codexRateLimits","status":"available","grantedAt":1,"expiresAt":2,"title":"Full reset","description":null}]}}"#.utf8)

        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: data)

        XCTAssertEqual(response.rateLimits.planType, "plus")
        XCTAssertEqual(response.rateLimits.primary?.windowDurationMins, 300)
        XCTAssertEqual(response.rateLimits.secondary?.usedPercent, 51)
        XCTAssertEqual(response.rateLimits.credits?.balance, "0")
        XCTAssertEqual(response.rateLimitResetCredits?.availableCount, 3)
        XCTAssertEqual(response.rateLimitResetCredits?.credits?.first?.title, "Full reset")

        let summary = ResetCreditSummary(availableCount: 2, credits: [
            ResetCredit(id: "late", resetType: "codexRateLimits", status: "available", grantedAt: 1, expiresAt: 200, title: nil, description: nil),
            ResetCredit(id: "used", resetType: "codexRateLimits", status: "redeemed", grantedAt: 1, expiresAt: 100, title: nil, description: nil),
            ResetCredit(id: "soon", resetType: "codexRateLimits", status: "available", grantedAt: 1, expiresAt: 100, title: nil, description: nil)
        ])
        XCTAssertEqual(summary.availableCredits.map(\.id), ["soon", "late"])
    }

    func testRateLimitResponseDecodesAdditionalLimitMap() throws {
        let data = Data(#"{"accountId":null,"rateLimits":{"limitId":"codex","limitName":"Codex","primary":null,"secondary":null,"credits":null,"individualLimit":null,"spendControlReached":null,"planType":null,"rateLimitReachedType":null},"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":"Codex","primary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":null},"secondary":null,"credits":null,"individualLimit":null,"spendControlReached":false,"planType":"pro","rateLimitReachedType":null},"gpt-reserve":{"limitId":"gpt-reserve","limitName":null,"primary":{"usedPercent":100,"windowDurationMins":60,"resetsAt":null},"secondary":null,"credits":null,"individualLimit":null,"spendControlReached":true,"planType":null,"rateLimitReachedType":"primary"}},"rateLimitResetCredits":null}"#.utf8)

        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: data)

        XCTAssertEqual(response.rateLimitsByLimitId?.count, 2)
        XCTAssertEqual(response.rateLimitsByLimitId?["codex"]?.primary?.usedPercent, 12)
        XCTAssertEqual(response.rateLimitsByLimitId?["gpt-reserve"]?.spendControlReached, true)
    }

    func testJSONValueDecodesNestedRPCResult() throws {
        let data = Data(#"{"jsonrpc":"2.0","id":42,"result":{"rateLimits":{"usedPercent":23},"items":[true,null,"ok"]}}"#.utf8)
        let envelope = try JSONDecoder().decode(JSONRPCEnvelope.self, from: data)

        XCTAssertEqual(envelope.id, 42)
        guard let resultValue = envelope.result else {
            return XCTFail("Expected an object result")
        }
        guard case let .object(result) = resultValue else {
            return XCTFail("Expected an object result")
        }
        guard let rateLimitsValue = result["rateLimits"], case let .object(rateLimits) = rateLimitsValue else {
            return XCTFail("Expected rate limits object")
        }
        guard let usedPercentValue = rateLimits["usedPercent"], case let .number(usedPercent) = usedPercentValue else {
            return XCTFail("Expected numeric used percent")
        }
        XCTAssertEqual(usedPercent, 23)
        guard let itemsValue = result["items"], case let .array(items) = itemsValue else {
            return XCTFail("Expected array result")
        }
        XCTAssertEqual(items.count, 3)
        if case .bool(true) = items[0] {} else { XCTFail("Expected true") }
        if case .null = items[1] {} else { XCTFail("Expected null") }
        if case .string("ok") = items[2] {} else { XCTFail("Expected string") }
    }

    func testJSONRPCErrorDecodesCodeAndMessage() throws {
        let data = Data(#"{"jsonrpc":"2.0","id":7,"error":{"code":-32000,"message":"not authorized"}}"#.utf8)
        let envelope = try JSONDecoder().decode(JSONRPCEnvelope.self, from: data)

        XCTAssertEqual(envelope.error?.code, -32000)
        XCTAssertEqual(envelope.error?.message, "not authorized")
        XCTAssertNil(envelope.result)
    }

    func testDisplayWindowRemainingPercentIsClamped() {
        let overused = DisplayWindow(id: "high", name: "5 小时", usedPercent: 140, durationMinutes: 300, resetDate: nil)
        let negative = DisplayWindow(id: "low", name: "5 小时", usedPercent: -10, durationMinutes: 300, resetDate: nil)
        let normal = DisplayWindow(id: "normal", name: "5 小时", usedPercent: 35, durationMinutes: 300, resetDate: nil)

        XCTAssertEqual(overused.remainingPercent, 0)
        XCTAssertEqual(negative.remainingPercent, 100)
        XCTAssertEqual(normal.remainingPercent, 65)
    }

    func testWidgetSnapshotSelectsCodexAndWeeklyWindows() {
        let short = WidgetWindow(id: "short", name: "5 小时", usedPercent: 25, durationMinutes: 300, resetDate: nil)
        let weekly = WidgetWindow(id: "weekly", name: "每周", usedPercent: 40, durationMinutes: 10080, resetDate: nil)
        let other = WidgetLimit(id: "other", name: "Other", windows: [short])
        let codex = WidgetLimit(id: "codex", name: "Codex", windows: [short, weekly])
        let snapshot = WidgetSnapshot(
            planName: "Plus",
            limits: [other, codex],
            availableResetCount: nil,
            resetCredits: [],
            history: [],
            updatedAt: nil,
            statusMessage: "Data OK"
        )

        XCTAssertEqual(snapshot.primaryLimit?.id, "codex")
        XCTAssertEqual(snapshot.primaryWindow?.id, "short")
        XCTAssertEqual(snapshot.weeklyWindow?.id, "weekly")
    }

    func testEmptyWidgetSnapshotDoesNotInventLimits() {
        XCTAssertNil(WidgetSnapshot.empty.primaryLimit)
        XCTAssertNil(WidgetSnapshot.empty.primaryWindow)
        XCTAssertNil(WidgetSnapshot.empty.weeklyWindow)
        XCTAssertNil(WidgetSnapshot.empty.updatedAt)
    }

    func testWidgetSnapshotCodableRoundTripPreservesDatesAndOptionalFields() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = WidgetSnapshot(
            planName: "Pro",
            limits: [WidgetLimit(
                id: "codex",
                name: "Codex",
                windows: [WidgetWindow(id: "short", name: "5 小时", usedPercent: 12, durationMinutes: 300, resetDate: now.addingTimeInterval(3600))]
            )],
            availableResetCount: 2,
            resetCredits: [WidgetResetCredit(id: "r1", title: "Full reset", expiresAt: now.addingTimeInterval(7200))],
            history: [WidgetHistoryPoint(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, date: now, primaryRemaining: 88, weeklyRemaining: 60)],
            updatedAt: now,
            statusMessage: "Data OK",
            languageCode: AppLanguage.english.rawValue,
            appearance: WidgetAppearance.dark.rawValue,
            consumptionRatePerHour: 4.5,
            estimatedExhaustionAt: now.addingTimeInterval(10_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(WidgetSnapshot.self, from: encoder.encode(snapshot))

        XCTAssertEqual(decoded, snapshot)
    }

    func testWidgetSnapshotStoreSavesAndLoadsInjectedFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CodexMeterTests-\(UUID().uuidString)")
        let fileURL = directory.appendingPathComponent("widget-snapshot.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        let snapshot = WidgetSnapshot(
            planName: "Team",
            limits: [],
            availableResetCount: 1,
            resetCredits: [],
            history: [],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            statusMessage: "Data OK"
        )

        store.save(snapshot)

        XCTAssertEqual(store.fileURL, fileURL)
        XCTAssertEqual(store.load(), snapshot)
    }

    func testWidgetSnapshotWithoutTimestampIsStale() {
        XCTAssertTrue(WidgetSnapshot.empty.isStale(at: Date(timeIntervalSince1970: 1_700_000_000)))
    }

    func testWidgetSnapshotUsesThirtyMinuteStaleBoundary() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fresh = WidgetSnapshot(
            planName: "Plus", limits: [], availableResetCount: nil, resetCredits: [], history: [],
            updatedAt: now.addingTimeInterval(-1_800), statusMessage: "Data OK"
        )
        let stale = WidgetSnapshot(
            planName: "Plus", limits: [], availableResetCount: nil, resetCredits: [], history: [],
            updatedAt: now.addingTimeInterval(-1_801), statusMessage: "Data OK"
        )

        XCTAssertFalse(fresh.isStale(at: now))
        XCTAssertTrue(stale.isStale(at: now))
    }

    func testCLIJSONContainsQuotaResetAndTrendFields() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = WidgetSnapshot(
            planName: "Pro",
            limits: [WidgetLimit(
                id: "codex",
                name: "Codex",
                windows: [WidgetWindow(id: "short", name: "5 小时", usedPercent: 20, durationMinutes: 300, resetDate: now.addingTimeInterval(3600))]
            )],
            availableResetCount: 3,
            resetCredits: [WidgetResetCredit(id: "r1", title: "Full reset", expiresAt: now.addingTimeInterval(7200))],
            history: [],
            updatedAt: now,
            statusMessage: "Data OK",
            consumptionRatePerHour: 2.5,
            estimatedExhaustionAt: now.addingTimeInterval(100_000)
        )

        let output = CodexMeterStatusOutput(snapshot: snapshot, now: now)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: output.jsonData()) as? [String: Any])
        let limits = try XCTUnwrap(object["limits"] as? [[String: Any]])
        let firstLimit = try XCTUnwrap(limits.first)
        let windows = try XCTUnwrap(firstLimit["windows"] as? [[String: Any]])
        let resetCredits = try XCTUnwrap(object["resetCredits"] as? [[String: Any]])

        XCTAssertEqual(object["schemaVersion"] as? Int, WidgetSnapshot.currentSchemaVersion)
        XCTAssertEqual(object["plan"] as? String, "Pro")
        XCTAssertEqual(object["stale"] as? Bool, false)
        XCTAssertEqual(object["availableResetCount"] as? Int, 3)
        XCTAssertEqual(object["consumptionRatePerHour"] as? Double, 2.5)
        XCTAssertEqual(limits.first?["id"] as? String, "codex")
        XCTAssertEqual(windows.first?["remainingPercent"] as? Int, 80)
        XCTAssertEqual(resetCredits.first?["title"] as? String, "Full reset")
    }

    func testCLIJSONMarksOldSnapshotStale() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = WidgetSnapshot(
            planName: "Plus", limits: [], availableResetCount: nil, resetCredits: [], history: [],
            updatedAt: now.addingTimeInterval(-1_801), statusMessage: "Data OK"
        )

        let output = CodexMeterStatusOutput(snapshot: snapshot, now: now)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: output.jsonData()) as? [String: Any])

        XCTAssertEqual(object["stale"] as? Bool, true)
    }

    func testHistoryStoreAppendsAndReturnsChronologicalSamples() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CodexMeterHistoryTests-\(UUID().uuidString)")
        let store = HistoryStore(fileURL: directory.appendingPathComponent("history.json"))
        defer { try? FileManager.default.removeItem(at: directory) }
        let older = Date().addingTimeInterval(-120)
        let newer = Date().addingTimeInterval(-60)

        store.append(HistorySample(id: UUID(), date: newer, primaryRemaining: 70, weeklyRemaining: 80))
        store.append(HistorySample(id: UUID(), date: older, primaryRemaining: 75, weeklyRemaining: 82))
        let samples = store.load()

        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples.map(\.primaryRemaining), [75, 70])
        XCTAssertLessThanOrEqual(samples[0].date, samples[1].date)
    }

    func testHistoryStoreRemoveAllClearsInjectedFile() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CodexMeterHistoryTests-\(UUID().uuidString)")
        let store = HistoryStore(fileURL: directory.appendingPathComponent("history.json"))
        defer { try? FileManager.default.removeItem(at: directory) }

        store.append(HistorySample(id: UUID(), date: Date(), primaryRemaining: 90, weeklyRemaining: nil))
        XCTAssertEqual(store.load().count, 1)
        store.removeAll()

        XCTAssertTrue(store.load().isEmpty)
    }
}
