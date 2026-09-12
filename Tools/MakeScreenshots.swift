import AppKit
import CoreGraphics
import CoreText
import Foundation

// Composes App Store screenshots: a caption set in SF Pro above an unframed,
// full-screen capture of the app. No device mockup, no gradient, no ornament —
// the app is the image.
//
//   swift Tools/MakeScreenshots.swift AppStore/screenshots.json
//
// Output PNGs are opaque (no alpha channel), which App Store Connect requires.

struct Manifest: Decodable {
    struct Canvas: Decodable {
        var width: Int
        var height: Int
        var top: Double
        var side: Double
        var bottom: Double
        var headlineSize: Double
        var sublineSize: Double
        var captionGap: Double
        var imageGap: Double
        /// Display corner radius as a fraction of the capture's width.
        var cornerRatio: Double
    }
    struct Shot: Decodable {
        var input: String
        var output: String
        var headline: String
        var subline: String
        var dark: Bool
    }
    var canvases: [String: Canvas]
    var shots: [String: [Shot]]
}

struct Theme {
    var background: CGColor
    var ink: CGColor
    var secondary: CGColor
    var border: CGColor
    var shadow: CGColor

    static let light = Theme(background: rgb(0xECEDF0), ink: rgb(0x111113), secondary: rgb(0x6A6B72),
                             border: rgb(0xD3D4DA), shadow: CGColor(gray: 0, alpha: 0.12))
    static let dark = Theme(background: rgb(0x131416), ink: rgb(0xF1F1F4), secondary: rgb(0x9B9CA4),
                            border: rgb(0x2C2D32), shadow: CGColor(gray: 0, alpha: 0.5))
}

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func attributed(_ text: String, size: Double, weight: NSFont.Weight, color: CGColor,
                kern: Double, lineHeight: Double) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.minimumLineHeight = size * lineHeight
    paragraph.maximumLineHeight = size * lineHeight
    paragraph.lineBreakMode = .byWordWrapping
    return NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(cgColor: color) ?? .black,
        .kern: kern,
        .paragraphStyle: paragraph
    ])
}

func textHeight(_ string: NSAttributedString, width: Double) -> Double {
    let setter = CTFramesetterCreateWithAttributedString(string)
    let size = CTFramesetterSuggestFrameSizeWithConstraints(
        setter, CFRange(location: 0, length: 0), nil,
        CGSize(width: width, height: .greatestFiniteMagnitude), nil)
    return ceil(size.height)
}

/// Draws with a top-left origin expressed in canvas coordinates.
func draw(_ string: NSAttributedString, in ctx: CGContext, x: Double, top: Double, width: Double,
          canvasHeight: Double) -> Double {
    let height = textHeight(string, width: width)
    let rect = CGRect(x: x, y: canvasHeight - top - height, width: width, height: height)
    let setter = CTFramesetterCreateWithAttributedString(string)
    let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil)
    CTFrameDraw(frame, ctx)
    return height
}

func loadImage(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func compose(_ shot: Manifest.Shot, canvas: Manifest.Canvas, root: URL) throws {
    let W = Double(canvas.width), H = Double(canvas.height)
    let theme = shot.dark ? Theme.dark : Theme.light

    guard let capture = loadImage(root.appendingPathComponent(shot.input).path) else {
        throw NSError(domain: "shots", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing capture \(shot.input)"])
    }
    guard let ctx = CGContext(data: nil, width: canvas.width, height: canvas.height, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        throw NSError(domain: "shots", code: 2)
    }
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    ctx.setShouldSmoothFonts(true)

    ctx.setFillColor(theme.background)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

    // Caption
    let textWidth = W - canvas.side * 2
    let headline = attributed(shot.headline, size: canvas.headlineSize, weight: .semibold, color: theme.ink,
                              kern: -canvas.headlineSize * 0.012, lineHeight: 1.06)
    let subline = attributed(shot.subline, size: canvas.sublineSize, weight: .regular, color: theme.secondary,
                             kern: -canvas.sublineSize * 0.004, lineHeight: 1.28)
    var y = canvas.top
    y += draw(headline, in: ctx, x: canvas.side, top: y, width: textWidth, canvasHeight: H)
    y += canvas.captionGap
    y += draw(subline, in: ctx, x: canvas.side, top: y, width: textWidth, canvasHeight: H)
    y += canvas.imageGap

    // Capture, scaled to the remaining space and centred
    let aspect = Double(capture.width) / Double(capture.height)
    let available = H - y - canvas.bottom
    var imageHeight = available
    var imageWidth = imageHeight * aspect
    if imageWidth > textWidth {
        imageWidth = textWidth
        imageHeight = imageWidth / aspect
    }
    let imageRect = CGRect(x: (W - imageWidth) / 2, y: canvas.bottom + (available - imageHeight),
                           width: imageWidth, height: imageHeight)
    let radius = imageWidth * canvas.cornerRatio
    let shape = CGPath(roundedRect: imageRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -H * 0.008), blur: H * 0.025, color: theme.shadow)
    ctx.addPath(shape)
    ctx.setFillColor(theme.background)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.draw(capture, in: imageRect)
    ctx.restoreGState()

    ctx.addPath(shape)
    ctx.setStrokeColor(theme.border)
    ctx.setLineWidth(max(2, W / 640))
    ctx.strokePath()

    guard let image = ctx.makeImage(),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw NSError(domain: "shots", code: 3)
    }
    let outputURL = root.appendingPathComponent(shot.output)
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: outputURL)
    print("\(canvas.width)×\(canvas.height)  \(shot.output)")
}

let manifestPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppStore/screenshots.json"
let manifestURL = URL(fileURLWithPath: manifestPath)
let root = manifestURL.deletingLastPathComponent()
let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))

for (device, shots) in manifest.shots.sorted(by: { $0.key < $1.key }) {
    guard let canvas = manifest.canvases[device] else { fatalError("No canvas for \(device)") }
    for shot in shots { try compose(shot, canvas: canvas, root: root) }
}
