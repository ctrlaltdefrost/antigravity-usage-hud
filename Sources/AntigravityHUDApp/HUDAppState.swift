import Combine
import Foundation
import HUDShaders
import ServiceManagement
import SwiftUI
import TelemetryCore

enum HUDMode: String, CaseIterable, Codable, Sendable {
    case compact
    case expanded
    case hidden

    var displayName: String {
        switch self {
        case .compact: return "Compact Reactor Pill"
        case .expanded: return "Full Command Deck"
        case .hidden: return "Hide HUD"
        }
    }
}

enum TelemetryTimeWindow: String, CaseIterable, Identifiable, Codable, Sendable {
    case h5
    case h24
    case d7

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .h5: return "5H BURST"
        case .h24: return "24H"
        case .d7: return "7D WEEKLY"
        }
    }
}

struct HUDToast: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let message: String
    let isWarning: Bool
}

@MainActor
final class HUDAppState: ObservableObject {
    private enum DefaultsKeys {
        static let hudMode = "com.antigravity.hud.mode"
        static let lastVisibleMode = "com.antigravity.hud.lastVisibleMode"
        static let theme = "com.antigravity.hud.theme"
        static let selectedWindow = "com.antigravity.hud.selectedWindow"
        static let audioMuted = "com.antigravity.hud.audioMuted"
    }

    let engine: TelemetryEngine

    @Published private(set) var snapshot: TelemetrySnapshot
    @Published private(set) var isAutoSyncing: Bool = false
    @Published private(set) var autoSyncEnabled: Bool = true
    @Published private(set) var lastAutoSyncStatus: String?
    @Published var mode: HUDMode
    @Published private(set) var lastVisibleMode: HUDMode
    @Published var theme: HUDTheme
    @Published var selectedWindow: TelemetryTimeWindow
    @Published var isGhostMode: Bool = false
    @Published var isAudioMuted: Bool
    @Published var toast: HUDToast?
    @Published var launchAtLoginError: String?

    private var cancellables: Set<AnyCancellable> = []
    private var toastClearTask: Task<Void, Never>?
    private var hasSeenInitialSnapshot = false
    private var previousRunningAgentIds: Set<String> = []
    private var previousAlertIds: Set<String> = []
    private let userDefaults: UserDefaults

    init(
        engine: TelemetryEngine? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        let resolvedEngine = engine ?? TelemetryEngine(userDefaults: userDefaults)
        self.engine = resolvedEngine
        self.userDefaults = userDefaults
        self.snapshot = resolvedEngine.snapshot
        self.isAutoSyncing = resolvedEngine.isAutoSyncing
        self.autoSyncEnabled = resolvedEngine.autoSyncEnabled
        self.lastAutoSyncStatus = resolvedEngine.lastAutoSyncStatus

        let savedLastVisible = userDefaults.string(forKey: DefaultsKeys.lastVisibleMode)
            .flatMap(HUDMode.init(rawValue:))
        let initialLastVisible: HUDMode = (savedLastVisible == .compact || savedLastVisible == .expanded)
            ? savedLastVisible!
            : .expanded
        self.lastVisibleMode = initialLastVisible

        if let savedModeRaw = userDefaults.string(forKey: DefaultsKeys.hudMode),
           let savedMode = HUDMode(rawValue: savedModeRaw) {
            self.mode = savedMode
        } else {
            self.mode = .expanded
        }

        if let savedThemeRaw = userDefaults.string(forKey: DefaultsKeys.theme),
           let savedTheme = HUDTheme(rawValue: savedThemeRaw) {
            self.theme = savedTheme
        } else {
            self.theme = .jarvisCyan
        }

        if let savedWindowRaw = userDefaults.string(forKey: DefaultsKeys.selectedWindow),
           let savedWindow = TelemetryTimeWindow(rawValue: savedWindowRaw) {
            self.selectedWindow = savedWindow
        } else {
            self.selectedWindow = .h5
        }

        let muted = userDefaults.bool(forKey: DefaultsKeys.audioMuted)
        self.isAudioMuted = muted
        TelemetryAudio.shared.isMuted = muted

        bindEngine()
        resolvedEngine.startPolling(interval: 2.5)
    }

