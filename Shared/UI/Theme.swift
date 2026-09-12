import SwiftUI
import UIKit

// MARK: - Colour

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    /// A colour that resolves per appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

/// The palette is deliberately small, and built on system colours so every
/// surface, separator and label behaves correctly in light mode, dark mode,
/// increased contrast and the grouped-list styles.
///
/// Colour carries meaning only: the accent marks what is interactive or
/// selected, green/amber/red mark state. Everything else stays in the system's
/// label and background colours.
enum Palette {
    /// Proxmox's orange, tuned per appearance to keep text contrast ≥ 4.5:1.
    static let accent = Color(light: 0xC4520B, dark: 0xFF8A3D)

    static let positive = Color(light: 0x1B8A4B, dark: 0x5CCB8F)
    static let warning = Color(light: 0xA8650A, dark: 0xE6A84E)
    static let critical = Color(light: 0xC0342F, dark: 0xF06B66)
    /// Second chart series — cool, so it never competes with the accent.
    static let secondarySeries = Color(light: 0x4F5BC4, dark: 0x8E98EC)

    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let fill = Color(uiColor: .tertiarySystemFill)
    static let separator = Color(uiColor: .separator)
    static let tertiaryLabel = Color(uiColor: .tertiaryLabel)

    static func state(_ state: PVERunState) -> Color {
        switch state {
        case .running, .online: return positive
        case .paused, .suspended: return warning
        case .stopped, .offline, .unknown: return tertiaryLabel
        }
    }

    /// Capacity bars stay neutral until the value is worth reacting to.
    static func capacity(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.80: return Color(uiColor: .secondaryLabel)
        case ..<0.92: return warning
        default: return critical
        }
    }

    static func series(_ token: String) -> Color {
        switch token {
        case "primary": return accent
        case "secondary": return secondarySeries
        case "positive": return positive
        case "warning": return warning
        case "critical": return critical
        default: return Color(uiColor: .secondaryLabel)
        }
    }
}

// MARK: - Motion

enum Motion {
    /// State changes.
    static let standard = Animation.smooth(duration: 0.3)
    /// Values that should read as moving — meters and counters.
    static let value = Animation.smooth(duration: 0.5)
}

// MARK: - Typography

/// All text uses Dynamic Type text styles. These add tabular figures so
/// numbers that update in place don't jitter horizontally.
extension Font {
    static let metricHero = Font.system(.largeTitle, weight: .semibold).monospacedDigit()
    static let metric = Font.system(.title3, weight: .semibold).monospacedDigit()
    static let metricBody = Font.system(.body, weight: .medium).monospacedDigit()
    static let metricCaption = Font.system(.subheadline).monospacedDigit()
    static let identifier = Font.system(.subheadline, design: .monospaced)
}
