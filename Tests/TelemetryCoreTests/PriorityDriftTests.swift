import XCTest
@testable import TelemetryCore

final class PriorityDriftTests: XCTestCase {

    func testPriorityDriftDetectedWhenUnpinnedOutburnsPinned() {
        let pinnedProject = ProjectSpend(
            id: "/workspace/projects/PinnedProject",
            name: "PinnedProject",
            workspacePath: "/workspace/projects/PinnedProject",
            tokens5h: 5_000,
            tokens24h: 15_000,
            tokens7d: 50_000,
            share5h: 0.10,
            activeAgents: 1,
            lastActive: Date(),
            isPinned: true
        )

        let rogueProject = ProjectSpend(
            id: "/workspace/projects/RogueProject",
            name: "RogueProject",
            workspacePath: "/workspace/projects/RogueProject",
            tokens5h: 45_000,
            tokens24h: 60_000,
            tokens7d: 100_000,
            share5h: 0.90,
            activeAgents: 2,
            lastActive: Date(),
            isPinned: false
        )

        let projects = [rogueProject, pinnedProject]
        let alerts = PriorityAdvisor.evaluate(
            projects: projects,
            pinnedProjectId: pinnedProject.id,
            window5h: .empty,
            activeAgents: [],
            quotas: []
        )

        let driftAlert = alerts.first { $0.id == "priority-drift" }
        XCTAssertNotNil(driftAlert, "Expected priority-drift alert when unpinned project outburns pinned project")
        XCTAssertEqual(driftAlert?.severity, "warning")
        XCTAssertTrue(driftAlert?.title.contains("RogueProject Outburning PinnedProject") == true)
        XCTAssertTrue(driftAlert?.detail.contains("45.0K") == true)
    }

    func testNoPriorityDriftWhenPinnedProjectIsTopSpender() {
        let pinnedProject = ProjectSpend(
            id: "/workspace/projects/PinnedProject",
            name: "PinnedProject",
            workspacePath: "/workspace/projects/PinnedProject",
            tokens5h: 50_000,
            tokens24h: 100_000,
            tokens7d: 200_000,
            share5h: 0.85,
            activeAgents: 1,
            lastActive: Date(),
            isPinned: true
        )

        let minorProject = ProjectSpend(
            id: "/workspace/projects/MinorProject",
            name: "MinorProject",
            workspacePath: "/workspace/projects/MinorProject",
            tokens5h: 8_000,
            tokens24h: 15_000,
            tokens7d: 20_000,
            share5h: 0.15,
            activeAgents: 0,
            lastActive: Date(),
            isPinned: false
        )

        let projects = [pinnedProject, minorProject]
        let alerts = PriorityAdvisor.evaluate(
            projects: projects,
            pinnedProjectId: pinnedProject.id,
            window5h: .empty,
            activeAgents: [],
            quotas: []
        )

        let driftAlert = alerts.first { $0.id == "priority-drift" }
        XCTAssertNil(driftAlert, "Should NOT trigger priority drift when pinned project is highest spender")
    }

    func testNoPriorityDriftWhenNoProjectIsPinned() {
        let p1 = ProjectSpend(
            id: "p1", name: "P1", workspacePath: "/workspace/p1",
            tokens5h: 50_000, tokens24h: 50_000, tokens7d: 50_000,
            share5h: 0.70, activeAgents: 1, lastActive: Date(), isPinned: false
        )
        let p2 = ProjectSpend(
            id: "p2", name: "P2", workspacePath: "/workspace/p2",
            tokens5h: 20_000, tokens24h: 20_000, tokens7d: 20_000,
            share5h: 0.30, activeAgents: 0, lastActive: Date(), isPinned: false
        )

        let alerts = PriorityAdvisor.evaluate(
            projects: [p1, p2],
            pinnedProjectId: nil,
            window5h: .empty,
            activeAgents: [],
            quotas: []
        )

        XCTAssertNil(alerts.first { $0.id == "priority-drift" })
    }

