import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                serverSection

                Section {
                    Picker("Refresh Every", selection: binding(\.refreshInterval)) {
                        Text("2 seconds").tag(2.0)
                        Text("5 seconds").tag(5.0)
                        Text("10 seconds").tag(10.0)
                        Text("30 seconds").tag(30.0)
                    }
                } header: {
                    Text("Live Updates")
                } footer: {
                    Text("Proxyn only polls while it's open. Shorter intervals make charts smoother but put more load on the server.")
                }

                Section("Appearance") {
                    Picker("Theme", selection: binding(\.appearance)) {
                        ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    Toggle("Confirm Before Stopping Guests", isOn: binding(\.confirmDestructiveActions))
                    Toggle("Show Templates", isOn: binding(\.showTemplates))
                    Toggle("Haptic Feedback", isOn: binding(\.hapticsEnabled))
                } header: {
                    Text("Behavior")
                } footer: {
                    Text("Deleting guests, backups and snapshots always asks for confirmation.")
                }

                Section {
                    LabeledContent("Version", value: "\(Bundle.main.appVersion) (\(Bundle.main.appBuild))")
                } header: {
                    Text("About")
                } footer: {
                    Text("Proxyn talks directly to your Proxmox VE servers. No data is sent to any other service, and credentials are stored in the Keychain on this device.\n\nProxmox is a registered trademark of Proxmox Server Solutions GmbH. Proxyn is an independent app and isn't affiliated with or endorsed by Proxmox.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: Route.self) { route in
                if case .servers = route { ServerListView() }
            }
        }
    }

    @ViewBuilder
    private var serverSection: some View {
        Section("Server") {
            if let server = model.selectedServer {
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.displayName)
                    Text(server.isDemo ? "Demo data" : server.addressLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Status", value: connectionLabel)
                if let version = model.snapshot.version?.version {
                    LabeledContent("Proxmox VE", value: version)
                }
            }
            NavigationLink("Manage Servers", value: Route.servers)
        }
    }

    private var connectionLabel: String {
        switch model.connection {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .needsTOTP: return "Waiting for code"
        case .failed: return "Not connected"
        case .idle: return "Idle"
        }
    }

    private func binding<Value: Equatable>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in model.update { $0[keyPath: keyPath] = value } })
    }
}

/// Add, edit, select and remove servers.
struct ServerListView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: ServerProfile?
    @State private var adding = false
    @State private var pendingDelete: ServerProfile?

    var body: some View {
        List {
            Section {
                ForEach(model.servers) { server in
                    Button {
                        model.selectServer(server)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.displayName)
                                    .foregroundStyle(.primary)
                                Text(server.isDemo ? "Demo data" : "\(server.addressLine) · \(server.identityLine)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 8)
                            if server.id == model.selectedServer?.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Palette.accent)
                                    .accessibilityLabel("Selected")
                            }
                        }
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash") { pendingDelete = server }
                            .tint(Palette.critical)
                        if !server.isDemo {
                            Button("Edit", systemImage: "pencil") { editing = server }
                        }
                    }
                    .contextMenu {
                        if !server.isDemo {
                            Button("Edit", systemImage: "pencil") { editing = server }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = server }
                    }
                }
            } footer: {
                Text("Tap a server to switch to it. Swipe to edit or delete.")
            }

            Section {
                Button("Add Server", systemImage: "plus") { adding = true }
                if !model.servers.contains(where: \.isDemo) {
                    Button("Add Demo Cluster", systemImage: "play.rectangle") {
                        model.addServer(.demo())
                    }
                }
            }
        }
        .navigationTitle("Servers")
        .sheet(isPresented: $adding) { AddServerView() }
        .sheet(item: $editing) { AddServerView(editing: $0) }
        .confirmationDialog("Delete \(pendingDelete?.displayName ?? "server")?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingDelete) { server in
            Button("Delete", role: .destructive) { model.deleteServer(server) }
        } message: { _ in
            Text("The saved credentials are removed from this device. Nothing changes on the server.")
        }
    }
}

extension Bundle {
    var appVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
    var appBuild: String { infoDictionary?["CFBundleVersion"] as? String ?? "1" }
}
