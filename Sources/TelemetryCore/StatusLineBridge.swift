import Foundation

public struct StatusLinePayload: Sendable, Codable, Equatable {
    public var modelDisplayName: String?
    public var agentState: String?
    public var contextUsedPercentage: Double?
    public var planTier: String?
    public var quotas: [QuotaBucketSnapshot]
    public var hasFreshQuotaPayload: Bool
    public var lastUpdated: Date

    public init(
        modelDisplayName: String?,
        agentState: String?,
        contextUsedPercentage: Double?,
        planTier: String? = nil,
        quotas: [QuotaBucketSnapshot],
        hasFreshQuotaPayload: Bool? = nil,
        lastUpdated: Date
    ) {
        self.modelDisplayName = modelDisplayName
        self.agentState = agentState
        self.contextUsedPercentage = contextUsedPercentage
        self.planTier = planTier
        self.quotas = quotas
        self.hasFreshQuotaPayload = hasFreshQuotaPayload ?? !quotas.isEmpty
        self.lastUpdated = lastUpdated
    }
}

public final class StatusLineBridge: @unchecked Sendable {
    public static let backupStatusLineKey = "_antigravity_hud_backup_statusLine"

    public let snapshotPath: String
    public let settingsPath: String
    public let hookScriptPath: String

    public init(
        snapshotPath: String? = nil,
        settingsPath: String? = nil,
        hookScriptPath: String? = nil
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.snapshotPath = snapshotPath
            ?? (home as NSString).appendingPathComponent(".gemini/antigravity-hud/statusline_snapshot.json")
        self.settingsPath = settingsPath
            ?? (home as NSString).appendingPathComponent(".gemini/antigravity-cli/settings.json")
        self.hookScriptPath = hookScriptPath
            ?? Self.resolveDefaultHookScriptPath(home: home)
    }

    private static func resolveDefaultHookScriptPath(home: String) -> String {
        return (home as NSString).appendingPathComponent(".gemini/antigravity-hud/agy-hud-hook.sh")
    }

