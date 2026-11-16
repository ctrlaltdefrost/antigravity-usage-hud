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

    func testPrioritySortingFourBuckets() {
        let json = """
        {
            "plan_tier": "Google AI Ultra",
            "agent_state": "idle",
            "quota": {
                "3p-weekly": {
                    "remaining_fraction": 0.95,
                    "reset_in_seconds": 259200
                },
                "gemini-5h": {
                    "remaining_fraction": 0.82,
                    "reset_in_seconds": 7200
                },
                "3p-5h": {
                    "remaining_fraction": 0.74,
                    "reset_in_seconds": 10800
                },
                "gemini-weekly": {
                    "remaining_fraction": 0.91,
                    "reset_in_seconds": 360000
                }
            }
        }
        """

        let payload = StatusLineBridge.parseStatusLineJSON(json)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.planTier, "Google AI Ultra")
        XCTAssertEqual(payload?.quotas.count, 4)

        // Exact Priority Order:
        // 1. gemini-5h -> Gemini 5h
        // 2. gemini-weekly -> Gemini Wk
        // 3. 3p-5h -> Claude/3P 5h
        // 4. 3p-weekly -> Claude/3P Wk
        XCTAssertEqual(payload?.quotas[0].id, "gemini-5h")
        XCTAssertEqual(payload?.quotas[0].label, "Gemini 5h")
        XCTAssertEqual(payload?.quotas[0].remainingFraction, 0.82)

        XCTAssertEqual(payload?.quotas[1].id, "gemini-weekly")
        XCTAssertEqual(payload?.quotas[1].label, "Gemini Wk")
        XCTAssertEqual(payload?.quotas[1].remainingFraction, 0.91)

        XCTAssertEqual(payload?.quotas[2].id, "3p-5h")
        XCTAssertEqual(payload?.quotas[2].label, "Claude/3P 5h")
        XCTAssertEqual(payload?.quotas[2].remainingFraction, 0.74)

        XCTAssertEqual(payload?.quotas[3].id, "3p-weekly")
        XCTAssertEqual(payload?.quotas[3].label, "Claude/3P Wk")
        XCTAssertEqual(payload?.quotas[3].remainingFraction, 0.95)
    }

    func testInitializingStateSuppressesModelAndContext() {
        let json = """
        {
            "model": "gemini-2.5-pro",
            "agent_state": "initializing",
            "plan_tier": "Standard Pro",
            "context_window": {
                "used_percentage": 0.0
            },
            "quota": {
                "gemini-5h": {
                    "remaining_fraction": 0.99,
                    "reset_in_seconds": 18000
                }
            }
        }
        """

        let payload = StatusLineBridge.parseStatusLineJSON(json)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.agentState, "initializing")
        XCTAssertEqual(payload?.planTier, "Standard Pro")
        // Model and context must be suppressed during initializing state to avoid clutter
        XCTAssertNil(payload?.modelDisplayName, "modelDisplayName must be nil when initializing")
        XCTAssertNil(payload?.contextUsedPercentage, "contextUsedPercentage must be nil when initializing")
        XCTAssertEqual(payload?.quotas.count, 1)
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
