import SwiftUI

// MARK: - Button styles

/// Every tappable surface compresses very slightly. 0.985 — just enough to feel
/// the touch, not enough to look like a toy.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.985
    var haptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(Motion.tap, value: configuration.isPressed)
            .sensoryFeedback(.selection, trigger: haptic && configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

/// The one filled button. At most one per screen.
struct ProminentButtonStyle: ButtonStyle {
    var tint: Color = Palette.ember
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15.5, weight: .semibold))
            .foregroundStyle(Color(hex: "1A0E06"))
            .padding(.vertical, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, fullWidth ? 0 : 22)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(Motion.tap, value: configuration.isPressed)
    }
}

/// Secondary button: filled with the raised surface, no outline.
struct QuietButtonStyle: ButtonStyle {
    var tint: Color = Palette.ink
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14.5, weight: .medium))
            .foregroundStyle(tint)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Palette.surfaceHi)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(Motion.tap, value: configuration.isPressed)
    }
}

/// The contextual primary action on a guest. Positive actions (start, resume)
/// are filled with the accent; everything else is a firm neutral so that
/// stopping a machine never looks like the happy path.
struct PrimaryGuestActionStyle: ButtonStyle {
    var positive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(positive ? Color(hex: "1A0E06") : Palette.ink)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                    .fill(positive ? Palette.ember : Palette.surfaceHi)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(Motion.tap, value: configuration.isPressed)
    }
}

/// Square icon button — the secondary actions everywhere in the app.
struct IconButton: View {
    var symbol: String
    var tint: Color = Palette.ink
    var size: CGFloat = 40
    var accessibilityName: String = ""
    var enabled: Bool = true
    var busy: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: { Haptics.tap(); action() }) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                    .fill(Palette.surfaceHi)
                if busy {
                    ProgressView().controlSize(.small).tint(Palette.inkSecondary)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.38, weight: .medium))
                        .foregroundStyle(enabled ? tint : Palette.inkTertiary.opacity(0.45))
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.pressable)
        .disabled(!enabled || busy)
        .accessibilityLabel(accessibilityName)
    }
}

// MARK: - Segmented rail

/// Selection slides as one object. The selected item is simply lighter — no
/// accent outline, no shadow.
struct SegmentedRail<T: Hashable & Identifiable>: View {
    var items: [T]
    var label: (T) -> String
    var symbol: ((T) -> String?)? = nil
    @Binding var selection: T
    var tint: Color = Palette.ember

    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let isOn = item == selection
                Button {
                    guard !isOn else { return }
                    Haptics.select()
                    withAnimation(Motion.snap) { selection = item }
                } label: {
                    HStack(spacing: 5) {
                        if let symbol, let name = symbol(item) {
                            Image(systemName: name).font(.system(size: 11, weight: .semibold))
                        }
                        Text(label(item))
                            .font(.system(size: 13.5, weight: isOn ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(isOn ? Palette.ink : Palette.inkTertiary)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background {
                        if isOn {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Palette.surfaceHi)
                                .matchedGeometryEffect(id: "rail", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Palette.surface)
        )
    }
}

// MARK: - Small parts

/// Status dot. Filled when up, hollow when down — shape carries the state as
/// well as colour, so it still reads without relying on hue.
struct StatusPip: View {
    var color: Color
    var pulsing: Bool = false
    var size: CGFloat = 7
    var hollow: Bool = false

    @State private var breathe = false

    var body: some View {
        Group {
            if hollow {
                Circle()
                    .strokeBorder(color, lineWidth: 1.3)
                    .frame(width: size, height: size)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
            }
        }
        .opacity(pulsing && breathe ? 0.45 : 1)
        .animation(pulsing ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : nil,
                   value: breathe)
        .frame(width: size * 1.6, height: size * 1.6)
        .onAppear { if pulsing { breathe = true } }
    }
}

struct TagChip: View {
    var text: String
    var tint: Color = Palette.inkSecondary
    var symbol: String? = nil
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 3.5) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 11.5))
                .lineLimit(1)
        }
        .foregroundStyle(filled ? Color(hex: "17100A") : tint)
        .padding(.horizontal, 6.5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: Metrics.chipRadius, style: .continuous)
                .fill(filled ? tint : Palette.surfaceHi)
        )
    }
}

// MARK: - States

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Palette.inkTertiary)
                .padding(.bottom, 4)

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Palette.inkTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(QuietButtonStyle(tint: Palette.ember))
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

/// Inline error strip. Stale data with an explanation beats a blank screen.
struct ErrorBanner: View {
    var message: String
    var retry: (() -> Void)? = nil
    var dismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.rose)
                .padding(.top, 2)

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            if let retry {
                Button("Réessayer", action: retry)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.ember)
            }
            if let dismiss {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.inkTertiary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Palette.surface))
        .overlay(alignment: .leading) {
            Capsule().fill(Palette.rose).frame(width: 2.5)
                .padding(.vertical, 7).padding(.leading, 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Color.white.opacity(0.06), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.55)
                        .offset(x: phase * geo.size.width * 1.6)
                }
                .mask(content)
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

struct SkeletonBlock: View {
    var height: CGFloat
    var radius: CGFloat = Metrics.cardRadius

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Palette.surface)
            .frame(height: height)
            .shimmering()
    }
}
