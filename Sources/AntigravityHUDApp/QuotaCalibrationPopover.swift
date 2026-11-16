import HUDShaders
import SwiftUI
import TelemetryCore

struct QuotaCalibrationPopover: View {
    @ObservedObject var appState: HUDAppState
    @Environment(\.dismiss) private var dismiss

    @State private var frontierPercent: Double = 85
    @State private var frontierResetHours: Double = 4.5
    @State private var flashPercent: Double = 95
    @State private var flashResetHours: Double = 5.0
    @State private var didSeedFromState = false

    var body: some View {
        let theme = appState.theme

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(theme.primary)
                Text("CALIBRATE QUOTA RINGS")
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Text("Match the bars in Antigravity Settings → Models, or enable the Live CLI Hook for automatic exact quota telemetry.")
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(theme.primary.opacity(0.2))

            // Frontier Pool Calibration
            calibrationBlock(
                title: "FRONTIER / PRO POOL",
                percent: $frontierPercent,
                resetHours: $frontierResetHours,
                accent: theme.primary,
                theme: theme
            )

            // Flash Pool Calibration
            calibrationBlock(
                title: "FLASH / FAST POOL",
                percent: $flashPercent,
                resetHours: $flashResetHours,
                accent: theme.accent,
                theme: theme
            )

            Divider().overlay(theme.primary.opacity(0.2))

            HStack(spacing: 8) {
                Button {
                    appState.toggleCLIStatusLineHook()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: appState.snapshot.hookInstalled ? "checkmark.seal.fill" : "bolt.fill")
                        Text(appState.snapshot.hookInstalled ? "CLI Hook Active" : "Enable CLI Hook")
                    }
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(theme.accent.opacity(0.16)))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.accent.opacity(0.5), lineWidth: 0.8))
                    .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Reset Auto") {
                    appState.engine.clearCalibratedQuotas()
                    TelemetryAudio.shared.playModeSwitch()
                    appState.showToast(icon: "arrow.counterclockwise", message: "QUOTA RINGS RESET TO AUTO")
                    dismiss()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .buttonStyle(.plain)

                Button {
                    appState.engine.setCalibratedQuota(
                        id: "frontier-pool",
                        label: "Frontier 5h",
                        remainingFraction: frontierPercent / 100.0,
                        resetHours: frontierResetHours
                    )
                    appState.engine.setCalibratedQuota(
                        id: "flash-pool",
                        label: "Flash 5h",
                        remainingFraction: flashPercent / 100.0,
                        resetHours: flashResetHours
                    )
                    TelemetryAudio.shared.playPinSound()
                    appState.showToast(icon: "dial.high.fill", message: "QUOTA RINGS CALIBRATED")
                    dismiss()
                } label: {
                    Text("Apply")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(theme.primary.opacity(0.28)))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.primary.opacity(0.8), lineWidth: 0.9))
                        .foregroundStyle(theme.textPrimary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 344)
        .background(Color(red: 0.04, green: 0.06, blue: 0.10))
        .onAppear {
            guard !didSeedFromState else { return }
            didSeedFromState = true
            let source = appState.engine.calibratedQuotas.isEmpty ? appState.snapshot.quotas : appState.engine.calibratedQuotas
            if let frontier = source.first(where: { $0.id == "frontier-pool" }) ?? source.first {
                frontierPercent = (frontier.remainingFraction * 100.0).rounded()
                if let secs = frontier.resetInSeconds {
                    frontierResetHours = Self.snappedResetHours(fromSeconds: secs)
                }
            }
            if let flash = source.first(where: { $0.id == "flash-pool" }) ?? source.dropFirst().first {
                flashPercent = (flash.remainingFraction * 100.0).rounded()
                if let secs = flash.resetInSeconds {
                    flashResetHours = Self.snappedResetHours(fromSeconds: secs)
                }
            }
        }
    }

    private static let resetTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static func snappedResetHours(fromSeconds secs: TimeInterval) -> Double {
        let minStep = 1.0 / 12.0
        let rawHours = min(max(secs / 3600.0, minStep), 24.0)
        return min(max((rawHours * 12.0).rounded() / 12.0, minStep), 24.0)
    }

    @ViewBuilder
    private func calibrationBlock(
        title: String,
        percent: Binding<Double>,
        resetHours: Binding<Double>,
        accent: Color,
        theme: HUDTheme
    ) -> some View {
        let now = Date()
        let resetSecs = (resetHours.wrappedValue * 3600.0).rounded()
        let durationText = HUDFormatters.countdown(resetTime: nil, fallbackSeconds: resetSecs, now: now)
        let resetClockText = Self.resetTimeFormatter.string(from: now.addingTimeInterval(resetSecs))

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(Int(percent.wrappedValue.rounded()))% · \(durationText) (Resets \(resetClockText))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Text("REM")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 28, alignment: .leading)
                Slider(value: percent, in: 0...100, step: 1)
                    .tint(accent)
            }

            HStack(spacing: 8) {
                Text("RST")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 28, alignment: .leading)
                Slider(value: resetHours, in: (1.0 / 12.0)...24.0, step: 1.0 / 12.0)
                    .tint(theme.secondary)
            }
        }
    }
}
