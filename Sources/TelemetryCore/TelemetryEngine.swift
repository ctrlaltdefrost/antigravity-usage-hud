import Combine
import Foundation

@MainActor
public final class TelemetryEngine: ObservableObject {
    private static let pinnedProjectDefaultsKey = "com.antigravity.hud.pinnedProjectId"
    private static let calibratedQuotasDefaultsKey = "com.antigravity.hud.calibratedQuotas"

    @Published public private(set) var snapshot: TelemetrySnapshot
    @Published public private(set) var pinnedProjectId: String?
    @Published public private(set) var calibratedQuotas: [QuotaBucketSnapshot]

    public let summaryReader: SQLiteSummaryReader
    public let transcriptReader: TranscriptReader
    public let statusLineBridge: StatusLineBridge
    private let userDefaults: UserDefaults
    private var pollTimer: Timer?

    public init(
        summaryReader: SQLiteSummaryReader = SQLiteSummaryReader(),
        transcriptReader: TranscriptReader = TranscriptReader(),
        statusLineBridge: StatusLineBridge = StatusLineBridge(),
        userDefaults: UserDefaults = .standard,
        autoRefreshOnInit: Bool = true
    ) {
        self.summaryReader = summaryReader
        self.transcriptReader = transcriptReader
        self.statusLineBridge = statusLineBridge
        self.userDefaults = userDefaults

        self.pinnedProjectId = userDefaults.string(forKey: Self.pinnedProjectDefaultsKey)
        if let data = userDefaults.data(forKey: Self.calibratedQuotasDefaultsKey),
           let decoded = try? JSONDecoder().decode([QuotaBucketSnapshot].self, from: data) {
            self.calibratedQuotas = decoded
        } else {
            self.calibratedQuotas = []
        }

        self.snapshot = TelemetrySnapshot.empty()

        if autoRefreshOnInit {
            refreshNow()
        }
    }

    public func startPolling(interval: TimeInterval = 2.5) {
        stopPolling()
        refreshNow()
        let safeInterval = max(0.5, interval)
        pollTimer = Timer.scheduledTimer(withTimeInterval: safeInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshNow()
            }
        }
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    public func pinProject(_ id: String?) {
        let normalized = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalized, !normalized.isEmpty {
            pinnedProjectId = normalized
            userDefaults.set(normalized, forKey: Self.pinnedProjectDefaultsKey)
        } else {
            pinnedProjectId = nil
            userDefaults.removeObject(forKey: Self.pinnedProjectDefaultsKey)
        }
        refreshNow()
    }

    public func setCalibratedQuota(
        id: String,
        label: String,
        remainingFraction: Double,
        resetHours: Double
    ) {
        let now = Date()
        let clampedFraction = min(max(remainingFraction, 0.0), 1.0)
        let resetSecs = max(0.0, resetHours * 3600.0)
        let resetDate = now.addingTimeInterval(resetSecs)

        let updatedBucket = QuotaBucketSnapshot(
            id: id,
            label: label,
            remainingFraction: clampedFraction,
            resetTime: resetDate,
            resetInSeconds: resetSecs,
            sourceBadge: "CALIBRATED",
            lastUpdated: now
        )

        if let idx = calibratedQuotas.firstIndex(where: { $0.id == id }) {
            calibratedQuotas[idx] = updatedBucket
        } else {
            calibratedQuotas.append(updatedBucket)
        }

        persistCalibratedQuotas()
        refreshNow(now: now)
    }

    public func clearCalibratedQuotas() {
        calibratedQuotas.removeAll()
        userDefaults.removeObject(forKey: Self.calibratedQuotasDefaultsKey)
        refreshNow()
    }

    @discardableResult
    public func toggleCLIStatusLineHook() -> Bool {
        if statusLineBridge.isCLIStatusLineHookInstalled() {
            _ = try? statusLineBridge.uninstallCLIStatusLineHook()
        } else {
            _ = try? statusLineBridge.installCLIStatusLineHook()
        }
        let installed = statusLineBridge.isCLIStatusLineHookInstalled()
        refreshNow()
        return installed
    }

    public func refreshNow() {
        refreshNow(now: Date())
    }

