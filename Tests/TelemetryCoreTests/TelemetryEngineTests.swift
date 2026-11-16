import XCTest
@testable import TelemetryCore

@MainActor
final class TelemetryEngineTests: XCTestCase {
    var tempDirectory: URL!
    var userDefaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TelemetryEngineTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        userDefaults = UserDefaults(suiteName: "TelemetryEngineTests_\(UUID().uuidString)")!
    }

    override func tearDownWithError() throws {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        userDefaults = nil
        try super.tearDownWithError()
    }

    func testPaceEstCountdownAnchorsToEarliestTurnIn5hWindow() throws {
        // Create an isolated transcript file with a turn at t0
        let transcriptPath = tempDirectory.appendingPathComponent("transcript.jsonl").path
        let baseTime = Date(timeIntervalSince1970: 1700000000)
        let t0 = baseTime.addingTimeInterval(-3600) // 1 hour before baseTime

        let turnLine = """
        {"step_index":1,"type":"PLANNER_RESPONSE","created_at":"2023-11-14T21:13:20Z","input_tokens":1000,"cache_read_tokens":0,"output_tokens":100}\n
        """
        // We will test with a mock transcriptReader or test the helper directly
        let brainRoot = TranscriptReader.BrainRoot(path: tempDirectory.path, sourceLabel: "Desktop")
        let transcriptReader = TranscriptReader(brainRoots: [brainRoot], maxFileAgeDays: 30)

        // Write a conversation dir structure: <tempDirectory>/conv-1/.system_generated/logs/transcript.jsonl
        let convLogsDir = tempDirectory
            .appendingPathComponent("conv-1")
            .appendingPathComponent(".system_generated/logs")
        try FileManager.default.createDirectory(at: convLogsDir, withIntermediateDirectories: true)
        let fullTranscriptPath = convLogsDir.appendingPathComponent("transcript.jsonl").path

        let isoDateStr = ISO8601DateFormatter().string(from: t0)
        let lineJSON = """
        {"step_index":1,"type":"PLANNER_RESPONSE","created_at":"\(isoDateStr)","input_tokens":5000,"cache_read_tokens":0,"output_tokens":500}\n
        """
        try lineJSON.write(toFile: fullTranscriptPath, atomically: true, encoding: .utf8)

        let engine = TelemetryEngine(
            summaryReader: SQLiteSummaryReader(databaseSources: []),
            transcriptReader: transcriptReader,
            statusLineBridge: StatusLineBridge(snapshotPath: "/dev/null/none", settingsPath: "/dev/null/none"),
            userDefaults: userDefaults,
            autoRefreshOnInit: false
        )

        // First poll at t1 = baseTime
        let t1 = baseTime
        engine.refreshNow(now: t1)

        guard let quota1 = engine.snapshot.quotas.first(where: { $0.id == "frontier-pool" }) else {
            XCTFail("frontier-pool quota bucket missing")
            return
        }

        XCTAssertEqual(quota1.sourceBadge, "PACE EST.")
        XCTAssertNotNil(quota1.resetTime, "Expected anchored resetTime when turns exist")

        let expectedResetTime = t0.addingTimeInterval(5.0 * 3600.0)
        if let resetTime1 = quota1.resetTime {
            XCTAssertEqual(resetTime1.timeIntervalSince1970, expectedResetTime.timeIntervalSince1970, accuracy: 1.0)
        }

        // Second poll at t2 = baseTime + 60s
        let t2 = baseTime.addingTimeInterval(60.0)
        engine.refreshNow(now: t2)

        guard let quota2 = engine.snapshot.quotas.first(where: { $0.id == "frontier-pool" }) else {
            XCTFail("frontier-pool quota bucket missing on second poll")
            return
        }

        // resetTime MUST remain anchored to t0 + 5h (NOT reset to t2 + 5h!)
        XCTAssertEqual(quota2.resetTime?.timeIntervalSince1970 ?? 0, expectedResetTime.timeIntervalSince1970, accuracy: 1.0)

        // resetInSeconds MUST have decreased by ~60 seconds
        if let secs1 = quota1.resetInSeconds, let secs2 = quota2.resetInSeconds {
            XCTAssertEqual(secs1 - secs2, 60.0, accuracy: 2.0)
        }
    }

    func testPaceEstWithZeroTurnsHasNilResetTime() {
        let emptyReader = TranscriptReader(brainRoots: [], maxFileAgeDays: 30)
        let engine = TelemetryEngine(
            summaryReader: SQLiteSummaryReader(databaseSources: []),
            transcriptReader: emptyReader,
            statusLineBridge: StatusLineBridge(snapshotPath: "/dev/null/none", settingsPath: "/dev/null/none"),
            userDefaults: userDefaults,
            autoRefreshOnInit: false
        )

        engine.refreshNow(now: Date())

        let quota = engine.snapshot.quotas.first(where: { $0.id == "frontier-pool" })
        XCTAssertNotNil(quota)
        XCTAssertEqual(quota?.sourceBadge, "PACE EST.")
        XCTAssertNil(quota?.resetTime, "With zero turns in 5h, resetTime should be nil (READY)")
        XCTAssertNil(quota?.resetInSeconds, "With zero turns in 5h, resetInSeconds should be nil (READY)")
    }
}
