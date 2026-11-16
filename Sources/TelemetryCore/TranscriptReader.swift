import Foundation

public final class TranscriptReader: @unchecked Sendable {
    public struct BrainRoot: Sendable, Equatable {
        public let path: String
        public let sourceLabel: String

        public init(path: String, sourceLabel: String) {
            self.path = path
            self.sourceLabel = sourceLabel
        }
    }

    public struct FileTailState: Sendable, Equatable {
        public var filePath: String
        public var conversationId: String
        public var source: String
        public var byteOffset: UInt64
        public var lastFileSize: UInt64
        public var lastModified: Date
        public var turns: [TurnRecord]
        public var latestTurn: TurnRecord?
    }

    private struct RawLineObject: Decodable {
        let type: String?
        let step_index: Int?
        let created_at: String?
        let input_tokens: Int?
        let cache_read_tokens: Int?
        let output_tokens: Int?
    }

    public let brainRoots: [BrainRoot]
    public let maxFileAgeSeconds: TimeInterval
    public let retentionSeconds: TimeInterval

    private let lock = NSLock()
    private var fileStates: [String: FileTailState] = [:]

    public init(
        brainRoots: [BrainRoot]? = nil,
        maxFileAgeDays: Double = 8.0,
        retentionSeconds: TimeInterval = 7.0 * 24.0 * 3600.0
    ) {
        if let brainRoots {
            self.brainRoots = brainRoots
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            self.brainRoots = [
                BrainRoot(
                    path: (home as NSString).appendingPathComponent(".gemini/antigravity/brain"),
                    sourceLabel: "Desktop"
                ),
                BrainRoot(
                    path: (home as NSString).appendingPathComponent(".gemini/antigravity-cli/brain"),
                    sourceLabel: "CLI"
                )
            ]
        }
        self.maxFileAgeSeconds = maxFileAgeDays * 24.0 * 3600.0
        self.retentionSeconds = retentionSeconds
    }

    public func trackedByteOffset(forFileAt path: String) -> UInt64? {
        lock.lock()
        defer { lock.unlock() }
        return fileStates[path]?.byteOffset
    }

    public func latestTurn(forConversationId conversationId: String) -> TurnRecord? {
        lock.lock()
        defer { lock.unlock() }
        var best: TurnRecord?
        for state in fileStates.values where state.conversationId == conversationId {
            if let candidate = state.latestTurn {
                if let current = best {
                    if candidate.createdAt >= current.createdAt {
                        best = candidate
                    }
                } else {
                    best = candidate
                }
            }
        }
        return best
    }

    public func poll(now: Date = Date()) -> [TurnRecord] {
        let fm = FileManager.default
        let cutoffModDate = now.addingTimeInterval(-maxFileAgeSeconds)
        let retentionCutoff = now.addingTimeInterval(-retentionSeconds)

        for root in brainRoots {
            guard fm.fileExists(atPath: root.path),
                  let convDirs = try? fm.contentsOfDirectory(atPath: root.path) else {
                continue
            }

            for convId in convDirs {
                guard !convId.hasPrefix(".") else { continue }
                let transcriptPath = (root.path as NSString)
                    .appendingPathComponent(convId)
                    .appending("/.system_generated/logs/transcript.jsonl")

                guard let attrs = try? fm.attributesOfItem(atPath: transcriptPath),
                      let mtime = attrs[.modificationDate] as? Date else {
                    continue
                }

                guard mtime >= cutoffModDate else {
                    continue
                }

                _ = readTranscriptFile(
                    at: transcriptPath,
                    conversationId: convId,
                    source: root.sourceLabel,
                    now: now
                )
            }
        }

        lock.lock()
        defer { lock.unlock() }

        var allTurns: [TurnRecord] = []
        for (path, var state) in fileStates {
            state.turns.removeAll { $0.createdAt < retentionCutoff }
            fileStates[path] = state
            allTurns.append(contentsOf: state.turns)
        }

        allTurns.sort { $0.createdAt < $1.createdAt }
        return allTurns
    }

    @discardableResult
    public func readTranscriptFile(
        at path: String,
        conversationId: String,
        source: String = "Desktop",
        now: Date = Date()
    ) -> [TurnRecord] {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let fileSizeNum = attrs[.size] as? NSNumber,
              let mtime = attrs[.modificationDate] as? Date else {
            lock.lock()
            fileStates.removeValue(forKey: path)
            lock.unlock()
            return []
        }

        let fileSize = fileSizeNum.uint64Value
        let retentionCutoff = now.addingTimeInterval(-retentionSeconds)

        lock.lock()
        var state = fileStates[path] ?? FileTailState(
            filePath: path,
            conversationId: conversationId,
            source: source,
            byteOffset: 0,
            lastFileSize: 0,
            lastModified: .distantPast,
            turns: [],
            latestTurn: nil
        )
        lock.unlock()

        // Detect truncation or same-size file replacement
        if fileSize < state.byteOffset || (fileSize == state.byteOffset && mtime > state.lastModified && state.byteOffset > 0) {
            state.byteOffset = 0
            state.lastFileSize = 0
            state.turns.removeAll()
            state.latestTurn = nil
        }

        if fileSize == state.byteOffset && mtime == state.lastModified {
            lock.lock()
            state.turns.removeAll { $0.createdAt < retentionCutoff }
            fileStates[path] = state
            let result = state.turns
            lock.unlock()
            return result
        }

        if fileSize > state.byteOffset, let handle = FileHandle(forReadingAtPath: path) {
            defer { try? handle.close() }
            do {
                try handle.seek(toOffset: state.byteOffset)
                if let chunk = try handle.readToEnd(), !chunk.isEmpty {
                    let (newTurns, consumedBytes) = Self.parseChunk(
                        chunk,
                        conversationId: conversationId,
                        source: source
                    )
                    state.byteOffset += UInt64(consumedBytes)
                    for turn in newTurns {
                        state.latestTurn = turn
                        if turn.createdAt >= retentionCutoff {
                            state.turns.append(turn)
                        }
                    }
                }
            } catch {
                // Keep existing state on transient I/O error
            }
        }

        state.lastFileSize = fileSize
        state.lastModified = mtime
        state.turns.removeAll { $0.createdAt < retentionCutoff }

        lock.lock()
        fileStates[path] = state
        let result = state.turns
        lock.unlock()
        return result
    }

