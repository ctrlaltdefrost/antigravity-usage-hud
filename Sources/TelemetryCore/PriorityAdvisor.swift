import Foundation

public enum PriorityAdvisor {
    public static func buildProjectSpends(
        summaries: [ConversationSummaryRecord],
        turns: [TurnRecord],
        pinnedProjectId: String?,
        now: Date = Date()
    ) -> [ProjectSpend] {
        let cutoff5h = now.addingTimeInterval(-5.0 * 3600.0)
        let cutoff24h = now.addingTimeInterval(-24.0 * 3600.0)
        let cutoff7d = now.addingTimeInterval(-7.0 * 24.0 * 3600.0)
        let futureTolerance = now.addingTimeInterval(60.0)

        var summaryById: [String: ConversationSummaryRecord] = [:]
        for summary in summaries {
            summaryById[summary.conversationId] = summary
        }

        func resolveWorkspace(for conversationId: String) -> WorkspaceInfo {
            if let summary = summaryById[conversationId] {
                if summary.projectName != WorkspaceInfo.unassigned.name {
                    return WorkspaceInfo(
                        id: summary.workspacePath,
                        name: summary.projectName,
                        workspacePath: summary.workspacePath
                    )
                }
                if let parentId = summary.parentConversationId,
                   let parent = summaryById[parentId],
                   parent.projectName != WorkspaceInfo.unassigned.name {
                    return WorkspaceInfo(
                        id: parent.workspacePath,
                        name: parent.projectName,
                        workspacePath: parent.workspacePath
                    )
                }
            }
            return .unassigned
        }

        struct Accumulator {
            var info: WorkspaceInfo
            var tokens5h: Int = 0
            var tokens24h: Int = 0
            var tokens7d: Int = 0
            var activeAgents: Int = 0
            var lastActive: Date = .distantPast
        }

        var accumulators: [String: Accumulator] = [:]

        for summary in summaries {
            let ws = resolveWorkspace(for: summary.conversationId)
            var acc = accumulators[ws.id] ?? Accumulator(info: ws)
            if summary.isRunning {
                acc.activeAgents += 1
            }
            if summary.lastModifiedTime > acc.lastActive {
                acc.lastActive = summary.lastModifiedTime
            }
            accumulators[ws.id] = acc
        }

        for turn in turns {
            guard turn.createdAt <= futureTolerance else { continue }
            let ws = resolveWorkspace(for: turn.conversationId)
            var acc = accumulators[ws.id] ?? Accumulator(info: ws)
            let tokens = turn.directTokens
            if turn.createdAt >= cutoff7d {
                acc.tokens7d += tokens
            }
            if turn.createdAt >= cutoff24h {
                acc.tokens24h += tokens
            }
            if turn.createdAt >= cutoff5h {
                acc.tokens5h += tokens
            }
            if turn.createdAt > acc.lastActive {
                acc.lastActive = turn.createdAt
            }
            accumulators[ws.id] = acc
        }

        let total5hAll = accumulators.values.reduce(0) { $0 + $1.tokens5h }

        var allProjects: [ProjectSpend] = accumulators.values.map { acc in
            let share = total5hAll > 0 ? Double(acc.tokens5h) / Double(total5hAll) : 0.0
            let isPinned = (pinnedProjectId != nil) && (acc.info.id == pinnedProjectId || acc.info.name == pinnedProjectId)
            return ProjectSpend(
                id: acc.info.id,
                name: acc.info.name,
                workspacePath: acc.info.workspacePath,
                tokens5h: acc.tokens5h,
                tokens24h: acc.tokens24h,
                tokens7d: acc.tokens7d,
                share5h: share,
                activeAgents: acc.activeAgents,
                lastActive: acc.lastActive,
                isPinned: isPinned
            )
        }

        allProjects.sort { lhs, rhs in
            if lhs.tokens5h != rhs.tokens5h { return lhs.tokens5h > rhs.tokens5h }
            if lhs.activeAgents != rhs.activeAgents { return lhs.activeAgents > rhs.activeAgents }
            if lhs.tokens24h != rhs.tokens24h { return lhs.tokens24h > rhs.tokens24h }
            if lhs.tokens7d != rhs.tokens7d { return lhs.tokens7d > rhs.tokens7d }
            return lhs.lastActive > rhs.lastActive
        }

        let activeOrRecent = allProjects.filter {
            $0.tokens7d > 0 || $0.activeAgents > 0 || $0.isPinned
        }

        if !activeOrRecent.isEmpty {
            return activeOrRecent
        }
        return Array(allProjects.prefix(6))
    }

