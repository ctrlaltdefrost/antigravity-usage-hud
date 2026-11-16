import Foundation
import SQLite3

public enum TimestampParser {
    private static let fallbackLock = NSLock()
    private static let fallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func parse(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let fast = parseFastISO8601(trimmed) {
            return fast
        }

        if let epoch = Double(trimmed) {
            return Date(timeIntervalSince1970: epoch)
        }

        fallbackLock.lock()
        defer { fallbackLock.unlock() }
        return fallbackFormatter.date(from: trimmed)
    }

    private static func parseFastISO8601(_ str: String) -> Date? {
        let bytes = Array(str.utf8)
        let n = bytes.count
        // Minimum "YYYY-MM-DDTHH:MM:SS" is 19 bytes
        guard n >= 19 else { return nil }
        guard bytes[4] == UInt8(ascii: "-"),
              bytes[7] == UInt8(ascii: "-"),
              (bytes[10] == UInt8(ascii: "T") || bytes[10] == UInt8(ascii: " ") || bytes[10] == UInt8(ascii: "t")),
              bytes[13] == UInt8(ascii: ":"),
              bytes[16] == UInt8(ascii: ":") else {
            return nil
        }

        guard let year = parseDigits(bytes, start: 0, length: 4),
              let month = parseDigits(bytes, start: 5, length: 2),
              let day = parseDigits(bytes, start: 8, length: 2),
              let hour = parseDigits(bytes, start: 11, length: 2),
              let minute = parseDigits(bytes, start: 14, length: 2),
              let second = parseDigits(bytes, start: 17, length: 2) else {
            return nil
        }

        var idx = 19
        var fractionalSeconds: Double = 0.0

        if idx < n && bytes[idx] == UInt8(ascii: ".") {
            idx += 1
            var fracAccum: Double = 0.0
            var divisor: Double = 10.0
            while idx < n {
                let b = bytes[idx]
                if b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9") {
                    fracAccum += Double(b - UInt8(ascii: "0")) / divisor
                    divisor *= 10.0
                    idx += 1
                } else {
                    break
                }
            }
            fractionalSeconds = fracAccum
        }

        var tzOffsetSeconds = 0
        if idx < n {
            let tzChar = bytes[idx]
            if tzChar == UInt8(ascii: "Z") || tzChar == UInt8(ascii: "z") {
                idx += 1
            } else if tzChar == UInt8(ascii: "+") || tzChar == UInt8(ascii: "-") {
                let sign = (tzChar == UInt8(ascii: "-")) ? -1 : 1
                idx += 1
                guard idx + 2 <= n,
                      let tzH = parseDigits(bytes, start: idx, length: 2) else {
                    return nil
                }
                idx += 2
                var tzM = 0
                if idx < n && bytes[idx] == UInt8(ascii: ":") {
                    idx += 1
                }
                if idx + 2 <= n, let m = parseDigits(bytes, start: idx, length: 2) {
                    tzM = m
                }
                tzOffsetSeconds = sign * (tzH * 3600 + tzM * 60)
            }
        }

        var tmVal = tm()
        tmVal.tm_year = Int32(year - 1900)
        tmVal.tm_mon = Int32(month - 1)
        tmVal.tm_mday = Int32(day)
        tmVal.tm_hour = Int32(hour)
        tmVal.tm_min = Int32(minute)
        tmVal.tm_sec = Int32(second)
        tmVal.tm_isdst = 0

        let epochSeconds = timegm(&tmVal)
        guard epochSeconds != -1 else { return nil }

        let finalTimestamp = Double(epochSeconds - tzOffsetSeconds) + fractionalSeconds
        return Date(timeIntervalSince1970: finalTimestamp)
    }

    @inline(__always)
    private static func parseDigits(_ bytes: [UInt8], start: Int, length: Int) -> Int? {
        var result = 0
        for i in start..<(start + length) {
            let b = bytes[i]
            guard b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9") else { return nil }
            result = result * 10 + Int(b - UInt8(ascii: "0"))
        }
        return result
    }
}

public final class SQLiteSummaryReader: @unchecked Sendable {
    public struct DatabaseSource: Sendable, Equatable {
        public let path: String
        public let defaultSourceLabel: String

        public init(path: String, defaultSourceLabel: String) {
            self.path = path
            self.defaultSourceLabel = defaultSourceLabel
        }
    }

    public let databaseSources: [DatabaseSource]

    public init(databaseSources: [DatabaseSource]? = nil) {
        if let databaseSources {
            self.databaseSources = databaseSources
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            self.databaseSources = [
                DatabaseSource(
                    path: (home as NSString).appendingPathComponent(".gemini/antigravity/conversation_summaries.db"),
                    defaultSourceLabel: "Desktop"
                ),
                DatabaseSource(
                    path: (home as NSString).appendingPathComponent(".gemini/antigravity-cli/conversation_summaries.db"),
                    defaultSourceLabel: "CLI"
                )
            ]
        }
    }

