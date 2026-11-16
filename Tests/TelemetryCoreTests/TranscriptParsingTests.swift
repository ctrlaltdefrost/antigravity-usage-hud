import XCTest
@testable import TelemetryCore

final class TranscriptParsingTests: XCTestCase {
    var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TelemetryCoreTests_Transcript_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - Timestamp Parsing

    func testTimestampParsingFractionalSeconds() {
        // Standard ISO-8601 UTC
        let d1 = TimestampParser.parse("2026-11-15T19:30:00Z")
        XCTAssertNotNil(d1)

        // Fractional milliseconds (.123Z)
        let d2 = TimestampParser.parse("2026-11-15T19:30:00.123Z")
        XCTAssertNotNil(d2)
        XCTAssertEqual(d2!.timeIntervalSince(d1!), 0.123, accuracy: 0.001)

        // Fractional microseconds (.500000Z)
        let d3 = TimestampParser.parse("2026-11-15T19:30:00.500000Z")
        XCTAssertNotNil(d3)
        XCTAssertEqual(d3!.timeIntervalSince(d1!), 0.5, accuracy: 0.001)

        // Space separated (SQLite / log format)
        let d4 = TimestampParser.parse("2026-11-15 19:30:00")
        XCTAssertNotNil(d4)
        XCTAssertEqual(d4!.timeIntervalSince1970, d1!.timeIntervalSince1970, accuracy: 0.001)

        // Epoch string
        let d5 = TimestampParser.parse("1794771000")
        XCTAssertNotNil(d5)
        XCTAssertEqual(d5!.timeIntervalSince1970, 1794771000.0, accuracy: 0.001)

        // Invalid string
        let dInvalid = TimestampParser.parse("not-a-timestamp")
        XCTAssertNil(dInvalid)
    }

    // MARK: - Single Line Parsing

    func testParsePlannerResponseLine() {
        let json = """
        {"step_index":4,"type":"PLANNER_RESPONSE","created_at":"2026-11-15T19:32:54.250Z","input_tokens":1200,"cache_read_tokens":4500,"output_tokens":350}
        """
        let turn = TranscriptReader.parseLine(json, conversationId: "test-conv-1", source: "Desktop")
        XCTAssertNotNil(turn)
        XCTAssertEqual(turn?.conversationId, "test-conv-1")
        XCTAssertEqual(turn?.stepIndex, 4)
        XCTAssertEqual(turn?.inputTokens, 1200)
        XCTAssertEqual(turn?.cacheReadTokens, 4500)
        XCTAssertEqual(turn?.outputTokens, 350)
        XCTAssertEqual(turn?.directTokens, 1550) // 1200 + 350
        XCTAssertEqual(turn?.contextTokensEstimate, 6050) // 1200 + 4500 + 350
        XCTAssertEqual(turn?.source, "Desktop")
    }

    func testParseNonPlannerLineIgnored() {
        let userInput = """
        {"step_index":1,"type":"USER_INPUT","created_at":"2026-11-15T19:32:00Z","content":"Hello agent"}
        """
        let result = TranscriptReader.parseLine(userInput, conversationId: "test-conv-1", source: "Desktop")
        XCTAssertNil(result)

        let malformed = "{ this is not json }"
        XCTAssertNil(TranscriptReader.parseLine(malformed, conversationId: "c1"))
    }

    // MARK: - Incremental Byte-Offset Tailing

    func testIncrementalByteOffsetTailing() throws {
        let reader = TranscriptReader(brainRoots: [], maxFileAgeDays: 30)
        let filePath = tempDirectory.appendingPathComponent("transcript.jsonl").path

        let line1 = """
        {"step_index":1,"type":"PLANNER_RESPONSE","created_at":"2026-11-15T19:00:00Z","input_tokens":100,"cache_read_tokens":50,"output_tokens":25}
        \n
        """
        try line1.write(toFile: filePath, atomically: true, encoding: .utf8)

        // First read: reads line 1
        let turns1 = reader.readTranscriptFile(at: filePath, conversationId: "conv-1", source: "Desktop")
        XCTAssertEqual(turns1.count, 1)
        XCTAssertEqual(turns1[0].inputTokens, 100)

        let offsetAfter1 = reader.trackedByteOffset(forFileAt: filePath)
        XCTAssertNotNil(offsetAfter1)
        XCTAssertGreaterThan(offsetAfter1!, 0)

        // Read again without changes: returns cached turns without reading again
        let turnsNoChange = reader.readTranscriptFile(at: filePath, conversationId: "conv-1", source: "Desktop")
        XCTAssertEqual(turnsNoChange.count, 1)
        XCTAssertEqual(reader.trackedByteOffset(forFileAt: filePath), offsetAfter1)

        // Append line 2
        let line2 = """
        {"step_index":2,"type":"PLANNER_RESPONSE","created_at":"2026-11-15T19:05:00Z","input_tokens":200,"cache_read_tokens":100,"output_tokens":50}
        \n
        """
        let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: filePath))
        fileHandle.seekToEndOfFile()
        fileHandle.write(line2.data(using: .utf8)!)
        try fileHandle.close()

        // Second read: only parses new bytes
        let turns2 = reader.readTranscriptFile(at: filePath, conversationId: "conv-1", source: "Desktop")
        XCTAssertEqual(turns2.count, 2)
        XCTAssertEqual(turns2[1].inputTokens, 200)

        let offsetAfter2 = reader.trackedByteOffset(forFileAt: filePath)
        XCTAssertGreaterThan(offsetAfter2!, offsetAfter1!)
    }

    // MARK: - File Growth & Truncation Handling

    func testFileTruncationResetsOffset() throws {
        let reader = TranscriptReader(brainRoots: [], maxFileAgeDays: 30)
        let filePath = tempDirectory.appendingPathComponent("transcript_trunc.jsonl").path

        let bigContent = """
        {"step_index":1,"type":"PLANNER_RESPONSE","created_at":"2026-11-15T19:00:00Z","input_tokens":500,"cache_read_tokens":0,"output_tokens":50}
        {"step_index":2,"type":"PLANNER_RESPONSE","created_at":"2026-11-15T19:01:00Z","input_tokens":600,"cache_read_tokens":0,"output_tokens":60}
        \n
        """
        try bigContent.write(toFile: filePath, atomically: true, encoding: .utf8)

        let turnsInitial = reader.readTranscriptFile(at: filePath, conversationId: "conv-trunc", source: "Desktop")
        XCTAssertEqual(turnsInitial.count, 2)
        let initialOffset = reader.trackedByteOffset(forFileAt: filePath)!
        XCTAssertGreaterThan(initialOffset, 0)

        // Truncate file to a much shorter content (e.g. log rotated or rewritten)
        let truncatedContent = """
        {"step_index":1,"type":"PLANNER_RESPONSE","created_at":"2026-11-15T19:10:00Z","input_tokens":50,"cache_read_tokens":0,"output_tokens":10}
        \n
        """
        try truncatedContent.write(toFile: filePath, atomically: true, encoding: .utf8)

        // Read again: should detect fileSize < byteOffset, reset offset to 0, and parse the new line
        let turnsAfterTrunc = reader.readTranscriptFile(at: filePath, conversationId: "conv-trunc", source: "Desktop")
        XCTAssertEqual(turnsAfterTrunc.count, 1)
        XCTAssertEqual(turnsAfterTrunc[0].inputTokens, 50)
        XCTAssertEqual(turnsAfterTrunc[0].outputTokens, 10)
    }
}
