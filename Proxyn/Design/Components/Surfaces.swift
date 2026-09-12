import SwiftUI

/// The only container in the app.
///
/// No border, no shadow, no gradient: it separates from the page by tone alone.
/// Outlining every block is what makes an interface look assembled rather than
/// designed — the rhythm of the spacing does that work here instead.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    var radius: CGFloat = Metrics.cardRadius
    /// When set, a 2pt bar runs down the leading edge. Reserved for a card that
    /// genuinely needs to be singled out (an alert, the active server).
    var tint: Color? = nil
    var highlight: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(alignment: .leading) {
                if let tint {
                    Capsule()
                        .fill(tint)
                        .frame(width: 2.5)
                        .padding(.vertical, radius * 0.42)
                        .padding(.leading, 1)
                }
            }
            .overlay {
                if highlight {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Palette.ember.opacity(0.5), lineWidth: 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Inset block used inside a card (fields, quiet groupings).
struct SoftTile<Content: View>: View {
    var padding: CGFloat = 12
    var radius: CGFloat = Metrics.tileRadius
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Palette.surfaceHi)
            )
    }
}

/// Hairline separator between rows of a card. Inset to line up with the text,
/// never full-bleed.
struct Divider1px: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Palette.hairlineSoft)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// Rows stacked inside a card with automatic hairlines — keeps every list in
/// the app built the same way.
struct RowStack<Data: RandomAccessCollection, RowContent: View>: View
where Data.Element: Identifiable {
    var data: Data
    var separatorInset: CGFloat = 0
    @ViewBuilder var row: (Data.Element) -> RowContent

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
                row(element)
                if index < data.count - 1 {
                    Divider1px(inset: separatorInset)
                }
            }
        }
    }
}

extension View {
    /// Cards settle in as they scroll into view. This — not glow — is where the
    /// app gets its sense of fluidity.
    func settleOnScroll() -> some View {
        scrollTransition(.interactive, axis: .vertical) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.35)
                .offset(y: phase.isIdentity ? 0 : (phase.value < 0 ? -8 : 14))
                .scaleEffect(phase.isIdentity ? 1 : 0.985, anchor: .center)
        }
    }
}
