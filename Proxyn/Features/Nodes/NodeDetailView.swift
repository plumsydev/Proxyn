import SwiftUI

struct NodeDetailView: View {
    @Environment(AppModel.self) private var app
    let node: String

    @State private var vm: NodeDetailModel
    @State private var page: Page = .summary
    @State private var pendingIntent: NodePowerIntent?
    @State private var showShell = false

    init(node: String) {
        self.node = node
        _vm = State(initialValue: NodeDetailModel(node: node))
    }

    enum Page: String, CaseIterable, Identifiable {
        case summary = "Summary", charts = "Charts", system = "System", tasks = "Tasks"
        var id: String { rawValue }
    }

    private var resource: PVEResource? {
        app.snapshot.nodes.first { $0.displayName == node }
    }

    var body: some View {
        List {
            if let error = vm.error {
                Section {
                    InlineErrorRow(message: error) { Task { await vm.load(using: app.client()) } }
                }
            }

            Section {
                Picker("Section", selection: $page) {
                    ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            switch page {
            case .summary: summary
            case .charts: charts
            case .system: system
            case .tasks: tasks
            }
        }
        .proxynList()
        .navigationTitle(node)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { actionsMenu }
        }
        .refreshable { await vm.load(using: app.client()) }
        .task {
            await vm.load(using: app.client())
            vm.startLive(api: app.client(), interval: app.settings.refreshInterval)
        }
        .onDisappear { vm.stopLive() }
        .sheet(isPresented: $showShell) {
            ConsoleView(target: .node(node), title: "Shell — \(node)")
        }
        .confirmationDialog(pendingIntent?.title ?? "",
                            isPresented: Binding(get: { pendingIntent != nil },
                                                 set: { if !$0 { pendingIntent = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingIntent) { intent in
            Button(intent.confirmLabel, role: intent.isDestructive ? .destructive : nil) { run(intent) }
        } message: { intent in
            Text(intent.message(node: node))
        }
    }

    // MARK: Toolbar

    private var actionsMenu: some View {
        Menu {
            Button("Open Shell", systemImage: "apple.terminal") { showShell = true }
            Divider()
            Button("Start All Guests", systemImage: "play") { pendingIntent = .startAll }
            Button("Stop All Guests", systemImage: "stop") { pendingIntent = .stopAll }
            Divider()
            Button("Reboot Node", systemImage: "arrow.clockwise", role: .destructive) { pendingIntent = .reboot }
            Button("Shut Down Node", systemImage: "power", role: .destructive) { pendingIntent = .shutdown }
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
    }

    // MARK: Summary

    @ViewBuilder
    private var summary: some View {
        Section {
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    StatusDot(state: resource?.state ?? .unknown)
                    Text(resource?.state.label ?? "—")
                }
            }
            LabeledContent("Uptime", value: Format.uptimeLong(vm.status?.uptime ?? resource?.uptime))
            LabeledContent("Proxmox VE", value: Format.pveVersion(vm.status?.pveVersion))
        }

        Section("Usage") {
            UsageRow(title: "CPU",
                     value: Format.percent(cpuFraction),
                     detail: "\(vm.status?.cpuCount ?? Int(resource?.maxcpu ?? 0)) cores",
                     fraction: cpuFraction, tint: Palette.accent)
            UsageRow(title: "Memory",
                     value: Format.bytes(vm.status?.memUsed ?? resource?.mem),
                     detail: "of \(Format.bytes(vm.status?.memTotal ?? resource?.maxmem))",
                     fraction: fraction(vm.status?.memUsed, of: vm.status?.memTotal) ?? resource?.memFraction ?? 0)
            if let total = vm.status?.swapTotal, total > 0 {
                UsageRow(title: "Swap",
                         value: Format.bytes(vm.status?.swapUsed),
                         detail: "of \(Format.bytes(total))",
                         fraction: fraction(vm.status?.swapUsed, of: total) ?? 0)
            }
            UsageRow(title: "Root disk",
                     value: Format.bytes(vm.status?.rootUsed ?? resource?.disk),
                     detail: "of \(Format.bytes(vm.status?.rootTotal ?? resource?.maxdisk))",
                     fraction: fraction(vm.status?.rootUsed, of: vm.status?.rootTotal) ?? resource?.diskFraction ?? 0)
            if let load = vm.status?.loadAverage, load.count >= 3 {
                LabeledContent("Load average") {
                    Text(load.prefix(3).map { Format.number($0, fractionDigits: 2) }.joined(separator: "  "))
                        .monospacedDigit()
                }
            }
            if let wait = vm.status?.ioWait {
                LabeledContent("IO delay", value: Format.percent(wait, decimals: 1))
            }
        }

        if !vm.updates.isEmpty {
            Section {
                ForEach(vm.updates.prefix(10)) { update in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(update.package)
                            .font(.identifier)
                        Text("\(update.oldVersion ?? "?") → \(update.version ?? "?")")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                if vm.updates.count > 10 {
                    Text("\(vm.updates.count - 10) more")
                        .foregroundStyle(.secondary)
                }
                Button("Refresh Package Lists") {
                    Task {
                        await app.perform("Refresh package lists", node: node) { api in
                            try await api.refreshRepositories(node)
                        }
                        await vm.load(using: app.client())
                    }
                }
            } header: {
                Text("\(vm.updates.count) Updates Available")
            } footer: {
                Text("Install updates from the node's shell with apt dist-upgrade.")
            }
        }

        if !vm.storages.isEmpty {
            Section("Storage") {
                ForEach(vm.storages) { storage in
                    NavigationLink(value: Route.storage(node: node, storage: storage.storage)) {
                        NodeStorageRow(storage: storage)
                    }
                }
            }
        }
    }

    private var cpuFraction: Double { vm.status?.cpu ?? resource?.cpuFraction ?? 0 }

    private func fraction(_ used: Double?, of total: Double?) -> Double? {
        guard let used, let total, total > 0 else { return nil }
        return used / total
    }

    // MARK: Charts

    @ViewBuilder
    private var charts: some View {
        Section {
            Picker("Range", selection: Binding(
                get: { vm.timeframe },
                set: { new in Task { await vm.changeTimeframe(new, api: app.client()) } })) {
                ForEach(PVETimeframe.allCases) { frame in
                    Text(frame.label).tag(frame).accessibilityLabel(frame.accessibilityName)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }

        Section("CPU") {
            MetricChart(series: vm.cpuSeries, timeframe: vm.timeframe, normalized: true)
                .padding(.vertical, 6)
        }
        Section("Memory") {
            MetricChart(series: vm.memorySeries, timeframe: vm.timeframe)
                .padding(.vertical, 6)
        }
        Section("Network") {
            MetricChart(series: vm.networkSeries, timeframe: vm.timeframe)
                .padding(.vertical, 6)
        }
        Section("Load") {
            MetricChart(series: vm.loadSeries, timeframe: vm.timeframe)
                .padding(.vertical, 6)
        }
    }

    // MARK: System

    @ViewBuilder
    private var system: some View {
        Section("Hardware") {
            LabeledContent("CPU") {
                Text(vm.status?.cpuModel ?? "—")
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Cores", value: vm.status?.cpuCount.map(String.init) ?? "—")
            LabeledContent("Memory", value: Format.bytes(vm.status?.memTotal))
            LabeledContent("Kernel") {
                Text(vm.status?.kernelVersion ?? "—")
                    .font(.caption.monospaced())
                    .multilineTextAlignment(.trailing)
            }
        }

        if !vm.disks.isEmpty {
            Section("Disks") {
                ForEach(vm.disks) { DiskRow(disk: $0) }
            }
        }

        if !vm.interfaces.isEmpty {
            Section("Network Interfaces") {
                ForEach(vm.interfaces.sorted { $0.iface < $1.iface }) { InterfaceRow(interface: $0) }
            }
        }

        if !vm.services.isEmpty {
            Section {
                ForEach(vm.services) { service in
                    ServiceRow(service: service, busy: vm.busyService == service.service)
                        .contextMenu { serviceActions(service) }
                        .swipeActions(edge: .trailing) {
                            Button("Restart", systemImage: "arrow.clockwise") {
                                serviceAction(service, "restart")
                            }
                            .tint(Palette.accent)
                        }
                }
            } header: {
                Text("Services")
            } footer: {
                Text("\(vm.runningServices) of \(vm.services.count) running. Swipe or touch and hold a service to control it.")
            }
        }
    }

    @ViewBuilder
    private func serviceActions(_ service: PVEService) -> some View {
        Button("Start", systemImage: "play") { serviceAction(service, "start") }
        Button("Restart", systemImage: "arrow.clockwise") { serviceAction(service, "restart") }
        Button("Stop", systemImage: "stop", role: .destructive) { serviceAction(service, "stop") }
    }

    // MARK: Tasks

    @ViewBuilder
    private var tasks: some View {
        Section {
            if vm.tasks.isEmpty {
                Text("No recent tasks on this node.")
                    .foregroundStyle(.secondary)
            }
            ForEach(vm.tasks) { task in
                NavigationLink(value: Route.task(node: node, upid: task.upid, title: Format.taskType(task.type))) {
                    TaskRow(task: task)
                }
            }
        }
    }

    // MARK: Actions

    private func serviceAction(_ service: PVEService, _ command: String) {
        vm.busyService = service.service
        Task {
            await app.perform("\(command.capitalized) \(service.name ?? service.service)", node: node) { api in
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
                await app.perform("Reboot \(node)", node: node) { api in
                    try await api.nodePower(node, command: "reboot")
                }
            case .shutdown:
                await app.perform("Shut down \(node)", node: node) { api in
                    try await api.nodePower(node, command: "shutdown")
                }
            case .startAll:
                await app.perform("Start all guests on \(node)", node: node) { api in
                    try await api.startAllGuests(node)
                }
            case .stopAll:
                await app.perform("Stop all guests on \(node)", node: node) { api in
                    try await api.stopAllGuests(node)
                }
            }
        }
    }
}

enum NodePowerIntent: Identifiable {
    case reboot, shutdown, startAll, stopAll

    var id: String { title }

    var isDestructive: Bool { self != .startAll }

    var title: String {
        switch self {
        case .reboot: return "Reboot this node?"
        case .shutdown: return "Shut down this node?"
        case .startAll: return "Start all guests?"
        case .stopAll: return "Stop all guests?"
        }
    }

    var confirmLabel: String {
        switch self {
        case .reboot: return "Reboot"
        case .shutdown: return "Shut Down"
        case .startAll: return "Start All"
        case .stopAll: return "Stop All"
        }
    }

    func message(node: String) -> String {
        switch self {
        case .reboot:
            return "Every guest on \(node) will be interrupted while it restarts."
        case .shutdown:
            return "\(node) will power off. You'll need physical access, IPMI or Wake-on-LAN to turn it back on."
        case .startAll:
            return "Guests on \(node) configured to start at boot will be started."
        case .stopAll:
            return "Every guest on \(node) will be sent a shutdown request."
        }
    }
}

// MARK: - Rows

private struct NodeStorageRow: View {
    var storage: PVEStorage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(storage.storage)
                    .lineLimit(1)
                if !storage.active {
                    Text("Inactive")
                        .font(.caption)
                        .foregroundStyle(Palette.critical)
                }
                Spacer(minLength: 8)
                Text(Format.percent(storage.fraction))
                    .font(.metricBody)
                    .fixedSize()
            }
            CapacityBar(fraction: storage.fraction)
            Text("\(Format.bytes(storage.used)) of \(Format.bytes(storage.total))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct DiskRow: View {
    var disk: PVEDisk

    private var healthy: Bool {
        ["PASSED", "OK"].contains((disk.health ?? "").uppercased())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(disk.devpath)
                    .font(.identifier)
                Spacer(minLength: 8)
                if let health = disk.health {
                    Label(health.capitalized, systemImage: healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(healthy ? Palette.positive : Palette.warning)
                        .labelStyle(.titleAndIcon)
                }
            }
            Text([disk.model, Format.bytes(disk.size), disk.type?.uppercased()]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let wear = disk.wearout, wear >= 0, wear <= 100 {
                Text("\(Int(100 - wear))% wear")
                    .font(.subheadline)
                    .foregroundStyle(wear < 20 ? Palette.warning : .secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct InterfaceRow: View {
    var interface: PVENetworkInterface

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                StatusDot(state: interface.active ? .online : .offline, size: 7)
                Text(interface.iface)
                    .font(.identifier)
                Text(interface.type ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let address = interface.cidr ?? interface.address {
                Text(address + (interface.gateway.map { "  via \($0)" } ?? ""))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let ports = interface.bridgePorts, !ports.isEmpty {
                Text("Ports: \(ports)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ServiceRow: View {
    var service: PVEService
    var busy: Bool

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(state: service.isRunning ? .running : .stopped, size: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name ?? service.service)
                if let description = service.desc {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if busy { ProgressView().controlSize(.small) }
        }
    }
}
