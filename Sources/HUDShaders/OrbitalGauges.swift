import SwiftUI

// MARK: - OrbitalRingGauge

/// Multi-layered sci-fi circular gauge featuring outer segmented tick marks,
/// an inner rotating dashed orbital arc, a glowing angular progress sweep,
/// an active shimmer sweep, and a centered metric + reset countdown pill.
public struct OrbitalRingGauge: View {
    public let progress: Double
    public let metricText: String?
    public let subtitle: String?
    public let countdownText: String?
    public let theme: HUDTheme
    public let isActive: Bool
    public let isWarning: Bool
    public let size: CGFloat
    public let showTicks: Bool

    public init(
        progress: Double,
        metricText: String? = nil,
        subtitle: String? = nil,
        countdownText: String? = nil,
        theme: HUDTheme,
        isActive: Bool = false,
        isWarning: Bool = false,
        size: CGFloat = 124,
        showTicks: Bool = true
    ) {
        self.progress = min(max(progress, 0.0), 1.0)
        self.metricText = metricText
        self.subtitle = subtitle
        self.countdownText = countdownText
        self.theme = theme
        self.isActive = isActive
        self.isWarning = isWarning
        self.size = max(size, 24)
        self.showTicks = showTicks
    }

    private var activePrimary: Color {
        if isWarning {
            return progress < 0.15 ? theme.danger : theme.warning
        }
        return theme.primary
    }

    private var activeSecondary: Color {
        isWarning ? theme.warning : theme.secondary
    }

    private var activeAccent: Color {
        isWarning ? theme.warning : theme.accent
    }

    private var displayMetric: String {
        if let metricText { return metricText }
        return "\(Int((progress * 100).rounded()))%"
    }

