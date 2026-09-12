import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editingServer: ServerProfile?
    @State private var showSwitcher = false

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            ZStack {
                Palette.sheetCanvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 15) {
                        serverCard
                        refreshCard
                        behaviourCard
                        aboutCard
                    }
                    .padding(18)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }.foregroundStyle(Palette.ember)
                }
            }
        }
        .presentationBackground(Palette.sheetCanvas)
        .sheet(item: $editingServer) { AddServerView(editing: $0) }
        .sheet(isPresented: $showSwitcher) { ServerSwitcherSheet() }
    }

    private var serverCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 13) {
                SectionLabel("Serveur actif")

                if let server = model.selectedServer {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(server.displayName)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text(server.subtitleLine)
                            .font(.mono(11.5))
                            .foregroundStyle(Palette.inkTertiary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 9) {
                        Button("Modifier") { editingServer = server }
                            .buttonStyle(QuietButtonStyle(tint: Palette.ink, fullWidth: true))
                        Button("Changer") { showSwitcher = true }
                            .buttonStyle(QuietButtonStyle(tint: Palette.ember, fullWidth: true))
                    }

                    Divider1px()

                    DetailRow(label: "État",
                              value: connectionLabel,
                              valueColor: model.connection.isConnected ? Palette.mint : Palette.rose)
                    if let version = model.snapshot.version {
                        DetailRow(label: "Proxmox VE",
                                  value: "\(version.version ?? "?") (\(version.release ?? "—"))")
                    }
                    DetailRow(label: "Dernier relevé",
                              value: model.snapshot.capturedAt == .distantPast
                              ? "—" : Format.clock(model.snapshot.capturedAt), monospaced: true)

                    Button {
                        Task { await model.connectAndRefresh(reset: true) }
                    } label: {
                        Label("Reconnecter", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(QuietButtonStyle(tint: Palette.ember, fullWidth: true))
                } else {
                    Text("Aucun serveur configuré.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.inkTertiary)
                }
            }
        }
    }

    private var connectionLabel: String {
        switch model.connection {
        case .connected: return "Connecté"
        case .connecting: return "Connexion…"
        case .needsTOTP: return "2FA requise"
        case .failed: return "Erreur"
        case .idle: return "Inactif"
        }
    }

    private var refreshCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("Temps réel")

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Intervalle de rafraîchissement", systemImage: "timer")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text("\(Int(model.settings.liveRefreshInterval)) s")
                            .font(.metric(15))
                            .foregroundStyle(Palette.ember)
                            .contentTransition(.numericText())
                    }
                    Slider(value: Binding(
                        get: { model.settings.liveRefreshInterval },
                        set: { value in
                            model.update { $0.liveRefreshInterval = value }
                        }), in: 2...30, step: 1)
                    .tint(Palette.ember)
                    .onChange(of: model.settings.liveRefreshInterval) { _, _ in
                        model.startPolling()
                    }
                    Text("Un intervalle court donne des graphes plus fluides mais sollicite davantage le cluster et la batterie.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider1px()

                ToggleRow(title: "Continuer en arrière-plan",
                          subtitle: "Reprend le suivi dès le retour dans l'app.",
                          isOn: Binding(
                            get: { model.settings.backgroundRefreshEnabled },
                            set: { value in model.update { $0.backgroundRefreshEnabled = value } }))
            }
        }
    }

    private var behaviourCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Comportement")

                ToggleRow(title: "Retours haptiques",
                          subtitle: "Vibrations sur les actions et les changements d'état.",
                          isOn: Binding(
                            get: { model.settings.hapticsEnabled },
                            set: { value in model.update { $0.hapticsEnabled = value } }))

                Divider1px()

                ToggleRow(title: "Confirmer les actions risquées",
                          subtitle: "Demande une confirmation avant un arrêt forcé ou un reset.",
                          isOn: Binding(
                            get: { model.settings.confirmDestructiveActions },
                            set: { value in model.update { $0.confirmDestructiveActions = value } }))

                Divider1px()

                ToggleRow(title: "Afficher les modèles",
                          subtitle: "Inclut les templates dans la liste des instances.",
                          isOn: Binding(
                            get: { model.settings.showTemplates },
                            set: { value in model.update { $0.showTemplates = value } }))

                Divider1px()

                ToggleRow(title: "Lignes compactes",
                          subtitle: "Masque les étiquettes et les mini-graphes dans les listes.",
                          isOn: Binding(
                            get: { model.settings.compactGuestRows },
                            set: { value in model.update { $0.compactGuestRows = value } }))
            }
        }
    }

    private var aboutCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("À propos")

                HStack(spacing: 14) {
                    ProxynMark(size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Proxyn")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text("version \(Bundle.main.appVersion) (\(Bundle.main.appBuild))")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.inkTertiary)
                    }
                    Spacer(minLength: 0)
                }

                Divider1px()

                Text("Proxyn communique directement avec l'API Proxmox VE de vos serveurs. Aucune donnée ne transite par un service tiers, et les identifiants restent dans le Trousseau de l'appareil.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                DetailRow(label: "Instances suivies", value: "\(model.snapshot.guests.count)")
                DetailRow(label: "Nœuds", value: "\(model.snapshot.nodes.count)")
                DetailRow(label: "Serveurs enregistrés", value: "\(model.servers.count)")
            }
        }
    }
}

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    var appBuild: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
