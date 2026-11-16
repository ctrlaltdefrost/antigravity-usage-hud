import Foundation

public struct WindowMetrics: Sendable, Codable, Equatable {
    public var totalInputTokens: Int
    public var cacheReadTokens: Int
    public var outputTokens: Int
    public var turnCount: Int
    public var tokensPerMinute: Double
    public var cacheHitRate: Double
    public var estimatedEquivalentCostUSD: Double
    public var sparklineBuckets: [Double]

    public var totalTokens: Int {
        totalInputTokens + outputTokens
    }

    public var totalTokensIncludingCache: Int {
        totalInputTokens + cacheReadTokens + outputTokens
    }

    public init(
        totalInputTokens: Int,
        cacheReadTokens: Int,
        outputTokens: Int,
        turnCount: Int,
        tokensPerMinute: Double,
        cacheHitRate: Double,
        estimatedEquivalentCostUSD: Double,
        sparklineBuckets: [Double]
    ) {
        self.totalInputTokens = totalInputTokens
        self.cacheReadTokens = cacheReadTokens
        self.outputTokens = outputTokens
        self.turnCount = turnCount
        self.tokensPerMinute = tokensPerMinute
        self.cacheHitRate = min(max(cacheHitRate, 0.0), 1.0)
        self.estimatedEquivalentCostUSD = estimatedEquivalentCostUSD
        if sparklineBuckets.count == 24 {
            self.sparklineBuckets = sparklineBuckets
        } else if sparklineBuckets.count > 24 {
            self.sparklineBuckets = Array(sparklineBuckets.suffix(24))
        } else {
            self.sparklineBuckets = sparklineBuckets + Array(repeating: 0.0, count: 24 - sparklineBuckets.count)
        }
    }

    public static let empty = WindowMetrics(
        totalInputTokens: 0,
        cacheReadTokens: 0,
        outputTokens: 0,
        turnCount: 0,
        tokensPerMinute: 0.0,
        cacheHitRate: 0.0,
        estimatedEquivalentCostUSD: 0.0,
        sparklineBuckets: Array(repeating: 0.0, count: 24)
    )
}

public struct ProjectSpend: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var workspacePath: String
    public var tokens5h: Int
    public var tokens24h: Int
    public var tokens7d: Int
    public var cost5h: Double
    public var cost24h: Double
    public var cost7d: Double
    public var share5h: Double
    public var activeAgents: Int
    public var lastActive: Date
    public var isPinned: Bool

    public init(
        id: String,
        name: String,
        workspacePath: String,
        tokens5h: Int,
        tokens24h: Int,
        tokens7d: Int,
        cost5h: Double = 0.0,
        cost24h: Double = 0.0,
        cost7d: Double = 0.0,
        share5h: Double,
        activeAgents: Int,
        lastActive: Date,
        isPinned: Bool
    ) {
        self.id = id
        self.name = name
        self.workspacePath = workspacePath
        self.tokens5h = tokens5h
        self.tokens24h = tokens24h
        self.tokens7d = tokens7d
        self.cost5h = cost5h
        self.cost24h = cost24h
        self.cost7d = cost7d
        self.share5h = min(max(share5h, 0.0), 1.0)
        self.activeAgents = activeAgents
        self.lastActive = lastActive
        self.isPinned = isPinned
    }
}

public struct ActiveAgentPulse: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var projectName: String
    public var source: String // "Desktop" | "CLI"
    public var isRunning: Bool
    public var isSubagent: Bool
    public var parentId: String?
    public var stepCount: Int
    public var latestTurnTokens: Int
    public var contextTokensEstimate: Int
    public var lastUpdated: Date

    public init(
        id: String,
        title: String,
        projectName: String,
        source: String,
        isRunning: Bool,
        isSubagent: Bool,
        parentId: String?,
        stepCount: Int,
        latestTurnTokens: Int,
        contextTokensEstimate: Int,
        lastUpdated: Date
    ) {
        self.id = id
        self.title = title
        self.projectName = projectName
        self.source = source
        self.isRunning = isRunning
        self.isSubagent = isSubagent
        self.parentId = parentId
        self.stepCount = stepCount
        self.latestTurnTokens = latestTurnTokens
        self.contextTokensEstimate = contextTokensEstimate
        self.lastUpdated = lastUpdated
    }
}

public struct QuotaBucketSnapshot: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var remainingFraction: Double // 0..1
    public var resetTime: Date?
    public var resetInSeconds: TimeInterval?
    public var sourceBadge: String // "LIVE CLI" | "CALIBRATED"
    public var lastUpdated: Date

    public init(
        id: String,
        label: String,
        remainingFraction: Double,
        resetTime: Date?,
        resetInSeconds: TimeInterval?,
        sourceBadge: String,
        lastUpdated: Date
    ) {
        self.id = id
        self.label = label
        self.remainingFraction = min(max(remainingFraction, 0.0), 1.0)
        self.resetTime = resetTime
        self.resetInSeconds = resetInSeconds
        self.sourceBadge = sourceBadge
        self.lastUpdated = lastUpdated
    }
}

public struct PriorityAlert: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var severity: String // "info" | "warning" | "critical"
    public var title: String
    public var detail: String

    public init(
        id: String,
        severity: String,
        title: String,
        detail: String
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
    }
}

