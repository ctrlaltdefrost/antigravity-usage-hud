import HUDShaders
import SwiftUI
import TelemetryCore

struct CommandDeckView: View {
    @ObservedObject var appState: HUDAppState

    @State private var showCalibrationPopover = false
    @State private var selectedAlertIndex = 0

    var body: some View {
        let theme = appState.theme

        VStack(spacing: 10) {
            headerBar(theme: theme)

            prioritizationAdvisorBanner(theme: theme)

            quotaAndVelocityCore(theme: theme)

            projectSpendRadar(theme: theme)

            liveAgentPulseFeed(theme: theme)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 1. Header Bar

    @ViewBuilder
    private func headerBar(theme: HUDTheme) -> some View {
        HStack(spacing: 8) {
            // Reactor Emblem + Title
            HStack(spacing: 7) {
                ReactorPulseIndicator(
                    theme: theme,
                    isActive: appState.hasRunningAgents,
                    size: 22,
                    style: .radar
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text("ANTIGRAVITY // ORBITAL TELEMETRY")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        liveAgentBadge(theme: theme)

                        if let model = appState.snapshot.activeModelName, !model.isEmpty {
                            Text(model.uppercased())
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.primary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(theme.primary.opacity(0.14)))
                                .overlay(Capsule().stroke(theme.primary.opacity(0.4), lineWidth: 0.6))
                                .lineLimit(1)
                        }

                        if let ctxPct = appState.snapshot.cliContextUsedPercent {
                            Text("CLI CTX \(Int(ctxPct.rounded()))%")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(theme.secondary)
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            // Theme Switcher Pills
            HStack(spacing: 4) {
                ForEach(HUDTheme.allCases) { option in
                    let isSelected = option == theme
                    Button {
                        appState.setTheme(option)
                    } label: {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(option.primary)
                                .frame(width: 6, height: 6)
                                .shadow(color: isSelected ? option.primary : .clear, radius: 3)
                            if isSelected {
                                Text(option.shortName)
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(option.textPrimary)
                            }
                        }
                        .padding(.horizontal, isSelected ? 6 : 5)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(isSelected ? option.primary.opacity(0.20) : Color.white.opacity(0.05))
                        )
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? option.primary.opacity(0.8) : Color.white.opacity(0.14), lineWidth: 0.75)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Theme: \(option.displayName)")
                }
            }

            // Action Buttons: Mute, Ghost, Collapse, Hide
            HStack(spacing: 4) {
                HUDIconButton(
                    systemName: appState.isAudioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    theme: theme,
                    isActive: !appState.isAudioMuted,
                    activeColor: theme.accent,
                    size: 24,
                    tooltip: appState.isAudioMuted ? "Unmute Sci-Fi Audio" : "Mute Sci-Fi Audio"
                ) {
                    appState.toggleAudioMute()
                }

                HUDIconButton(
                    systemName: appState.isGhostMode ? "eye.slash.fill" : "cursorarrow.rays",
                    theme: theme,
                    isActive: appState.isGhostMode,
                    activeColor: theme.warning,
                    size: 24,
                    tooltip: "Ghost Click-Through Mode (⌘⇧G)"
                ) {
                    appState.toggleGhostMode()
                }

                HUDIconButton(
                    systemName: "rectangle.compress.vertical",
                    theme: theme,
                    size: 24,
                    tooltip: "Collapse to Compact Pill (⌘⇧E)"
                ) {
                    appState.setMode(.compact)
                }

                HUDIconButton(
                    systemName: "xmark",
                    theme: theme,
                    size: 24,
                    tooltip: "Hide HUD to Menu Bar (⌘⇧H)"
                ) {
                    appState.setMode(.hidden)
                }
            }
        }
    }

    @ViewBuilder
    private func liveAgentBadge(theme: HUDTheme) -> some View {
        let count = appState.runningAgents.count
        let isLive = count > 0
        HStack(spacing: 4) {
            Circle()
                .fill(isLive ? theme.accent : theme.textSecondary.opacity(0.5))
                .frame(width: 5.5, height: 5.5)
                .shadow(color: isLive ? theme.accent : .clear, radius: 4)
            Text(isLive ? "\(count) LIVE AGENT\(count == 1 ? "" : "S")" : "STANDBY")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(isLive ? theme.accent : theme.textSecondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1.5)
        .background(Capsule().fill((isLive ? theme.accent : theme.textSecondary).opacity(0.12)))
        .overlay(Capsule().stroke((isLive ? theme.accent : theme.textSecondary).opacity(0.35), lineWidth: 0.6))
    }

    // MARK: - 2. Prioritization Advisor Banner

    @ViewBuilder
    private func prioritizationAdvisorBanner(theme: HUDTheme) -> some View {
        let alerts = sortedAlerts(appState.snapshot.alerts)
        if alerts.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: appState.pinnedProject != nil ? "checkmark.shield.fill" : "scope")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.pinnedProject.map { "PRIORITY LOCK NOMINAL // \($0.name.uppercased())" } ?? "PRIORITIZATION ADVISOR // STANDBY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.accent)
                    Text(appState.pinnedProject != nil
                         ? "No drift or quota threats detected. Telemetry polling every 2.5s."
                         : "Click the ★ Star icon on your top project below to arm Priority Drift alerts.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button {
                    appState.refreshNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(theme.primary)
                        .padding(5)
                        .background(Circle().fill(theme.primary.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .help("Refresh Telemetry Now")
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(theme.accent.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(theme.accent.opacity(0.35), lineWidth: 0.9)
            )
        } else {
            let safeIdx = min(selectedAlertIndex, alerts.count - 1)
            let activeAlert = alerts[safeIdx]
            let color = alertColor(for: activeAlert.severity, theme: theme)
            let icon = alertIcon(for: activeAlert.severity)

            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(color)
                    .shadow(color: color.opacity(0.7), radius: 5)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(activeAlert.severity.uppercased())
                            .font(.system(size: 8.5, weight: .black, design: .monospaced))
                            .foregroundStyle(.black.opacity(0.85))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(color))

                        Text(activeAlert.title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                    }

                    Text(activeAlert.detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                if alerts.count > 1 {
                    HStack(spacing: 4) {
                        Button {
                            selectedAlertIndex = (safeIdx - 1 + alerts.count) % alerts.count
                            TelemetryAudio.shared.playModeSwitch()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(color)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(color.opacity(0.16)))
                        }
                        .buttonStyle(.plain)

                        Text("\(safeIdx + 1)/\(alerts.count)")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(color)

                        Button {
                            selectedAlertIndex = (safeIdx + 1) % alerts.count
                            TelemetryAudio.shared.playModeSwitch()
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(color)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(color.opacity(0.16)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(color.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(color.opacity(0.65), lineWidth: 1.0)
            )
            .shadow(color: color.opacity(0.20), radius: 8)
        }
    }

    private func sortedAlerts(_ alerts: [PriorityAlert]) -> [PriorityAlert] {
        func rank(_ s: String) -> Int {
            switch s {
            case "critical": return 0
            case "warning": return 1
            default: return 2
            }
        }
        return alerts.sorted { rank($0.severity) < rank($1.severity) }
    }

    private func alertColor(for severity: String, theme: HUDTheme) -> Color {
        switch severity {
        case "critical": return theme.danger
        case "warning": return theme.warning
        default: return theme.accent
        }
    }

    private func alertIcon(for severity: String) -> String {
        switch severity {
        case "critical": return "flame.fill"
        case "warning": return "exclamationmark.triangle.fill"
        default: return "cpu.fill"
        }
    }

    // MARK: - 3. Quota & Burn Velocity Core

    @ViewBuilder
    private func quotaAndVelocityCore(theme: HUDTheme) -> some View {
        let metrics = appState.activeMetrics
        let hasLiveCLI = appState.snapshot.quotas.contains { $0.sourceBadge == "LIVE CLI" }
        let hasCalibrated = appState.snapshot.quotas.contains { $0.sourceBadge == "CALIBRATED" }
        let quotaModeLabel = hasLiveCLI ? "LIVE CLI" : (hasCalibrated ? "CALIBRATED" : "PACE EST.")
        let quotaModeColor = hasLiveCLI ? theme.accent : (hasCalibrated ? theme.primary : theme.secondary)
        let hasLowQuotaAlert = appState.snapshot.quotas.contains {
            ($0.sourceBadge == "LIVE CLI" || $0.sourceBadge == "CALIBRATED") && $0.remainingFraction < 0.25
        }

        CyberPanelCard(
            theme: theme,
            title: nil,
            badge: nil,
            isAlert: hasLowQuotaAlert,
            alertColor: theme.warning,
            cornerRadius: 13,
            padding: 10
        ) {
            VStack(spacing: 8) {
                // Sub-header: Title + Calibrate + Sync CLI + Window Selector
                HStack(spacing: 5) {
                    HStack(spacing: 4) {
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 6.5))
                            .foregroundStyle(theme.primary)
                        Text("QUOTA & VELOCITY")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                            .fixedSize()
                    }

                    Text(quotaModeLabel)
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundStyle(quotaModeColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(quotaModeColor.opacity(0.16)))
                        .overlay(Capsule().stroke(quotaModeColor.opacity(0.45), lineWidth: 0.7))
                        .fixedSize()

                    Button {
                        showCalibrationPopover.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 8.5))
                            Text("Calibrate")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        }
                        .foregroundStyle(theme.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(theme.primary.opacity(0.14)))
                        .overlay(Capsule().stroke(theme.primary.opacity(0.45), lineWidth: 0.75))
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showCalibrationPopover, arrowEdge: .bottom) {
                        QuotaCalibrationPopover(appState: appState)
                    }

                    if !appState.snapshot.hookInstalled {
                        Button {
                            appState.toggleCLIStatusLineHook()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 8.5))
                                Text("Sync CLI")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(theme.accent.opacity(0.16)))
                            .overlay(Capsule().stroke(theme.accent.opacity(0.55), lineWidth: 0.75))
                            .fixedSize()
                        }
                        .buttonStyle(.plain)
                        .help("Enable official agy CLI statusLine hook for live quota sync")
                    } else if !hasLiveCLI {
                        HStack(spacing: 2.5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 8))
                            Text("CLI SYNCED")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(theme.accent.opacity(0.14)))
                        .overlay(Capsule().stroke(theme.accent.opacity(0.42), lineWidth: 0.7))
                        .fixedSize()
                        .help("CLI hook active — run 'agy' in terminal to stream exact backend quota % & reset times, or click Calibrate to sync Desktop Settings.")
                    }

                    Spacer(minLength: 2)

                    // Rolling Window Selector
                    HStack(spacing: 3) {
                        ForEach(TelemetryTimeWindow.allCases) { window in
                            let selected = appState.selectedWindow == window
                            Button {
                                appState.setSelectedWindow(window)
                            } label: {
                                Text(window.shortTitle)
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(selected ? theme.textPrimary : theme.textSecondary)
                                    .padding(.horizontal, 5.5)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(selected ? theme.primary.opacity(0.24) : Color.white.opacity(0.04))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(selected ? theme.primary.opacity(0.75) : Color.white.opacity(0.10), lineWidth: 0.75)
                                    )
                                    .fixedSize()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Main Dual-Column Core
                HStack(alignment: .center, spacing: 12) {
                    // Left: Orbital Quota Rings with ticking countdown
                    let quotas = appState.snapshot.quotas
                    let ringSize: CGFloat = quotas.count == 1 ? 112 : 98
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(quotas.prefix(4)) { quota in
                                VStack(spacing: 4) {
                                    TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                                        let countdown = HUDFormatters.countdown(
                                            resetTime: quota.resetTime,
                                            fallbackSeconds: quota.resetInSeconds,
                                            now: timeline.date
                                        )
                                        OrbitalRingGauge(
                                            progress: quota.remainingFraction,
                                            metricText: HUDFormatters.percent(quota.remainingFraction),
                                            subtitle: compactQuotaLabel(quota.label),
                                            countdownText: "↻ \(countdown)",
                                            theme: theme,
                                            isActive: appState.hasRunningAgents,
                                            isWarning: (quota.sourceBadge == "LIVE CLI" || quota.sourceBadge == "CALIBRATED") && quota.remainingFraction < 0.25,
                                            size: ringSize,
                                            showTicks: true
                                        )
                                    }
                                    .frame(width: ringSize, height: ringSize)

                                    Text(quota.sourceBadge)
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(quota.sourceBadge == "LIVE CLI" ? theme.accent : theme.textSecondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(width: quotas.count == 1 ? 122 : 212)

                    // Right: Sparkline + Burn Velocity Stats
                    VStack(alignment: .leading, spacing: 7) {
                        VelocitySparklineView(
                            data: metrics.sparklineBuckets,
                            theme: theme,
                            isActive: appState.hasRunningAgents,
                            height: 76,
                            unitSuffix: "/m"
                        )

                        // Metrics Strip
                        HStack(spacing: 8) {
                            statPill(
                                label: "BURN RATE",
                                value: HUDFormatters.rate(metrics.tokensPerMinute),
                                color: theme.primary,
                                theme: theme
                            )
                            statPill(
                                label: "DIRECT",
                                value: HUDFormatters.tokens(metrics.totalTokens),
                                color: theme.textPrimary,
                                theme: theme
                            )
                            statPill(
                                label: "EST COST",
                                value: HUDFormatters.currency(metrics.estimatedEquivalentCostUSD),
                                color: theme.secondary,
                                theme: theme
                            )
                        }

                        // Breakdown & Cache-Hit Savings Badge
                        HStack(spacing: 6) {
                            Text("IN \(HUDFormatters.tokens(metrics.totalInputTokens)) · OUT \(HUDFormatters.tokens(metrics.outputTokens))")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)

                            Spacer(minLength: 2)

                            HStack(spacing: 4) {
                                Image(systemName: "bolt.shield.fill")
                                    .font(.system(size: 8.5))
                                Text("CACHE \(HUDFormatters.percent(metrics.cacheHitRate)) (\(HUDFormatters.tokens(metrics.cacheReadTokens)))")
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .monospacedDigit()
                            }
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(theme.accent.opacity(0.14)))
                            .overlay(Capsule().stroke(theme.accent.opacity(0.45), lineWidth: 0.7))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statPill(label: String, value: String, color: Color, theme: HUDTheme) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.textSecondary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 0.7))
    }

    private func compactQuotaLabel(_ raw: String) -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized.lowercased() {
        case "frontier 5h pool", "frontier 5h":
            return "FRONTIER 5H"
        case "flash / fast pool", "flash 5h", "flash / fast":
            return "FLASH 5H"
        default:
            let upper = normalized.uppercased()
            if upper.count <= 11 { return upper }
            return String(upper.prefix(10)) + "…"
        }
    }

    // MARK: - 4. Project Spend Radar

    @ViewBuilder
    private func projectSpendRadar(theme: HUDTheme) -> some View {
        let projects = rankedProjectsForActiveWindow()
        let maxWindowTokens = max(1, projects.map { appState.tokens(for: $0, in: appState.selectedWindow) }.max() ?? 1)
        let totalWindowTokens = max(1, projects.reduce(0) { $0 + appState.tokens(for: $1, in: appState.selectedWindow) })

        CyberPanelCard(
            theme: theme,
            title: "PROJECT SPEND RADAR",
            badge: appState.pinnedProject.map { "★ \($0.name.uppercased())" } ?? appState.selectedWindow.shortTitle,
            isAlert: appState.isPriorityDrifting,
            alertColor: theme.warning,
            cornerRadius: 13,
            padding: 10
        ) {
            if projects.isEmpty {
                HStack {
                    Spacer()
                    Text("No project token spend recorded in window.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                }
                .padding(.vertical, 14)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 8) {
                        ForEach(projects.prefix(10)) { project in
                            let tokens = appState.tokens(for: project, in: appState.selectedWindow)
                            let barProgress = Double(tokens) / Double(maxWindowTokens)
                            let share = Double(tokens) / Double(totalWindowTokens)
                            let isDrifting = appState.isOutburningPinned(project)

                            HStack(alignment: .center, spacing: 8) {
                                // Pin Priority Star Button
                                Button {
                                    appState.togglePinProject(project)
                                } label: {
                                    Image(systemName: project.isPinned ? "star.fill" : "star")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(project.isPinned ? theme.accent : theme.textSecondary.opacity(0.65))
                                        .shadow(color: project.isPinned ? theme.accent.opacity(0.8) : .clear, radius: 5)
                                        .frame(width: 22, height: 22)
                                        .background(
                                            Circle()
                                                .fill(project.isPinned ? theme.accent.opacity(0.16) : Color.white.opacity(0.04))
                                        )
                                        .overlay(
                                            Circle()
                                                .stroke(project.isPinned ? theme.accent.opacity(0.6) : Color.white.opacity(0.10), lineWidth: 0.7)
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(project.isPinned ? "Unpin Priority Project" : "Pin \(project.name) as Priority Project")

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(project.name)
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundStyle(isDrifting ? theme.warning : theme.textPrimary)
                                            .lineLimit(1)

                                        if project.isPinned {
                                            Text("PRIORITY")
                                                .font(.system(size: 7.5, weight: .black, design: .monospaced))
                                                .foregroundStyle(theme.accent)
                                                .padding(.horizontal, 4.5)
                                                .padding(.vertical, 1)
                                                .background(Capsule().fill(theme.accent.opacity(0.16)))
                                        }

                                        if isDrifting {
                                            DriftAlertFlashBadge(theme: theme)
                                        }

                                        if project.activeAgents > 0 {
                                            Text("\(project.activeAgents) LIVE")
                                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                                .foregroundStyle(theme.primary)
                                                .padding(.horizontal, 4.5)
                                                .padding(.vertical, 1)
                                                .background(Capsule().fill(theme.primary.opacity(0.15)))
                                        }

                                        Spacer(minLength: 4)

                                        Text("\(HUDFormatters.tokens(tokens)) · \(HUDFormatters.percent(share))")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .monospacedDigit()
                                            .foregroundStyle(isDrifting ? theme.warning : theme.textSecondary)
                                    }

                                    HorizontalEnergyBar(
                                        progress: barProgress,
                                        theme: theme,
                                        label: nil,
                                        valueText: nil,
                                        segments: 24,
                                        isAlert: isDrifting,
                                        isHighlighted: project.isPinned,
                                        height: 7
                                    )
                                }
                            }
                            .padding(.vertical, 1)
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(height: 118)
            }
        }
    }

    private func rankedProjectsForActiveWindow() -> [ProjectSpend] {
        snapshotProjectsSorted(appState.snapshot.projects, window: appState.selectedWindow)
    }

    private func snapshotProjectsSorted(_ projects: [ProjectSpend], window: TelemetryTimeWindow) -> [ProjectSpend] {
        projects.sorted { lhs, rhs in
            let lTok = appState.tokens(for: lhs, in: window)
            let rTok = appState.tokens(for: rhs, in: window)
            if lTok != rTok { return lTok > rTok }
            if lhs.activeAgents != rhs.activeAgents { return lhs.activeAgents > rhs.activeAgents }
            return lhs.lastActive > rhs.lastActive
        }
    }

    // MARK: - 5. Live Agent & Swarm Pulse Feed

    @ViewBuilder
    private func liveAgentPulseFeed(theme: HUDTheme) -> some View {
        let agents = appState.snapshot.activeAgents
        let runningCount = appState.runningAgents.count
        let badge = runningCount > 0 ? "\(runningCount) RUNNING · \(agents.count) SHOWN" : "\(agents.count) RECENT"

        CyberPanelCard(
            theme: theme,
            title: "LIVE AGENT & SWARM PULSE",
            badge: badge,
            isAlert: false,
            cornerRadius: 13,
            padding: 10
        ) {
            if agents.isEmpty {
                HStack {
                    Spacer()
                    Text("No active or recent agent sessions detected.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                }
                .padding(.vertical, 14)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 7) {
                        ForEach(agents.prefix(12)) { agent in
                            agentRow(agent, theme: theme)
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func agentRow(_ agent: ActiveAgentPulse, theme: HUDTheme) -> some View {
        // Estimate fill against a 200K typical frontier context window
        let contextFill = min(max(Double(agent.contextTokensEstimate) / 200_000.0, 0.0), 1.0)
        let isCLI = agent.source.uppercased() == "CLI"

        HStack(alignment: .center, spacing: 8) {
            ReactorPulseIndicator(
                theme: theme,
                isActive: agent.isRunning,
                size: 22,
                style: agent.isRunning ? .combined : .radar
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(agent.title.isEmpty ? "Untitled Session" : agent.title)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(agent.isRunning ? theme.textPrimary : theme.textSecondary)
                        .lineLimit(1)

                    if agent.isSubagent {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 7.5, weight: .bold))
                            Text("SWARM")
                                .font(.system(size: 7.5, weight: .black, design: .monospaced))
                        }
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(theme.accent.opacity(0.15)))
                    }

                    Spacer(minLength: 4)

                    Text(agent.source.uppercased())
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(isCLI ? theme.primary : theme.secondary)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill((isCLI ? theme.primary : theme.secondary).opacity(0.14)))

                    Text(HUDFormatters.relativeAge(from: agent.lastUpdated, now: appState.snapshot.generatedAt))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary.opacity(0.8))
                }

                HStack(spacing: 8) {
                    Text(agent.projectName)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.primary.opacity(0.9))
                        .lineLimit(1)

                    Text("· \(agent.stepCount) steps")
                        .font(.system(size: 9, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)

                    if agent.latestTurnTokens > 0 {
                        Text("· +\(HUDFormatters.tokens(agent.latestTurnTokens))")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(theme.accent.opacity(0.9))
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 4) {
                        Text("CTX \(HUDFormatters.tokens(agent.contextTokensEstimate))")
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(contextFill > 0.78 ? theme.warning : theme.textSecondary)
                            .frame(width: 68, alignment: .trailing)

                        HorizontalEnergyBar(
                            progress: contextFill,
                            theme: theme,
                            label: nil,
                            valueText: nil,
                            segments: 10,
                            isAlert: contextFill > 0.80,
                            isHighlighted: agent.isRunning,
                            height: 5
                        )
                        .frame(width: 58)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(agent.isRunning ? theme.primary.opacity(0.08) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(agent.isRunning ? theme.primary.opacity(0.35) : Color.white.opacity(0.07), lineWidth: 0.7)
        )
    }
}

private struct DriftAlertFlashBadge: View {
    let theme: HUDTheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 8.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = 0.72 + 0.28 * sin(t * 4.5)
            HStack(spacing: 2) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 7.5))
                Text("DRIFT ↑")
                    .font(.system(size: 7.5, weight: .black, design: .monospaced))
            }
            .foregroundStyle(theme.danger)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(theme.danger.opacity(0.16)))
            .overlay(Capsule().stroke(theme.danger.opacity(0.72), lineWidth: 0.75))
            .fixedSize()
            .opacity(pulse)
        }
    }
}
