import XCTest
@testable import TelemetryCore

final class ProjectCostTests: XCTestCase {

    func testProjectSpendsCostAccurateAcrossRollingWindows() {
        let now = Date(timeIntervalSince1970: 1700000000)
        let convId = "conv-cost-test"

        let summary = ConversationSummaryRecord(
            conversationId: convId,
            title: "Cost Analytics Task",
            stepCount: 10,
            lastModifiedTime: now,
            workspaceUris: #"["file:///workspace/demo/QuantumEngine"]"#,
            projectName: "QuantumEngine",
            workspacePath: "/workspace/demo/QuantumEngine",
            status: "CASCADE_RUN_STATUS_IDLE",
            source: "Desktop",
            parentConversationId: nil,
            nestingDepth: 0,
            notFullyIdle: false,
            killed: false
        )

        // Turn 1: 1 hour ago (within 5h, 24h, 7d)
        // Cost: 1M * $3/1M + 10M * $0.30/1M + 100k * $15/1M = $3.00 + $3.00 + $1.50 = $7.50
        let turn1 = TurnRecord(
            conversationId: convId,
            stepIndex: 1,
            createdAt: now.addingTimeInterval(-1.0 * 3600.0),
            inputTokens: 1_000_000,
            cacheReadTokens: 10_000_000,
            outputTokens: 100_000
        )

        // Turn 2: 10 hours ago (within 24h, 7d, outside 5h)
        // Cost: 500k * $3/1M + 0 + 50k * $15/1M = $1.50 + $0.75 = $2.25
        let turn2 = TurnRecord(
            conversationId: convId,
            stepIndex: 2,
            createdAt: now.addingTimeInterval(-10.0 * 3600.0),
            inputTokens: 500_000,
            cacheReadTokens: 0,
            outputTokens: 50_000
        )

        // Turn 3: 3 days ago (within 7d, outside 24h, 5h)
        // Cost: 2M * $3/1M = $6.00
        let turn3 = TurnRecord(
            conversationId: convId,
            stepIndex: 3,
            createdAt: now.addingTimeInterval(-3.0 * 24.0 * 3600.0),
            inputTokens: 2_000_000,
            cacheReadTokens: 0,
            outputTokens: 0
        )

        let projects = PriorityAdvisor.buildProjectSpends(
            summaries: [summary],
            turns: [turn1, turn2, turn3],
            pinnedProjectId: nil,
            now: now
        )

        XCTAssertEqual(projects.count, 1)
        guard let p = projects.first else { return }

        XCTAssertEqual(p.name, "QuantumEngine")
        XCTAssertEqual(p.cost5h, 7.50, accuracy: 0.001)
        XCTAssertEqual(p.cost24h, 9.75, accuracy: 0.001) // 7.50 + 2.25
        XCTAssertEqual(p.cost7d, 15.75, accuracy: 0.001) // 9.75 + 6.00
    }
}
