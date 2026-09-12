import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()
    @State private var showSettings = false

    private var snapshot: ClusterSnapshot { model.snapshot }

    private var title: String {
        snapshot.clusterName ?? model.selectedServer?.displayName ?? "Overview"
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                statusSection

                if !snapshot.isEmpty {
                    summarySection
                    alertsSection
                    nodesSection
                    guestsSection
                    storageSection
                    activitySection
                }
            }
            .proxynList()
            .navigationTitle(title)
            .toolbar { toolbar }
            .refreshable { await model.refresh() }
            .proxynDestinations()
            .handlesDeepLinks(for: .overview, path: $path)
            .sheet(isPresented: $showSettings) { SettingsView() }
            .overlay {
                if snapshot.isEmpty, model.connection == .connecting {
                    ProgressView("Connecting…")
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Picker("Server", selection: Binding(
                    get: { model.selectedServer?.id },
                    set: { id in
                        if let server = model.servers.first(where: { $0.id == id }) {
                            model.selectServer(server)
                        }
                    })) {
                    ForEach(model.servers) { server in
                        Text(server.displayName).tag(Optional(server.id))
                    }
                }
                Button("Manage Servers", systemImage: "server.rack") {
                    path.append(Route.servers)
                }
            } label: {
                Label("Servers", systemImage: "arrow.left.arrow.right")
            }

            Button("Settings", systemImage: "gearshape") { showSettings = true }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var statusSection: some View {
        if let failure = model.connection.failure {
            Section {
                ConnectionFailureView(error: failure)
            }
        } else if let error = model.lastRefreshError, !snapshot.isEmpty {
            Section {
                InlineErrorRow(message: "Showing data from \(Format.ago(snapshot.capturedAt)). \(error.localizedDescription)") {
                    Task { await model.refresh() }
                }
            }
        }
    }

    private var summarySection: some View {
        Section {
            ClusterSummary(snapshot: snapshot, history: model.history)
        } footer: {
            Text(summaryFooter)
        }
    }

    private var summaryFooter: String {
        let nodes = "\(snapshot.onlineNodes.count) of \(snapshot.nodes.count) nodes online"
        return "\(nodes) · \(snapshot.runningGuests.count) running · \(snapshot.stoppedGuests.count) stopped"
    }

    @ViewBuilder
    private var alertsSection: some View {
        if !snapshot.alerts.isEmpty {
            Section("Alerts") {
                ForEach(snapshot.alerts.prefix(5)) { AlertRow(alert: $0) }
            }
        }
    }

    private var nodesSection: some View {
        Section("Nodes") {
            ForEach(snapshot.nodes) { node in
                NavigationLink(value: Route.node(node.displayName)) {
                    NodeRow(node: node, history: model.history(forNode: node.displayName))
                }
            }
        }
    }

    @ViewBuilder
    private var guestsSection: some View {
        let pinned = snapshot.guests.filter { model.isFavorite($0) }
        let busiest = snapshot.runningGuests
            .filter { !model.isFavorite($0) }
            .sorted { $0.cpuFraction > $1.cpuFraction }
            .prefix(max(0, 5 - pinned.count))
        let shown = pinned + busiest

        if !shown.isEmpty {
            Section {
                ForEach(shown) { guest in
                    if let ref = GuestRef(resource: guest) {
                        NavigationLink(value: Route.guest(ref: ref, name: guest.displayName)) {
                            GuestRow(guest: guest, isFavorite: model.isFavorite(guest))
                        }
                    }
                }
            } header: {
                SectionHeader(title: pinned.isEmpty ? "Busiest Guests" : "Pinned & Busiest",
                              linkTitle: "See All", route: .allGuests)
            }
        }
    }

    @ViewBuilder
    private var storageSection: some View {
        let busiest = snapshot.uniqueStorages.sorted { $0.diskFraction > $1.diskFraction }.prefix(4)
        if !busiest.isEmpty {
            Section("Storage") {
                ForEach(busiest) { storage in
                    NavigationLink(value: Route.storage(node: storage.node ?? "",
                                                        storage: storage.storage ?? storage.displayName)) {
                        StorageRow(storage: storage)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var activitySection: some View {
        if !snapshot.tasks.isEmpty {
            Section {
                ForEach(snapshot.tasks.prefix(5)) { task in
                    NavigationLink(value: Route.task(node: task.node ?? "", upid: task.upid,
                                                     title: Format.taskType(task.type))) {
                        TaskRow(task: task, showsUser: false)
                    }
                }
            } header: {
                SectionHeader(title: "Recent Activity", linkTitle: "See All", route: .allTasks)
            }
        }
    }
}

/// The headline block: cluster CPU with its live trace, then memory, storage
/// and network.
private struct ClusterSummary: View {
    var snapshot: ClusterSnapshot
    var history: LiveHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CPU")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Format.percent(snapshot.aggregateCPU))
                        .font(.metricHero)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("\(Int(snapshot.totalCores)) cores")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .fixedSize()
                .accessibilityElement(children: .combine)

                Sparkline(values: history.cpu, tint: Palette.accent, filled: true, lineWidth: 2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }

            UsageRow(title: "Memory",
                     value: Format.bytes(snapshot.memoryUsed),
                     detail: "of \(Format.bytes(snapshot.memoryTotal))",
                     fraction: snapshot.aggregateMemory)

            UsageRow(title: "Storage",
                     value: Format.bytes(snapshot.storageUsed),
                     detail: "of \(Format.bytes(snapshot.storageTotal))",
                     fraction: snapshot.aggregateStorage)

            if history.netIn.count > 1 {
                HStack(spacing: 16) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down")
                        Text(Format.rate(history.netIn.last))
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up")
                        Text(Format.rate(history.netOut.last))
                    }
                }
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Network: \(Format.rate(history.netIn.last)) in, \(Format.rate(history.netOut.last)) out")
            }
        }
        .padding(.vertical, 8)
    }
}

/// Explains a connection failure and offers the fix that matches it.
struct ConnectionFailureView: View {
    @Environment(AppModel.self) private var model
    var error: ProxmoxError

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.critical)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let fingerprint = error.certificateFingerprint {
                Text(fingerprint)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 12) {
                if case .certificateChanged = error, let fingerprint = error.certificateFingerprint {
                    Button("Trust New Certificate") { model.trustCurrentCertificate(fingerprint) }
                        .buttonStyle(.borderedProminent)
                } else if case .untrustedCertificate = error, let fingerprint = error.certificateFingerprint {
                    Button("Trust Certificate") { model.trustCurrentCertificate(fingerprint) }
                        .buttonStyle(.borderedProminent)
                }
                Button("Try Again") { Task { await model.connect() } }
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        switch error {
        case .certificateChanged: return "Certificate Changed"
        case .untrustedCertificate: return "Untrusted Certificate"
        case .badCredentials, .notAuthenticated: return "Sign-In Failed"
        default: return "Can't Reach Server"
        }
    }
}
