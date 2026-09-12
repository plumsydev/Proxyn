import SwiftUI

/// Shown over the app when a ticket expires on a 2FA-protected account.
struct TOTPPrompt: View {
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @State private var submitting = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Palette.canvas.opacity(0.7))
                .ignoresSafeArea()

            GlassCard(padding: 22) {
                VStack(spacing: 16) {
                    Image(systemName: "lock.rotation")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Palette.ember)

                    VStack(spacing: 5) {
                        Text("Vérification en deux étapes")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        Text("Saisissez le code à usage unique de \(model.selectedServer?.fullUsername ?? "votre compte").")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.inkSecondary)
                            .multilineTextAlignment(.center)
                    }

                    TextField("000000", text: $code)
                        .font(.mono(28, weight: .medium))
                        .tracking(8)
                        .multilineTextAlignment(.center)
                        .keyboardType(.numberPad)
                        .focused($focused)
                        .foregroundStyle(Palette.ink)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Palette.surfaceHi))
                        .onChange(of: code) { _, value in
                            let digits = value.filter(\.isNumber)
                            if digits != value { code = String(digits.prefix(6)) }
                            else if digits.count > 6 { code = String(digits.prefix(6)) }
                            if code.count == 6 { submit() }
                        }

                    Button {
                        submit()
                    } label: {
                        HStack(spacing: 8) {
                            if submitting { ProgressView().controlSize(.small).tint(.black) }
                            Text("Valider")
                        }
                    }
                    .buttonStyle(ProminentButtonStyle())
                    .disabled(code.count < 6 || submitting)
                    .opacity(code.count < 6 ? 0.5 : 1)
                }
            }
            .frame(maxWidth: 340)
            .padding(.horizontal, 26)
        }
        .onAppear { focused = true }
    }

    private func submit() {
        guard !submitting, code.count == 6 else { return }
        submitting = true
        Task {
            await model.submitTOTP(code)
            submitting = false
            code = ""
        }
    }
}
