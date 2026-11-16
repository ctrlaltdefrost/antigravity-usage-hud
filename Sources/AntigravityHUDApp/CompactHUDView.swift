import HUDShaders
import SwiftUI
import TelemetryCore

struct CompactHUDView: View {
    @ObservedObject var appState: HUDAppState

    var body: some View {
        let theme = appState.theme
        let lowestQuota = appState.lowestQuota
        let ringProgress = lowestQuota?.remainingFraction ?? max(0.15, 1.0 - min(Double(appState.snapshot.window5h.totalTokens) / 25_000_000.0, 0.85))
        let ringMetric = HUDFormatters.percent(ringProgress)
        let isLowQuota = (lowestQuota?.sourceBadge == "LIVE CLI" || lowestQuota?.sourceBadge == "CALIBRATED") && ringProgress < 0.25

        HStack(spacing: 10) {
            // Mini Orbital Gauge
            OrbitalRingGauge(
                progress: ringProgress,
                metricText: ringMetric,
                subtitle: nil,
                countdownText: nil,
                theme: theme,
                isActive: appState.hasRunningAgents,
                isWarning: isLowQuota,
                size: 50,
                showTicks: false
            )
            .help(lowestQuota.map { "\($0.label): \(ringMetric) remaining" } ?? "5h Quota Pool")

            // Active Agent Reactor Pulse
            ReactorPulseIndicator(
                theme: theme,
                isActive: appState.hasRunningAgents,
                size: 22,
                style: .combined
            )
            .help(appState.hasRunningAgents ? "\(appState.runningAgents.count) agent(s) running" : "All agents idle")

            // Center Telemetry Stack
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if let project = appState.topProject {
                        let isDrifting = appState.isOutburningPinned(project)
                        HStack(spacing: 4) {
                            if project.isPinned {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundStyle(theme.accent)
                            } else if isDrifting {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundStyle(theme.warning)
                            }
                            Text(project.name)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(isDrifting ? theme.warning : theme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule()
                                .fill((isDrifting ? theme.warning : theme.primary).opacity(0.15))
                        )
                        .overlay(
                            Capsule()
                                .stroke((isDrifting ? theme.warning : theme.primary).opacity(0.45), lineWidth: 0.75)
                        )
                    } else {
                        Text("NO ACTIVE WORKSPACE")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.textSecondary)
                    }

                    Spacer(minLength: 2)

                    if let quota = lowestQuota {
                        TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                            let cd = HUDFormatters.countdown(
                                resetTime: quota.resetTime,
                                fallbackSeconds: quota.resetInSeconds,
                                now: timeline.date
                            )
                            HStack(spacing: 3) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 8.5, weight: .semibold))
                                Text(cd)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .monospacedDigit()
                            }
                            .foregroundStyle(isLowQuota ? theme.warning : theme.accent)
                        }
                    }
                }

                HStack(spacing: 8) {
                    let w5 = appState.snapshot.window5h
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(theme.primary)
                        Text("\(HUDFormatters.tokens(w5.totalTokens))/5h")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(theme.textPrimary)
                    }

                    Text("·")
                        .foregroundStyle(theme.textSecondary.opacity(0.6))

                    Text(HUDFormatters.rate(w5.tokensPerMinute))
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)

                    if appState.hasRunningAgents {
                        Text("\(appState.runningAgents.count) RUN")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(theme.accent.opacity(0.16)))
                            .overlay(Capsule().stroke(theme.accent.opacity(0.45), lineWidth: 0.7))
                    } else if w5.cacheHitRate > 0 {
                        Text("\(HUDFormatters.percent(w5.cacheHitRate)) HIT")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.secondary)
                    }

                    Spacer(minLength: 0)
                }
            }

            // Right Controls
            HStack(spacing: 5) {
                HUDIconButton(
                    systemName: appState.isGhostMode ? "eye.slash.fill" : "cursorarrow.rays",
                    theme: theme,
                    isActive: appState.isGhostMode,
                    activeColor: theme.warning,
                    tooltip: "Ghost Click-Through Mode (⌘⇧G)"
                ) {
                    appState.toggleGhostMode()
                }

                HUDIconButton(
                    systemName: "arrow.up.left.and.arrow.down.right",
                    theme: theme,
                    isActive: false,
                    tooltip: "Expand Command Deck (⌘⇧E)"
                ) {
                    appState.setMode(.expanded)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            appState.setMode(.expanded)
        }
    }
}

struct HUDIconButton: View {
    let systemName: String
    let theme: HUDTheme
    var isActive: Bool = false
    var activeColor: Color? = nil
    var size: CGFloat = 26
    var tooltip: String = ""
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        let tint = isActive ? (activeColor ?? theme.accent) : (isHovering ? theme.primary : theme.textSecondary)
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isActive ? tint.opacity(0.20) : (isHovering ? theme.primary.opacity(0.14) : Color.white.opacity(0.05)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(tint.opacity(isActive ? 0.65 : (isHovering ? 0.45 : 0.18)), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(tooltip)
    }
}