    public static func buildActiveAgentPulses(
        summaries: [ConversationSummaryRecord],
        turns: [TurnRecord],
        latestTurnLookup: ((String) -> TurnRecord?)? = nil,
        limit: Int = 16
    ) -> [ActiveAgentPulse] {
        var latestTurnByConv: [String: TurnRecord] = [:]
        for turn in turns {
            if let existing = latestTurnByConv[turn.conversationId] {
                if turn.createdAt >= existing.createdAt {
                    latestTurnByConv[turn.conversationId] = turn
                }
            } else {
                latestTurnByConv[turn.conversationId] = turn
            }
        }

        let sortedSummaries = summaries.sorted { lhs, rhs in
            if lhs.isRunning != rhs.isRunning {
                return lhs.isRunning && !rhs.isRunning
            }
            return lhs.lastModifiedTime > rhs.lastModifiedTime
        }

        return sortedSummaries.prefix(limit).map { summary in
            let latestTurn = latestTurnByConv[summary.conversationId]
                ?? latestTurnLookup?(summary.conversationId)
            let latestTurnTokens = latestTurn?.directTokens ?? 0
            let contextEstimate = latestTurn?.contextTokensEstimate ?? 0
            let lastUpdated = max(summary.lastModifiedTime, latestTurn?.createdAt ?? .distantPast)

            return ActiveAgentPulse(
                id: summary.conversationId,
                title: summary.title,
                projectName: summary.projectName,
                source: summary.source,
                isRunning: summary.isRunning,
                isSubagent: summary.isSubagent,
                parentId: summary.parentConversationId,
                stepCount: summary.stepCount,
                latestTurnTokens: latestTurnTokens,
                contextTokensEstimate: contextEstimate,
                lastUpdated: lastUpdated
            )
        }
    }

    public static func evaluate(
        projects: [ProjectSpend],
        pinnedProjectId: String?,
        window5h: WindowMetrics,
        activeAgents: [ActiveAgentPulse],
        quotas: [QuotaBucketSnapshot],
        burnSurgeTokensPerMinuteThreshold: Double = 1500.0
    ) -> [PriorityAlert] {
        var alerts: [PriorityAlert] = []

        // 1. Priority Drift Detection: non-pinned project exceeding pinned priority project's 5h spend
        if let pinnedKey = pinnedProjectId, !pinnedKey.isEmpty {
            let pinnedProject = projects.first {
                $0.isPinned || $0.id == pinnedKey || $0.name == pinnedKey
            }
            let pinnedSpend = pinnedProject?.tokens5h ?? 0
            let pinnedName = pinnedProject?.name ?? pinnedKey

            if let topOutburning = projects
                .filter({ !$0.isPinned && $0.id != pinnedKey && $0.name != pinnedKey && $0.tokens5h > pinnedSpend && $0.tokens5h > 0 })
                .max(by: { $0.tokens5h < $1.tokens5h }) {
                let sharePct = Int((topOutburning.share5h * 100.0).rounded())
                alerts.append(
                    PriorityAlert(
                        id: "priority-drift",
                        severity: "warning",
                        title: "Priority Drift: \(topOutburning.name) Outburning \(pinnedName)",
                        detail: "\(topOutburning.name) consumed \(formatTokens(topOutburning.tokens5h)) (\(sharePct)% of 5h pool) vs \(formatTokens(pinnedSpend)) on pinned priority \(pinnedName)."
                    )
                )
            }
        }

        // 2. Low Calibrated / CLI Quota (<25%)
        for bucket in quotas where (bucket.sourceBadge == "LIVE CLI" || bucket.sourceBadge == "CALIBRATED") && bucket.remainingFraction < 0.25 {
            let pct = Int((bucket.remainingFraction * 100.0).rounded())
            let isCritical = bucket.remainingFraction < 0.10
            alerts.append(
                PriorityAlert(
                    id: "low-quota-\(bucket.id)",
                    severity: isCritical ? "critical" : "warning",
                    title: "\(isCritical ? "Critical" : "Low") Quota: \(bucket.label) (\(pct)%)",
                    detail: "\(bucket.label) is down to \(pct)% remaining (\(bucket.sourceBadge)). Reserve remaining budget for your pinned priority project."
                )
            )
        }

        // 3. 5h Burn Velocity Surge
        if window5h.tokensPerMinute >= burnSurgeTokensPerMinuteThreshold {
            let rate = Int(window5h.tokensPerMinute.rounded())
            alerts.append(
                PriorityAlert(
                    id: "burn-velocity-surge",
                    severity: "warning",
                    title: "High 5h Burn Velocity (\(formatTokens(rate))/min)",
                    detail: "Sustained burst of \(formatTokens(window5h.totalTokens)) in 5h. Consider offloading routine exploration or subagent passes to Flash / Medium tier."
                )
            )
        }

        // 4. Active Swarm / Multi-Agent Parallelism
        let runningAgents = activeAgents.filter { $0.isRunning }
        let runningSubagents = runningAgents.filter { $0.isSubagent }
        if runningAgents.count > 1 || !runningSubagents.isEmpty {
            alerts.append(
                PriorityAlert(
                    id: "active-swarm",
                    severity: "info",
                    title: "Active Swarm: \(runningAgents.count) Concurrent Agent\(runningAgents.count == 1 ? "" : "s")",
                    detail: "\(runningAgents.count) running session(s) (\(runningSubagents.count) subagent worker(s)) multiplying token throughput right now."
                )
            )
        }

        return alerts
    }

    private static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}
