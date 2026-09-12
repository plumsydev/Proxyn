import SwiftUI

/// The page backdrop.
///
/// Flat black with one barely-there warm lift behind the header — enough that a
/// large empty area isn't a dead sheet of grey, far short of a decorative
/// gradient competing with the content.
struct AuroraBackground: View {
    var tint: Color = Palette.ember
    var intensity: Double = 1
    var animated: Bool = true

    var body: some View {
        ZStack(alignment: .top) {
            Palette.canvas

            LinearGradient(
                colors: [tint.opacity(0.055 * intensity), .clear],
                startPoint: .top, endPoint: .bottom)
                .frame(height: 360)

            LinearGradient(
                colors: [Color.white.opacity(0.02), .clear],
                startPoint: .top, endPoint: .bottom)
                .frame(height: 180)
        }
        .ignoresSafeArea()
    }
}

/// Kept for the splash and the empty states; much softer than a glow.
struct GlowHalo: View {
    var color: Color
    var radius: CGFloat = 120
    var opacity: Double = 0.22

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(opacity), .clear],
                                 center: .center, startRadius: 0, endRadius: radius))
            .frame(width: radius * 2, height: radius * 2)
            .blur(radius: 18)
            .allowsHitTesting(false)
    }
}
