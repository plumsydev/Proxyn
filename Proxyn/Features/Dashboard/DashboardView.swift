import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Binding var showServerSwitcher: Bool
    @Binding var showSettings: Bool

    @State private var path = NavigationPath()

    private var snapshot: ClusterSnapshot { model.snapshot }

    var body: some View {
        NavigationStack(path: $path) {
            ScreenScaffold(
                title: snapshot.clusterName ?? model.selectedServer?.displayName ?? "Proxmox",
                eyebrow: subtitle,
                statusColor: statusColor,
                statusPulsing: model.connection.isConnected,
                onRefresh: { await model.refresh() },
                trailing: {
                    CircleIconButton(symbol: "square.stack.3d.up") { showServerSwitcher = true }
                    CircleIconButton(symbol: "gearshape") { showSettings = true }
                },
                content: {
                    if case .failed(let message) = model.connection {
                        ErrorBanner(message: message, retry: {
                            Task { await model.connectAndRefresh() }
                        })
                    }

                    if snapshot.capturedAt == .distantPast {
                        loadingSkeleton
                    } else {
                        vitalsCard.settleOnScroll()
                        if !snapshot.alerts.isEmpty { alertsSection }
                        networkCard.settleOnScroll()
                        nodesSection
                        guestsSection
                        storageSection
                        activitySection
                    }
                })
            .proxynDestinations()
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        parts.append("\(snapshot.nodes.count) nœud\(snapshot.nodes.count > 1 ? "s" : "")")
        let guests = snapshot.guests.filter { !$0.isTemplate }.count
        parts.append("\(guests) instance\(guests > 1 ? "s" : "")")
        switch model.connection {
        case .connected:
            parts.append(Date().timeIntervalSince(snapshot.capturedAt) < 12
                         ? "en direct" : "màj \(Format.ago(snapshot.capturedAt))")
        case .connecting: parts.append("connexion…")
        case .needsTOTP: parts.append("2FA requise")
        case .failed: parts.append("hors ligne")
        case .idle: parts.append("inactif")
        }
        return parts.joined(separator: " · ")
    }

    private var statusColor: Color {
        switch model.connection {
        case .connected: return Palette.mint
        case .connecting: return Palette.amber
        default: return Palette.rose
        }
    }

    // MARK: Vitals

    /// The hero. A headline figure with its own trace, then the three ratios as
    /// stacked bars — a bar states a ratio more precisely than an arc and
    /// leaves room for the actual numbers beside it.
    private var vitalsCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Charge du cluster")
                            .font(.system(size: 13.5))
                            .foregroundStyle(Palette.inkTertiary)
                        MetricText(value: Format.percent(snapshot.aggregateCPU), unit: "%",
                                   size: 40, weight: .medium)
                            .animation(Motion.meter, value: snapshot.aggregateCPU)
                    }
                    Spacer(minLength: 12)
                    if model.history.cpu.count > 2 {
                        Sparkline(values: model.history.cpu, tint: Palette.ember, filled: true)
                            .frame(width: 130, height: 46)
                            .padding(.top, 10)
                    }
                }

                Divider1px()

                VStack(spacing: 18) {
                    VitalRow(label: "Processeur",
                             value: Format.percent(snapshot.aggregateCPU), unit: "%",
                             fraction: snapshot.aggregateCPU,
                             leadingDetail: "\(Int(snapshot.totalCores)) cœurs",
                             trailingDetail: model.history.cpu.isEmpty
                                ? nil : "pic \(Format.percent(model.history.cpu.max() ?? 0))",
                             tint: Palette.ember)

                    VitalRow(label: "Mémoire",
                             value: Format.bytesParts(snapshot.memoryUsed).value,
                             unit: Format.bytesParts(snapshot.memoryUsed).unit,
                             fraction: snapshot.aggregateMemory,
                             leadingDetail: "sur \(Format.bytes(snapshot.memoryTotal))",
                             trailingDetail: Format.percent(snapshot.aggregateMemory))

                    VitalRow(label: "Stockage",
                             value: Format.bytesParts(snapshot.storageUsed).value,
                             unit: Format.bytesParts(snapshot.storageUsed).unit,
                             fraction: snapshot.aggregateStorage,
                             leadingDetail: "\(Format.bytes(snapshot.storageTotal - snapshot.storageUsed)) libres",
                             trailingDetail: Format.percent(snapshot.aggregateStorage))
                }

                Divider1px()

                HStack(spacing: 0) {
                    HeroStat(value: "\(snapshot.onlineNodes.count)/\(max(snapshot.nodes.count, 1))",
                             label: "nœuds",
                             tint: snapshot.offlineNodes.isEmpty ? Palette.ink : Palette.rose)
                    HeroStat(value: "\(snapshot.runningGuests.count)", label: "actives")
                    HeroStat(value: "\(snapshot.stoppedGuests.count)", label: "arrêtées",
                             tint: Palette.inkSecondary)
                    HeroStat(value: "\(snapshot.runningTasks.count)", label: "tâches",
                             tint: snapshot.runningTasks.isEmpty ? Palette.inkSecondary : Palette.ember)
                }
            }
        }
    }

    // MARK: Alerts

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Alertes", trailing: "\(snapshot.alerts.count)")
            ForEach(snapshot.alerts.sorted { $0.level > $1.level }.prefix(4)) { alert in
                AlertCard(alert: alert).settleOnScroll()
            }
        }
    }

    // MARK: Network

    private var networkCard: some View {
        let inRate = model.history.netIn.last ?? 0
        let outRate = model.history.netOut.last ?? 0
        let peak = max(model.history.netIn.max() ?? 1, model.history.netOut.max() ?? 1)

        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel("Réseau")
                    Spacer(minLength: 8)
                    HStack(spacing: 14) {
                        ThroughputLabel(symbol: "arrow.down", value: Format.bytes(inRate) + "/s",
                                        tint: Palette.ember)
                        ThroughputLabel(symbol: "arrow.up", value: Format.bytes(outRate) + "/s",
                                        tint: Palette.sky)
                    }
                }

                ZStack {
                    Sparkline(values: model.history.netIn, tint: Palette.ember,
                              filled: true, referenceMax: peak)
                    Sparkline(values: model.history.netOut, tint: Palette.sky,
                              referenceMax: peak)
                }
                .frame(height: 48)
            }
        }
    }

    // MARK: Nodes

    private var nodesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Nœuds", trailing: snapshot.isQuorate ? nil : "quorum perdu")
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(snapshot.nodes) { node in
                        NavigationLink(value: Route.node(node.displayName)) {
                            NodeMiniCard(node: node, history: model.history(forNode: node.displayName).cpu)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    // MARK: Guests

    private var guestsSection: some View {
        let favorites = snapshot.guests.filter { model.isFavorite($0) }
        let busiest = snapshot.runningGuests
            .sorted { $0.cpuFraction > $1.cpuFraction }
            .prefix(favorites.isEmpty ? 5 : 3)
        let shown = Array((favorites + busiest.filter { g in
            !favorites.contains(where: { $0.id == g.id })
        }).prefix(6))

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(favorites.isEmpty ? "Instances les plus actives" : "Épinglées & actives")
                Spacer()
                NavigationLink(value: Route.allGuests) {
                    Text("Tout voir")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.ember)
                }
            }

            GlassCard(padding: 0) {
                if shown.isEmpty {
                    Text("Aucune instance en cours d'exécution.")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.inkTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 26)
                } else {
                    RowStack(data: shown, separatorInset: Metrics.rowInset + 18) { guest in
                        if let ref = GuestRef(resource: guest) {
                            NavigationLink(value: Route.guest(ref: ref, name: guest.displayName)) {
                                GuestRow(guest: guest, history: model.history(forGuest: guest.id).cpu)
                                    .padding(.horizontal, Metrics.rowInset)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }
            }
        }
    }

    // MARK: Storage

    private var storageSection: some View {
        let storages = Array(snapshot.uniqueStorages
            .sorted { $0.diskFraction > $1.diskFraction }
            .prefix(4))
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Stockage", trailing: Format.bytes(snapshot.storageTotal) + " au total")
            GlassCard(padding: 0) {
                RowStack(data: storages, separatorInset: Metrics.rowInset) { storage in
                    NavigationLink(value: Route.storage(node: storage.node ?? "",
                                                        storage: storage.storage ?? storage.displayName)) {
                        StorageRow(storage: storage)
                            .padding(.horizontal, Metrics.rowInset)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    // MARK: Activity

    private var activitySection: some View {
        let tasks = Array(snapshot.tasks.prefix(5))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Activité récente")
                Spacer()
                NavigationLink(value: Route.allTasks) {
                    Text("Journal")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.ember)
                }
            }
            GlassCard(padding: 0) {
                if tasks.isEmpty {
                    Text("Rien à signaler.")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.inkTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    RowStack(data: tasks, separatorInset: Metrics.rowInset + 26) { task in
                        NavigationLink(value: Route.task(node: task.node ?? "",
                                                         upid: task.upid,
                                                         title: Format.taskType(task.type))) {
                            TaskRow(task: task, compact: true)
                                .padding(.horizontal, Metrics.rowInset)
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
        }
    }

    private var loadingSkeleton: some View {
        VStack(spacing: 12) {
            SkeletonBlock(height: 300)
            SkeletonBlock(height: 110)
            SkeletonBlock(height: 170)
        }
    }
}

// MARK: - Pieces

struct ThroughputLabel: View {
    var symbol: String
    var value: String
    var tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.metric(13))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
        }
    }
}

struct AlertCard: View {
    var alert: ClusterAlert

    private var tint: Color {
        switch alert.level {
        case .critical: return Palette.rose
        case .warning: return Palette.amber
        case .info: return Palette.inkSecondary
        }
    }

    var body: some View {
        GlassCard(padding: 14, tint: tint) {
            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text(alert.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 8)
        }
    }
}
