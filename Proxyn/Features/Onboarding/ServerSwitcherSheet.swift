import SwiftUI

struct ServerSwitcherSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var editingServer: ServerProfile?
    @State private var confirmDelete: ServerProfile?

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.sheetCanvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(model.servers) { server in
                            serverRow(server)
                        }

                        Button {
                            Haptics.commit()
                            showAdd = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Ajouter un serveur")
                                    .font(.system(size: 15, weight: .medium))
                                Spacer()
                            }
                            .foregroundStyle(Palette.ember)
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                                .fill(Palette.surface))
                        }
                        .buttonStyle(.pressable)

                        if !model.servers.contains(where: { $0.isDemo }) {
                            Button {
                                Haptics.tap()
                                model.addServer(.demo())
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.circle")
                                    Text("Ajouter le cluster de démonstration")
                                    Spacer()
                                }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Palette.inkTertiary)
                                .padding(.top, 4)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Serveurs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }.foregroundStyle(Palette.ember)
                }
            }
        }
        .presentationBackground(Palette.sheetCanvas)
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showAdd) { AddServerView() }
        .sheet(item: $editingServer) { AddServerView(editing: $0) }
        .alert("Supprimer ce serveur ?", isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } })) {
            Button("Supprimer", role: .destructive) {
                if let confirmDelete { model.deleteServer(confirmDelete) }
                confirmDelete = nil
            }
            Button("Annuler", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("Les identifiants enregistrés dans le Trousseau seront effacés. Rien n'est modifié côté Proxmox.")
        }
    }

    private func serverRow(_ server: ServerProfile) -> some View {
        let isActive = server.id == model.selectedServer?.id
        return Button {
            model.selectServer(server)
            dismiss()
        } label: {
            GlassCard(padding: 15, tint: isActive ? Palette.ember : nil) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(server.displayName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Palette.ink)
                            if isActive { TagChip(text: "actif", tint: Palette.mint) }
                        }
                        Text(server.subtitleLine)
                            .font(.mono(11.5))
                            .foregroundStyle(Palette.inkTertiary)
                            .lineLimit(1)
                        if let last = server.lastConnectedAt {
                            Text("dernière connexion \(Format.ago(last))")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.inkTertiary.opacity(0.8))
                        }
                    }

                    Spacer(minLength: 4)

                    Menu {
                        Button { editingServer = server } label: {
                            Label("Modifier", systemImage: "pencil")
                        }
                        Button(role: .destructive) { confirmDelete = server } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.inkTertiary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.leading, isActive ? 8 : 0)
            }
        }
        .buttonStyle(.pressable)
    }
}
