import SwiftUI

/// Filled when up, hollow when down: the shape carries state as well as the
/// colour, so it still reads for colour-blind users and in grayscale.
struct StatusDot: View {
    var state: PVERunState
    var size: CGFloat = 8

    private var isFilled: Bool { state.isUp || state.isPaused }

    var body: some View {
        ZStack {
            if isFilled {
                Circle().fill(Palette.state(state))
            } else {
                Circle().strokeBorder(Palette.state(state), lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(state.label)
    }
}

/// Thin capacity bar with a neutral-until-critical tint.
struct CapacityBar: View {
    var fraction: Double
    var tint: Color? = nil

    private var clamped: Double { max(0, min(1, fraction.isFinite ? fraction : 0)) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.fill)
                Capsule()
                    .fill(tint ?? Palette.capacity(clamped))
                    .frame(width: clamped > 0 ? max(4, geo.size.width * clamped) : 0)
            }
        }
        .frame(height: 4)
        .animation(Motion.value, value: clamped)
        .accessibilityHidden(true)
    }
}

/// Label, figures and a capacity bar. Stacks vertically so long values wrap
/// at large Dynamic Type sizes instead of running off the edge.
struct UsageRow: View {
    var title: String
    var value: String
    var detail: String?
    var fraction: Double
    var tint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    figures
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.secondary)
                    figures
                }
            }
            CapacityBar(fraction: fraction, tint: tint)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([value, detail].compactMap { $0 }.joined(separator: ", "))
    }

    private var figures: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.metricBody)
                .contentTransition(.numericText())
            if let detail {
                Text(detail)
                    .font(.metricCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }
}

/// Proxmox tags, wrapped to as many lines as needed.
struct TagList: View {
    var tags: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Palette.fill, in: .rect(cornerRadius: 6))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tags: \(tags.joined(separator: ", "))")
    }
}

/// Minimal wrapping layout for tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Inline error inside a list: the stale data stays visible underneath.
struct InlineErrorRow: View {
    var message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.critical)
                .font(.subheadline)
            if let retry {
                Button("Try Again", action: retry)
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

extension View {
    /// Standard grouped-list look for every screen.
    func proxynList() -> some View {
        listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .textCase(nil)
    }
}

/// Icon-over-title action button, the pattern Contacts uses for call / message.
/// The title never wraps: it scales down slightly, then truncates.
struct ActionTileStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(ActionTileLabelStyle())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .foregroundStyle(prominent ? Color(uiColor: .systemBackground) : Palette.accent)
            .background(prominent ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Palette.fill),
                        in: .rect(cornerRadius: 12))
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ActionTileLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 4) {
            configuration.icon
                .font(.title3)
                .frame(height: 24)
            configuration.title
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}
