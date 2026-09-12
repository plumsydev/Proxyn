import SwiftUI

struct GuestDetailView: View {
    @Environment(AppModel.self) private var app
    let ref: GuestRef
    let name: String

    @State private var vm: GuestDetailModel
    @State private var page: Page = .summary
    @State private var sheet: GuestSheet?
    @State private var pendingPower: PendingPowerAction?
    @State private var pendingRestorePoint: RestorePointAction?
    @State private var pendingLifecycle: LifecycleAction?

    init(ref: GuestRef, name: String) {
        self.ref = ref
        self.name = name
        _vm = State(initialValue: GuestDetailModel(ref: ref))
    }

    enum Page: String, CaseIterable, Identifiable {
        case summary = "Summary", charts = "Charts", hardware = "Hardware", backups = "Backups"
        var id: String { rawValue }
    }

    private var resource: PVEResource? {
        app.snapshot.guests.first { $0.vmid == ref.vmid && $0.node == ref.node }
    }

    private var displayName: String { vm.status?.name ?? resource?.displayName ?? name }
    private var state: PVERunState { vm.status?.state ?? resource?.state ?? .unknown }
    private var isRunning: Bool { state.isUp }

    var body: some View {
        List {
            if let error = vm.error {
                Section {
                    InlineErrorRow(message: error) { Task { await reload() } }
                }
            }

            Section { header }

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
            case .hardware: hardware
            case .backups: restorePoints
            }
        }
        .proxynList()
        .navigationTitle(displayName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { actionsMenu }
        }
        .refreshable { await reload() }
        .task {
            await vm.load(using: app.client())
            await vm.loadBackups(using: app.client(), storages: app.snapshot.storages)
            vm.startLive(api: app.client(), interval: app.settings.refreshInterval)
        }
        .onDisappear { vm.stopLive() }
        .sheet(item: $sheet) { guestSheet($0) }
        .powerConfirmation($pendingPower)
        .restorePointConfirmation($pendingRestorePoint, ref: ref, onDone: { await reload() })
        .confirmationDialog(pendingLifecycle?.title ?? "",
                            isPresented: Binding(get: { pendingLifecycle != nil },
                                                 set: { if !$0 { pendingLifecycle = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingLifecycle) { action in
            Button(action.confirmLabel, role: .destructive) { run(action) }
        } message: { action in
            Text(action.message(vmid: ref.vmid))
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    StatusDot(state: state)
                    Text(state.label)
                        .font(.subheadline.weight(.medium))
                    if vm.isLocked {
                        Label("Locked", systemImage: "lock.fill")
                            .font(.subheadline)
                            .foregroundStyle(Palette.warning)
                    }
                }
                Text(identityLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !vm.tags.isEmpty {
                TagList(tags: vm.tags)
            }

            HStack(spacing: 8) { actionButtons }
                .disabled(vm.isLocked)
        }
        .padding(.vertical, 6)
    }

    private var identityLine: String {
        var line = "\(ref.kind.label) \(ref.vmid) on \(ref.node)"
        if isRunning, let uptime = vm.status?.uptime, uptime > 0 {
            line += " · up \(Format.uptime(uptime))"
        }
        return line
    }

    @ViewBuilder
    private var actionButtons: some View {
        if isRunning {
            Button("Shut Down", systemImage: "power") { request(.shutdown) }
                .buttonStyle(ActionTileStyle())
            Button("Reboot", systemImage: "arrow.clockwise") { request(.reboot) }
                .buttonStyle(ActionTileStyle())
            Button("Console", systemImage: "apple.terminal") { sheet = .console }
                .buttonStyle(ActionTileStyle())
        } else if state.isPaused {
            Button("Resume", systemImage: "playpause.fill") { request(.resume) }
                .buttonStyle(ActionTileStyle(prominent: true))
            Button("Force Stop", systemImage: "stop.fill") { request(.stop) }
                .buttonStyle(ActionTileStyle())
        } else if resource?.isTemplate != true {
            Button("Start", systemImage: "play.fill") { request(.start) }
                .buttonStyle(ActionTileStyle(prominent: true))
            Button("Clone", systemImage: "plus.square.on.square") { sheet = .clone }
                .buttonStyle(ActionTileStyle())
            Button("Back Up", systemImage: "externaldrive.badge.timemachine") { sheet = .backup }
                .buttonStyle(ActionTileStyle())
        } else {
            Button("Clone", systemImage: "plus.square.on.square") { sheet = .clone }
                .buttonStyle(ActionTileStyle(prominent: true))
        }
    }

    // MARK: Toolbar

    private var actionsMenu: some View {
        Menu {
            Section {
                Button("Take Snapshot…", systemImage: "camera") { sheet = .snapshot }
                Button("Back Up Now…", systemImage: "externaldrive.badge.timemachine") { sheet = .backup }
                Button("Clone…", systemImage: "plus.square.on.square") { sheet = .clone }
                Button("Migrate…", systemImage: "arrow.left.arrow.right") { sheet = .migrate }
            }

            Section {
                ForEach(GuestPowerAction.allCases.filter {
                    [.suspend, .stop, .reset].contains($0) && $0.isAvailable(for: state, kind: ref.kind)
                }) { action in
                    Button(action.label, systemImage: action.symbol,
                           role: action.isDestructive ? .destructive : nil) {
                        request(action)
                    }
                }
            }

            Section {
                if let resource {
                    Button(app.isFavorite(resource) ? "Unpin" : "Pin",
                           systemImage: app.isFavorite(resource) ? "pin.slash" : "pin") {
                        app.toggleFavorite(resource)
                    }
                }
            }

            Section {
                if resource?.isTemplate != true {
                    Button("Convert to Template…", systemImage: "doc.on.doc") {
                        pendingLifecycle = .template
                    }
                    .disabled(isRunning)
                }
                Button("Delete…", systemImage: "trash", role: .destructive) {
                    pendingLifecycle = .delete
                }
                .disabled(isRunning)
            }
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
    }

    // MARK: Summary

    @ViewBuilder
    private var summary: some View {
        if isRunning {
            Section("Usage") {
                UsageRow(title: "CPU",
                         value: Format.percent(vm.cpuFraction, decimals: 1),
                         detail: "of \(vm.cores) vCPU",
                         fraction: vm.cpuFraction, tint: Palette.accent)
                UsageRow(title: "Memory",
                         value: Format.bytes(vm.status?.mem),
                         detail: "of \(Format.bytes(vm.status?.maxmem))",
                         fraction: vm.memFraction)
                if (vm.status?.maxdisk ?? 0) > 0, (vm.status?.disk ?? 0) > 0 {
                    UsageRow(title: "Disk",
                             value: Format.bytes(vm.status?.disk),
                             detail: "of \(Format.bytes(vm.status?.maxdisk))",
                             fraction: vm.diskFraction)
                }
                LabeledContent("Network") {
                    Text("↓ \(Format.bytes(vm.status?.netin))  ↑ \(Format.bytes(vm.status?.netout))")
                        .monospacedDigit()
                }
                LabeledContent("Disk I/O") {
                    Text("\(Format.bytes(vm.status?.diskread)) read  \(Format.bytes(vm.status?.diskwrite)) written")
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                }
            }
        }

        if vm.agentOS != nil || !vm.agentInterfaces.isEmpty {
            Section {
                if let os = vm.agentOS {
                    LabeledContent("Operating system") {
                        Text(os).multilineTextAlignment(.trailing)
                    }
                }
                ForEach(vm.agentInterfaces) { interface in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(interface.name)
                            .font(.identifier)
                        ForEach(interface.addresses, id: \.self) { address in
                            Text(address)
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .contextMenu {
                        ForEach(interface.addresses, id: \.self) { address in
                            Button("Copy \(address)", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = address.components(separatedBy: "/").first
                            }
                        }
                    }
                }
            } header: {
                Text("Guest Agent")
            }
        }

        Section {
            Toggle("Start at Boot", isOn: configToggle(key: "onboot", current: vm.onBoot, title: "Start at boot"))
            Toggle("Protection", isOn: configToggle(key: "protection", current: vm.isProtected, title: "Protection"))
            Toggle("Firewall", isOn: Binding(
                get: { vm.firewallEnabled },
                set: { enabled in
                    vm.firewallEnabled = enabled
                    Task {
                        let ok = await app.perform(enabled ? "Enable firewall" : "Disable firewall",
                                                   node: ref.node) { api in
                            try await api.setGuestFirewall(ref, enabled: enabled)
                        }
                        if !ok { vm.firewallEnabled = !enabled }
                    }
                }))
        } header: {
            Text("Options")
        } footer: {
            Text("Protection prevents the guest and its disks from being deleted.")
        }

        if let notes = vm.description {
            Section("Notes") {
                Text(notes)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
        }
    }

    private func configToggle(key: String, current: Bool, title: String) -> Binding<Bool> {
        Binding(
            get: { current },
            set: { enabled in
                vm.config[key] = .number(enabled ? 1 : 0)
                Task {
                    let ok = await app.perform("\(title) \(enabled ? "on" : "off")", node: ref.node) { api in
                        try await api.updateGuestConfig(ref, values: [key: enabled ? "1" : "0"])
                    }
                    if !ok { vm.config[key] = .number(enabled ? 0 : 1) }
                }
            })
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
        Section("Disk I/O") {
            MetricChart(series: vm.diskSeries, timeframe: vm.timeframe)
                .padding(.vertical, 6)
        }
    }

    // MARK: Hardware

    @ViewBuilder
    private var hardware: some View {
        Section {
            LabeledContent("Cores", value: "\(vm.cores)")
            LabeledContent("Memory", value: Format.bytes(Double(vm.memoryMB) * 1_048_576))
            if let cpu = vm.config["cpu"]?.displayString {
                LabeledContent("CPU type", value: cpu)
            }
            LabeledContent("Operating system", value: vm.osName)
            if ref.kind == .qemu {
                if let bios = vm.config["bios"]?.displayString {
                    LabeledContent("Firmware", value: bios == "ovmf" ? "UEFI (OVMF)" : "BIOS (SeaBIOS)")
                }
                if let machine = vm.config["machine"]?.displayString {
                    LabeledContent("Machine", value: machine)
                }
            }
            Button("Edit CPU and Memory…") { sheet = .resources }
        } header: {
            Text("Resources")
        }

        if !vm.diskDevices.isEmpty {
            Section {
                ForEach(vm.diskDevices, id: \.key) { device in
                    ConfigValueRow(key: device.key, value: device.value)
                }
                Button("Resize Disk…") { sheet = .resize }
            } header: {
                Text("Disks")
            }
        }

        if !vm.netDevices.isEmpty {
            Section("Network Devices") {
                ForEach(vm.netDevices, id: \.key) { device in
                    ConfigValueRow(key: device.key, value: device.value)
                }
            }
        }

        if !vm.firewallRules.isEmpty {
            Section("Firewall Rules") {
                ForEach(vm.firewallRules) { FirewallRuleRow(rule: $0) }
            }
        }
    }

    // MARK: Snapshots & backups

    @ViewBuilder
    private var restorePoints: some View {
        Section {
            Button("Take Snapshot…", systemImage: "camera") { sheet = .snapshot }
            ForEach(vm.snapshots.sorted { ($0.snaptime ?? 0) > ($1.snaptime ?? 0) }) { snapshot in
                SnapshotRow(snapshot: snapshot)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash") {
                            pendingRestorePoint = .deleteSnapshot(snapshot)
                        }
                        .tint(Palette.critical)
                        Button("Roll Back", systemImage: "arrow.uturn.backward") {
                            pendingRestorePoint = .rollback(snapshot)
                        }
                        .tint(Palette.warning)
                    }
            }
        } header: {
            Text("Snapshots")
        } footer: {
            Text("Snapshots live on the same storage as the guest. They aren't a substitute for backups.")
        }

        Section {
            Button("Back Up Now…", systemImage: "externaldrive.badge.timemachine") { sheet = .backup }
            if vm.backups.isEmpty {
                Text("No backups found on storages attached to \(ref.node).")
                    .foregroundStyle(.secondary)
            }
            ForEach(vm.backups) { backup in
                BackupRow(backup: backup)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash") {
                            pendingRestorePoint = .deleteBackup(backup)
                        }
                        .tint(Palette.critical)
                        Button("Restore", systemImage: "arrow.uturn.backward") {
                            pendingRestorePoint = .restore(backup)
                        }
                        .tint(Palette.warning)
                    }
                    .contextMenu {
                        Button(backup.isProtected ? "Remove Protection" : "Protect",
                               systemImage: backup.isProtected ? "lock.open" : "lock") {
                            Task {
                                await app.perform(backup.isProtected ? "Remove protection" : "Protect backup",
                                                  node: ref.node) { api in
                                    try await api.setVolumeProtection(node: ref.node, volid: backup.volid,
                                                                      isProtected: !backup.isProtected)
                                }
                                await vm.loadBackups(using: app.client(), storages: app.snapshot.storages)
                            }
                        }
                        Button("Copy Volume ID", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = backup.volid
                        }
                    }
            }
        } header: {
            Text("Backups")
        }
    }

    // MARK: Sheets

    @ViewBuilder
    private func guestSheet(_ item: GuestSheet) -> some View {
        switch item {
        case .snapshot:
            SnapshotSheet(ref: ref) { await reload() }
        case .clone:
            CloneSheet(ref: ref, currentName: displayName)
        case .migrate:
            MigrateSheet(ref: ref)
        case .backup:
            BackupSheet(ref: ref) {
                await vm.loadBackups(using: app.client(), storages: app.snapshot.storages)
            }
        case .resources:
            EditResourcesSheet(ref: ref, cores: vm.cores, memoryMB: vm.memoryMB) { await reload() }
        case .resize:
            ResizeDiskSheet(ref: ref, disks: vm.diskDevices.map(\.key)) { await reload() }
        case .console:
            ConsoleView(target: .guest(ref), title: displayName)
        }
    }

    // MARK: Actions

    private func request(_ action: GuestPowerAction) {
        if app.settings.confirmDestructiveActions, action.requiresConfirmation {
            pendingPower = PendingPowerAction(ref: ref, action: action, name: displayName)
        } else {
            Task {
                await app.power(ref, action: action, name: displayName)
                await vm.load(using: app.client(), full: false)
            }
        }
    }

    private func run(_ action: LifecycleAction) {
        Task {
            switch action {
            case .template:
                await app.perform("Convert \(displayName) to template", node: ref.node) { api in
                    try await api.convertToTemplate(ref)
                }
                await reload()
            case .delete:
                await app.perform("Delete \(displayName)", node: ref.node) { api in
                    try await api.deleteGuest(ref, purge: true, destroyUnreferenced: true)
                }
            }
        }
    }

    private func reload() async {
        await vm.load(using: app.client())
        if page == .backups {
            await vm.loadBackups(using: app.client(), storages: app.snapshot.storages)
        }
        await app.refresh()
    }
}

enum GuestSheet: Int, Identifiable {
    case snapshot, clone, migrate, backup, resources, resize, console
    var id: Int { rawValue }
}

enum LifecycleAction: Identifiable {
    case template, delete
    var id: Int { self == .template ? 0 : 1 }