    public func readSnapshot(now: Date = Date()) -> StatusLinePayload? {
        guard FileManager.default.fileExists(atPath: snapshotPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: snapshotPath)) else {
            return nil
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: snapshotPath)
        let mtime = (attrs?[.modificationDate] as? Date) ?? now
        return Self.parseStatusLineData(data, fileModifiedAt: mtime, now: now)
    }

    public static func parseStatusLineJSON(
        _ jsonString: String,
        fileModifiedAt: Date = Date(),
        now: Date = Date()
    ) -> StatusLinePayload? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return parseStatusLineData(data, fileModifiedAt: fileModifiedAt, now: now)
    }

    public static func parseStatusLineData(
        _ data: Data,
        fileModifiedAt: Date = Date(),
        now: Date = Date()
    ) -> StatusLinePayload? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var rawModelDisplayName: String?
        if let modelDict = root["model"] as? [String: Any] {
            rawModelDisplayName = (modelDict["display_name"] as? String)
                ?? (modelDict["name"] as? String)
                ?? (modelDict["id"] as? String)
        } else if let modelStr = root["model"] as? String {
            rawModelDisplayName = modelStr
        }

        let agentState = (root["agent_state"] as? String)
            ?? (root["state"] as? String)
            ?? (root["status"] as? String)

        let rawPlanTier = ((root["plan_tier"] as? String) ?? (root["planTier"] as? String))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let planTier: String? = (rawPlanTier?.isEmpty == false) ? rawPlanTier : nil

        var rawContextUsedPercentage: Double?
        if let ctxDict = root["context_window"] as? [String: Any] {
            rawContextUsedPercentage = doubleValue(ctxDict["used_percentage"])
                ?? doubleValue(ctxDict["used_percent"])
        }

        let isInitializing = agentState?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "initializing"
        let modelDisplayName: String? = isInitializing ? nil : rawModelDisplayName
        let contextUsedPercentage: Double? = isInitializing ? nil : rawContextUsedPercentage

        var quotas: [QuotaBucketSnapshot] = []
        if let quotaDict = root["quota"] as? [String: Any] {
            if quotaDict["remaining_fraction"] != nil || quotaDict["remainingFraction"] != nil {
                let id = (quotaDict["id"] as? String) ?? "cli-quota"
                if let snap = parseSingleQuotaBucket(
                    id: id,
                    defaultLabel: (quotaDict["label"] as? String) ?? rawModelDisplayName ?? displayLabel(forBucketId: id),
                    dict: quotaDict,
                    fileModifiedAt: fileModifiedAt,
                    now: now
                ) {
                    quotas.append(snap)
                }
            } else if let bucketsArray = quotaDict["buckets"] as? [[String: Any]] {
                for (index, item) in bucketsArray.enumerated() {
                    let id = (item["id"] as? String) ?? "cli-quota-\(index)"
                    let label = (item["label"] as? String) ?? (item["name"] as? String) ?? displayLabel(forBucketId: id)
                    if let snap = parseSingleQuotaBucket(
                        id: id,
                        defaultLabel: label,
                        dict: item,
                        fileModifiedAt: fileModifiedAt,
                        now: now
                    ) {
                        quotas.append(snap)
                    }
                }
            } else {
                let sortedKeys = quotaDict.keys.sorted { lhs, rhs in
                    let pL = priorityRank(forBucketId: lhs)
                    let pR = priorityRank(forBucketId: rhs)
                    if pL != pR { return pL < pR }
                    return lhs < rhs
                }
                for key in sortedKeys {
                    if let subDict = quotaDict[key] as? [String: Any],
                       let snap = parseSingleQuotaBucket(
                           id: key,
                           defaultLabel: (subDict["label"] as? String) ?? displayLabel(forBucketId: key),
                           dict: subDict,
                           fileModifiedAt: fileModifiedAt,
                           now: now
                       ) {
                        quotas.append(snap)
                    }
                }
            }
        } else if let quotaArray = root["quota"] as? [[String: Any]] {
            for (index, item) in quotaArray.enumerated() {
                let id = (item["id"] as? String) ?? "cli-quota-\(index)"
                let label = (item["label"] as? String) ?? displayLabel(forBucketId: id)
                if let snap = parseSingleQuotaBucket(
                    id: id,
                    defaultLabel: label,
                    dict: item,
                    fileModifiedAt: fileModifiedAt,
                    now: now
                ) {
                    quotas.append(snap)
                }
            }
        }

        let explicitFreshFlag = root["_has_live_quota"] as? Bool
        let hasFreshQuota = !quotas.isEmpty && (explicitFreshFlag ?? true)

        return StatusLinePayload(
            modelDisplayName: modelDisplayName,
            agentState: agentState,
            contextUsedPercentage: contextUsedPercentage,
            planTier: planTier,
            quotas: quotas,
            hasFreshQuotaPayload: hasFreshQuota,
            lastUpdated: fileModifiedAt
        )
    }

    public static func displayLabel(forBucketId id: String) -> String {
        switch id.lowercased() {
        case "gemini-5h":
            return "Gemini 5h"
        case "gemini-weekly":
            return "Gemini Wk"
        case "3p-5h":
            return "Claude/3P 5h"
        case "3p-weekly":
            return "Claude/3P Wk"
        default:
            return id
        }
    }

    public static func priorityRank(forBucketId id: String) -> Int {
        switch id.lowercased() {
        case "gemini-5h":
            return 0
        case "gemini-weekly":
            return 1
        case "3p-5h":
            return 2
        case "3p-weekly":
            return 3
        default:
            return 100
        }
    }

    private static func parseSingleQuotaBucket(
        id: String,
        defaultLabel: String,
        dict: [String: Any],
        fileModifiedAt: Date,
        now: Date
    ) -> QuotaBucketSnapshot? {
        guard let rem = doubleValue(dict["remaining_fraction"]) ?? doubleValue(dict["remainingFraction"]) else {
            return nil
        }

        let label = (dict["label"] as? String) ?? (dict["display_name"] as? String) ?? defaultLabel

        var resetTime: Date?
        if let resetStr = (dict["reset_time"] as? String) ?? (dict["resetTime"] as? String) {
            resetTime = TimestampParser.parse(resetStr)
        } else if let resetEpoch = doubleValue(dict["reset_time"]) {
            resetTime = Date(timeIntervalSince1970: resetEpoch)
        }

        var resetInSeconds = doubleValue(dict["reset_in_seconds"]) ?? doubleValue(dict["resetInSeconds"])

        if resetTime == nil, let resetInSeconds {
            resetTime = fileModifiedAt.addingTimeInterval(resetInSeconds)
        }
        if let resetTime {
            let liveRemaining = resetTime.timeIntervalSince(now)
            if resetInSeconds == nil || abs(now.timeIntervalSince(fileModifiedAt)) > 1.0 {
                resetInSeconds = max(0.0, liveRemaining)
            }
        }

        return QuotaBucketSnapshot(
            id: id,
            label: label,
            remainingFraction: min(max(rem, 0.0), 1.0),
            resetTime: resetTime,
            resetInSeconds: resetInSeconds,
            sourceBadge: "LIVE CLI",
            lastUpdated: fileModifiedAt
        )
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    // MARK: - Hook Installation Management (Explicit User Action Only)

    public func isCLIStatusLineHookInstalled() -> Bool {
        Self.isCLIStatusLineHookInstalled(settingsPath: settingsPath, hookScriptPath: hookScriptPath)
    }

    @discardableResult
    public func installCLIStatusLineHook() throws -> Bool {
        try Self.installCLIStatusLineHook(settingsPath: settingsPath, hookScriptPath: hookScriptPath)
    }

    @discardableResult
    public func uninstallCLIStatusLineHook() throws -> Bool {
        try Self.uninstallCLIStatusLineHook(settingsPath: settingsPath, hookScriptPath: hookScriptPath)
    }

    public static func isCLIStatusLineHookInstalled(
        settingsPath: String,
        hookScriptPath: String? = nil
    ) -> Bool {
        guard FileManager.default.fileExists(atPath: settingsPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusLine = dict["statusLine"] else {
            return false
        }

        if let str = statusLine as? String {
            return matchesHookCommand(str, hookScriptPath: hookScriptPath)
        }
        if let statusDict = statusLine as? [String: Any],
           let cmd = statusDict["command"] as? String {
            return matchesHookCommand(cmd, hookScriptPath: hookScriptPath)
        }
        return false
    }

    private static func matchesHookCommand(_ command: String, hookScriptPath: String?) -> Bool {
        if command.contains("agy-hud-hook.sh") {
            return true
        }
        if let hookScriptPath, !hookScriptPath.isEmpty, command.contains(hookScriptPath) {
            return true
        }
        return false
    }

    @discardableResult
    public static func installCLIStatusLineHook(
        settingsPath: String,
        hookScriptPath: String
    ) throws -> Bool {
        let fm = FileManager.default
        ensureHookScriptExistsIfDefault(at: hookScriptPath)
        let settingsURL = URL(fileURLWithPath: settingsPath)
        let parentDir = settingsURL.deletingLastPathComponent()
        try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)

        var dict: [String: Any] = [:]
        if fm.fileExists(atPath: settingsPath),
           let data = try? Data(contentsOf: settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = existing
        }

        if let existingStatusLine = dict["statusLine"] {
            let alreadyOurs: Bool
            if let s = existingStatusLine as? String {
                alreadyOurs = matchesHookCommand(s, hookScriptPath: hookScriptPath)
            } else if let d = existingStatusLine as? [String: Any], let c = d["command"] as? String {
                alreadyOurs = matchesHookCommand(c, hookScriptPath: hookScriptPath)
            } else {
                alreadyOurs = false
            }

            if !alreadyOurs && dict[backupStatusLineKey] == nil {
                dict[backupStatusLineKey] = existingStatusLine
            }
        }

        dict["statusLine"] = [
            "type": "command",
            "command": hookScriptPath
        ]

        let outputData = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try outputData.write(to: settingsURL, options: .atomic)
        return true
    }

    @discardableResult
    public static func uninstallCLIStatusLineHook(
        settingsPath: String,
        hookScriptPath: String? = nil
    ) throws -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: settingsPath) else {
            return false
        }
        let settingsURL = URL(fileURLWithPath: settingsPath)
        guard let data = try? Data(contentsOf: settingsURL),
              var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        if let backup = dict[backupStatusLineKey] {
            dict["statusLine"] = backup
            dict.removeValue(forKey: backupStatusLineKey)
        } else if let current = dict["statusLine"] {
            let isOurs: Bool
            if let s = current as? String {
                isOurs = matchesHookCommand(s, hookScriptPath: hookScriptPath)
            } else if let d = current as? [String: Any], let c = d["command"] as? String {
                isOurs = matchesHookCommand(c, hookScriptPath: hookScriptPath)
            } else {
                isOurs = true
            }
            if isOurs {
                dict.removeValue(forKey: "statusLine")
            }
        }

        let outputData = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try outputData.write(to: settingsURL, options: .atomic)
        return true
    }

    private static func ensureHookScriptExistsIfDefault(at hookScriptPath: String) {
        let fm = FileManager.default
        let defaultHomeHook = resolveDefaultHookScriptPath(home: fm.homeDirectoryForCurrentUser.path)
        guard hookScriptPath == defaultHomeHook else { return }

        let targetURL = URL(fileURLWithPath: hookScriptPath)
        try? fm.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let candidates: [String] = [
            Bundle.main.path(forResource: "agy-hud-hook", ofType: "sh"),
            (fm.currentDirectoryPath as NSString).appendingPathComponent("scripts/agy-hud-hook.sh")
        ].compactMap { $0 }

        for sourcePath in candidates where fm.fileExists(atPath: sourcePath) {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: sourcePath)) {
                try? data.write(to: targetURL, options: .atomic)
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScriptPath)
                return
            }
        }
    }
}
