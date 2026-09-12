import SwiftUI

/// Rounded hexagon — the node. Drawn as a path so it can be stroke-animated.
struct HexShape: Shape {
    var cornerRadius: CGFloat = 0.16   // fraction of the radius

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, cy = rect.midY
        let radius = min(rect.width, rect.height) / 2
        let r = radius * cornerRadius

        var points: [CGPoint] = []
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3 - .pi / 2
            points.append(CGPoint(x: cx + radius * cos(angle), y: cy + radius * sin(angle)))
        }

        var path = Path()
        for i in 0..<6 {
            let current = points[i]
            let next = points[(i + 1) % 6]
            let prev = points[(i + 5) % 6]

            let toPrev = normalize(CGPoint(x: prev.x - current.x, y: prev.y - current.y))
            let toNext = normalize(CGPoint(x: next.x - current.x, y: next.y - current.y))

            let start = CGPoint(x: current.x + toPrev.x * r, y: current.y + toPrev.y * r)
            let end = CGPoint(x: current.x + toNext.x * r, y: current.y + toNext.y * r)

            if i == 0 { path.move(to: start) } else { path.addLine(to: start) }
            path.addQuadCurve(to: end, control: current)
        }
        path.closeSubpath()
        return path
    }

    private func normalize(_ p: CGPoint) -> CGPoint {
        let len = max(sqrt(p.x * p.x + p.y * p.y), 0.0001)
        return CGPoint(x: p.x / len, y: p.y / len)
    }
}

/// The mark: a hexagon enclosing three rack units. Flat accent stroke, no
/// gradient and no halo — it has to survive at 22pt in a settings row.
struct ProxynMark: View {
    var size: CGFloat = 96
    /// 0 → undrawn, 1 → complete. Drives the launch animation.
    var progress: Double = 1
    var glow: Bool = false

    private var barProgress: Double { max(0, min(1, (progress - 0.5) / 0.5)) }

    var body: some View {
        ZStack {
            if glow {
                GlowHalo(color: Palette.ember, radius: size * 0.8, opacity: 0.16)
            }

            HexShape()
                .trim(from: 0, to: max(0.001, min(1, progress / 0.8)))
                .stroke(Palette.ember,
                        style: StrokeStyle(lineWidth: size * 0.052, lineCap: .round, lineJoin: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)

            VStack(alignment: .leading, spacing: size * 0.075) {
                bar(width: 0.30, delay: 0)
                bar(width: 0.20, delay: 0.25)
                bar(width: 0.26, delay: 0.5)
            }
            .frame(width: size * 0.30, alignment: .leading)
        }
        .frame(width: size * 1.04, height: size * 1.04)
    }

    private func bar(width: CGFloat, delay: Double) -> some View {
        let local = max(0, min(1, (barProgress - delay) / max(0.001, 1 - delay)))
        return Capsule()
            .fill(Palette.ink)
            .frame(width: size * width * local, height: size * 0.045)
            .opacity(local)
    }
}

/// Wordmark whose letter-spacing settles as it appears.
struct ProxynWordmark: View {
    var progress: Double = 1
    var size: CGFloat = 30

    var body: some View {
        Text("PROXYN")
            .font(.system(size: size, weight: .semibold))
            .tracking((1 - progress) * 12 + 4.5)
            .foregroundStyle(Palette.ink)
            .opacity(progress)
    }
}
