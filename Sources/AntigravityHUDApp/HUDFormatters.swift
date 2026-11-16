import Foundation

enum HUDFormatters {
    static func tokens(_ count: Int) -> String {
        let absCount = abs(count)
        let sign = count < 0 ? "-" : ""
        if absCount >= 1_000_000_000 {
            return String(format: "%@%.2fB", sign, Double(absCount) / 1_000_000_000.0)
        } else if absCount >= 1_000_000 {
            return String(format: "%@%.2fM", sign, Double(absCount) / 1_000_000.0)
        } else if absCount >= 10_000 {
            return String(format: "%@%.1fK", sign, Double(absCount) / 1_000.0)
        } else if absCount >= 1_000 {
            return String(format: "%@%.1fK", sign, Double(absCount) / 1_000.0)
        }
        return "\(count)"
    }

    static func rate(_ tokensPerMinute: Double) -> String {
        let rounded = Int(tokensPerMinute.rounded())
        return "\(tokens(rounded))/m"
    }

    static func percent(_ fraction: Double) -> String {
        let clamped = min(max(fraction, 0.0), 1.0)
        return "\(Int((clamped * 100.0).rounded()))%"
    }

    static func currency(_ usd: Double) -> String {
        if usd >= 100 {
            return String(format: "$%.0f", usd)
        } else if usd >= 10 {
            return String(format: "$%.1f", usd)
        }
        return String(format: "$%.2f", usd)
    }

    static func countdown(resetTime: Date?, fallbackSeconds: TimeInterval?, now: Date) -> String {
        let remaining: TimeInterval?
        if let resetTime {
            remaining = max(0, resetTime.timeIntervalSince(now))
        } else if let fallbackSeconds {
            remaining = max(0, fallbackSeconds)
        } else {
            remaining = nil
        }

        guard let remaining else { return "READY" }
        let totalSecs = Int(remaining.rounded(.down))
        if totalSecs <= 0 { return "READY" }

        let days = totalSecs / 86_400
        let hours = (totalSecs % 86_400) / 3_600
        let minutes = (totalSecs % 3_600) / 60
        let seconds = totalSecs % 60

        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        } else {
            return "\(seconds)s"
        }
    }

    static func relativeAge(from date: Date, now: Date) -> String {
        if date == .distantPast { return "--" }
        let elapsed = max(0, Int(now.timeIntervalSince(date)))
        if elapsed < 10 { return "now" }
        if elapsed < 60 { return "\(elapsed)s" }
        if elapsed < 3_600 { return "\(elapsed / 60)m" }
        if elapsed < 86_400 { return "\(elapsed / 3_600)h" }
        return "\(elapsed / 86_400)d"
    }
}
