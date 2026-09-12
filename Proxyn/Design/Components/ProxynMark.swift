import SwiftUI

/// Rounded hexagon — the node. A path, so it can be stroke-animated.
struct HexShape: Shape {
    var cornerRadius: CGFloat = 0.16

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, cy = rect.midY
        let radius = min(rect.width, rect.height) / 2
        let r = radius * cornerRadius

        let points: [CGPoint] = (0..<6).map { i in
            let angle = CGFloat(i) * .pi / 3 - .pi / 2
            return CGPoint(x: cx + radius * cos(angle), y: cy + radius * sin(angle))
        }

        var path = Path()
        for i in 0..<6 {
            let current = points[i], next = points[(i + 1) % 6], prev = points[(i + 5) % 6]
            let toPrev = unit(from: current, to: prev), toNext = unit(from: current, to: next)
            let start = CGPoint(x: current.x + toPrev.x * r, y: current.y + toPrev.y * r)
            let end = CGPoint(x: current.x + toNext.x * r, y: current.y + toNext.y * r)
            if i == 0 { path.move(to: start) } else { path.addLine(to: start) }
            path.addQuadCurve(to: end, control: current)
        }
        path.closeSubpath()
        return path
    }

    private func unit(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = max(sqrt(dx * dx + dy * dy), 0.0001)
        return CGPoint(x: dx / length, y: dy / length)
    }
}

/// The Proxyn mark: a hexagon enclosing three rack units.
struct ProxynMark: View {
    var size: CGFloat = 64
    /// 0 → undrawn, 1 → complete.
    var progress: Double = 1

    private var barProgress: Double { max(0, min(1, (progress - 0.5) / 0.5)) }

    var body: some View {
        ZStack {
            HexShape()
                .trim(from: 0, to: max(0.001, min(1, progress / 0.8)))
                .stroke(Palette.accent,
                        style: StrokeStyle(lineWidth: size * 0.055, lineCap: .round, lineJoin: .round))
                .rotationEffect(.degrees(-90))

            VStack(alignment: .leading, spacing: size * 0.075) {
                bar(width: 0.30, delay: 0)
                bar(width: 0.20, delay: 0.25)
                bar(width: 0.26, delay: 0.5)
            }
            .frame(width: size * 0.30, alignment: .leading)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat, delay: Double) -> some View {
        let local = max(0, min(1, (barProgress - delay) / max(0.001, 1 - delay)))
        return Capsule()
            .fill(.primary)
            .frame(width: size * width * local, height: size * 0.048)
            .opacity(local)
    }
}
