import AppKit
import CoreGraphics

// Renders the Proxyn app icon at 1024×1024.
//
//   swift Tools/MakeIcon.swift <output.png> [default|dark|tinted]
//
// `default` is fully opaque with no alpha channel — App Store Connect rejects a
// marketing icon that has one. `dark` and `tinted` use a transparent background
// so iOS can draw its own, as the iOS 18 icon appearances expect.

let arguments = CommandLine.arguments
let output = arguments.count > 1 ? arguments[1] : "icon.png"
let variant = arguments.count > 2 ? arguments[2] : "default"

let size = 1024.0
let colorSpace = CGColorSpaceCreateDeviceRGB()
let opaque = variant == "default"
let alphaInfo: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast

guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                          bytesPerRow: 0, space: colorSpace, bitmapInfo: alphaInfo.rawValue) else {
    fatalError("Could not create a drawing context")
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let strokeColor: CGColor
let barColor: CGColor

switch variant {
case "tinted":
    strokeColor = color(0xFFFFFF)
    barColor = color(0xFFFFFF, 0.72)
case "dark":
    strokeColor = color(0xFF8A3D)
    barColor = color(0xECECEF)
default:
    if let gradient = CGGradient(colorsSpace: colorSpace,
                                 colors: [color(0x1B1B20), color(0x0B0B0D)] as CFArray,
                                 locations: [0, 1]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: .zero, options: [])
    }
    strokeColor = color(0xFF8A3D)
    barColor = color(0xECECEF)
}

// Hexagon
let center = CGPoint(x: size / 2, y: size / 2)
let radius = size * 0.315
let corner = radius * 0.16

let hexagon = CGMutablePath()
let vertices: [CGPoint] = (0..<6).map { i in
    let angle = Double(i) * .pi / 3 + .pi / 2
    return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
}
func unit(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    let dx = b.x - a.x, dy = b.y - a.y
    let length = max(sqrt(dx * dx + dy * dy), 0.0001)
    return CGPoint(x: dx / length, y: dy / length)
}
for i in 0..<6 {
    let current = vertices[i], next = vertices[(i + 1) % 6], previous = vertices[(i + 5) % 6]
    let toPrevious = unit(current, previous), toNext = unit(current, next)
    let start = CGPoint(x: current.x + toPrevious.x * corner, y: current.y + toPrevious.y * corner)
    let end = CGPoint(x: current.x + toNext.x * corner, y: current.y + toNext.y * corner)
    if i == 0 { hexagon.move(to: start) } else { hexagon.addLine(to: start) }
    hexagon.addQuadCurve(to: end, control: current)
}
hexagon.closeSubpath()

ctx.addPath(hexagon)
ctx.setLineWidth(size * 0.055)
ctx.setLineJoin(.round)
ctx.setStrokeColor(strokeColor)
ctx.strokePath()

// Rack units
let barHeight = size * 0.048
let widths: [CGFloat] = [0.30, 0.20, 0.26]
let gap = size * 0.075
let totalHeight = barHeight * 3 + gap * 2
let left = center.x - size * 0.30 / 2
var y = center.y + totalHeight / 2 - barHeight

ctx.setFillColor(barColor)
for width in widths {
    let rect = CGRect(x: left, y: y, width: size * width, height: barHeight)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2, transform: nil))
    ctx.fillPath()
    y -= barHeight + gap
}

guard let image = ctx.makeImage(),
      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
    fatalError("Could not encode the icon")
}
try data.write(to: URL(fileURLWithPath: output))
print("\(variant) → \(output)")