    public var body: some View {
        let trackInset = showTicks ? size * 0.11 : size * 0.06
        let ringStroke = max(2.6, size * 0.068)
        let innerRadiusScale: CGFloat = size < 70 ? 0.60 : 0.66

        ZStack {
            // Soft outer reactor halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            activePrimary.opacity(isActive ? 0.20 : 0.10),
                            activeSecondary.opacity(0.05),
                            .clear
                        ],
                        center: .center,
                        startRadius: size * 0.15,
                        endRadius: size * 0.54
                    )
                )

            // Outer segmented precision tick ring
            if showTicks {
                TickReticleRing(
                    progress: progress,
                    tickCount: size < 64 ? 24 : 40,
                    activeColor: activePrimary,
                    inactiveColor: theme.textSecondary.opacity(0.22),
                    tickLength: max(2.5, size * 0.048),
                    lineWidth: size < 64 ? 1.0 : 1.3
                )
            }

            // Recessed dark track
            Circle()
                .inset(by: trackInset)
                .stroke(theme.textSecondary.opacity(0.14), lineWidth: ringStroke)

            // Inner rotating dashed orbital arc + active shimmer sweep (Canvas avoids per-tick view layout diffing)
            TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: !isActive)) { timeline in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let orbitRad = isActive ? (elapsed * 26.0 * .pi / 180.0).truncatingRemainder(dividingBy: 2.0 * .pi) : 0.0
                let shimmerPhase = isActive ? (elapsed * 0.65).truncatingRemainder(dividingBy: 1.0) : 0.0

                Canvas { context, canvasSize in
                    let center = CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
                    let innerRadius = (size * innerRadiusScale) * 0.5
                    let dashA = max(3, size * 0.045)
                    let dashB = max(4, size * 0.055)

                    // Rotating inner dashed orbital reticle
                    context.drawLayer { layer in
                        layer.translateBy(x: center.x, y: center.y)
                        layer.rotate(by: .radians(orbitRad))
                        let circleRect = CGRect(
                            x: -innerRadius,
                            y: -innerRadius,
                            width: innerRadius * 2,
                            height: innerRadius * 2
                        )
                        layer.stroke(
                            Path(ellipseIn: circleRect),
                            with: .color(activeAccent.opacity(isActive ? 0.55 : 0.25)),
                            style: StrokeStyle(
                                lineWidth: max(0.8, size * 0.014),
                                lineCap: .round,
                                dash: [dashA, dashB]
                            )
                        )
                    }

                    // Animated progress shimmer glint when active
                    if isActive && progress > 0.04 {
                        let shimmerStart = min(shimmerPhase * progress, progress)
                        let shimmerEnd = min(progress, shimmerStart + 0.14)
                        if shimmerEnd > shimmerStart {
                            let arcRadius = (size * 0.5) - trackInset
                            let startAngle = Angle(radians: shimmerStart * 2.0 * .pi - .pi * 0.5)
                            let endAngle = Angle(radians: shimmerEnd * 2.0 * .pi - .pi * 0.5)
                            var shimmerPath = Path()
                            shimmerPath.addArc(
                                center: center,
                                radius: arcRadius,
                                startAngle: startAngle,
                                endAngle: endAngle,
                                clockwise: false
                            )
                            context.stroke(
                                shimmerPath,
                                with: .color(Color.white.opacity(0.28)),
                                style: StrokeStyle(lineWidth: ringStroke * 1.35, lineCap: .round)
                            )
                            context.stroke(
                                shimmerPath,
                                with: .color(Color.white.opacity(0.80)),
                                style: StrokeStyle(lineWidth: ringStroke * 0.62, lineCap: .round)
                            )
                        }
                    }
                }
                .frame(width: size, height: size)
                .drawingGroup()
            }
            .frame(width: size, height: size)

            // Outer bloom under progress arc (layered translucent strokes avoid software blur)
            Circle()
                .inset(by: trackInset)
                .trim(from: 0, to: progress)
                .stroke(
                    activePrimary.opacity(0.18),
                    style: StrokeStyle(lineWidth: ringStroke * 2.1, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Circle()
                .inset(by: trackInset)
                .trim(from: 0, to: progress)
                .stroke(
                    activePrimary.opacity(0.30),
                    style: StrokeStyle(lineWidth: ringStroke * 1.45, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Primary luminous angular sweep
            Circle()
                .inset(by: trackInset)
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            activeSecondary,
                            activePrimary,
                            activeAccent,
                            activePrimary
                        ]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: ringStroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Glowing tip flare at sweep endpoint
            if progress > 0.02 {
                let radius = (size * 0.5) - trackInset
                let angleRad = (progress * 2.0 * .pi) - (.pi / 2.0)
                let tipX = cos(angleRad) * radius
                let tipY = sin(angleRad) * radius
                Circle()
                    .fill(Color.white)
                    .frame(width: ringStroke * 1.15, height: ringStroke * 1.15)
                    .shadow(color: activeAccent, radius: 5)
                    .shadow(color: activePrimary, radius: 8)
                    .offset(x: tipX, y: tipY)
            }

            // Center telemetry readout
            VStack(spacing: size >= 84 ? 2.5 : 1) {
                Text(displayMetric)
                    .font(.system(size: max(10, size * (size < 64 ? 0.25 : 0.20)), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                if size >= 68, let subtitle, !subtitle.isEmpty {
                    Text(subtitle.uppercased())
                        .font(.system(size: max(7.5, size * 0.076), weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .frame(maxWidth: size * 0.72)
                }

                if size >= 76, let countdownText, !countdownText.isEmpty {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(isWarning ? theme.warning : activeAccent)
                            .frame(width: 4, height: 4)
                        Text(countdownText)
                            .font(.system(size: max(8.0, size * 0.08), weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(theme.textPrimary.opacity(0.92))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.38))
                            .overlay(
                                Capsule().stroke(activePrimary.opacity(0.45), lineWidth: 0.75)
                            )
                    )
                    .padding(.top, 1)
                }
            }
            .padding(.horizontal, size * 0.12)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: progress)
    }
}

private struct TickReticleRing: View {
    let progress: Double
    let tickCount: Int
    let activeColor: Color
    let inactiveColor: Color
    let tickLength: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            let outerR = min(size.width, size.height) * 0.5 - 1.0
            let litCount = Int((progress * Double(tickCount)).rounded(.down))

            for index in 0..<tickCount {
                let frac = Double(index) / Double(tickCount)
                let angle = (frac * 2.0 * .pi) - (.pi / 2.0)
                let isMajor = index % max(1, tickCount / 4) == 0
                let len = isMajor ? tickLength * 1.45 : tickLength

                let p0 = CGPoint(
                    x: center.x + cos(angle) * (outerR - len),
                    y: center.y + sin(angle) * (outerR - len)
                )
                let p1 = CGPoint(
                    x: center.x + cos(angle) * outerR,
                    y: center.y + sin(angle) * outerR
                )

                var path = Path()
                path.move(to: p0)
                path.addLine(to: p1)

                let isLit = index < litCount && progress > 0.01
                context.stroke(
                    path,
                    with: .color(isLit ? activeColor.opacity(isMajor ? 0.95 : 0.72) : inactiveColor),
                    lineWidth: isMajor ? lineWidth * 1.2 : lineWidth
                )
            }
        }
    }
}

// MARK: - VelocitySparklineView

/// Glowing holographic waveform chart with vertical tactical gridlines,
/// peak marker dot, animated laser cursor sweep, and gradient area fill.
public struct VelocitySparklineView: View {
    public let data: [Double]
    public let theme: HUDTheme
    public let isActive: Bool
    public let height: CGFloat
    public let unitSuffix: String
    public let accentColor: Color?

    public init(
        data: [Double],
        theme: HUDTheme,
        isActive: Bool = false,
        height: CGFloat = 86,
        unitSuffix: String = "/m",
        accentColor: Color? = nil
    ) {
        self.data = data
        self.theme = theme
        self.isActive = isActive
        self.height = max(height, 36)
        self.unitSuffix = unitSuffix
        self.accentColor = accentColor
    }

    private var strokeColor: Color {
        accentColor ?? theme.primary
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: !isActive)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let laserNorm: CGFloat? = isActive
                ? CGFloat((t * 0.42).truncatingRemainder(dividingBy: 1.0))
                : nil

            Canvas { context, size in
                drawSparkline(in: &context, size: size, laserNorm: laserNorm)
            }
            .frame(height: height)
            .drawingGroup()
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func drawSparkline(in context: inout GraphicsContext, size: CGSize, laserNorm: CGFloat?) {
        let insetTop: CGFloat = 14
        let insetBottom: CGFloat = 6
        let plotHeight = max(size.height - insetTop - insetBottom, 12)
        let plotRect = CGRect(x: 0, y: insetTop, width: size.width, height: plotHeight)

        // Subtle dark plot background
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(Color.black.opacity(0.24))
        )

        // Vertical tactical gridlines + horizontal reference dashed rules
        var gridPath = Path()
        let vCols = 8
        for col in 1..<vCols {
            let x = size.width * CGFloat(col) / CGFloat(vCols)
            gridPath.move(to: CGPoint(x: x, y: 0))
            gridPath.addLine(to: CGPoint(x: x, y: size.height))
        }
        context.stroke(gridPath, with: .color(strokeColor.opacity(0.11)), lineWidth: 0.75)

        var refPath = Path()
        for frac in [0.0, 0.5, 1.0] as [CGFloat] {
            let y = plotRect.maxY - frac * plotRect.height
            refPath.move(to: CGPoint(x: 0, y: y))
            refPath.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(
            refPath,
            with: .color(theme.textSecondary.opacity(0.14)),
            style: StrokeStyle(lineWidth: 0.7, dash: [3, 4])
        )

        let values = sanitizedValues()
        let maxVal = values.max() ?? 0
        let hasSignal = maxVal > 0

        let points = normalizedPoints(values: values, maxVal: maxVal, in: plotRect)
        guard points.count >= 2 else { return }

        let linePath = smoothCurvePath(points: points)
        var areaPath = linePath
        areaPath.addLine(to: CGPoint(x: points.last!.x, y: size.height))
        areaPath.addLine(to: CGPoint(x: points.first!.x, y: size.height))
        areaPath.closeSubpath()

        // Gradient fill beneath waveform
        context.fill(
            areaPath,
            with: .linearGradient(
                Gradient(colors: [
                    strokeColor.opacity(hasSignal ? 0.36 : 0.10),
                    theme.secondary.opacity(hasSignal ? 0.14 : 0.04),
                    .clear
                ]),
                startPoint: CGPoint(x: 0, y: plotRect.minY),
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )

        // Layered translucent neon bloom strokes (avoids expensive per-frame software blur)
        context.stroke(
            linePath,
            with: .color(strokeColor.opacity(hasSignal ? 0.15 : 0.06)),
            style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round)
        )
        context.stroke(
            linePath,
            with: .color(strokeColor.opacity(hasSignal ? 0.32 : 0.12)),
            style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round)
        )

        // Core razor-sharp waveform stroke
        context.stroke(
            linePath,
            with: .linearGradient(
                Gradient(colors: [theme.secondary, strokeColor, theme.accent]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: size.width, y: 0)
            ),
            style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)
        )

        // Peak marker dot + micro peak label
        if hasSignal, let peakIdx = values.indices.max(by: { values[$0] < values[$1] }) {
            let peakPt = points[peakIdx]
            let haloRadius: CGFloat = 5.5
            let haloRect = CGRect(
                x: peakPt.x - haloRadius,
                y: peakPt.y - haloRadius,
                width: haloRadius * 2,
                height: haloRadius * 2
            )
            context.stroke(Path(ellipseIn: haloRect), with: .color(theme.accent.opacity(0.65)), lineWidth: 1.1)

            let dotRect = CGRect(x: peakPt.x - 2.6, y: peakPt.y - 2.6, width: 5.2, height: 5.2)
            context.fill(Path(ellipseIn: dotRect), with: .color(.white))

            let label = "PK \(Self.formatCompactNumber(maxVal))\(unitSuffix)"
            let resolved = context.resolve(
                Text(label)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.accent)
            )
            let textX = min(max(peakPt.x, 34), size.width - 34)
            let textY = max(7.0, peakPt.y - 9.0)
            context.draw(resolved, at: CGPoint(x: textX, y: textY), anchor: .center)
        }

        // Animated laser cursor sweep riding along waveform when active
        if let laserNorm {
            let laserX = laserNorm * size.width
            let laserY = interpolatedY(atNormalizedX: laserNorm, points: points, in: plotRect)

            var laserBeam = Path()
            laserBeam.move(to: CGPoint(x: laserX, y: 0))
            laserBeam.addLine(to: CGPoint(x: laserX, y: size.height))
            context.stroke(
                laserBeam,
                with: .linearGradient(
                    Gradient(colors: [.clear, theme.accent.opacity(0.65), strokeColor.opacity(0.35), .clear]),
                    startPoint: CGPoint(x: laserX, y: 0),
                    endPoint: CGPoint(x: laserX, y: size.height)
                ),
                lineWidth: 1.2
            )

            let cursorGlowRect = CGRect(x: laserX - 5.5, y: laserY - 5.5, width: 11, height: 11)
            context.fill(
                Path(ellipseIn: cursorGlowRect),
                with: .radialGradient(
                    Gradient(colors: [theme.accent.opacity(0.85), strokeColor.opacity(0.0)]),
                    center: CGPoint(x: laserX, y: laserY),
                    startRadius: 0.5,
                    endRadius: 5.5
                )
            )
            let cursorDot = CGRect(x: laserX - 2.0, y: laserY - 2.0, width: 4.0, height: 4.0)
            context.fill(Path(ellipseIn: cursorDot), with: .color(.white))
        }
    }

    private func sanitizedValues() -> [Double] {
        let cleaned = data.map { val in
            (val.isFinite && val > 0) ? val : 0.0
        }
        if cleaned.isEmpty {
            return Array(repeating: 0.0, count: 12)
        }
        if cleaned.count == 1 {
            return [cleaned[0], cleaned[0]]
        }
        return cleaned
    }

    private func normalizedPoints(values: [Double], maxVal: Double, in rect: CGRect) -> [CGPoint] {
        let denom = max(maxVal, 1e-6)
        let count = values.count
        return values.enumerated().map { idx, val in
            let x = rect.minX + (CGFloat(idx) / CGFloat(max(count - 1, 1))) * rect.width
            let normY = maxVal > 0 ? CGFloat(val / denom) : 0.0
            let y = rect.maxY - normY * rect.height
            return CGPoint(x: x, y: y)
        }
    }

    private func smoothCurvePath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)

        for index in 1..<points.count {
            let prev = points[index - 1]
            let curr = points[index]
            let midX = (prev.x + curr.x) * 0.5
            path.addCurve(
                to: curr,
                control1: CGPoint(x: midX, y: prev.y),
                control2: CGPoint(x: midX, y: curr.y)
            )
        }
        return path
    }

    private func interpolatedY(atNormalizedX normX: CGFloat, points: [CGPoint], in rect: CGRect) -> CGFloat {
        guard points.count >= 2 else { return rect.maxY }
        let clamped = min(max(normX, 0), 1)
        let scaled = clamped * CGFloat(points.count - 1)
        let idx = min(Int(scaled), points.count - 2)
        let frac = scaled - CGFloat(idx)
        // Smoothstep matches cubic tangent curve closely for cursor tracking
        let smoothFrac = frac * frac * (3.0 - 2.0 * frac)
        return points[idx].y + (points[idx + 1].y - points[idx].y) * smoothFrac
    }

    private static func formatCompactNumber(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000.0)
        } else if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000.0)
        } else if value >= 10 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }
}