    var title: String { self == .template ? "Convert to template?" : "Delete this guest?" }
    var confirmLabel: String { self == .template ? "Convert" : "Delete" }

    func message(vmid: Int) -> String {
        switch self {
        case .template:
            return "Guest \(vmid) becomes a read-only template for cloning. This can't be undone."
        case .delete:
            return "Guest \(vmid) and its disks will be permanently destroyed."
        }
    }
}

// MARK: - Rows

private struct ConfigValueRow: View {
    var key: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key)
                .font(.identifier)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

private struct FirewallRuleRow: View {
    var rule: PVEFirewallRule

    private var summary: String {
        [rule.proto?.uppercased(), rule.dport.map { "port \($0)" }, rule.source.map { "from \($0)" }]
            .compactMap { $0 }.joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\((rule.type ?? "in").uppercased()) \(rule.action ?? "—")")
                    .font(.body.weight(.medium))
                    .foregroundStyle(rule.enable ? .primary : .secondary)
                if !rule.enable {
                    Text("Disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !summary.isEmpty {
                Text(summary)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let comment = rule.comment, !comment.isEmpty {
                Text(comment)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SnapshotRow: View {
    var snapshot: PVESnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(snapshot.name)
                if snapshot.vmstate {
                    Text("RAM")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Palette.fill, in: .rect(cornerRadius: 4))
                        .foregroundStyle(.secondary)
                }
            }
            Text([snapshot.description.flatMap { $0.isEmpty ? nil : $0 }, Format.dateTime(snapshot.date)]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

struct BackupRow: View {
    var backup: PVEStorageContent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(Format.dateTime(backup.date))
                if backup.isProtected {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Protected")
                }
                if let state = backup.verificationState, state.lowercased() != "ok" {
                    Text("Verification \(state)")
                        .font(.caption)
                        .foregroundStyle(Palette.critical)
                }
            }
            Text("\(Format.bytes(backup.size)) · \(backup.volid.components(separatedBy: ":").first ?? "")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Restore point confirmation

enum RestorePointAction: Identifiable {
    case rollback(PVESnapshot)
    case deleteSnapshot(PVESnapshot)
    case restore(PVEStorageContent)
    case deleteBackup(PVEStorageContent)

    var id: String {
        switch self {
        case .rollback(let s): return "rollback-\(s.name)"
        case .deleteSnapshot(let s): return "delete-\(s.name)"
        case .restore(let b): return "restore-\(b.volid)"
        case .deleteBackup(let b): return "delete-\(b.volid)"
        }
    }

    var title: String {
        switch self {
        case .rollback(let s): return "Roll back to “\(s.name)”?"
        case .deleteSnapshot(let s): return "Delete snapshot “\(s.name)”?"
        case .restore: return "Restore this backup?"
        case .deleteBackup: return "Delete this backup?"
        }
    }

    var message: String {
        switch self {
        case .rollback:
            return "The guest's current disks are replaced with the snapshot. Changes made since then are lost."
        case .deleteSnapshot:
            return "The snapshot is removed permanently."
        case .restore(let b):
            return "The guest is overwritten with the backup from \(Format.dateTime(b.date)). Its current data is lost."
        case .deleteBackup:
            return "The backup file is removed from storage permanently."
        }
    }

    var confirmLabel: String {
        switch self {
        case .rollback: return "Roll Back"
        case .restore: return "Restore"
        case .deleteSnapshot, .deleteBackup: return "Delete"
        }
    }
}

private struct RestorePointConfirmation: ViewModifier {
    @Environment(AppModel.self) private var app
    @Binding var pending: RestorePointAction?
    var ref: GuestRef
    var onDone: () async -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            pending?.title ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { action in
            Button(action.confirmLabel, role: .destructive) { run(action) }
        } message: { action in
            Text(action.message)
        }
    }

    private func run(_ action: RestorePointAction) {
        Task {
            switch action {
            case .rollback(let snapshot):
                await app.perform("Roll back to \(snapshot.name)", node: ref.node) { api in
                    try await api.rollbackSnapshot(ref, name: snapshot.name)
                }
            case .deleteSnapshot(let snapshot):
                await app.perform("Delete snapshot \(snapshot.name)", node: ref.node) { api in
                    try await api.deleteSnapshot(ref, name: snapshot.name)
                }
            case .restore(let backup):
                await app.perform("Restore \(ref.kind.label) \(ref.vmid)", node: ref.node) { api in
                    try await api.restoreBackup(node: ref.node, kind: ref.kind, vmid: ref.vmid,
                                                archive: backup.volid, storage: nil,
                                                force: true, startAfter: false)
                }
            case .deleteBackup(let backup):
                await app.perform("Delete backup", node: ref.node) { api in
                    try await api.deleteVolume(node: ref.node, volid: backup.volid)
                }
            }
            await onDone()
        }
    }
}

extension View {
    func restorePointConfirmation(_ pending: Binding<RestorePointAction?>, ref: GuestRef,
                                  onDone: @escaping () async -> Void) -> some View {
        modifier(RestorePointConfirmation(pending: pending, ref: ref, onDone: onDone))
    }
}
