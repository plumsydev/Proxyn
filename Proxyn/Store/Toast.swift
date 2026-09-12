import SwiftUI

struct Toast: Identifiable, Equatable {
    enum Kind: Equatable {
        case success, failure, info, progress

        var symbol: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .failure: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            case .progress: return "arrow.triangle.2.circlepath"
            }
        }

        var tint: Color {
            switch self {
            case .success: return Palette.positive
            case .failure: return Palette.critical
            case .info: return .secondary
            case .progress: return Palette.accent
            }
        }
    }

    let id = UUID()
    var kind: Kind
    var title: String
    var detail: String?
    var upid: String?
    var node: String?
}

/// Compact capsule banners at the top of the screen, like the system's own
/// status notifications. Swipe up or tap to dismiss; tap a task banner to
/// open its log.
struct ToastOverlay: View {
    var toasts: [Toast]
    var onTap: (Toast) -> Void
    var onDismiss: (Toast) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(toasts) { toast in
                ToastCapsule(toast: toast)
                    .onTapGesture { onTap(toast) }
                    .gesture(DragGesture(minimumDistance: 12).onEnded { value in
                        if value.translation.height < 0 { onDismiss(toast) }
                    })
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .frame(maxWidth: 520)
        .animation(Motion.standard, value: toasts.map(\.id))
    }
}

private struct ToastCapsule: View {
    var toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if toast.kind == .progress {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: toast.kind.symbol)
                        .foregroundStyle(toast.kind.tint)
                }
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let detail = toast.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if toast.upid != nil {
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .capsule)
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(toast.upid != nil ? .isButton : [])
    }
}