    public static func parseChunk(
        _ data: Data,
        conversationId: String,
        source: String = "Desktop"
    ) -> (turns: [TurnRecord], consumedBytes: Int) {
        var turns: [TurnRecord] = []
        let newline = UInt8(ascii: "\n")
        var lineStart = 0
        let count = data.count

        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            for i in 0..<count {
                if base[i] == newline {
                    let lineLength = i - lineStart
                    if lineLength > 0 {
                        let lineData = Data(bytes: base.advanced(by: lineStart), count: lineLength)
                        if let turn = parseLineData(lineData, conversationId: conversationId, source: source) {
                            turns.append(turn)
                        }
                    }
                    lineStart = i + 1
                }
            }

            // Check if there is a trailing line without a newline
            if lineStart < count {
                let remLength = count - lineStart
                let remData = Data(bytes: base.advanced(by: lineStart), count: remLength)
                if isCompleteJSONLine(remData) {
                    if let turn = parseLineData(remData, conversationId: conversationId, source: source) {
                        turns.append(turn)
                    }
                    lineStart = count
                }
            }
        }

        return (turns, lineStart)
    }

    private static func isCompleteJSONLine(_ data: Data) -> Bool {
        guard let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              str.hasPrefix("{"),
              str.hasSuffix("}") else {
            return false
        }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    public static func parseLine(
        _ line: String,
        conversationId: String,
        source: String = "Desktop"
    ) -> TurnRecord? {
        guard let data = line.data(using: .utf8) else { return nil }
        return parseLineData(data, conversationId: conversationId, source: source)
    }

    public static func parseLineData(
        _ data: Data,
        conversationId: String,
        source: String = "Desktop"
    ) -> TurnRecord? {
        // Fast pre-check before JSON decoding so non-PLANNER_RESPONSE lines skip full decode
        guard let utf8String = String(data: data, encoding: .utf8),
              utf8String.contains("PLANNER_RESPONSE") else {
            return nil
        }

        guard let decoded = try? JSONDecoder().decode(RawLineObject.self, from: data),
              decoded.type == "PLANNER_RESPONSE" else {
            return nil
        }

        let createdAt: Date
        if let createdStr = decoded.created_at, let parsed = TimestampParser.parse(createdStr) {
            createdAt = parsed
        } else {
            return nil
        }

        let inputTokens = max(0, decoded.input_tokens ?? 0)
        let cacheReadTokens = max(0, decoded.cache_read_tokens ?? 0)
        let outputTokens = max(0, decoded.output_tokens ?? 0)
        let stepIndex = decoded.step_index ?? 0

        return TurnRecord(
            conversationId: conversationId,
            stepIndex: stepIndex,
            createdAt: createdAt,
            inputTokens: inputTokens,
            cacheReadTokens: cacheReadTokens,
            outputTokens: outputTokens,
            source: source
        )
    }

    public static func computeWindowMetrics(
        turns: [TurnRecord],
        windowDuration: TimeInterval,
        now: Date = Date(),
        bucketCount: Int = 24
    ) -> WindowMetrics {
        let safeBucketCount = max(1, bucketCount)
        let windowStart = now.addingTimeInterval(-windowDuration)
        let futureTolerance = now.addingTimeInterval(60.0)
        let bucketWidth = max(windowDuration / Double(safeBucketCount), 1.0)

        var totalInput = 0
        var totalCacheRead = 0
        var totalOutput = 0
        var turnCount = 0
        var buckets = Array(repeating: 0.0, count: safeBucketCount)

        for turn in turns {
            guard turn.createdAt >= windowStart && turn.createdAt <= futureTolerance else {
                continue
            }
            totalInput += turn.inputTokens
            totalCacheRead += turn.cacheReadTokens
            totalOutput += turn.outputTokens
            turnCount += 1

            let elapsed = max(0.0, turn.createdAt.timeIntervalSince(windowStart))
            let bucketIdx = min(max(Int(elapsed / bucketWidth), 0), safeBucketCount - 1)
            buckets[bucketIdx] += Double(turn.directTokens)
        }

        let windowMinutes = max(windowDuration / 60.0, 1.0)
        let tokensPerMinute = Double(totalInput + totalOutput) / windowMinutes

        let totalPromptContext = totalInput + totalCacheRead
        let cacheHitRate: Double
        if totalPromptContext > 0 {
            cacheHitRate = Double(totalCacheRead) / Double(totalPromptContext)
        } else {
            cacheHitRate = 0.0
        }

        // Equivalent frontier API pricing estimate ($3/1M input, $0.30/1M cached input, $15/1M output)
        let estimatedCost = (
            Double(totalInput) * 3.0 +
            Double(totalCacheRead) * 0.30 +
            Double(totalOutput) * 15.0
        ) / 1_000_000.0

        return WindowMetrics(
            totalInputTokens: totalInput,
            cacheReadTokens: totalCacheRead,
            outputTokens: totalOutput,
            turnCount: turnCount,
            tokensPerMinute: tokensPerMinute,
            cacheHitRate: cacheHitRate,
            estimatedEquivalentCostUSD: estimatedCost,
            sparklineBuckets: buckets
        )
    }
}
