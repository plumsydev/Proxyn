import SwiftUI

// MARK: - Colour

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleaned.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 255, 122, 51)
        }
        self.init(.sRGB,
                  red: Double(r) / 255, green: Double(g) / 255,
                  blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

/// Dark-only, and deliberately quiet.
///
/// Two surface elevations, three inks, **one** accent. Colour carries meaning —
/// a coloured element on screen means something is running, selected, or wrong.
/// Everything else is greyscale, so the numbers are what the eye lands on.
enum Palette {

    // Surfaces. There is no third elevation: anything that needs to feel
    // "above" uses spacing, not another shade.
    static let canvas       = Color(hex: "0A0A0C")
    static let canvasLift   = Color(hex: "141417")
    static let surface      = Color(hex: "141417")
    static let surfaceHi    = Color(hex: "1C1C21")
    static let sheetCanvas  = Color(hex: "0E0E11")

    /// Separators — never used as an outline around a whole card.
    static let hairline     = Color.white.opacity(0.08)
    static let hairlineSoft = Color.white.opacity(0.05)

    // Ink
    static let ink          = Color(hex: "ECECEF")
    static let inkSecondary = Color(hex: "95959D")
    static let inkTertiary  = Color(hex: "5C5C65")

    // The accent, descended from Proxmox orange but desaturated so it can sit
    // on black without vibrating.
    static let ember        = Color(hex: "FF7A33")
    static let emberDeep    = Color(hex: "C85C22")

    // Status. Muted on purpose: these read as state, not as decoration.
    static let mint         = Color(hex: "5CC98F")   // running / healthy
    static let amber        = Color(hex: "DFA24A")   // attention
    static let rose         = Color(hex: "DF6260")   // failure
    static let sky          = Color(hex: "7E8CE0")   // secondary data series
    static let violet       = Color(hex: "9A8FCF")

    /// Chart series, in order. The first one is the accent; the rest step down
    /// in saturation so a multi-series chart still has a clear protagonist.
    static let series: [Color] = [ember, sky, mint, inkSecondary, amber, rose]

    static func series(_ index: Int) -> Color { series[index % series.count] }

    static func token(_ name: String) -> Color {
        switch name {
        case "ember": return ember
        case "amber": return amber
        case "mint": return mint
        case "sky": return sky
        case "violet": return violet
        case "rose": return rose
        case "ink": return inkSecondary
        default: return ember
        }
    }

    /// Meters are neutral until they matter. A wall of green/amber/red bars
    /// tells you nothing; a single amber bar in a grey column tells you where
    /// to look.
    static func load(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.80: return Color.white.opacity(0.52)
        case ..<0.92: return amber
        default: return rose
        }
    }

    static func state(_ state: PVERunState) -> Color {
        switch state {
        case .running, .online: return mint
        case .paused, .suspended: return amber
        case .stopped, .offline, .unknown: return inkTertiary
        }
    }

}

// MARK: - Metrics

enum Metrics {
    static let cardRadius: CGFloat = 16
    static let tileRadius: CGFloat = 12
    static let chipRadius: CGFloat = 7
    static let gutter: CGFloat = 20
    /// Space between cards inside one section.
    static let stackSpacing: CGFloat = 12
    /// Space between sections.
    static let sectionSpacing: CGFloat = 26
    /// Left inset of row separators, aligned with row content.
    static let rowInset: CGFloat = 16
}

// MARK: - Motion

enum Motion {
    /// The default. Used for anything that changes layout or state.
    static let snap = Animation.smooth(duration: 0.34)
    /// Larger surfaces, sheets, tab changes.
    static let glide = Animation.smooth(duration: 0.45)
    /// Meters and counters — slower, so a value change reads as a movement.
    static let meter = Animation.smooth(duration: 0.55)
    /// Immediate feedback on touch.
    static let tap = Animation.snappy(duration: 0.22, extraBounce: 0)
    static let fade = Animation.easeOut(duration: 0.18)
}

// MARK: - Typography

extension Font {
    /// Numerals and large headings. Default (not rounded): rounded reads as a
    /// consumer app, and this is a tool.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }
    /// Metric readouts.
    static func metric(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
    static let rowTitle = Font.system(size: 15.5, weight: .medium)
    static let rowMeta = Font.system(size: 12.5, weight: .regular)
    static let label = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 11.5, weight: .regular)
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Section heading. Sentence case, secondary ink — no uppercase micro-tracking.
struct SectionLabel: View {
    var text: String
    var trailing: String?

    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
    }
}

/// A number with its unit set smaller and quieter — used everywhere a metric is
/// displayed so they all line up optically.
struct MetricText: View {
    var value: String
    var unit: String?
    var size: CGFloat
    var weight: Font.Weight = .medium
    var color: Color = Palette.ink

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.1) {
            Text(value)
                .font(.system(size: size, weight: weight))
                .monospacedDigit()
                .tracking(size > 22 ? -0.6 : -0.2)
                .foregroundStyle(color)
                .contentTransition(.numericText())
            if let unit {
                Text(unit)
                    .font(.system(size: max(10, size * 0.46), weight: .medium))
                    .foregroundStyle(Palette.inkTertiary)
            }
        }
    }
}
