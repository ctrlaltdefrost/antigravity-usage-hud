import Darwin
import Foundation

public enum QuotaAutoSyncResult: Sendable, Equatable {
    case synced(updatedAt: Date)
    case cliNotFound
    case timedOut
    case failed(String)

    public var isSuccess: Bool {
        if case .synced = self { return true }
        return false
    }

    public var statusDescription: String {
        switch self {
        case .synced:
            return "Live CLI Synced"
        case .cliNotFound:
            return "agy CLI Not Found"
        case .timedOut:
            return "CLI Sync Timed Out"
        case .failed(let reason):
            return "Sync Failed: \(reason)"
        }
    }
}

public enum QuotaAutoSync {
    public static func resolveAgyExecutablePath(
        customSearchPaths: [String]? = nil,
        environmentPath: String? = ProcessInfo.processInfo.environment["PATH"]
    ) -> String? {
        let fm = FileManager.default

        if let customSearchPaths {
            for entry in customSearchPaths {
                let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: trimmed, isDirectory: &isDir) {
                    if isDir.boolValue {
                        let candidate = (trimmed as NSString).appendingPathComponent("agy")
                        if fm.isExecutableFile(atPath: candidate) {
                            return candidate
                        }
                    } else if fm.isExecutableFile(atPath: trimmed) {
                        return trimmed
                    }
                }
            }
            return nil
        }

        var candidateFiles: [String] = []
        if let environmentPath, !environmentPath.isEmpty {
            for dir in environmentPath.split(separator: ":") {
                let dirPath = String(dir).trimmingCharacters(in: .whitespacesAndNewlines)
                if !dirPath.isEmpty {
                    candidateFiles.append((dirPath as NSString).appendingPathComponent("agy"))
                }
            }
        }

        let home = fm.homeDirectoryForCurrentUser.path
        candidateFiles.append((home as NSString).appendingPathComponent(".local/bin/agy"))
        candidateFiles.append("/opt/homebrew/bin/agy")
        candidateFiles.append("/usr/local/bin/agy")
        candidateFiles.append("/usr/bin/agy")

        for path in candidateFiles {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    public static func sync(
        statusLineBridge: StatusLineBridge = StatusLineBridge(),
        customAgyPath: String? = nil,
        customSearchPaths: [String]? = nil,
        timeoutSeconds: TimeInterval = 9.0
    ) async -> QuotaAutoSyncResult {
        await Task.detached(priority: .utility) {
            performSync(
                statusLineBridge: statusLineBridge,
                customAgyPath: customAgyPath,
                customSearchPaths: customSearchPaths,
                timeoutSeconds: timeoutSeconds
            )
        }.value
    }

    public static func isSnapshotReady(_ payload: StatusLinePayload?) -> Bool {
        guard let payload else { return false }
        return !payload.quotas.isEmpty && payload.hasFreshQuotaPayload
    }

    public static func performSync(
        statusLineBridge: StatusLineBridge = StatusLineBridge(),
        customAgyPath: String? = nil,
        customSearchPaths: [String]? = nil,
        timeoutSeconds: TimeInterval = 9.0
    ) -> QuotaAutoSyncResult {
        let fm = FileManager.default
        let resolvedAgy: String?
        if let customAgyPath {
            resolvedAgy = fm.isExecutableFile(atPath: customAgyPath) ? customAgyPath : nil
        } else {
            resolvedAgy = resolveAgyExecutablePath(customSearchPaths: customSearchPaths)
        }

        guard let agyPath = resolvedAgy else {
            return .cliNotFound
        }

        if !statusLineBridge.isCLIStatusLineHookInstalled() {
            _ = try? statusLineBridge.installCLIStatusLineHook()
        }

        let snapshotPath = statusLineBridge.snapshotPath
        let initialMtime = (try? fm.attributesOfItem(atPath: snapshotPath)[.modificationDate] as? Date) ?? .distantPast

        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        var win = winsize(ws_row: 24, ws_col: 100, ws_xpixel: 0, ws_ypixel: 0)

        guard Darwin.openpty(&masterFD, &slaveFD, nil, nil, &win) == 0 else {
            return .failed("openpty failed")
        }

        let flags = Darwin.fcntl(masterFD, F_GETFL, 0)
        if flags != -1 {
            _ = Darwin.fcntl(masterFD, F_SETFL, flags | O_NONBLOCK)
        }

        let slaveHandle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: agyPath)
        process.currentDirectoryURL = fm.temporaryDirectory
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        var env = ProcessInfo.processInfo.environment
        let home = fm.homeDirectoryForCurrentUser.path
        let extraPath = "\((home as NSString).appendingPathComponent(".local/bin")):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        if let existingPath = env["PATH"], !existingPath.isEmpty {
            env["PATH"] = "\(extraPath):\(existingPath)"
        } else {
            env["PATH"] = extraPath
        }
        env["TERM"] = "xterm-256color"
        process.environment = env

        do {
            try process.run()
        } catch {
            Darwin.close(slaveFD)
            Darwin.close(masterFD)
            return .failed(error.localizedDescription)
        }

        Darwin.close(slaveFD)

        let deadline = Date().addingTimeInterval(max(1.0, timeoutSeconds))
        var scratch = [UInt8](repeating: 0, count: 4096)
        var syncedDate: Date?

        while Date() < deadline {
            while Darwin.read(masterFD, &scratch, scratch.count) > 0 {}

            if let attrs = try? fm.attributesOfItem(atPath: snapshotPath),
               let mtime = attrs[.modificationDate] as? Date,
               let size = (attrs[.size] as? NSNumber)?.intValue,
               size > 10,
               mtime > initialMtime,
               isSnapshotReady(statusLineBridge.readSnapshot()) {
                syncedDate = mtime
                break
            }

            if !process.isRunning {
                if let attrs = try? fm.attributesOfItem(atPath: snapshotPath),
                   let mtime = attrs[.modificationDate] as? Date,
                   mtime > initialMtime,
                   isSnapshotReady(statusLineBridge.readSnapshot()) {
                    syncedDate = mtime
                }
                break
            }

            usleep(100_000) // 100ms
        }

        // Cleanly exit TUI and terminate child process
        let exitCmd = Array("/exit\r\n".utf8)
        _ = exitCmd.withUnsafeBytes { rawBuf in
            if let base = rawBuf.baseAddress {
                return Darwin.write(masterFD, base, exitCmd.count)
            }
            return 0
        }

        usleep(120_000)

        if process.isRunning {
            process.terminate()
            usleep(120_000)
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }

        Darwin.close(masterFD)

        if let syncedDate {
            return .synced(updatedAt: syncedDate)
        }
        return .timedOut
    }
}
