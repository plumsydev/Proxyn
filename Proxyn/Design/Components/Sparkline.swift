import SwiftUI

/// Inline trend line, drawn with Canvas so a long list can carry one per row.
/// Hairline weight and no fill by default — at this size a filled area is a
/// smudge, not information.
struct Sparkline: View {
    var values: [Double]
    var tint: Color = Palette.ember
    var filled: Bool = false
    var lineWidth: CGFloat = 1.3
    /// Normalise against this instead of the series' own maximum.
    var referenceMax: Double? = nil

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let lo = min(values.min() ?? 0, referenceMax ?? .greatestFiniteMagnitude)
            let hi = referenceMax ?? (values.max() ?? 1)
            let span = hi - lo
            let stepX = size.width / CGFloat(values.count - 1)
            let inset = lineWidth / 2 + 0.5

            func point(_ i: Int) -> CGPoint {
                let normalized = span < 0.000_001 ? 0.5 : (values[i] - lo) / span
                return CGPoint(x: CGFloat(i) * stepX,
                               y: size.height - inset - CGFloat(normalized) * (size.height - inset * 2))
            }

            var line = Path()
            line.move(to: point(0))
            for i in 1..<values.count {
                let p = point(i)
                let prev = point(i - 1)
                let mid = CGPoint(x: (prev.x + p.x) / 2, y: (prev.y + p.y) / 2)
                line.addQuadCurve(to: mid, control: prev)
                if i == values.count - 1 { line.addLine(to: p) }
            }

            if filled {
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.16), tint.opacity(0.0)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }

            context.stroke(line, with: .color(tint),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .drawingGroup()
    }
}