    private func bindEngine() {
        engine.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] newSnapshot in
                self?.handleSnapshotUpdate(newSnapshot)
            }
            .store(in: &cancellables)

        engine.$isAutoSyncing
            .receive(on: RunLoop.main)
            .sink { [weak self] syncing in
                guard let self else { return }
                let wasSyncing = self.isAutoSyncing
                self.isAutoSyncing = syncing
                if wasSyncing && !syncing, let status = self.engine.lastAutoSyncStatus {
                    self.lastAutoSyncStatus = status
                    self.showToast(
                        icon: "arrow.triangle.2.circlepath.circle.fill",
                        message: status.uppercased()
                    )
                }
            }
            .store(in: &cancellables)

        engine.$autoSyncEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.autoSyncEnabled = enabled
            }
            .store(in: &cancellables)

        engine.$lastAutoSyncStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.lastAutoSyncStatus = status
            }
            .store(in: &cancellables)
    }

    private func handleSnapshotUpdate(_ newSnapshot: TelemetrySnapshot) {
        snapshot = newSnapshot

        let runningIds = Set(newSnapshot.activeAgents.filter(\.isRunning).map(\.id))
        let alertIds = Set(newSnapshot.alerts.filter { $0.severity == "warning" || $0.severity == "critical" }.map(\.id))

        if hasSeenInitialSnapshot {
            let newlyRunning = runningIds.subtracting(previousRunningAgentIds)
            let newAlerts = alertIds.subtracting(previousAlertIds)
            if !newlyRunning.isEmpty || !newAlerts.isEmpty {
                TelemetryAudio.shared.playPing()
            }
        } else {
            hasSeenInitialSnapshot = true
        }

        previousRunningAgentIds = runningIds
        previousAlertIds = alertIds
    }

    // MARK: - Derived Telemetry Properties

    var activeMetrics: WindowMetrics {
        switch selectedWindow {
        case .h5: return snapshot.window5h
        case .h24: return snapshot.window24h
        case .d7: return snapshot.window7d
        }
    }

    var runningAgents: [ActiveAgentPulse] {
        snapshot.activeAgents.filter(\.isRunning)
    }

    var hasRunningAgents: Bool {
        !runningAgents.isEmpty
    }

    var lowestQuota: QuotaBucketSnapshot? {
        snapshot.quotas.min(by: { $0.remainingFraction < $1.remainingFraction })
    }

    var lowest5hQuota: QuotaBucketSnapshot? {
        snapshot.quotas
            .filter { $0.id.localizedCaseInsensitiveContains("5h") || $0.label.localizedCaseInsensitiveContains("5h") }
            .min(by: { $0.remainingFraction < $1.remainingFraction })
    }

    var lowestWeeklyQuota: QuotaBucketSnapshot? {
        snapshot.quotas
            .filter {
                $0.id.localizedCaseInsensitiveContains("weekly")
                    || $0.label.localizedCaseInsensitiveContains("wk")
                    || $0.label.localizedCaseInsensitiveContains("week")
            }
            .min(by: { $0.remainingFraction < $1.remainingFraction })
    }

    var pinnedProject: ProjectSpend? {
        if let pinnedId = snapshot.pinnedProjectId {
            return snapshot.projects.first { $0.isPinned || $0.id == pinnedId || $0.name == pinnedId }
        }
        return snapshot.projects.first(where: \.isPinned)
    }

    var topProject: ProjectSpend? {
        snapshot.projects.first
    }

    var isPriorityDrifting: Bool {
        snapshot.alerts.contains { $0.id == "priority-drift" }
    }

    func tokens(for project: ProjectSpend, in window: TelemetryTimeWindow) -> Int {
        switch window {
        case .h5: return project.tokens5h
        case .h24: return project.tokens24h
        case .d7: return project.tokens7d
        }
    }

    func cost(for project: ProjectSpend, in window: TelemetryTimeWindow) -> Double {
        switch window {
        case .h5: return project.cost5h
        case .h24: return project.cost24h
        case .d7: return project.cost7d
        }
    }

    func isOutburningPinned(_ project: ProjectSpend) -> Bool {
        guard let pinned = pinnedProject else { return false }
        if project.id == pinned.id || project.isPinned { return false }
        return project.tokens5h > pinned.tokens5h && project.tokens5h > 0
    }

    var activityIntensity: Double {
        let burnFactor = min(snapshot.window5h.tokensPerMinute / 2_500.0, 1.0)
        let runningFactor = min(Double(runningAgents.count) * 0.28, 0.75)
        let alertBoost = isPriorityDrifting ? 0.2 : 0.0
        return min(max(0.18 + burnFactor * 0.45 + runningFactor + alertBoost, 0.18), 1.0)
    }

    // MARK: - User Actions

    func setMode(_ newMode: HUDMode) {
        guard mode != newMode else { return }
        if newMode == .compact || newMode == .expanded {
            lastVisibleMode = newMode
            userDefaults.set(newMode.rawValue, forKey: DefaultsKeys.lastVisibleMode)
        }
        mode = newMode
        userDefaults.set(newMode.rawValue, forKey: DefaultsKeys.hudMode)
        TelemetryAudio.shared.playModeSwitch()
    }

    func toggleVisibility() {
        if mode == .hidden {
            setMode(lastVisibleMode)
        } else {
            setMode(.hidden)
        }
    }

    func toggleCompactExpanded() {
        switch mode {
        case .compact:
            setMode(.expanded)
        case .expanded:
            setMode(.compact)
        case .hidden:
            setMode(.expanded)
        }
    }

    func setTheme(_ newTheme: HUDTheme) {
        guard theme != newTheme else { return }
        theme = newTheme
        userDefaults.set(newTheme.rawValue, forKey: DefaultsKeys.theme)
        TelemetryAudio.shared.playModeSwitch()
        showToast(icon: "sparkles", message: "THEME // \(newTheme.displayName.uppercased())")
    }

    func setSelectedWindow(_ window: TelemetryTimeWindow) {
        guard selectedWindow != window else { return }
        selectedWindow = window
        userDefaults.set(window.rawValue, forKey: DefaultsKeys.selectedWindow)
        TelemetryAudio.shared.playModeSwitch()
    }

    func toggleGhostMode() {
        isGhostMode.toggle()
        TelemetryAudio.shared.playModeSwitch()
        if isGhostMode {
            if mode == .hidden {
                setMode(lastVisibleMode)
            }
            showToast(
                icon: "eye.slash.fill",
                message: "GHOST MODE ON · ⌘⇧G TO INTERACT",
                isWarning: true,
                duration: 3.0
            )
        } else {
            showToast(icon: "hand.tap.fill", message: "INTERACTIVE MODE RESTORED")
        }
    }

    func toggleAudioMute() {
        isAudioMuted.toggle()
        userDefaults.set(isAudioMuted, forKey: DefaultsKeys.audioMuted)
        TelemetryAudio.shared.isMuted = isAudioMuted
        if !isAudioMuted {
            TelemetryAudio.shared.playModeSwitch()
        }
    }

    func togglePinProject(_ project: ProjectSpend) {
        let shouldUnpin = project.isPinned || snapshot.pinnedProjectId == project.id
        if shouldUnpin {
            engine.pinProject(nil)
            showToast(icon: "star.slash", message: "UNPINNED // \(project.name.uppercased())")
        } else {
            engine.pinProject(project.id)
            showToast(icon: "star.fill", message: "PRIORITY PINNED // \(project.name.uppercased())")
        }
        TelemetryAudio.shared.playPinSound()
    }

    func toggleCLIStatusLineHook() {
        let currentlyInstalled = snapshot.hookInstalled
        if !currentlyInstalled {
            ensureHookScriptExistsIfNeeded()
        }
        let nowInstalled = engine.toggleCLIStatusLineHook()
        TelemetryAudio.shared.playModeSwitch()
        if nowInstalled {
            showToast(icon: "bolt.badge.checkmark.fill", message: "CLI QUOTA HOOK ACTIVE")
        } else {
            showToast(icon: "bolt.slash", message: "CLI QUOTA HOOK DISABLED")
        }
    }

    func refreshNow() {
        engine.refreshNow()
        showToast(icon: "arrow.clockwise", message: "TELEMETRY SYNCED")
    }

    func syncCLIQuotaNow() {
        guard !engine.isAutoSyncing else { return }
        ensureHookScriptExistsIfNeeded()
        TelemetryAudio.shared.playModeSwitch()
        showToast(icon: "arrow.triangle.2.circlepath", message: "SYNCING LIVE QUOTA...")
        engine.syncCLIQuotaNow()
    }

    func toggleAutoSyncEnabled() {
        engine.autoSyncEnabled.toggle()
        TelemetryAudio.shared.playModeSwitch()
        showToast(
            icon: engine.autoSyncEnabled ? "clock.badge.checkmark" : "pause.circle",
            message: engine.autoSyncEnabled ? "AUTO-SYNC EVERY 5M ON" : "AUTO-SYNC PAUSED"
        )
    }

    // MARK: - Launch at Login (SMAppService)

    var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    var isLaunchAtLoginEnabled: Bool {
        guard isRunningFromAppBundle else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    func toggleLaunchAtLogin() {
        guard isRunningFromAppBundle else {
            launchAtLoginError = "Launch at Login requires running from AntigravityHUD.app"
            showToast(icon: "exclamationmark.triangle", message: "REQUIRES .APP BUNDLE FOR LOGIN ITEM", isWarning: true)
            return
        }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                showToast(icon: "power", message: "LAUNCH AT LOGIN DISABLED")
            } else {
                try SMAppService.mainApp.register()
                showToast(icon: "power", message: "LAUNCH AT LOGIN ENABLED")
            }
            launchAtLoginError = nil
            objectWillChange.send()
        } catch {
            launchAtLoginError = error.localizedDescription
            showToast(icon: "exclamationmark.triangle", message: "LOGIN ITEM: \(error.localizedDescription)", isWarning: true)
        }
    }

    // MARK: - Helpers

    func showToast(icon: String, message: String, isWarning: Bool = false, duration: TimeInterval = 2.2) {
        toastClearTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) {
            toast = HUDToast(icon: icon, message: message, isWarning: isWarning)
        }
        toastClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.22)) {
                self?.toast = nil
            }
        }
    }

    /// Ensures `agy-hud-hook.sh` exists at `engine.statusLineBridge.hookScriptPath`
    /// when invoked from an `.app` bundle outside the source checkout.
    private func ensureHookScriptExistsIfNeeded() {
        let targetPath = engine.statusLineBridge.hookScriptPath
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: targetPath),
           let existing = try? String(contentsOfFile: targetPath, encoding: .utf8),
           existing.contains("_has_live_quota") {
            return
        }

        let targetURL = URL(fileURLWithPath: targetPath)
        let dirURL = targetURL.deletingLastPathComponent()
        try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)

        if let bundledScript = Bundle.main.url(forResource: "agy-hud-hook", withExtension: "sh"),
           let data = try? Data(contentsOf: bundledScript) {
            try? data.write(to: targetURL, options: .atomic)
        } else {
            try? Self.embeddedHookScript.write(to: targetURL, atomically: true, encoding: .utf8)
        }
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targetPath)
    }

    private static let embeddedHookScript = """
    #!/usr/bin/env bash
    set -euo pipefail

    HUD_DIR="${AGY_HUD_DIR:-$HOME/.gemini/antigravity-hud}"
    SNAPSHOT_PATH="${AGY_HUD_SNAPSHOT_PATH:-$HUD_DIR/statusline_snapshot.json}"

    mkdir -p "$HUD_DIR"

    INPUT_JSON="$(cat || true)"

    if [ -n "$INPUT_JSON" ]; then
        TMP_FILE="$(mktemp "$HUD_DIR/statusline_snapshot.XXXXXX")"
        if command -v python3 >/dev/null 2>&1; then
            python3 - "$INPUT_JSON" "$SNAPSHOT_PATH" "$TMP_FILE" <<'PY' 2>/dev/null || printf '%s\\n' "$INPUT_JSON" > "$TMP_FILE"
    import json, os, sys

    raw_in, snap_path, tmp_path = sys.argv[1], sys.argv[2], sys.argv[3]
    try:
        data = json.loads(raw_in)
        if not isinstance(data, dict):
            raise ValueError("not dict")
    except Exception:
        with open(tmp_path, "w", encoding="utf-8") as f:
            f.write(raw_in + "\\n")
        sys.exit(0)

    data.pop("email", None)

    q = data.get("quota")
    has_non_empty_quota = isinstance(q, (dict, list)) and len(q) > 0

    if has_non_empty_quota:
        data["_has_live_quota"] = True
    else:
        data["_has_live_quota"] = False
        if os.path.exists(snap_path):
            try:
                with open(snap_path, "r", encoding="utf-8") as prev_f:
                    prev = json.load(prev_f)
                if isinstance(prev, dict):
                    prev_q = prev.get("quota")
                    if isinstance(prev_q, (dict, list)) and len(prev_q) > 0:
                        data["quota"] = prev_q
                    if not data.get("plan_tier") and prev.get("plan_tier"):
                        data["plan_tier"] = prev["plan_tier"]
            except Exception:
                pass

    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(data, f)
        f.write("\\n")
    PY
        else
            printf '%s\\n' "$INPUT_JSON" > "$TMP_FILE"
        fi
        mv -f "$TMP_FILE" "$SNAPSHOT_PATH"
    fi

    if command -v python3 >/dev/null 2>&1 && [ -n "$INPUT_JSON" ]; then
        python3 - "$SNAPSHOT_PATH" "$INPUT_JSON" <<'PY' 2>/dev/null || printf "⚡ AGY HUD\\n"
    import json, os, sys

    snap_path, raw_in = sys.argv[1], sys.argv[2]
    data = {}
    try:
        if os.path.exists(snap_path):
            with open(snap_path, "r", encoding="utf-8") as f:
                data = json.load(f)
        else:
            data = json.loads(raw_in)
    except Exception:
        print("⚡ AGY HUD")
        sys.exit(0)

    model = data.get("plan_tier") or "AGY"
    m = data.get("model")
    if isinstance(m, dict):
        model = m.get("display_name") or m.get("name") or model
    elif isinstance(m, str) and m:
        model = m

    ctx_part = ""
    ctx = data.get("context_window")
    if isinstance(ctx, dict) and ctx.get("used_percentage") is not None:
        try:
            pct = float(ctx["used_percentage"])
            if pct > 0:
                ctx_part = f" · Ctx {pct:.0f}%"
        except Exception:
            pass

    quota_part = ""
    q = data.get("quota")
    if isinstance(q, dict):
        rem = q.get("remaining_fraction")
        if rem is None:
            for k in ("gemini-5h", "3p-5h", "gemini-weekly", "3p-weekly"):
                v = q.get(k)
                if isinstance(v, dict) and v.get("remaining_fraction") is not None:
                    rem = v.get("remaining_fraction")
                    break
        if rem is None:
            for v in q.values():
                if isinstance(v, dict) and v.get("remaining_fraction") is not None:
                    rem = v.get("remaining_fraction")
                    break
        if rem is not None:
            try:
                quota_part = f" · Quota {float(rem) * 100.0:.0f}%"
            except Exception:
                pass

    print(f"⚡ {model}{ctx_part}{quota_part}")
    PY
    else
        printf "⚡ AGY HUD\\n"
    fi
    """
}
