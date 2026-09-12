import SwiftUI
import WidgetKit

/// Widget building blocks. Few of them, reused everywhere, so every widget in
/// the family shares the same header, figures and meters.

struct WidgetHeader<Trailing: View>: View {
    var symbol: String
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.accent)
                .widgetAccentable()
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            trailing
        }
    }
}

extension WidgetHeader where Trailing == EmptyView {
    init(symbol: String, title: String) {
        self.init(symbol: symbol, title: title) { EmptyView() }
    }
}

/// The large number of a widget, with its caption underneath.
struct WidgetFigure: View {
    var value: String
    var caption: String
    var size: CGFloat = 36
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: size, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .widgetAccentable()
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// Label and value over a thin capacity bar.
struct WidgetMeter: View {
    var label: String
    var value: String
    var fraction: Double
    var tint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(label)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(value)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .font(.caption2)
            WidgetBar(fraction: fraction, tint: tint)
        }
    }
}

struct WidgetBar: View {
    var fraction: Double
    var tint: Color? = nil
    var height: CGFloat = 4

    private var clamped: Double { max(0, min(1, fraction)) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(clamped >= 0.9 ? Palette.critical : (tint ?? Color.primary.opacity(0.55)))
                    .frame(width: clamped > 0 ? max(height, geo.size.width * clamped) : 0)
                    .widgetAccentable()
            }
        }
        .frame(height: height)
    }
}

/// Filled trend line. Draws a flat baseline when there's not enough history yet
/// rather than leaving a hole in the layout.
struct WidgetSparkline: View {
    var values: [Double]

    var body: some View {
        GeometryReader { geo in
            let points = values.count > 1 ? values : [0.5, 0.5]
            let low = points.min() ?? 0
            let high = max(points.max() ?? 1, low + 0.05)
            let step = geo.size.width / CGFloat(points.count - 1)
            let y: (Double) -> CGFloat = { value in
                geo.size.height - 1 - CGFloat((value - low) / (high - low)) * (geo.size.height - 2)
            }

            let line = Path { path in
                for (index, value) in points.enumerated() {
                    let point = CGPoint(x: CGFloat(index) * step, y: y(value))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }

            ZStack {
                Path { path in
                    path.addPath(line)
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    path.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [Palette.accent.opacity(0.22), Palette.accent.opacity(0)],
                                     startPoint: .top, endPoint: .bottom))

                line
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .widgetAccentable()
            }
        }
    }
}

struct WidgetStateDot: View {
    var running: Bool
    var paused: Bool = false
    var size: CGFloat = 7

    var body: some View {
        Group {
            if running || paused {
                Circle().fill(paused ? Palette.warning : Palette.positive)
            } else {
                Circle().strokeBorder(.secondary, lineWidth: 1.3)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Shown when the app hasn't been set up yet.
struct WidgetEmptyState: View {
    var symbol: String
    var message: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "Updated 4 min ago". Static on purpose: a live `.relative` timer ticks
/// every second, which is distracting on a Home Screen, and it would follow the
/// system language instead of the app's.
struct WidgetUpdatedLabel: View {
    var date: Date

    var body: some View {
        Text("Updated \(Format.ago(date))")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }
}

extension View {
    /// Widgets render in the app's language with the device's regional formats.
    func widgetLocale() -> some View {
        environment(\.locale, AppLocale.current)
    }
}
