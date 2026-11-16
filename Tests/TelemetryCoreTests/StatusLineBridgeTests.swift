import XCTest
@testable import TelemetryCore

final class StatusLineBridgeTests: XCTestCase {
    var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TelemetryCoreTests_StatusLine_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - JSON Parsing Tests

    func testParseStatusLineJSONSingleBucket() {
        let json = """
        {
            "model": {
                "display_name": "Gemini 1.5 Pro",
                "id": "gemini-1.5-pro"
            },
            "agent_state": "idle",
            "context_window": {
                "used_percentage": 0.42
            },
            "quota": {
                "id": "gemini-pro-quota",
                "label": "Gemini 1.5 Pro Quota",
                "remaining_fraction": 0.78,
                "reset_in_seconds": 3600
            }
        }
        """

        let payload = StatusLineBridge.parseStatusLineJSON(json)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.modelDisplayName, "Gemini 1.5 Pro")
        XCTAssertEqual(payload?.agentState, "idle")
        XCTAssertEqual(payload?.contextUsedPercentage, 0.42)
        XCTAssertEqual(payload?.quotas.count, 1)

        let q = payload?.quotas.first
        XCTAssertEqual(q?.id, "gemini-pro-quota")
        XCTAssertEqual(q?.label, "Gemini 1.5 Pro Quota")
        XCTAssertEqual(q?.remainingFraction, 0.78)
        XCTAssertEqual(q?.resetInSeconds, 3600)
        XCTAssertEqual(q?.sourceBadge, "LIVE CLI")
    }

    func testParseStatusLineJSONMultipleBucketsArray() {
        let json = """
        {
            "model": "Claude 3.5 Sonnet",
            "state": "working",
            "context_window": {
                "used_percent": 0.15
            },
            "quota": {
                "buckets": [
                    {
                        "id": "claude-tier-1",
                        "label": "5-Hour Burst",
                        "remaining_fraction": 0.65,
                        "reset_in_seconds": 7200
                    },
                    {
                        "id": "claude-tier-2",
                        "label": "Daily Quota",
                        "remaining_fraction": 0.90,
                        "reset_in_seconds": 86400
                    }
                ]
            }
        }
        """

        let payload = StatusLineBridge.parseStatusLineJSON(json)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.modelDisplayName, "Claude 3.5 Sonnet")
        XCTAssertEqual(payload?.agentState, "working")
        XCTAssertEqual(payload?.contextUsedPercentage, 0.15)
        XCTAssertEqual(payload?.quotas.count, 2)
        XCTAssertEqual(payload?.quotas[0].id, "claude-tier-1")
        XCTAssertEqual(payload?.quotas[0].remainingFraction, 0.65)
        XCTAssertEqual(payload?.quotas[1].id, "claude-tier-2")
        XCTAssertEqual(payload?.quotas[1].remainingFraction, 0.90)
    }

    // MARK: - settings.json Hook Install & Uninstall (Isolated Temp Directory)

    func testHookInstallPreservesUnrelatedSettingsKeys() throws {
        let settingsURL = tempDirectory.appendingPathComponent("settings.json")
        let hookScriptURL = tempDirectory.appendingPathComponent("agy-hud-hook.sh")
        try "#!/bin/sh\nexit 0".write(to: hookScriptURL, atomically: true, encoding: .utf8)

        // Initial settings with arbitrary user configurations
        let initialSettings: [String: Any] = [
            "theme": "cyberpunk-neon",
            "editor.fontSize": 14,
            "telemetry.enabled": false,
            "customPlugins": ["git-tools", "docker-helper"]
        ]
        let initialData = try JSONSerialization.data(withJSONObject: initialSettings, options: [.prettyPrinted])
        try initialData.write(to: settingsURL)

        // Install hook
        let installed = try StatusLineBridge.installCLIStatusLineHook(
            settingsPath: settingsURL.path,
            hookScriptPath: hookScriptURL.path
        )
        XCTAssertTrue(installed)

        // Check isCLIStatusLineHookInstalled
        let isInstalled = StatusLineBridge.isCLIStatusLineHookInstalled(
            settingsPath: settingsURL.path,
            hookScriptPath: hookScriptURL.path
        )
        XCTAssertTrue(isInstalled)

        // Read modified settings and verify all unrelated keys preserved
        let modifiedData = try Data(contentsOf: settingsURL)
        let modifiedDict = try JSONSerialization.jsonObject(with: modifiedData) as? [String: Any]
        XCTAssertNotNil(modifiedDict)
        XCTAssertEqual(modifiedDict?["theme"] as? String, "cyberpunk-neon")
        XCTAssertEqual(modifiedDict?["editor.fontSize"] as? Int, 14)
        XCTAssertEqual(modifiedDict?["telemetry.enabled"] as? Bool, false)
        XCTAssertEqual((modifiedDict?["customPlugins"] as? [String])?.count, 2)

        // Verify statusLine was added
        let statusLineObj = modifiedDict?["statusLine"] as? [String: Any]
        XCTAssertEqual(statusLineObj?["type"] as? String, "command")
        XCTAssertEqual(statusLineObj?["command"] as? String, hookScriptURL.path)

        // Uninstall hook
        let uninstalled = try StatusLineBridge.uninstallCLIStatusLineHook(
            settingsPath: settingsURL.path,
            hookScriptPath: hookScriptURL.path
        )
        XCTAssertTrue(uninstalled)

        // Check isCLIStatusLineHookInstalled is now false
        let isStillInstalled = StatusLineBridge.isCLIStatusLineHookInstalled(
            settingsPath: settingsURL.path,
            hookScriptPath: hookScriptURL.path
        )
        XCTAssertFalse(isStillInstalled)

        // Verify unrelated keys STILL preserved after uninstall
        let finalData = try Data(contentsOf: settingsURL)
        let finalDict = try JSONSerialization.jsonObject(with: finalData) as? [String: Any]
        XCTAssertNotNil(finalDict)
        XCTAssertEqual(finalDict?["theme"] as? String, "cyberpunk-neon")
        XCTAssertEqual(finalDict?["editor.fontSize"] as? Int, 14)
        XCTAssertNil(finalDict?["statusLine"])
    }

    func testHookInstallRestoresPriorUserStatusLine() throws {
        let settingsURL = tempDirectory.appendingPathComponent("settings_with_prior.json")
        let hookScriptURL = tempDirectory.appendingPathComponent("agy-hud-hook.sh")

        // Pre-existing custom statusline configured by the user
        let initialSettings: [String: Any] = [
            "statusLine": [
                "type": "command",
                "command": "/usr/local/bin/my-custom-statusline"
            ],
            "editor.cursorBlink": true
        ]
        let initialData = try JSONSerialization.data(withJSONObject: initialSettings, options: [.prettyPrinted])
        try initialData.write(to: settingsURL)

        // Install our HUD hook
        _ = try StatusLineBridge.installCLIStatusLineHook(
            settingsPath: settingsURL.path,
            hookScriptPath: hookScriptURL.path
        )

        // Verify backup key was created
        let midData = try Data(contentsOf: settingsURL)
        let midDict = try JSONSerialization.jsonObject(with: midData) as? [String: Any]
        XCTAssertNotNil(midDict?[StatusLineBridge.backupStatusLineKey])

        // Uninstall hook: MUST restore user's original custom statusline!
        _ = try StatusLineBridge.uninstallCLIStatusLineHook(
            settingsPath: settingsURL.path,
            hookScriptPath: hookScriptURL.path
        )

        let restoredData = try Data(contentsOf: settingsURL)
        let restoredDict = try JSONSerialization.jsonObject(with: restoredData) as? [String: Any]
        let restoredStatusLine = restoredDict?["statusLine"] as? [String: Any]
        XCTAssertEqual(restoredStatusLine?["command"] as? String, "/usr/local/bin/my-custom-statusline")
        XCTAssertNil(restoredDict?[StatusLineBridge.backupStatusLineKey])
    }
}
