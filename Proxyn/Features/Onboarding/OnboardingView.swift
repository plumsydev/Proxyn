import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var showAdd = false
    @State private var appear = false

    private let bullets: [(String, String)] = [
        ("Temps réel", "CPU, mémoire, disques et réseau rafraîchis en continu, avec des graphes que l'on peut parcourir."),
        ("Contrôle complet", "Démarrer, migrer, cloner, snapshoter, sauvegarder — sans ouvrir un navigateur."),
        ("Sans compromis", "Secrets dans le Trousseau, certificats auto-signés épinglés, jetons d'API pris en charge.")
    ]

    var body: some View {
        ZStack {
            AuroraBackground(tint: Palette.ember, intensity: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 60)

                    ProxynMark(size: 60)
                        .scaleEffect(appear ? 1 : 0.82)
                        .opacity(appear ? 1 : 0)
                        .padding(.bottom, 26)

                    Text("Proxyn")
                        .font(.system(size: 40, weight: .semibold))
                        .tracking(-1)
                        .foregroundStyle(Palette.ink)

                    Text("Votre cluster Proxmox, entièrement pilotable depuis votre poche.")
                        .font(.system(size: 16))
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                        .frame(maxWidth: 320, alignment: .leading)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(bullets.enumerated()), id: \.offset) { index, item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.0)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Palette.ink)
                                Text(item.1)
                                    .font(.system(size: 13.5))
                                    .foregroundStyle(Palette.inkTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 14)
                            .opacity(appear ? 1 : 0)
                            .offset(y: appear ? 0 : 16)
                            .animation(.smooth(duration: 0.5).delay(0.12 + Double(index) * 0.08),
                                       value: appear)

                            if index < bullets.count - 1 { Divider1px() }
                        }
                    }
                    .padding(.top, 30)

                    Spacer(minLength: 34)

                    VStack(spacing: 12) {
                        Button {
                            Haptics.commit()
                            showAdd = true
                        } label: {
                            Text("Connecter un serveur")
                        }
                        .buttonStyle(ProminentButtonStyle())

                        Button {
                            Haptics.tap()
                            model.addServer(.demo())
                        } label: {
                            Text("Explorer un cluster de démonstration")
                        }
                        .buttonStyle(QuietButtonStyle(tint: Palette.inkSecondary, fullWidth: true))

                        Text("Proxmox VE 7 et 8 · cluster ou nœud isolé")
                            .font(.caption)
                            .foregroundStyle(Palette.inkTertiary)
                            .padding(.top, 2)
                    }
                    .opacity(appear ? 1 : 0)
                    .animation(.easeOut(duration: 0.45).delay(0.42), value: appear)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showAdd) { AddServerView() }
        .onAppear {
            withAnimation(.smooth(duration: 0.6)) { appear = true }
        }
    }
}
