import AppKit
import Combine
import HUDShaders
import SwiftUI

final class FloatingHUDPanel: NSPanel {
    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class HUDWindowController: NSObject, NSWindowDelegate {
    private enum DefaultsKeys {
        static let originX = "com.antigravity.hud.windowOriginX"
        static let originY = "com.antigravity.hud.windowOriginY"
    }

    static let compactSize = CGSize(width: 396, height: 76)
    static let expandedSize = CGSize(width: 548, height: 684)

    private let appState: HUDAppState
    private let userDefaults: UserDefaults
    private let panel: FloatingHUDPanel
    private let visualEffectView: NSVisualEffectView
    private let hostingView: NSHostingView<HUDRootView>

    private var cancellables: Set<AnyCancellable> = []
    private var isProgrammaticFrameUpdate = false
    private var snapWorkItem: DispatchWorkItem?
    private var currentRenderedMode: HUDMode

    init(appState: HUDAppState, userDefaults: UserDefaults = .standard) {
        self.appState = appState
        self.userDefaults = userDefaults
        self.currentRenderedMode = appState.mode == .hidden ? appState.lastVisibleMode : appState.mode

        let initialSize = Self.size(for: appState.mode == .hidden ? appState.lastVisibleMode : appState.mode)
        let initialFrame = CGRect(origin: .zero, size: initialSize)

        let panel = FloatingHUDPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none

        let visualEffect = NSVisualEffectView(frame: CGRect(origin: .zero, size: initialSize))
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerCurve = .continuous
        visualEffect.layer?.cornerRadius = Self.cornerRadius(for: appState.mode == .hidden ? appState.lastVisibleMode : appState.mode)
        visualEffect.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: HUDRootView(appState: appState))
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        visualEffect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor)
        ])

        panel.contentView = visualEffect

        self.panel = panel
        self.visualEffectView = visualEffect
        self.hostingView = hosting

        super.init()

        panel.delegate = self
        restoreInitialFrame(size: initialSize)
        observeState()
        observeScreenChanges()

        applyMode(appState.mode, animated: false)
        applyGhostMode(appState.isGhostMode, animated: false)
    }

    private func observeState() {
        appState.$mode
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] newMode in
                self?.applyMode(newMode, animated: true)
            }
            .store(in: &cancellables)

        appState.$isGhostMode
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] ghost in
                self?.applyGhostMode(ghost, animated: true)
            }
            .store(in: &cancellables)
    }

    private func observeScreenChanges() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.clampCurrentFrameToScreen(animated: false)
            }
            .store(in: &cancellables)
    }

    // MARK: - Mode & Ghost Transitions

    private func applyMode(_ mode: HUDMode, animated: Bool) {
        if mode == .hidden {
            panel.orderOut(nil)
            return
        }

        let targetSize = Self.size(for: mode)
        let currentFrame = panel.frame
        let screen = targetScreen(for: currentFrame)
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        let anchoredOrigin = anchoredOriginForResize(
            currentFrame: currentFrame,
            newSize: targetSize,
            visibleFrame: visibleFrame
        )
        let clampedOrigin = clampOrigin(anchoredOrigin, size: targetSize, inside: visibleFrame)
        let targetFrame = CGRect(origin: clampedOrigin, size: targetSize)

        currentRenderedMode = mode
        visualEffectView.layer?.cornerRadius = Self.cornerRadius(for: mode)

        setPanelFrame(targetFrame, animated: animated)
        persistOrigin(targetFrame.origin)
        panel.invalidateShadow()

        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func applyGhostMode(_ isGhost: Bool, animated: Bool) {
        panel.ignoresMouseEvents = isGhost
        if isGhost && panel.isKeyWindow {
            panel.resignKey()
        }
        let targetAlpha: CGFloat = isGhost ? 0.62 : 1.0
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.20
                panel.animator().alphaValue = targetAlpha
            }
        } else {
            panel.alphaValue = targetAlpha
        }
    }

    // MARK: - Positioning, Clamping & Magnetic Edge Snapping

    private func restoreInitialFrame(size: CGSize) {
        let fallbackScreen = NSScreen.main ?? NSScreen.screens.first
        let visible = fallbackScreen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        let desiredOrigin: CGPoint
        if userDefaults.object(forKey: DefaultsKeys.originX) != nil,
           userDefaults.object(forKey: DefaultsKeys.originY) != nil {
            desiredOrigin = CGPoint(
                x: userDefaults.double(forKey: DefaultsKeys.originX),
                y: userDefaults.double(forKey: DefaultsKeys.originY)
            )
        } else {
            // Default position: clean top-right orbital perch
            desiredOrigin = CGPoint(
                x: visible.maxX - size.width - 20,
                y: visible.maxY - size.height - 20
            )
        }

        let probeFrame = CGRect(origin: desiredOrigin, size: size)
        let screen = targetScreen(for: probeFrame) ?? fallbackScreen
        let targetVisible = screen?.visibleFrame ?? visible
        let clampedOrigin = clampOrigin(desiredOrigin, size: size, inside: targetVisible)
        let finalFrame = CGRect(origin: clampedOrigin, size: size)

        setPanelFrame(finalFrame, animated: false)
        persistOrigin(clampedOrigin)
    }

    private func anchoredOriginForResize(
        currentFrame: CGRect,
        newSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        let onRightHalf = currentFrame.midX >= visibleFrame.midX
        let onUpperHalf = currentFrame.midY >= visibleFrame.midY

        let newX = onRightHalf ? (currentFrame.maxX - newSize.width) : currentFrame.minX
        let newY = onUpperHalf ? (currentFrame.maxY - newSize.height) : currentFrame.minY
        return CGPoint(x: newX, y: newY)
    }

    private func clampCurrentFrameToScreen(animated: Bool) {
        let frame = panel.frame
        let screen = targetScreen(for: frame) ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let clamped = clampOrigin(frame.origin, size: frame.size, inside: visible)
        if clamped != frame.origin {
            setPanelFrame(CGRect(origin: clamped, size: frame.size), animated: animated)
            persistOrigin(clamped)
        }
    }

    private func snapAndClampAfterDrag() {
        let frame = panel.frame
        guard let visible = (targetScreen(for: frame) ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
            return
        }

        let margin: CGFloat = 10
        let snapThreshold: CGFloat = 18
        var snapped = clampOrigin(frame.origin, size: frame.size, inside: visible, margin: margin)

        if abs(snapped.x - (visible.minX + margin)) <= snapThreshold {
            snapped.x = visible.minX + margin
        } else if abs((snapped.x + frame.width) - (visible.maxX - margin)) <= snapThreshold {
            snapped.x = visible.maxX - margin - frame.width
        }

        if abs(snapped.y - (visible.minY + margin)) <= snapThreshold {
            snapped.y = visible.minY + margin
        } else if abs((snapped.y + frame.height) - (visible.maxY - margin)) <= snapThreshold {
            snapped.y = visible.maxY - margin - frame.height
        }

        if abs(snapped.x - frame.origin.x) > 0.5 || abs(snapped.y - frame.origin.y) > 0.5 {
            setPanelFrame(CGRect(origin: snapped, size: frame.size), animated: true)
        }
        persistOrigin(snapped)
    }

    private func targetScreen(for frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let containing = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return containing
        }
        var bestScreen: NSScreen?
        var bestArea: CGFloat = 0
        for screen in NSScreen.screens {
            let inter = screen.frame.intersection(frame)
            let area = inter.isNull ? 0 : inter.width * inter.height
            if area > bestArea {
                bestArea = area
                bestScreen = screen
            }
        }
        return bestScreen ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func clampOrigin(
        _ origin: CGPoint,
        size: CGSize,
        inside visible: CGRect,
        margin: CGFloat = 8
    ) -> CGPoint {
        let minX = visible.minX + margin
        let maxX = max(minX, visible.maxX - margin - size.width)
        let minY = visible.minY + margin
        let maxY = max(minY, visible.maxY - margin - size.height)

        return CGPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    private func setPanelFrame(_ frame: CGRect, animated: Bool) {
        isProgrammaticFrameUpdate = true
        panel.setFrame(frame, display: true, animate: animated)
        isProgrammaticFrameUpdate = false
    }

    private func persistOrigin(_ origin: CGPoint) {
        userDefaults.set(Double(origin.x), forKey: DefaultsKeys.originX)
        userDefaults.set(Double(origin.y), forKey: DefaultsKeys.originY)
    }

    private static func size(for mode: HUDMode) -> CGSize {
        switch mode {
        case .compact: return compactSize
        case .expanded, .hidden: return expandedSize
        }
    }

    private static func cornerRadius(for mode: HUDMode) -> CGFloat {
        switch mode {
        case .compact: return 22
        case .expanded, .hidden: return 20
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticFrameUpdate else { return }
        persistOrigin(panel.frame.origin)

        snapWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.snapAndClampAfterDrag()
            }
        }
        snapWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }
}
