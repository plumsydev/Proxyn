import SwiftUI

/// Shared page chrome.
///
/// A large title that trades places with a compact bar *continuously* as you
/// scroll — driven by the scroll offset rather than by a boolean, so there is
/// no snap at the threshold. The status line sits under the title, where it
/// reads as a sentence instead of as a label stuck above it.
struct ScreenScaffold<Content: View, Trailing: View>: View {
    var title: String
    var eyebrow: String?
    var statusColor: Color?
    var statusPulsing: Bool = false
    var tint: Color = Palette.ember
    var onRefresh: (() async -> Void)?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    @State private var scrollY: CGFloat = 0

    /// 0 = expanded, 1 = fully collapsed.
    private var progress: CGFloat { max(0, min(1, scrollY / 46)) }

    var body: some View {
        ZStack(alignment: .top) {
            scroller
            compactBar
                .opacity(Double(progress))
                .allowsHitTesting(progress > 0.9)
        }
        .background(AuroraBackground(tint: tint))
    }

    private var scroller: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                header
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 4)
                    .opacity(Double(1 - progress * 1.35))
                    .offset(y: -progress * 12)

                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    content
                }
                .padding(.horizontal, Metrics.gutter)
            }
            .padding(.bottom, 92)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, value in
            scrollY = value
        }
        .refreshable { await onRefresh?() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 31, weight: .semibold))
                        .tracking(-0.7)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let statusColor {
                        StatusPip(color: statusColor, pulsing: statusPulsing, size: 6)
                            .offset(y: -2)
                    }
                }
                if let eyebrow {
                    Text(eyebrow)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Palette.inkTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) { trailing }
        }
    }

    private var compactBar: some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            if let statusColor {
                StatusPip(color: statusColor, pulsing: statusPulsing, size: 5)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) { trailing }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 9)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(Palette.canvas.opacity(0.5)))
                .overlay(alignment: .bottom) { Divider1px() }
                .ignoresSafeArea(edges: .top)
        }
    }
}

extension ScreenScaffold where Trailing == EmptyView {
    init(title: String, eyebrow: String? = nil, statusColor: Color? = nil,
         statusPulsing: Bool = false, tint: Color = Palette.ember,
         onRefresh: (() async -> Void)? = nil,
         @ViewBuilder content: () -> Content) {
        self.init(title: title, eyebrow: eyebrow, statusColor: statusColor,
                  statusPulsing: statusPulsing, tint: tint, onRefresh: onRefresh,
                  trailing: { EmptyView() }, content: content)
    }
}

/// Header action. A plain glyph — no circular chrome around every icon.
struct CircleIconButton: View {
    var symbol: String
    var tint: Color = Palette.inkSecondary
    var badge: Int = 0
    var action: () -> Void

    var body: some View {
        Button(action: { Haptics.tap(); action() }) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Circle()
                            .fill(Palette.ember)
                            .frame(width: 6, height: 6)
                            .offset(x: -4, y: 5)
                    }
                }
        }
        .buttonStyle(.pressable)
    }
}

/// Key/value row used across detail screens.
struct DetailRow: View {
    var label: String
    var value: String
    var valueColor: Color = Palette.ink
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.inkTertiary)
            Spacer(minLength: 12)
            Text(value)
                .font(monospaced ? .mono(12.5) : .system(size: 13.5))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 6)
    }
}

/// Four-up figure strip. Values are ink by default: a number is only coloured
/// when its colour means something.
struct HeroStat: View {
    var value: String
    var label: String
    var tint: Color = Palette.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.metric(18, weight: .medium))
                .tracking(-0.3)
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.inkTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Small labelled figure used inside cards.
struct MiniFact: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.inkTertiary)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