    func testLowQuotaAlerts() {
        let warningQuota = QuotaBucketSnapshot(
            id: "gemini-pro",
            label: "Gemini Pro",
            remainingFraction: 0.20, // 20% -> warning (<25%)
            resetTime: nil,
            resetInSeconds: 3600,
            sourceBadge: "LIVE CLI",
            lastUpdated: Date()
        )

        let criticalQuota = QuotaBucketSnapshot(
            id: "gemini-flash",
            label: "Gemini Flash",
            remainingFraction: 0.05, // 5% -> critical (<10%)
            resetTime: nil,
            resetInSeconds: 1800,
            sourceBadge: "CALIBRATED",
            lastUpdated: Date()
        )

        let healthyQuota = QuotaBucketSnapshot(
            id: "claude",
            label: "Claude",
            remainingFraction: 0.85,
            resetTime: nil,
            resetInSeconds: nil,
            sourceBadge: "CALIBRATED",
            lastUpdated: Date()
        )

        let alerts = PriorityAdvisor.evaluate(
            projects: [],
            pinnedProjectId: nil,
            window5h: .empty,
            activeAgents: [],
            quotas: [warningQuota, criticalQuota, healthyQuota]
        )

        let warnAlert = alerts.first { $0.id == "low-quota-gemini-pro" }
        XCTAssertNotNil(warnAlert)
        XCTAssertEqual(warnAlert?.severity, "warning")

        let critAlert = alerts.first { $0.id == "low-quota-gemini-flash" }
        XCTAssertNotNil(critAlert)
        XCTAssertEqual(critAlert?.severity, "critical")

        XCTAssertNil(alerts.first { $0.id == "low-quota-claude" })
    }

    func testPaceEstQuotaDoesNotEmitFalseLowQuotaAlerts() {
        let paceEstQuota = QuotaBucketSnapshot(
            id: "frontier-5h",
            label: "Frontier 5h",
            remainingFraction: 0.05, // 5% remaining
            resetTime: nil,
            resetInSeconds: 1800,
            sourceBadge: "PACE EST.",
            lastUpdated: Date()
        )

        let calibratedQuota = QuotaBucketSnapshot(
            id: "calibrated-5h",
            label: "Calibrated 5h",
            remainingFraction: 0.05, // 5% remaining
            resetTime: nil,
            resetInSeconds: 1800,
            sourceBadge: "CALIBRATED",
            lastUpdated: Date()
        )

        let liveCLIQuota = QuotaBucketSnapshot(
            id: "live-cli-5h",
            label: "Live CLI 5h",
            remainingFraction: 0.08, // 8% remaining
            resetTime: nil,
            resetInSeconds: 900,
            sourceBadge: "LIVE CLI",
            lastUpdated: Date()
        )

        let alerts = PriorityAdvisor.evaluate(
            projects: [],
            pinnedProjectId: nil,
            window5h: .empty,
            activeAgents: [],
            quotas: [paceEstQuota, calibratedQuota, liveCLIQuota]
        )

        // PACE EST. must NOT emit alert
        XCTAssertNil(alerts.first { $0.id == "low-quota-frontier-5h" }, "PACE EST. fallback must never emit false low-quota alerts")

        // CALIBRATED MUST emit alert
        let calAlert = alerts.first { $0.id == "low-quota-calibrated-5h" }
        XCTAssertNotNil(calAlert, "CALIBRATED bucket below threshold must emit alert")
        XCTAssertEqual(calAlert?.severity, "critical")

        // LIVE CLI MUST emit alert
        let cliAlert = alerts.first { $0.id == "low-quota-live-cli-5h" }
        XCTAssertNotNil(cliAlert, "LIVE CLI bucket below threshold must emit alert")
        XCTAssertEqual(cliAlert?.severity, "critical")
    }

    func testBurnVelocitySurgeAlert() {
        var highMetrics = WindowMetrics.empty
        highMetrics.tokensPerMinute = 2500.0 // Threshold default is 1500
        highMetrics.totalInputTokens = 500_000
        highMetrics.outputTokens = 25_000

        let alerts = PriorityAdvisor.evaluate(
            projects: [],
            pinnedProjectId: nil,
            window5h: highMetrics,
            activeAgents: [],
            quotas: []
        )

        let surgeAlert = alerts.first { $0.id == "burn-velocity-surge" }
        XCTAssertNotNil(surgeAlert)
        XCTAssertEqual(surgeAlert?.severity, "warning")
    }

    func testActiveSwarmAlert() {
        let agent1 = ActiveAgentPulse(
            id: "a1", title: "Coordinator", projectName: "Proj", source: "Desktop",
            isRunning: true, isSubagent: false, parentId: nil, stepCount: 5,
            latestTurnTokens: 100, contextTokensEstimate: 1000, lastUpdated: Date()
        )
        let agent2 = ActiveAgentPulse(
            id: "a2", title: "Worker 1", projectName: "Proj", source: "Desktop",
            isRunning: true, isSubagent: true, parentId: "a1", stepCount: 2,
            latestTurnTokens: 50, contextTokensEstimate: 500, lastUpdated: Date()
        )

        let alerts = PriorityAdvisor.evaluate(
            projects: [],
            pinnedProjectId: nil,
            window5h: .empty,
            activeAgents: [agent1, agent2],
            quotas: []
        )

        let swarmAlert = alerts.first { $0.id == "active-swarm" }
        XCTAssertNotNil(swarmAlert)
        XCTAssertEqual(swarmAlert?.severity, "info")
    }
}
