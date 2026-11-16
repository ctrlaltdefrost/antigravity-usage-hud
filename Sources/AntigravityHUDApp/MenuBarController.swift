import AppKit
import Combine
import HUDShaders
import TelemetryCore

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let appState: HUDAppState
    private let statusItem: NSStatusItem
    private let menu: NSMenu

    private var cancellables: Set<AnyCancellable> = []

    init(appState: HUDAppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.menu = NSMenu(title: "Antigravity HUD")

        super.init()

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        if let button = statusItem.button {
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            button.imagePosition = .imageLeading
        }

        updateStatusButton()
        observeState()
    }

    private func observeState() {
        appState.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusButton()
            }
            .store(in: &cancellables)

        appState.$isGhostMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusButton()
            }
            .store(in: &cancellables)

        appState.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusButton()
            }
            .store(in: &cancellables)

        appState.$isAutoSyncing
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusButton()
            }
            .store(in: &cancellables)
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        let snap = appState.snapshot
        let burnText = "\(HUDFormatters.tokens(snap.window5h.totalTokens))/5h"
        let quotaText = appState.lowestQuota.map { HUDFormatters.percent($0.remainingFraction) } ?? "--"
        let runningCount = appState.runningAgents.count

        let symbolName: String
        if appState.isGhostMode {
            symbolName = "eye.slash.fill"
        } else if runningCount > 0 {
            symbolName = "waveform.path.ecg"
        } else {
            symbolName = "bolt.fill"
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Antigravity Telemetry HUD") {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            let configured = image.withSymbolConfiguration(config) ?? image
            configured.isTemplate = true
            button.image = configured
        }

        var parts: [String] = []
        if appState.isGhostMode {
            parts.append("GHOST")
        } else if runningCount > 0 {
            parts.append("\(runningCount) RUN")
        }

        if let q5h = appState.lowest5hQuota, let qWk = appState.lowestWeeklyQuota {
            parts.append("\(HUDFormatters.percent(q5h.remainingFraction)) 5H")
            parts.append("\(HUDFormatters.percent(qWk.remainingFraction)) WK")
        } else {
            parts.append(quotaText)
            parts.append(burnText)
        }
        button.title = " " + parts.joined(separator: " · ")

        let tooltipRate = HUDFormatters.rate(snap.window5h.tokensPerMinute)
        let tierPart = snap.planTier.map { " · \($0)" } ?? ""
        button.toolTip = "Antigravity HUD\(tierPart) · \(burnText) (\(tooltipRate)) · Lowest Quota \(quotaText)"
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let snap = appState.snapshot
        let w5 = snap.window5h

        // Summary Header
        let summaryTitle = "5h: \(HUDFormatters.tokens(w5.totalTokens)) · \(HUDFormatters.rate(w5.tokensPerMinute)) · Cache \(HUDFormatters.percent(w5.cacheHitRate))"
        let headerItem = NSMenuItem(title: summaryTitle, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        if let planTier = snap.planTier, !planTier.isEmpty {
            let tierItem = NSMenuItem(title: "Plan: \(planTier)", action: nil, keyEquivalent: "")
            tierItem.isEnabled = false
            menu.addItem(tierItem)
        }

        if let model = snap.activeModelName, !model.isEmpty {
            let modelItem = NSMenuItem(title: "CLI Model: \(model)", action: nil, keyEquivalent: "")
            modelItem.isEnabled = false
            menu.addItem(modelItem)
        }

        if let syncStatus = appState.lastAutoSyncStatus, !syncStatus.isEmpty {
            let syncInfoItem = NSMenuItem(title: "Quota Sync: \(syncStatus)", action: nil, keyEquivalent: "")
            syncInfoItem.isEnabled = false
            menu.addItem(syncInfoItem)
        }

        menu.addItem(.separator())

        // Mode Switchers
        let compactItem = makeActionItem(
            title: "Compact Reactor Pill",
            action: #selector(selectCompactMode),
            checked: appState.mode == .compact
        )
        let expandedItem = makeActionItem(
            title: "Full Command Deck",
            action: #selector(selectExpandedMode),
            checked: appState.mode == .expanded
        )
        let hiddenItem = makeActionItem(
            title: "Hide HUD",
            action: #selector(selectHiddenMode),
            keyEquivalent: "h",
            modifiers: [.command, .shift],
            checked: appState.mode == .hidden
        )
        menu.addItem(compactItem)
        menu.addItem(expandedItem)
        menu.addItem(hiddenItem)

        menu.addItem(.separator())

        // Ghost Click-Through Mode
        let ghostItem = makeActionItem(
            title: appState.isGhostMode ? "Disable Ghost Click-Through Mode" : "Ghost Click-Through Mode",
            action: #selector(toggleGhostMode),
            keyEquivalent: "g",
            modifiers: [.command, .shift],
            checked: appState.isGhostMode
        )
        menu.addItem(ghostItem)

        // Theme Picker Submenu
        let themeRoot = NSMenuItem(title: "Theme: \(appState.theme.displayName)", action: nil, keyEquivalent: "")
        let themeSubmenu = NSMenu(title: "Theme")
        for theme in HUDTheme.allCases {
            let item = NSMenuItem(
                title: theme.displayName,
                action: #selector(selectTheme(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = theme.rawValue
            item.state = (theme == appState.theme) ? .on : .off
            themeSubmenu.addItem(item)
        }
        themeRoot.submenu = themeSubmenu
        menu.addItem(themeRoot)

        // Sound FX Mute Toggle
        let muteItem = makeActionItem(
            title: "Mute Sound FX",
            action: #selector(toggleSoundMute),
            checked: appState.isAudioMuted
        )
        menu.addItem(muteItem)

        // Launch at Login Toggle
        let loginItem = makeActionItem(
            title: appState.isRunningFromAppBundle ? "Launch at Login" : "Launch at Login (.app bundle only)",
            action: #selector(toggleLaunchAtLogin),
            checked: appState.isLaunchAtLoginEnabled
        )
        loginItem.isEnabled = appState.isRunningFromAppBundle
        menu.addItem(loginItem)

        // Official agy CLI statusLine Hook & Auto-Sync
        let syncNowItem = makeActionItem(
            title: appState.isAutoSyncing ? "Syncing Live Quota…" : "Sync Live Quota Now",
            action: #selector(syncLiveQuotaNow)
        )
        syncNowItem.isEnabled = !appState.isAutoSyncing
        menu.addItem(syncNowItem)

        let autoSyncItem = makeActionItem(
            title: "Auto-Sync Quota Every 5m",
            action: #selector(toggleAutoSync),
            checked: appState.autoSyncEnabled
        )
        menu.addItem(autoSyncItem)

        let hookTitle = snap.hookInstalled
            ? "CLI Hook Active ✓ (Disable)"
            : "Enable Live CLI Quota Hook"
        let hookItem = makeActionItem(
            title: hookTitle,
            action: #selector(toggleCLIStatusLineHook),
            checked: snap.hookInstalled
        )
        menu.addItem(hookItem)

        menu.addItem(.separator())

        let refreshItem = makeActionItem(
            title: "Refresh Now",
            action: #selector(refreshNow),
            keyEquivalent: "r",
            modifiers: [.command]
        )
        let quitItem = makeActionItem(
            title: "Quit Antigravity HUD",
            action: #selector(quitApp),
            keyEquivalent: "q",
            modifiers: [.command]
        )
        menu.addItem(refreshItem)
        menu.addItem(quitItem)
    }

    private func makeActionItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = [],
        checked: Bool = false
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if !modifiers.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        item.state = checked ? .on : .off
        return item
    }

    // MARK: - Menu Actions

    @objc private func selectCompactMode() {
        appState.setMode(.compact)
    }

    @objc private func selectExpandedMode() {
        appState.setMode(.expanded)
    }

    @objc private func selectHiddenMode() {
        appState.setMode(.hidden)
    }

    @objc private func toggleGhostMode() {
        appState.toggleGhostMode()
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let theme = HUDTheme(rawValue: raw) else {
            return
        }
        appState.setTheme(theme)
    }

    @objc private func toggleSoundMute() {
        appState.toggleAudioMute()
    }

    @objc private func toggleLaunchAtLogin() {
        appState.toggleLaunchAtLogin()
    }

    @objc private func toggleCLIStatusLineHook() {
        appState.toggleCLIStatusLineHook()
    }

    @objc private func syncLiveQuotaNow() {
        appState.syncCLIQuotaNow()
    }

    @objc private func toggleAutoSync() {
        appState.toggleAutoSyncEnabled()
    }

    @objc private func refreshNow() {
        appState.refreshNow()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