public struct TelemetrySnapshot: Sendable, Codable, Equatable {
    public var generatedAt: Date
    public var window5h: WindowMetrics
    public var window24h: WindowMetrics
    public var window7d: WindowMetrics
    public var projects: [ProjectSpend]
    public var activeAgents: [ActiveAgentPulse]
    public var quotas: [QuotaBucketSnapshot]
    public var activeModelName: String?
    public var cliAgentState: String?
    public var cliContextUsedPercent: Double?
    public var planTier: String?
    public var alerts: [PriorityAlert]
    public var pinnedProjectId: String?
    public var hookInstalled: Bool

    public init(
        generatedAt: Date,
        window5h: WindowMetrics,
        window24h: WindowMetrics,
        window7d: WindowMetrics,
        projects: [ProjectSpend],
        activeAgents: [ActiveAgentPulse],
        quotas: [QuotaBucketSnapshot],
        activeModelName: String?,
        cliAgentState: String?,
        cliContextUsedPercent: Double?,
        planTier: String? = nil,
        alerts: [PriorityAlert],
        pinnedProjectId: String?,
        hookInstalled: Bool
    ) {
        self.generatedAt = generatedAt
        self.window5h = window5h
        self.window24h = window24h
        self.window7d = window7d
        self.projects = projects
        self.activeAgents = activeAgents
        self.quotas = quotas
        self.activeModelName = activeModelName
        self.cliAgentState = cliAgentState
        self.cliContextUsedPercent = cliContextUsedPercent
        self.planTier = planTier
        self.alerts = alerts
        self.pinnedProjectId = pinnedProjectId
        self.hookInstalled = hookInstalled
    }

    public static func empty(now: Date = Date()) -> TelemetrySnapshot {
        TelemetrySnapshot(
            generatedAt: now,
            window5h: .empty,
            window24h: .empty,
            window7d: .empty,
            projects: [],
            activeAgents: [],
            quotas: [],
            activeModelName: nil,
            cliAgentState: nil,
            cliContextUsedPercent: nil,
            planTier: nil,
            alerts: [],
            pinnedProjectId: nil,
            hookInstalled: false
        )
    }
}

public struct TurnRecord: Sendable, Codable, Equatable {
    public var conversationId: String
    public var stepIndex: Int
    public var createdAt: Date
    public var inputTokens: Int
    public var cacheReadTokens: Int
    public var outputTokens: Int
    public var source: String

    public var directTokens: Int {
        inputTokens + outputTokens
    }

    public var contextTokensEstimate: Int {
        inputTokens + cacheReadTokens + outputTokens
    }

    public init(
        conversationId: String,
        stepIndex: Int = 0,
        createdAt: Date,
        inputTokens: Int,
        cacheReadTokens: Int,
        outputTokens: Int,
        source: String = "Desktop"
    ) {
        self.conversationId = conversationId
        self.stepIndex = stepIndex
        self.createdAt = createdAt
        self.inputTokens = inputTokens
        self.cacheReadTokens = cacheReadTokens
        self.outputTokens = outputTokens
        self.source = source
    }
}

public struct WorkspaceInfo: Sendable, Codable, Equatable {
    public var id: String
    public var name: String
    public var workspacePath: String

    public init(id: String, name: String, workspacePath: String) {
        self.id = id
        self.name = name
        self.workspacePath = workspacePath
    }

    public static let unassigned = WorkspaceInfo(
        id: "General / Unassigned",
        name: "General / Unassigned",
        workspacePath: "General / Unassigned"
    )
}

public struct ConversationSummaryRecord: Sendable, Codable, Equatable, Identifiable {
    public var id: String { conversationId }
    public var conversationId: String
    public var title: String
    public var stepCount: Int
    public var lastModifiedTime: Date
    public var workspaceUris: String
    public var projectName: String
    public var workspacePath: String
    public var status: String
    public var source: String // "Desktop" | "CLI"
    public var parentConversationId: String?
    public var nestingDepth: Int
    public var notFullyIdle: Bool
    public var killed: Bool

    public var isRunning: Bool {
        if killed { return false }
        return status == "CASCADE_RUN_STATUS_RUNNING" || status.localizedCaseInsensitiveContains("RUNNING")
    }

    public var isSubagent: Bool {
        if let parent = parentConversationId, !parent.isEmpty {
            return true
        }
        return nestingDepth > 0
    }

    public init(
        conversationId: String,
        title: String,
        stepCount: Int,
        lastModifiedTime: Date,
        workspaceUris: String,
        projectName: String,
        workspacePath: String,
        status: String,
        source: String,
        parentConversationId: String?,
        nestingDepth: Int,
        notFullyIdle: Bool,
        killed: Bool
    ) {
        self.conversationId = conversationId
        self.title = title
        self.stepCount = stepCount
        self.lastModifiedTime = lastModifiedTime
        self.workspaceUris = workspaceUris
        self.projectName = projectName
        self.workspacePath = workspacePath
        self.status = status
        self.source = source
        self.parentConversationId = parentConversationId
        self.nestingDepth = nestingDepth
        self.notFullyIdle = notFullyIdle
        self.killed = killed
    }
}
