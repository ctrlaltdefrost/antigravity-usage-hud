import AppKit
import SwiftUI
import simd

/// Visual theme palette for the Antigravity Orbital Telemetry HUD.
public enum HUDTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case jarvisCyan
    case cyberpunkNeon
    case solarAmber
    case stealthObsidian

    public var id: String { rawValue }

    /// Full human-readable theme name for menus and settings.
    public var displayName: String {
        switch self {
        case .jarvisCyan: return "Jarvis Cyan"
        case .cyberpunkNeon: return "Cyberpunk Neon"
        case .solarAmber: return "Solar Reactor"
        case .stealthObsidian: return "Stealth Obsidian"
        }
    }

    /// Compact badge label for inline HUD theme pills.
    public var shortName: String {
        switch self {
        case .jarvisCyan: return "JARVIS"
        case .cyberpunkNeon: return "NEON"
        case .solarAmber: return "SOLAR"
        case .stealthObsidian: return "STEALTH"
        }
    }

    /// Primary luminous vector color.
    public var primary: Color { palette.primary.color }

    /// Secondary harmonic gradient color.
    public var secondary: Color { palette.secondary.color }

    /// High-contrast spark / reticle accent color.
    public var accent: Color { palette.accent.color }

    /// Tactical caution / priority drift highlight color.
    public var warning: Color { palette.warning.color }

    /// Critical alert / low-quota color.
    public var danger: Color { palette.danger.color }

    /// Translucent dark glass backing tint.
    public var glassTint: Color { palette.glassTint.color(alpha: palette.glassAlpha) }

    /// Outer radial bloom / drop-glow color.
    public var glowColor: Color { palette.glow.color }

    /// Crisp high-legibility foreground text color.
    public var textPrimary: Color { Color(red: 0.95, green: 0.97, blue: 1.0) }

    /// Muted telemetry metadata foreground text color.
    public var textSecondary: Color { Color(red: 0.72, green: 0.79, blue: 0.87) }

    /// Subtle dark surface gradient for panel interiors.
    public var surfaceGradient: LinearGradient {
        LinearGradient(
            colors: [
                glassTint.opacity(0.95),
                Color(red: 0.02, green: 0.03, blue: 0.06).opacity(0.86)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Luminous 1px perimeter border gradient.
    public var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                primary.opacity(0.75),
                secondary.opacity(0.45),
                accent.opacity(0.65)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Shader-ready RGBA vector for primary color.
    public var primarySIMD: SIMD4<Float> { palette.primary.simd(alpha: 1.0) }

    /// Shader-ready RGBA vector for secondary color.
    public var secondarySIMD: SIMD4<Float> { palette.secondary.simd(alpha: 1.0) }

    /// Shader-ready RGBA vector for accent color.
    public var accentSIMD: SIMD4<Float> { palette.accent.simd(alpha: 1.0) }

    /// Shader-ready RGBA vector for dark glass backdrop tint.
    public var glassTintSIMD: SIMD4<Float> { palette.glassTint.simd(alpha: Float(palette.glassAlpha)) }
}

// MARK: - Unified Palette Definitions

private struct RGBHex: Sendable {
    let r: Double
    let g: Double
    let b: Double

    init(_ hex: UInt32) {
        self.r = Double((hex >> 16) & 0xFF) / 255.0
        self.g = Double((hex >> 8) & 0xFF) / 255.0
        self.b = Double(hex & 0xFF) / 255.0
    }

    var color: Color {
        Color(red: r, green: g, blue: b)
    }

    func color(alpha: Double) -> Color {
        Color(red: r, green: g, blue: b, opacity: alpha)
    }

    func simd(alpha: Float) -> SIMD4<Float> {
        SIMD4<Float>(Float(r), Float(g), Float(b), alpha)
    }
}

private struct ThemePalette: Sendable {
    let primary: RGBHex
    let secondary: RGBHex
    let accent: RGBHex
    let warning: RGBHex
    let danger: RGBHex
    let glassTint: RGBHex
    let glassAlpha: Double
    let glow: RGBHex
}

private extension HUDTheme {
    var palette: ThemePalette {
        switch self {
        case .jarvisCyan:
            return ThemePalette(
                primary: RGBHex(0x00F0FF),
                secondary: RGBHex(0x0066FF),
                accent: RGBHex(0x4CFFB3),
                warning: RGBHex(0xFFB703),
                danger: RGBHex(0xFF3B5C),
                glassTint: RGBHex(0x04101D),
                glassAlpha: 0.72,
                glow: RGBHex(0x00F0FF)
            )
        case .cyberpunkNeon:
            return ThemePalette(
                primary: RGBHex(0xFF2A85),
                secondary: RGBHex(0x9D4EDD),
                accent: RGBHex(0x00F5D4),
                warning: RGBHex(0xFFBE0B),
                danger: RGBHex(0xFF1E56),
                glassTint: RGBHex(0x11051A),
                glassAlpha: 0.74,
                glow: RGBHex(0xFF2A85)
            )
        case .solarAmber:
            return ThemePalette(
                primary: RGBHex(0xFFB703),
                secondary: RGBHex(0xFB5607),
                accent: RGBHex(0xE0FBFC),
                warning: RGBHex(0xFFD166),
                danger: RGBHex(0xFF334B),
                glassTint: RGBHex(0x160B04),
                glassAlpha: 0.74,
                glow: RGBHex(0xFFB703)
            )
        case .stealthObsidian:
            return ThemePalette(
                primary: RGBHex(0x94A3B8),
                secondary: RGBHex(0x10B981),
                accent: RGBHex(0xE2E8F0),
                warning: RGBHex(0xF59E0B),
                danger: RGBHex(0xEF4444),
                glassTint: RGBHex(0x0B0E14),
                glassAlpha: 0.78,
                glow: RGBHex(0x10B981)
            )
        }
    }
}
