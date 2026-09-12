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
            case .success: return Palette.mint
            case .failure: return Palette.rose
            case .info: return Palette.inkSecondary
            case .progress: return Palette.ember
            }
        }
    }

    let id = UUID()
    var kind: Kind
    var title: String
    var detail: String?
    var upid: String?
    var node: String?
    var createdAt = Date()
}

/// Toasts stack from the top, under the nav bar, and auto-dismiss — except
/// progress toasts, which stay until their task finishes.
struct ToastStack: View {
    var toasts: [Toast]
    var onTap: (Toast) -> Void
    var onDismiss: (Toast) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(toasts) { toast in
                ToastRow(toast: toast, onTap: { onTap(toast) }, onDismiss: { onDismiss(toast) })
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity)
                            .combined(with: .scale(scale: 0.94, anchor: .bottom)),
                        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom))))
            }
        }
        .padding(.horizontal, 14)
        .animation(Motion.snap, value: toasts.map(\.id))
    }
}

private struct ToastRow: View {
    var toast: Toast
    var onTap: () -> Void
    var onDismiss: () -> Void
    @State private var spin = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                Image(systemName: toast.kind.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(toast.kind.tint)
                    .rotationEffect(.degrees(toast.kind == .progress && spin ? 360 : 0))
                    .animation(toast.kind == .progress
                               ? .linear(duration: 1.4).repeatForever(autoreverses: false)
                               : .default, value: spin)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let detail = toast.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.inkTertiary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 4)

                if toast.upid != nil {
                    Text("Voir")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Palette.ember)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.surfaceHi)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.35)))
                    .shadow(color: .black.opacity(0.45), radius: 20, y: 6)
            }
        }
        .buttonStyle(.pressable)
        .onAppear { spin = true }
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .onEnded { value in if value.translation.height > 10 { onDismiss() } }
        )
    }
}
