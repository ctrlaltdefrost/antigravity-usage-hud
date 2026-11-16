import XCTest
@testable import TelemetryCore

final class WindowMetricsTests: XCTestCase {

    func testRollingWindowFilteringAndTotals() {
        let referenceTime = Date(timeIntervalSince1970: 1700000000)

        let turns: [TurnRecord] = [
            // Inside 5h window (-2 hours)
            TurnRecord(
                conversationId: "c1",
                stepIndex: 1,
                createdAt: referenceTime.addingTimeInterval(-2.0 * 3600),
                inputTokens: 1000,
                cacheReadTokens: 4000,
                outputTokens: 200
            ),
            // Inside 24h window (-10 hours)
            TurnRecord(
                conversationId: "c2",
                stepIndex: 1,
                createdAt: referenceTime.addingTimeInterval(-10.0 * 3600),
                inputTokens: 2000,
                cacheReadTokens: 8000,
                outputTokens: 400
            ),
            // Inside 7d window (-3 days)
            TurnRecord(
                conversationId: "c3",
                stepIndex: 1,
                createdAt: referenceTime.addingTimeInterval(-3.0 * 24 * 3600),
                inputTokens: 5000,
                cacheReadTokens: 15000,
                outputTokens: 1000
            ),
            // Outside 7d window (-10 days)
            TurnRecord(
                conversationId: "c4",
                stepIndex: 1,
                createdAt: referenceTime.addingTimeInterval(-10.0 * 24 * 3600),
                inputTokens: 50000,
                cacheReadTokens: 50000,
                outputTokens: 10000
            )
        ]

        // 5h Window
        let m5h = TranscriptReader.computeWindowMetrics(
            turns: turns,
            windowDuration: 5.0 * 3600.0,
            now: referenceTime,
            bucketCount: 24
        )
        XCTAssertEqual(m5h.turnCount, 1)
        XCTAssertEqual(m5h.totalInputTokens, 1000)
        XCTAssertEqual(m5h.cacheReadTokens, 4000)
        XCTAssertEqual(m5h.outputTokens, 200)
        XCTAssertEqual(m5h.totalTokens, 1200)
        XCTAssertEqual(m5h.totalTokensIncludingCache, 5200)

        // Cache hit rate: 4000 / (1000 + 4000) = 80% (0.80)
        XCTAssertEqual(m5h.cacheHitRate, 0.80, accuracy: 0.001)

        // 24h Window
        let m24h = TranscriptReader.computeWindowMetrics(
            turns: turns,
            windowDuration: 24.0 * 3600.0,
            now: referenceTime,
            bucketCount: 24
        )
        XCTAssertEqual(m24h.turnCount, 2)
        XCTAssertEqual(m24h.totalInputTokens, 3000)
        XCTAssertEqual(m24h.cacheReadTokens, 12000)
        XCTAssertEqual(m24h.outputTokens, 600)
        // Cache hit rate: 12000 / (3000 + 12000) = 80%
        XCTAssertEqual(m24h.cacheHitRate, 0.80, accuracy: 0.001)

        // 7d Window
        let m7d = TranscriptReader.computeWindowMetrics(
            turns: turns,
            windowDuration: 7.0 * 24 * 3600.0,
            now: referenceTime,
            bucketCount: 24
        )
        XCTAssertEqual(m7d.turnCount, 3)
        XCTAssertEqual(m7d.totalInputTokens, 8000)
        XCTAssertEqual(m7d.cacheReadTokens, 27000)
        XCTAssertEqual(m7d.outputTokens, 1600)
        XCTAssertEqual(m7d.totalTokens, 9600)
    }

    func testSparklineBucketsCountAndPlacement() {
        let referenceTime = Date(timeIntervalSince1970: 1700000000)
        let windowDuration: TimeInterval = 24.0 * 3600.0 // 24 hours -> each bucket is 1 hour

        // Turn at exactly 12 hours ago (bucket index 12 of 24)
        let turn = TurnRecord(
            conversationId: "c1",
            stepIndex: 1,
            createdAt: referenceTime.addingTimeInterval(-11.5 * 3600), // ~12.5h after windowStart (windowStart is -24h)
            inputTokens: 500,
            cacheReadTokens: 0,
            outputTokens: 100
        )

        let metrics = TranscriptReader.computeWindowMetrics(
            turns: [turn],
            windowDuration: windowDuration,
            now: referenceTime,
            bucketCount: 24
        )

        XCTAssertEqual(metrics.sparklineBuckets.count, 24)
        let totalBucketTokens = metrics.sparklineBuckets.reduce(0.0, +)
        XCTAssertEqual(totalBucketTokens, 600.0, accuracy: 0.001) // directTokens = 500 + 100
    }

    func testEmptyWindowMetrics() {
        let empty = TranscriptReader.computeWindowMetrics(
            turns: [],
            windowDuration: 3600,
            now: Date(),
            bucketCount: 24
        )
        XCTAssertEqual(empty.turnCount, 0)
        XCTAssertEqual(empty.totalInputTokens, 0)
        XCTAssertEqual(empty.cacheReadTokens, 0)
        XCTAssertEqual(empty.outputTokens, 0)
        XCTAssertEqual(empty.cacheHitRate, 0.0)
        XCTAssertEqual(empty.tokensPerMinute, 0.0)
        XCTAssertEqual(empty.sparklineBuckets.count, 24)
        XCTAssertEqual(empty.estimatedEquivalentCostUSD, 0.0)
    }
}