// MARK: - CyberPanelCard

/// Dark frosted glass container with a 1px luminous border gradient,
/// four corner L-bracket HUD reticles, and optional alert glow state.
public struct CyberPanelCard<Content: View>: View {
    public let theme: HUDTheme
    public let title: String?
    public let badge: String?
    public let isAlert: Bool
    public let alertColor: Color?
    public let cornerRadius: CGFloat
    public let padding: CGFloat
    private let content: Content

    public init(
        theme: HUDTheme,
        title: String? = nil,
        badge: String? = nil,
        isAlert: Bool = false,
        alertColor: Color? = nil,
        cornerRadius: CGFloat = 14,
        padding: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.theme = theme
        self.title = title
        self.badge = badge
        self.isAlert = isAlert
        self.alertColor = alertColor
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    private var resolvedAlertColor: Color {
        alertColor ?? theme.warning
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        VStack(alignment: .leading, spacing: 8) {
            if title != nil || badge != nil {
                HStack(spacing: 6) {
                    if let title {
                        HStack(spacing: 5) {
                            Image(systemName: "diamond.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(isAlert ? resolvedAlertColor : theme.accent)
                            Text(title.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1.1)
                                .foregroundStyle(theme.textSecondary)
                        }
                    }

                    Spacer(minLength: 4)

                    if let badge {
                        Text(badge.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(isAlert ? resolvedAlertColor : theme.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill((isAlert ? resolvedAlertColor : theme.primary).opacity(0.14))
                                    .overlay(
                                        Capsule().stroke(
                                            (isAlert ? resolvedAlertColor : theme.primary).opacity(0.45),
                                            lineWidth: 0.7
                                        )
                                    )
                            )
                    }
                }
            }

            content
        }
        .padding(padding)
        .background(
            ZStack {
                shape.fill(theme.surfaceGradient)
                // Top inner specular highlight
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), .clear, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
        )
        .overlay(
            shape.strokeBorder(
                isAlert
                    ? LinearGradient(
                        colors: [resolvedAlertColor.opacity(0.92), theme.danger.opacity(0.65), resolvedAlertColor.opacity(0.92)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    : theme.borderGradient,
                lineWidth: 1
            )
        )
        .overlay(
            CornerReticleOverlay(
                color: isAlert ? resolvedAlertColor : theme.accent,
                armLength: min(11, cornerRadius * 0.85),
                inset: 3.5,
                lineWidth: 1.5
            )
            .allowsHitTesting(false)
        )
        .shadow(
            color: (isAlert ? resolvedAlertColor : theme.glowColor).opacity(isAlert ? 0.34 : 0.14),
            radius: isAlert ? 12 : 7,
            x: 0,
            y: 2
        )
    }
}

private struct CornerReticleOverlay: View {
    let color: Color
    let armLength: CGFloat
    let inset: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            guard size.width > inset * 2 + armLength,
                  size.height > inset * 2 + armLength else {
                return
            }

            let minX = inset
            let minY = inset
            let maxX = size.width - inset
            let maxY = size.height - inset

            var path = Path()
            // Top-left L
            path.move(to: CGPoint(x: minX, y: minY + armLength))
            path.addLine(to: CGPoint(x: minX, y: minY))
            path.addLine(to: CGPoint(x: minX + armLength, y: minY))
            // Top-right L
            path.move(to: CGPoint(x: maxX - armLength, y: minY))
            path.addLine(to: CGPoint(x: maxX, y: minY))
            path.addLine(to: CGPoint(x: maxX, y: minY + armLength))
            // Bottom-right L
            path.move(to: CGPoint(x: maxX, y: maxY - armLength))
            path.addLine(to: CGPoint(x: maxX, y: maxY))
            path.addLine(to: CGPoint(x: maxX - armLength, y: maxY))
            // Bottom-left L
            path.move(to: CGPoint(x: minX + armLength, y: maxY))
            path.addLine(to: CGPoint(x: minX, y: maxY))
            path.addLine(to: CGPoint(x: minX, y: maxY - armLength))

            context.stroke(
                path,
                with: .color(color.opacity(0.88)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .square, lineJoin: .miter)
            )
        }
    }
}

// MARK: - ReactorPulseIndicator

/// Sleek stationary bezel indicator with a calm breathing core or equalizer bars
/// signaling live agent or multi-agent swarm execution.
public struct ReactorPulseIndicator: View {
    public enum PulseStyle: String, Sendable {
        case radar
        case equalizer
        case combined
    }

    public let theme: HUDTheme
    public let isActive: Bool
    public let size: CGFloat
    public let style: PulseStyle

    public init(
        theme: HUDTheme,
        isActive: Bool,
        size: CGFloat = 24,
        style: PulseStyle = .combined
    ) {
        self.theme = theme
        self.isActive = isActive
        self.size = max(size, 12)
        self.style = style
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: !isActive)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let breath = isActive ? (0.5 + 0.5 * sin(t * 2.4)) : 0.0

            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
                let minDim = min(canvasSize.width, canvasSize.height)

                if style == .radar || style == .combined {
                    let bezelInset: CGFloat = 1.5
                    let bezelRect = CGRect(
                        x: center.x - (minDim * 0.5 - bezelInset),
                        y: center.y - (minDim * 0.5 - bezelInset),
                        width: max(4, minDim - bezelInset * 2),
                        height: max(4, minDim - bezelInset * 2)
                    )
                    let bezelPath = Path(ellipseIn: bezelRect)
                    context.fill(bezelPath, with: .color(Color.black.opacity(0.28)))
                    context.stroke(
                        bezelPath,
                        with: .color(
                            isActive
                                ? theme.accent.opacity(0.45 + 0.38 * breath)
                                : theme.textSecondary.opacity(0.30)
                        ),
                        lineWidth: max(0.9, minDim * 0.055)
                    )
                }

                if style == .equalizer || (style == .combined && size >= 20) {
                    let barCount = 3
                    let spacing = max(1.5, minDim * 0.07)
                    let barWidth = max(1.8, minDim * 0.11)
                    let maxBarHeight = minDim * 0.44
                    let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
                    let startX = center.x - totalWidth * 0.5
                    let bottomY = center.y + maxBarHeight * 0.5
                    let barColor = isActive ? theme.primary : theme.textSecondary.opacity(0.45)

                    for bar in 0..<barCount {
                        let wave = isActive
                            ? (0.40 + 0.55 * (0.5 + 0.5 * sin(t * 3.4 + Double(bar) * 1.25)))
                            : 0.28
                        let barHeight = max(3, maxBarHeight * wave)
                        let x = startX + CGFloat(bar) * (barWidth + spacing)
                        let rect = CGRect(x: x, y: bottomY - barHeight, width: barWidth, height: barHeight)
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: barWidth * 0.5),
                            with: .color(barColor)
                        )
                    }
                } else {
                    if isActive {
                        let glowR = minDim * 0.29
                        let glowRect = CGRect(
                            x: center.x - glowR,
                            y: center.y - glowR,
                            width: glowR * 2,
                            height: glowR * 2
                        )
                        context.fill(
                            Path(ellipseIn: glowRect),
                            with: .color(theme.primary.opacity(0.18 + 0.18 * breath))
                        )
                    }
                    let coreR = minDim * 0.19
                    let coreRect = CGRect(
                        x: center.x - coreR,
                        y: center.y - coreR,
                        width: coreR * 2,
                        height: coreR * 2
                    )
                    context.fill(
                        Path(ellipseIn: coreRect),
                        with: .color(
                            isActive
                                ? theme.accent.opacity(0.68 + 0.32 * breath)
                                : theme.textSecondary.opacity(0.45)
                        )
                    )
                }
            }
            .frame(width: size, height: size)
            .drawingGroup()
        }
        .frame(width: size, height: size)
    }
}

