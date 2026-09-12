import AppKit
import CoreGraphics

// Renders the Proxyn app icon (hexagon + rack bars on an ember gradient) at 1024².
let size = 1024.0
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                          bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Background: near-black with a single, very slight vertical lift. No radial
// bloom — the icon has to read at 40pt on a Home Screen, not glow at 1024.
ctx.setFillColor(color(0x0A0A0C))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

if let grad = CGGradient(colorsSpace: cs,
                         colors: [color(0x16161A), color(0x0A0A0C)] as CFArray,
                         locations: [0, 1]) {
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: 0, y: size),
                           end: CGPoint(x: 0, y: 0),
                           options: [])
}

// Hexagon outline, flat accent.
let center = CGPoint(x: size / 2, y: size / 2)
let radius = size * 0.315
let lineWidth = size * 0.052
let corner = radius * 0.16

func hexPath(radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    var pts: [CGPoint] = []
    for i in 0..<6 {
        let angle = Double(i) * .pi / 3 + .pi / 2
        pts.append(CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
    }
    for i in 0..<6 {
        let cur = pts[i], next = pts[(i + 1) % 6], prev = pts[(i + 5) % 6]
        func unit(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            let dx = b.x - a.x, dy = b.y - a.y
            let l = max(sqrt(dx * dx + dy * dy), 0.0001)
            return CGPoint(x: dx / l, y: dy / l)
        }
        let toPrev = unit(cur, prev), toNext = unit(cur, next)
        let start = CGPoint(x: cur.x + toPrev.x * corner, y: cur.y + toPrev.y * corner)
        let end = CGPoint(x: cur.x + toNext.x * corner, y: cur.y + toNext.y * corner)
        if i == 0 { path.move(to: start) } else { path.addLine(to: start) }
        path.addQuadCurve(to: end, control: cur)
    }
    path.closeSubpath()
    return path
}

ctx.addPath(hexPath(radius: radius))
ctx.setLineWidth(lineWidth)
ctx.setLineJoin(.round)
ctx.setLineCap(.round)
ctx.setStrokeColor(color(0xFF7A33))
ctx.strokePath()

// Three rack bars.
let barHeight = size * 0.045
let widths: [CGFloat] = [0.30, 0.20, 0.26]
let gap = size * 0.075
let totalHeight = barHeight * 3 + gap * 2
var y = center.y + totalHeight / 2 - barHeight

ctx.setFillColor(color(0xECECEF))
let barLeft = center.x - size * 0.30 / 2
for w in widths {
    let width = size * w
    let rect = CGRect(x: barLeft, y: y, width: width, height: barHeight)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: barHeight / 2,
                       cornerHeight: barHeight / 2, transform: nil))
    ctx.fillPath()
    y -= barHeight + gap
}

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try data.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
