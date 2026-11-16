import XCTest
@testable import TelemetryCore

final class QuotaAutoSyncTests: XCTestCase {
    var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TelemetryCoreTests_AutoSync_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    func testResolveAgyExecutableWithCustomSearchPaths() throws {
        // 1. When binary does not exist in search path, returns nil
        let notFound = QuotaAutoSync.resolveAgyExecutablePath(customSearchPaths: [tempDirectory.path])
        XCTAssertNil(notFound)

        // 2. Create mock executable 'agy' in tempDirectory
        let mockAgyURL = tempDirectory.appendingPathComponent("agy")
        let scriptContent = "#!/bin/sh\nexit 0\n"
        try scriptContent.write(to: mockAgyURL, atomically: true, encoding: .utf8)
        let permissions: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
        try FileManager.default.setAttributes(permissions, ofItemAtPath: mockAgyURL.path)

        // 3. Must find the executable via customSearchPaths
        let found = QuotaAutoSync.resolveAgyExecutablePath(customSearchPaths: [tempDirectory.path])
        XCTAssertEqual(found, mockAgyURL.path)
    }

    func testPerformSyncReturnsCliNotFoundWhenBinaryMissing() {
        let fakePath = tempDirectory.appendingPathComponent("non_existent_agy").path
        let bridge = StatusLineBridge(
            snapshotPath: tempDirectory.appendingPathComponent("snapshot.json").path,
            settingsPath: tempDirectory.appendingPathComponent("settings.json").path
        )

        let result = QuotaAutoSync.performSync(
            statusLineBridge: bridge,
            customAgyPath: fakePath,
            customSearchPaths: [tempDirectory.path],
            timeoutSeconds: 1.0
        )

        XCTAssertEqual(result, .cliNotFound)
        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(result.statusDescription, "agy CLI Not Found")
    }
}