    public static func decodeWorkspaceUris(_ rawJSON: String) -> WorkspaceInfo {
        let trimmed = rawJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "[]" else {
            return .unassigned
        }

        var candidateURI: String?
        if let data = trimmed.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [String] {
            candidateURI = array.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        } else if !trimmed.hasPrefix("[") {
            candidateURI = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        guard let rawURI = candidateURI?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawURI.isEmpty else {
            return .unassigned
        }

        var resolvedPath: String = ""
        if rawURI.lowercased().hasPrefix("file://") {
            if let url = URL(string: rawURI) {
                resolvedPath = url.path
            } else {
                let withoutScheme = String(rawURI.dropFirst("file://".count))
                resolvedPath = withoutScheme.removingPercentEncoding ?? withoutScheme
            }
        } else {
            resolvedPath = rawURI.removingPercentEncoding ?? rawURI
        }

        while resolvedPath.count > 1 && resolvedPath.hasSuffix("/") {
            resolvedPath.removeLast()
        }

        resolvedPath = resolvedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedPath.isEmpty, resolvedPath != "/" else {
            return .unassigned
        }

        let name = (resolvedPath as NSString).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "/" else {
            return .unassigned
        }

        return WorkspaceInfo(id: resolvedPath, name: name, workspacePath: resolvedPath)
    }

    public static func decodeWorkspaceURIs(_ rawJSON: String) -> WorkspaceInfo {
        decodeWorkspaceUris(rawJSON)
    }

    public func readAllSummaries() -> [ConversationSummaryRecord] {
        var byId: [String: ConversationSummaryRecord] = [:]
        for source in databaseSources {
            let records = Self.readSummaries(fromDatabaseAt: source.path, defaultSource: source.defaultSourceLabel)
            for record in records {
                if let existing = byId[record.conversationId] {
                    if record.lastModifiedTime >= existing.lastModifiedTime {
                        byId[record.conversationId] = record
                    }
                } else {
                    byId[record.conversationId] = record
                }
            }
        }
        return byId.values.sorted { $0.lastModifiedTime > $1.lastModifiedTime }
    }

    public static func makeReadOnlyURI(forPath path: String, immutable: Bool = false) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#")
        let encoded = path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
        if immutable {
            return "file:\(encoded)?mode=ro&immutable=1"
        }
        return "file:\(encoded)?mode=ro"
    }

    public static func readSummaries(
        fromDatabaseAt path: String,
        defaultSource: String = "Desktop"
    ) -> [ConversationSummaryRecord] {
        guard FileManager.default.fileExists(atPath: path) else {
            return []
        }

        if let records = queryDatabase(at: path, defaultSource: defaultSource, immutable: false) {
            return records
        }
        // Fallback with immutable=1 in case WAL -shm cannot be locked in read-only sandbox
        return queryDatabase(at: path, defaultSource: defaultSource, immutable: true) ?? []
    }

    private static func queryDatabase(
        at path: String,
        defaultSource: String,
        immutable: Bool
    ) -> [ConversationSummaryRecord]? {
        let uri = makeReadOnlyURI(forPath: path, immutable: immutable)
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        let openResult = sqlite3_open_v2(uri, &db, flags, nil)
        guard openResult == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }

        sqlite3_busy_timeout(db, 250)

        let sql = """
        SELECT
            conversation_id,
            title,
            step_count,
            last_modified_time,
            workspace_uris,
            status,
            source,
            parent_conversation_id,
            nesting_depth,
            not_fully_idle,
            killed
        FROM conversation_summaries
        ORDER BY last_modified_time DESC;
        """

        var stmt: OpaquePointer?
        let prepResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepResult == SQLITE_OK, let stmt else {
            if let stmt { sqlite3_finalize(stmt) }
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        var records: [ConversationSummaryRecord] = []
        while true {
            let stepResult = sqlite3_step(stmt)
            if stepResult == SQLITE_ROW {
                let convId = columnString(stmt, 0)
                guard !convId.isEmpty else { continue }

                let rawTitle = columnString(stmt, 1).trimmingCharacters(in: .whitespacesAndNewlines)
                let stepCount = Int(sqlite3_column_int64(stmt, 2))
                let lastModStr = columnString(stmt, 3)
                let lastModified = TimestampParser.parse(lastModStr) ?? Date.distantPast
                let workspaceUris = columnString(stmt, 4)
                let status = columnString(stmt, 5)
                let rawSource = columnString(stmt, 6).trimmingCharacters(in: .whitespacesAndNewlines)
                let parentIdRaw = columnString(stmt, 7).trimmingCharacters(in: .whitespacesAndNewlines)
                let nestingDepth = Int(sqlite3_column_int64(stmt, 8))
                let notFullyIdle = sqlite3_column_int(stmt, 9) != 0
                let killed = sqlite3_column_int(stmt, 10) != 0

                let workspaceInfo = decodeWorkspaceUris(workspaceUris)
                let parentId: String? = parentIdRaw.isEmpty ? nil : parentIdRaw
                let isSubagent = (parentId != nil) || nestingDepth > 0

                let resolvedSource: String
                if defaultSource == "CLI" || rawSource.localizedCaseInsensitiveContains("cli") {
                    resolvedSource = "CLI"
                } else {
                    resolvedSource = "Desktop"
                }

                let resolvedTitle: String
                if !rawTitle.isEmpty {
                    resolvedTitle = rawTitle
                } else if isSubagent {
                    resolvedTitle = "Swarm Worker (\(convId.prefix(6)))"
                } else {
                    resolvedTitle = "Session \(convId.prefix(6))"
                }

                records.append(
                    ConversationSummaryRecord(
                        conversationId: convId,
                        title: resolvedTitle,
                        stepCount: stepCount,
                        lastModifiedTime: lastModified,
                        workspaceUris: workspaceUris,
                        projectName: workspaceInfo.name,
                        workspacePath: workspaceInfo.workspacePath,
                        status: status,
                        source: resolvedSource,
                        parentConversationId: parentId,
                        nestingDepth: nestingDepth,
                        notFullyIdle: notFullyIdle,
                        killed: killed
                    )
                )
            } else if stepResult == SQLITE_DONE {
                break
            } else {
                break
            }
        }

        return records
    }

    private static func columnString(_ stmt: OpaquePointer, _ index: Int32) -> String {
        guard let cStr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cStr)
    }
}
