import SwiftUI

/// Text input. Label in sentence case above the field, raised-surface fill, and
/// a single accent hairline on focus — no permanent outline.
struct ProxynField: View {
    var label: String
    var placeholder: String = ""
    @Binding var text: String
    var symbol: String? = nil
    var keyboard: UIKeyboardType = .default
    var isSecure: Bool = false
    var autocapitalization: TextInputAutocapitalization = .never
    var monospaced: Bool = false
    var submitLabel: SubmitLabel = .next
    var onSubmit: (() -> Void)? = nil

    @FocusState private var focused: Bool
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.inkTertiary)

            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(focused ? Palette.ember : Palette.inkTertiary)
                        .frame(width: 16)
                        .animation(Motion.fade, value: focused)
                }

                Group {
                    if isSecure && !revealed {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .font(monospaced ? .mono(15) : .system(size: 15))
                .foregroundStyle(Palette.ink)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(submitLabel)
                .onSubmit { onSubmit?() }

                if isSecure && !text.isEmpty {
                    Button { revealed.toggle(); Haptics.tap() } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.inkTertiary)
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Palette.surfaceHi)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Palette.ember.opacity(focused ? 0.75 : 0), lineWidth: 1)
            )
            .animation(Motion.fade, value: focused)
        }
    }
}

struct ToggleRow: View {
    var title: String
    var subtitle: String?
    var symbol: String?
    @Binding var isOn: Bool
    var tint: Color = Palette.ember

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(tint)
        }
        .padding(.vertical, 7)
    }
}

/// Menu-backed picker, styled like the rest of the app.
struct PickerRow<T: Hashable & Identifiable>: View {
    var title: String
    var symbol: String?
    var options: [T]
    var label: (T) -> String
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            Menu {
                ForEach(options) { option in
                    Button {
                        Haptics.select()
                        selection = option
                    } label: {
                        if option == selection {
                            Label(label(option), systemImage: "checkmark")
                        } else {
                            Text(label(option))
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(label(selection))
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(Palette.ember)
            }
        }
        .padding(.vertical, 7)
    }
}

struct StringOption: Identifiable, Hashable {
    var id: String { value }
    var value: String
    var title: String
    init(_ value: String, _ title: String? = nil) {
        self.value = value
        self.title = title ?? value
    }
}

/// Search input.
struct SearchField: View {
    @Binding var text: String
    var placeholder: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.inkTertiary)

            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .foregroundStyle(Palette.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focused)
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    Haptics.tap()
                    withAnimation(Motion.fade) { text = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.inkTertiary)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Palette.ember.opacity(focused ? 0.7 : 0), lineWidth: 1))
        .animation(Motion.fade, value: focused)
    }
}
