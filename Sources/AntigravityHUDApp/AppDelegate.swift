import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: HUDAppState?
    private var windowController: HUDWindowController?
    private var menuBarController: MenuBarController?
    private var hotKeyManager: GlobalHotKeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let state = HUDAppState()
        let windowCtrl = HUDWindowController(appState: state)
        let menuCtrl = MenuBarController(appState: state)
        let hotKeys = GlobalHotKeyManager()

        hotKeys.onToggleVisibility = { [weak state] in
            state?.toggleVisibility()
        }
        hotKeys.onToggleGhostMode = { [weak state] in
            state?.toggleGhostMode()
        }
        hotKeys.onToggleExpand = { [weak state] in
            state?.toggleCompactExpanded()
        }

        self.appState = state
        self.windowController = windowCtrl
        self.menuBarController = menuCtrl
        self.hotKeyManager = hotKeys
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.engine.stopPolling()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