    public func refreshNow(now: Date) {
        let summaries = summaryReader.readAllSummaries()
        let turns = transcriptReader.poll(now: now)

        let window5h = TranscriptReader.computeWindowMetrics(
            turns: turns,
            windowDuration: 5.0 * 3600.0,
            now: now
        )
        let window24h = TranscriptReader.computeWindowMetrics(
            turns: turns,
            windowDuration: 24.0 * 3600.0,
            now: now
        )
        let window7d = TranscriptReader.computeWindowMetrics(
            turns: turns,
            windowDuration: 7.0 * 24.0 * 3600.0,
            now: now
        )

        let projects = PriorityAdvisor.buildProjectSpends(
            summaries: summaries,
            turns: turns,
            pinnedProjectId: pinnedProjectId,
            now: now
        )

        let activeAgents = PriorityAdvisor.buildActiveAgentPulses(
            summaries: summaries,
            turns: turns,
            latestTurnLookup: { [transcriptReader] convId in
                transcriptReader.latestTurn(forConversationId: convId)
            }
        )

        let cliPayload = statusLineBridge.readSnapshot(now: now)
        let hookInstalled = statusLineBridge.isCLIStatusLineHookInstalled()

        let resolvedQuotas = buildResolvedQuotas(
            cliPayload: cliPayload,
            window5h: window5h,
            turns: turns,
            now: now
        )

        let alerts = PriorityAdvisor.evaluate(
            projects: projects,
            pinnedProjectId: pinnedProjectId,
            window5h: window5h,
            activeAgents: activeAgents,
            quotas: resolvedQuotas
        )

        snapshot = TelemetrySnapshot(
            generatedAt: now,
            window5h: window5h,
            window24h: window24h,
            window7d: window7d,
            projects: projects,
            activeAgents: activeAgents,
            quotas: resolvedQuotas,
            activeModelName: cliPayload?.modelDisplayName,
            cliAgentState: cliPayload?.agentState,
            cliContextUsedPercent: cliPayload?.contextUsedPercentage,
            alerts: alerts,
            pinnedProjectId: pinnedProjectId,
            hookInstalled: hookInstalled
        )
    }

    private func buildResolvedQuotas(
        cliPayload: StatusLinePayload?,
        window5h: WindowMetrics,
        turns: [TurnRecord],
        now: Date
    ) -> [QuotaBucketSnapshot] {
        var result: [QuotaBucketSnapshot] = []

        if let cliQuotas = cliPayload?.quotas, !cliQuotas.isEmpty {
            result.append(contentsOf: cliQuotas)
        }

        for calibrated in calibratedQuotas {
            if result.contains(where: { $0.id == calibrated.id }) {
                continue
            }
            var adjusted = calibrated
            if let resetTime = calibrated.resetTime {
                let remainingSecs = resetTime.timeIntervalSince(now)
                if remainingSecs <= 0 {
                    adjusted.remainingFraction = 1.0
                    adjusted.resetInSeconds = 0.0
                } else {
                    adjusted.resetInSeconds = remainingSecs
                }
            }
            result.append(adjusted)
        }

        if result.isEmpty {
            // Default estimated 5h rolling quota gauges when neither live CLI nor manual calibration is set yet
            let estimatedProBudget = 25_000_000.0
            let usedFraction = min(max(Double(window5h.totalTokens) / estimatedProBudget, 0.0), 0.85)
            let remaining = min(max(1.0 - usedFraction, 0.15), 1.0)

            let windowStart = now.addingTimeInterval(-5.0 * 3600.0)
            let futureTolerance = now.addingTimeInterval(60.0)
            let earliestTurnIn5h = turns
                .filter { $0.createdAt >= windowStart && $0.createdAt <= futureTolerance }
                .min(by: { $0.createdAt < $1.createdAt })

            let windowResetTime: Date?
            let resetSecs: TimeInterval?
            if let earliest = earliestTurnIn5h {
                let targetReset = earliest.createdAt.addingTimeInterval(5.0 * 3600.0)
                windowResetTime = targetReset
                resetSecs = max(0.0, targetReset.timeIntervalSince(now))
            } else {
                windowResetTime = nil
                resetSecs = nil
            }

            result.append(
                QuotaBucketSnapshot(
                    id: "frontier-pool",
                    label: "Frontier 5h",
                    remainingFraction: remaining,
                    resetTime: windowResetTime,
                    resetInSeconds: resetSecs,
                    sourceBadge: "PACE EST.",
                    lastUpdated: now
                )
            )
            result.append(
                QuotaBucketSnapshot(
                    id: "flash-pool",
                    label: "Flash 5h",
                    remainingFraction: min(1.0, remaining + 0.15),
                    resetTime: windowResetTime,
                    resetInSeconds: resetSecs,
                    sourceBadge: "PACE EST.",
                    lastUpdated: now
                )
            )
        }

        return result
    }

    private func persistCalibratedQuotas() {
        if let data = try? JSONEncoder().encode(calibratedQuotas) {
            userDefaults.set(data, forKey: Self.calibratedQuotasDefaultsKey)
        }
    }
}
