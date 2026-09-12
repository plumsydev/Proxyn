import SwiftUI

struct NodeDetailView: View {
    @Environment(AppModel.self) private var app
    let node: String

    @State private var vm: NodeDetailModel
    @State private var section: NodeSection = .overview
    @State private var confirmPower: NodePowerIntent?
    @State private var showShell = false

    init(node: String) {
        self.node = node
        _vm = State(initialValue: NodeDetailModel(node: node))
    }

    enum NodeSection: Int, CaseIterable, Identifiable, Hashable {
        case overview, hardware, network, services, tasks
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .overview: return "Aperçu"
            case .hardware: return "Matériel"
            case .network: return "Réseau"
            case .services: return "Services"
            case .tasks: return "Tâches"
            }
        }
    }

    private var resource: PVEResource? {
        app.snapshot.nodes.first { $0.displayName == node }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard

                SegmentedRail(items: NodeSection.allCases, label: \.title, selection: $section)

                switch section {
                case .overview: overviewSection
                case .hardware: hardwareSection
                case .network: networkSection
                case .services: servicesSection
                case .tasks: tasksSection
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 92)
            .animation(Motion.snap, value: section)
        }
        .scrollIndicators(.hidden)
        .background(AuroraBackground(tint: Palette.ember, intensity: 0.55).ignoresSafeArea())
        .navigationTitle(node)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showShell = true } label: {
                        Label("Terminal du nœud", systemImage: "terminal.fill")
                    }
                    Divider()
                    Button { confirmPower = .startAll } label: {
                        Label("Démarrer toutes les instances", systemImage: "play.circle")
                    }
                    Button { confirmPower = .stopAll } label: {
                        Label("Arrêter toutes les instances", systemImage: "stop.circle")
                    }
                    Divider()
                    Button(role: .destructive) { confirmPower = .reboot } label: {
                        Label("Redémarrer le nœud", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) { confirmPower = .shutdown } label: {
                        Label("Éteindre le nœud", systemImage: "power")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.ember)
                }
            }
        }
        .refreshable { await vm.load(using: app.client()) }
        .task {
            await vm.load(using: app.client())
            vm.startLive(api: app.client(), interval: app.settings.liveRefreshInterval)
        }
        .onDisappear { vm.stopLive() }
        .sheet(isPresented: $showShell) {
            ConsoleView(target: .node(node), title: "Terminal · \(node)")
        }
        .alert(confirmPower?.title ?? "",
               isPresented: Binding(get: { confirmPower != nil },
                                    set: { if !$0 { confirmPower = nil } }),
               presenting: confirmPower) { intent in
            Button(intent.confirmLabel, role: .destructive) { run(intent) }
            Button("Annuler", role: .cancel) {}
        } message: { intent in
            Text(intent.message(node: node))
        }
    }

    // MARK: Header

    private var headerCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            StatusPip(color: Palette.state(resource?.state ?? .unknown),
                                      pulsing: resource?.state.isUp ?? false, size: 7,
                                      hollow: !(resource?.state.isUp ?? false))
                            Text(node)
                                .font(.system(size: 24, weight: .semibold))
                                .tracking(-0.5)
                                .foregroundStyle(Palette.ink)
                        }
                        if let status = vm.status {
                            Text("Proxmox VE \(Self.shortVersion(status.pveVersion)) · \(Format.uptimeLong(status.uptime))")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.inkTertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    if !vm.updates.isEmpty {
                        TagChip(text: "\(vm.updates.count) mises à jour", tint: Palette.amber)
                    }
                }

                if vm.metrics.count > 2 {
                    Sparkline(values: vm.metrics.compactMap { $0["cpu"] },
                              tint: Palette.ember, filled: true)
                        .frame(height: 38)
                }

                VStack(spacing: 16) {
                    VitalRow(label: "Processeur",
                             value: Format.percent(vm.status?.cpu ?? resource?.cpuFraction ?? 0),
                             unit: "%",
                             fraction: vm.status?.cpu ?? resource?.cpuFraction ?? 0,
                             leadingDetail: "\(vm.status?.cpuCount ?? Int(resource?.maxcpu ?? 0)) cœurs",
                             trailingDetail: vm.status.map {
                                "I/O wait " + Format.percent($0.ioWait ?? 0, decimals: 1) },
                             tint: Palette.ember, valueSize: 19)

                    VitalRow(label: "Mémoire",
                             value: Format.bytesParts(vm.status?.memUsed ?? resource?.mem).value,
                             unit: Format.bytesParts(vm.status?.memUsed ?? resource?.mem).unit,
                             fraction: memFraction,
                             leadingDetail: "sur \(Format.bytes(vm.status?.memTotal ?? resource?.maxmem))",
                             trailingDetail: Format.percent(memFraction),
                             valueSize: 19)

                    VitalRow(label: "Racine",
                             value: Format.bytesParts(vm.status?.rootUsed ?? resource?.disk).value,
                             unit: Format.bytesParts(vm.status?.rootUsed ?? resource?.disk).unit,
                             fraction: rootFraction,
                             leadingDetail: "sur \(Format.bytes(vm.status?.rootTotal ?? resource?.maxdisk))",
                             trailingDetail: Format.percent(rootFraction),
                             valueSize: 19)
                }

                if let load = vm.status?.loadAverage, load.count >= 3 {
                    Divider1px()
                    HStack(spacing: 0) {
                        HeroStat(value: String(format: "%.2f", load[0]), label: "charge 1 min",
                                 tint: loadTint(load[0]))
                        HeroStat(value: String(format: "%.2f", load[1]), label: "5 min",
                                 tint: Palette.inkSecondary)
                        HeroStat(value: String(format: "%.2f", load[2]), label: "15 min",
                                 tint: Palette.inkSecondary)
                        HeroStat(value: "\(vm.services.filter(\.isRunning).count)/\(max(vm.services.count, 1))",
                                 label: "services", tint: Palette.inkSecondary)
                    }
                }
            }
        }
    }

    /// `pve-manager/8.3.2/d4b9f1e2` → `8.3.2`
    static func shortVersion(_ raw: String?) -> String {
        guard let raw else { return "?" }
        let parts = raw.split(separator: "/")
        return parts.count > 1 ? String(parts[1]) : raw
    }

    private var memFraction: Double {
        guard let total = vm.status?.memTotal, total > 0 else { return resource?.memFraction ?? 0 }
        return (vm.status?.memUsed ?? 0) / total
    }

    private var rootFraction: Double {
        guard let total = vm.status?.rootTotal, total > 0 else { return resource?.diskFraction ?? 0 }
        return (vm.status?.rootUsed ?? 0) / total
    }

    private func loadTint(_ value: Double) -> Color {
        let cores = Double(vm.status?.cpuCount ?? 1)
        return Palette.load(cores > 0 ? value / cores : 0)
    }

    // MARK: Sections

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            timeframePicker

            ChartCard(title: "Processeur", series: vm.cpuSeries, timeframe: vm.timeframe, normalized: true)
            ChartCard(title: "Mémoire", series: vm.memorySeries, timeframe: vm.timeframe)
            ChartCard(title: "Réseau", series: vm.networkSeries, timeframe: vm.timeframe)
            ChartCard(title: "Charge système", series: vm.loadSeries, timeframe: vm.timeframe)

            if !vm.storages.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Stockage sur ce nœud", trailing: "\(vm.storages.count)")
                    GlassCard(padding: 0) {
                        RowStack(data: vm.storages, separatorInset: Metrics.rowInset) { storage in
                            NavigationLink(value: Route.storage(node: node, storage: storage.storage)) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        Text(storage.storage)
                                            .font(.rowTitle)
                                            .foregroundStyle(Palette.ink)
                                        if !storage.active { TagChip(text: "inactif", tint: Palette.rose) }
                                        Spacer(minLength: 8)
                                        Text("\(Format.bytes(storage.used)) / \(Format.bytes(storage.total))")
                                            .font(.metric(12.5))
                                            .foregroundStyle(Palette.inkSecondary)
                                    }
                                    MeterBar(fraction: storage.fraction)
                                }
                                .padding(.horizontal, Metrics.rowInset)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }
            }

            if !vm.updates.isEmpty { updatesCard }
        }
    }

    private var timeframePicker: some View {
        SegmentedRail(items: PVETimeframe.allCases, label: \.label,
                      selection: Binding(
                        get: { vm.timeframe },
                        set: { new in Task { await vm.changeTimeframe(new, api: app.client()) } }))
    }

    private var updatesCard: some View {
        GlassCard(tint: Palette.amber) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel("Mises à jour disponibles", trailing: "\(vm.updates.count)")
                    Spacer()
                    Button {
                        Task {
                            await app.perform("Actualiser les dépôts", node: node) { api in
                                try await api.refreshRepositories(node)
                            }
                            await vm.load(using: app.client())
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.ember)
                    }
                }
                .padding(.leading, 8)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(vm.updates.prefix(8)) { update in
                        HStack(spacing: 8) {
                            Text(update.package)
                                .font(.mono(12.5))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text("\(update.oldVersion ?? "") → \(update.version ?? "")")
                                .font(.mono(11.5))
                                .foregroundStyle(Palette.inkTertiary)
                                .lineLimit(1)
                        }
                    }
                    if vm.updates.count > 8 {
                        Text("+ \(vm.updates.count - 8) autres paquets")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.inkTertiary)
                    }
                    Text("L'installation se fait depuis le terminal du nœud (apt dist-upgrade).")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.inkTertiary)
                        .padding(.top, 4)
                }
                .padding(.leading, 8)
            }
        }
    }

    private var hardwareSection: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Système")
                    DetailRow(label: "Processeur", value: vm.status?.cpuModel ?? "—")
                    DetailRow(label: "Cœurs", value: "\(vm.status?.cpuCount ?? 0)")
                    DetailRow(label: "Noyau", value: vm.status?.kernelVersion ?? "—", monospaced: true)
                    DetailRow(label: "Proxmox VE", value: vm.status?.pveVersion ?? "—")
                    DetailRow(label: "Uptime", value: Format.uptimeLong(vm.status?.uptime))
                    Divider1px()
                    LabeledMeter(label: "Mémoire", fraction: memFraction,
                                 detail: "\(Format.bytes(vm.status?.memUsed)) / \(Format.bytes(vm.status?.memTotal))")
                    LabeledMeter(label: "Swap", fraction: swapFraction,
                                 detail: "\(Format.bytes(vm.status?.swapUsed)) / \(Format.bytes(vm.status?.swapTotal))",
                                 tint: Palette.violet)
                }
            }

            if !vm.disks.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    SectionLabel("Disques physiques", trailing: "\(vm.disks.count)")
                    ForEach(vm.disks) { disk in DiskCard(disk: disk) }
                }
            }
        }
    }

    private var swapFraction: Double {
        guard let total = vm.status?.swapTotal, total > 0 else { return 0 }
        return (vm.status?.swapUsed ?? 0) / total
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            ChartCard(title: "Trafic", series: vm.networkSeries, timeframe: vm.timeframe)

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Interfaces", trailing: "\(vm.interfaces.count)")
                GlassCard(padding: 0) {
                    RowStack(data: vm.interfaces.sorted { $0.iface < $1.iface },
                             separatorInset: Metrics.rowInset + 18) { iface in
                        HStack(alignment: .top, spacing: 11) {
                            StatusPip(color: iface.active ? Palette.mint : Palette.inkTertiary,
                                      size: 6, hollow: !iface.active)
                                .padding(.top, 3)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(iface.iface)
                                        .font(.mono(14, weight: .medium))
                                        .foregroundStyle(Palette.ink)
                                    TagChip(text: iface.type ?? "—")
                                    if iface.autostart { TagChip(text: "auto") }
                                }
                                if let cidr = iface.cidr ?? iface.address {
                                    Text(cidr + (iface.gateway.map { " → \($0)" } ?? ""))
                                        .font(.mono(12))
                                        .foregroundStyle(Palette.inkSecondary)
                                }
                                if let ports = iface.bridgePorts, !ports.isEmpty {
                                    Text("ports : \(ports)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Palette.inkTertiary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Metrics.rowInset)
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Services", trailing: "\(vm.runningServices) actifs sur \(vm.services.count)")
            GlassCard(padding: 0) {
                RowStack(data: vm.services, separatorInset: Metrics.rowInset + 18) { service in
                    HStack(spacing: 11) {
                        StatusPip(color: service.isRunning ? Palette.mint : Palette.inkTertiary,
                                  size: 6, hollow: !service.isRunning)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(service.name ?? service.service)
                                .font(.system(size: 14.5))
                                .foregroundStyle(Palette.ink)
                            Text(service.desc ?? service.service)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.inkTertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)

                        if vm.busyService == service.service {
                            ProgressView().controlSize(.small).tint(Palette.inkSecondary)
                        } else {
                            Menu {
                                Button { serviceAction(service, "start") } label: {
                                    Label("Démarrer", systemImage: "play")
                                }
                                Button { serviceAction(service, "restart") } label: {
                                    Label("Redémarrer", systemImage: "arrow.clockwise")
                                }
                                Button(role: .destructive) { serviceAction(service, "stop") } label: {
                                    Label("Arrêter", systemImage: "stop")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Palette.inkTertiary)
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                        }
                    }
                    .padding(.horizontal, Metrics.rowInset)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Tâches du nœud", trailing: "\(vm.tasks.count)")
            GlassCard(padding: 0) {
                if vm.tasks.isEmpty {
                    Text("Aucune tâche enregistrée.")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.inkTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 26)
                } else {
                    RowStack(data: vm.tasks, separatorInset: Metrics.rowInset + 26) { task in
                        NavigationLink(value: Route.task(node: node, upid: task.upid,
                                                         title: Format.taskType(task.type))) {
                            TaskRow(task: task).padding(.horizontal, Metrics.rowInset)
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func serviceAction(_ service: PVEService, _ command: String) {
        vm.busyService = service.service
        Task {
            await app.perform("\(command.capitalized) \(service.service)", node: node) { api in
                try await api.serviceCommand(node, service: service.service, command: command)
            }
            await vm.load(using: app.client())
            vm.busyService = nil
        }
    }

    private func run(_ intent: NodePowerIntent) {
        Task {
            switch intent {
            case .reboot:
                await app.perform("Redémarrage de \(node)", node: node) { api in
                    try await api.nodePower(node, command: "reboot")
                }
            case .shutdown:
                await app.perform("Extinction de \(node)", node: node) { api in
                    try await api.nodePower(node, command: "shutdown")
                }
            case .startAll:
                await app.perform("Démarrage groupé", node: node) { api in
                    try await api.startAllGuests(node)
                }
            case .stopAll:
                await app.perform("Arrêt groupé", node: node) { api in
                    try await api.stopAllGuests(node)
                }
            }
        }
    }
}

enum NodePowerIntent: Identifiable {
    case reboot, shutdown, startAll, stopAll
    var id: Int {
        switch self {
        case .reboot: return 0
        case .shutdown: return 1
        case .startAll: return 2
        case .stopAll: return 3
        }
    }
    var title: String {
        switch self {
        case .reboot: return "Redémarrer le nœud ?"
        case .shutdown: return "Éteindre le nœud ?"
        case .startAll: return "Démarrer toutes les instances ?"
        case .stopAll: return "Arrêter toutes les instances ?"
        }
    }
    var confirmLabel: String {
        switch self {
        case .reboot: return "Redémarrer"
        case .shutdown: return "Éteindre"
        case .startAll: return "Démarrer"
        case .stopAll: return "Arrêter"
        }
    }
    func message(node: String) -> String {
        switch self {
        case .reboot:
            return "Toutes les VM et conteneurs de \(node) seront interrompus le temps du redémarrage."
        case .shutdown:
            return "\(node) sera éteint. Vous devrez le rallumer physiquement ou via IPMI/Wake-on-LAN."
        case .startAll:
            return "Proxmox démarrera les instances configurées en autostart sur \(node)."
        case .stopAll:
            return "Toutes les instances de \(node) recevront une demande d'arrêt."
        }
    }
}

/// Physical disk card with SMART state.
struct DiskCard: View {
    var disk: PVEDisk

    private var healthColor: Color {
        switch (disk.health ?? "").uppercased() {
        case "PASSED", "OK": return Palette.mint
        case "": return Palette.inkTertiary
        default: return Palette.amber
        }
    }

    private var isSolidState: Bool {
        let type = (disk.type ?? "").lowercased()
        return type.contains("ssd") || type.contains("nvme")
    }

    var body: some View {
        GlassCard(padding: 15) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    StatusPip(color: healthColor, size: 6,
                              hollow: (disk.health ?? "").uppercased() != "PASSED")
                    Text(disk.devpath)
                        .font(.mono(14, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    Text(disk.health ?? "—")
                        .font(.system(size: 12))
                        .foregroundStyle(healthColor)
                }

                Text([disk.vendor, disk.model].compactMap { $0 }.joined(separator: " "))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.inkTertiary)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    MiniFact(label: "Taille", value: Format.bytes(disk.size))
                    MiniFact(label: "Type", value: isSolidState ? (disk.type ?? "ssd") : "hdd")
                    MiniFact(label: "Usage", value: disk.used ?? "libre")
                    if let wear = disk.wearout, wear >= 0, wear <= 100 {
                        MiniFact(label: "Usure", value: "\(Int(100 - wear)) %")
                    }
                }
            }
        }
    }
}
