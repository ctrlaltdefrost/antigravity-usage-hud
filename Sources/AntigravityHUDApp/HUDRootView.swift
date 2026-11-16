import HUDShaders
import SwiftUI

struct HUDRootView: View {
    @ObservedObject var appState: HUDAppState

    var body: some View {
        let theme = appState.theme
        let cornerRadius: CGFloat = appState.mode == .compact ? 22 : 20
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            if appState.mode != .hidden {
                MetalReactorBackdrop(
                    theme: theme,
                    activityIntensity: appState.activityIntensity,
                    isPulseActive: appState.hasRunningAgents,
                    cornerRadius: cornerRadius
                )
                .allowsHitTesting(false)
            }

            switch appState.mode {
            case .compact:
                CompactHUDView(appState: appState)
            case .expanded:
                CommandDeckView(appState: appState)
            case .hidden:
                Color.clear
            }

            // Persistent Ghost Mode Strip (lets user know clicks pass through)
            if appState.isGhostMode && appState.mode != .hidden {
                VStack {
                    Spacer()
                    HStack(spacing: 5) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 8.5))
                        Text("GHOST PASS-THROUGH · ⌘⇧G TO INTERACT")
                            .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                    }
                    .foregroundStyle(theme.warning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(Color.black.opacity(0.72)))
                    .overlay(Capsule().stroke(theme.warning.opacity(0.7), lineWidth: 0.75))
                    .padding(.bottom, 5)
                }
                .allowsHitTesting(false)
            }

            // Transient Toast Overlay
            if let toast = appState.toast, appState.mode != .hidden {
                VStack {
                    HStack(spacing: 6) {
                        Image(systemName: toast.icon)
                            .font(.system(size: 10.5, weight: .bold))
                        Text(toast.message)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(toast.isWarning ? theme.warning : theme.accent)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.84))
                    )
                    .overlay(
                        Capsule()
                            .stroke((toast.isWarning ? theme.warning : theme.accent).opacity(0.8), lineWidth: 0.9)
                    )
                    .shadow(color: (toast.isWarning ? theme.warning : theme.accent).opacity(0.35), radius: 8)
                    .padding(.top, appState.mode == .compact ? 4 : 10)

                    Spacer()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .allowsHitTesting(false)
            }
        }
        .clipShape(shape)
        .overlay(
            shape
                .stroke(
                    appState.isGhostMode
                        ? AnyShapeStyle(theme.warning.opacity(0.75))
                        : AnyShapeStyle(theme.borderGradient),
                    lineWidth: appState.isGhostMode ? 1.3 : 1.1
                )
        )
        .shadow(color: theme.glowColor.opacity(0.18), radius: 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