// MARK: - HorizontalEnergyBar

/// Segmented futuristic energy progress bar with a glowing plasma tip
/// and optional label / numeric readout for project spend & context fill.
public struct HorizontalEnergyBar: View {
    public let progress: Double
    public let theme: HUDTheme
    public let label: String?
    public let valueText: String?
    public let segments: Int
    public let isAlert: Bool
    public let isHighlighted: Bool
    public let height: CGFloat

    public init(
        progress: Double,
        theme: HUDTheme,
        label: String? = nil,
        valueText: String? = nil,
        segments: Int = 20,
        isAlert: Bool = false,
        isHighlighted: Bool = false,
        height: CGFloat = 10
    ) {
        self.progress = min(max(progress, 0.0), 1.0)
        self.theme = theme
        self.label = label
        self.valueText = valueText
        self.segments = max(segments, 4)
        self.isAlert = isAlert
        self.isHighlighted = isHighlighted
        self.height = max(height, 4)
    }

    private var startColor: Color {
        isAlert ? theme.warning : theme.secondary
    }

    private var endColor: Color {
        if isAlert { return theme.danger }
        return isHighlighted ? theme.accent : theme.primary
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if label != nil || valueText != nil {
                HStack(spacing: 6) {
                    if let label {
                        Text(label)
                            .font(.system(size: 11, weight: isHighlighted ? .semibold : .medium, design: .rounded))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 4)
                    if let valueText {
                        Text(valueText)
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(isAlert ? theme.warning : theme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }

            Canvas { context, size in
                let gap: CGFloat = size.width > 120 ? 2.2 : 1.5
                let totalGap = gap * CGFloat(segments - 1)
                let cellWidth = max((size.width - totalGap) / CGFloat(segments), 1.5)
                let corner = min(height * 0.35, 3.0)
                let activeCells = progress * Double(segments)

                for index in 0..<segments {
                    let x = CGFloat(index) * (cellWidth + gap)
                    let cellRect = CGRect(x: x, y: 0, width: cellWidth, height: size.height)
                    let cellPath = Path(roundedRect: cellRect, cornerRadius: corner)

                    // Recessed unlit cell
                    context.fill(cellPath, with: .color(theme.textSecondary.opacity(0.14)))

                    let fillAmount = min(max(activeCells - Double(index), 0.0), 1.0)
                    if fillAmount > 0.01 {
                        let t = Double(index) / Double(max(segments - 1, 1))
                        let litRect = CGRect(
                            x: x,
                            y: 0,
                            width: cellWidth * CGFloat(fillAmount),
                            height: size.height
                        )
                        let litPath = Path(roundedRect: litRect, cornerRadius: corner)
                        let cellColor = Self.interpolateColor(
                            indexFraction: t,
                            isAlert: isAlert,
                            isHighlighted: isHighlighted,
                            theme: theme
                        )
                        context.fill(litPath, with: .color(cellColor.opacity(0.92)))
                    }
                }

                // Glowing leading plasma tip
                if progress > 0.015 {
                    let tipX = min(max(CGFloat(progress) * size.width, 2), size.width - 1)
                    let tipCenter = CGPoint(x: tipX, y: size.height * 0.5)
                    let flareRadius = max(size.height * 1.1, 8)
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: tipCenter.x - flareRadius,
                            y: tipCenter.y - flareRadius,
                            width: flareRadius * 2,
                            height: flareRadius * 2
                        )),
                        with: .radialGradient(
                            Gradient(colors: [
                                Color.white.opacity(0.9),
                                endColor.opacity(0.65),
                                .clear
                            ]),
                            center: tipCenter,
                            startRadius: 0.5,
                            endRadius: flareRadius
                        )
                    )

                    let capRect = CGRect(x: tipX - 1.2, y: 0, width: 2.4, height: size.height)
                    context.fill(Path(roundedRect: capRect, cornerRadius: 1.2), with: .color(.white.opacity(0.95)))
                }
            }
            .frame(height: height)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: progress)
    }

    private static func interpolateColor(
        indexFraction: Double,
        isAlert: Bool,
        isHighlighted: Bool,
        theme: HUDTheme
    ) -> Color {
        if isAlert {
            return indexFraction > 0.65 ? theme.danger : theme.warning
        }
        if isHighlighted {
            return indexFraction > 0.55 ? theme.accent : theme.primary
        }
        return indexFraction > 0.72 ? theme.accent : (indexFraction > 0.30 ? theme.primary : theme.secondary)
    }
}
