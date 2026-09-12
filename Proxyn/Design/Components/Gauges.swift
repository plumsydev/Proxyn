import SwiftUI

/// Horizontal meter. Three points tall, no glow, neutral until the value is
/// worth reacting to.
struct MeterBar: View {
    var fraction: Double
    /// Drawn behind the main fill — provisioned vs used, swap behind RAM.
    var ghostFraction: Double? = nil
    var tint: Color? = nil
    var height: CGFloat = 3

    private var clamped: Double { max(0, min(1, fraction.isFinite ? fraction : 0)) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))

                if let ghostFraction, ghostFraction > 0 {
                    Capsule()
                        .fill(Color.white.opacity(0.13))
                        .frame(width: geo.size.width * max(0, min(1, ghostFraction)))
                }

                Capsule()
                    .fill(tint ?? Palette.load(clamped))
                    .frame(width: max(clamped > 0 ? height : 0, geo.size.width * clamped))
            }
        }
        .frame(height: height)
        .animation(Motion.meter, value: clamped)
    }
}

/// The app's headline metric block.
///
///     Processeur                              24 %
///     ────────────────────────────────────────────
///     32 cœurs                             pic 41 %
///
/// It replaces the ring gauges: a bar carries a ratio more precisely than an
/// arc, leaves room for the real numbers, and three of them stack into a
/// readable column instead of a row of decorations.
struct VitalRow: View {
    var label: String
    var value: String
    var unit: String?
    var fraction: Double
    var leadingDetail: String?
    var trailingDetail: String?
    var tint: Color? = nil
    var valueSize: CGFloat = 21

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
                Spacer(minLength: 12)
                MetricText(value: value, unit: unit, size: valueSize, weight: .medium)
            }

            MeterBar(fraction: fraction, tint: tint)

            if leadingDetail != nil || trailingDetail != nil {
                HStack {
                    if let leadingDetail {
                        Text(leadingDetail)
                            .font(.caption)
                            .foregroundStyle(Palette.inkTertiary)
                    }
                    Spacer(minLength: 8)
                    if let trailingDetail {
                        Text(trailingDetail)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Palette.inkTertiary)
                    }
                }
            }
        }
    }
}

/// Compact version for cards that list several ratios in a row.
struct LabeledMeter: View {
    var label: String
    var fraction: Double
    var detail: String
    var tint: Color? = nil
    var symbol: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.inkSecondary)
                Spacer(minLength: 8)
                Text(detail)
                    .font(.metric(12.5))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
            }
            MeterBar(fraction: fraction, tint: tint)
        }
    }
}

/// Single-line ratio used inside dense cards: `CPU  27 %` over a thin bar.
struct StatLine: View {
    var label: String
    var value: String
    var fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.inkTertiary)
                Spacer(minLength: 4)
                Text(value)
                    .font(.metric(11.5))
                    .foregroundStyle(Palette.inkSecondary)
            }
            MeterBar(fraction: fraction, height: 2.5)
        }
    }
}

/// Percentage that tweens digit by digit.
struct AnimatedPercent: View {
    var fraction: Double
    var decimals: Int = 0
    var size: CGFloat = 17
    var color: Color = Palette.ink

    var body: some View {
        let pct = max(0, min(100, (fraction.isFinite ? fraction : 0) * 100))
        MetricText(value: String(format: "%.\(decimals)f", pct), unit: "%",
                   size: size, color: color)
            .animation(Motion.meter, value: pct)
    }
}
