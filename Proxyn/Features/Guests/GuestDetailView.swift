import SwiftUI

struct GuestDetailView: View {
    @Environment(AppModel.self) private var app
    let ref: GuestRef
    let name: String

    @State private var vm: GuestDetailModel
    @State private var section: GuestSection = .overview
    @State private var pendingAction: GuestPowerAction?
    @State private var busyAction: GuestPowerAction?
    @State private var sheet: GuestSheet?
    @State private var confirmDelete = false

    init(ref: GuestRef, name: String) {
        self.ref = ref
        self.name = name
        _vm = State(initialValue: GuestDetailModel(ref: ref))
    }

    enum GuestSection: Int, CaseIterable, Identifiable, Hashable {
        case overview, metrics, config, restore
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .overview: return "Aperçu"
            case .metrics: return "Métriques"
            case .config: return "Config"
            case .restore: return "Restauration"
            }
        }
    }

    private var resource: PVEResource? {
        app.snapshot.guests.first { $0.vmid == ref.vmid && $0.node == ref.node }
    }

    private var displayName: String {
        vm.status?.name ?? resource?.displayName ?? name
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                heroCard
                controlBar

                if vm.isLocked {
                    lockBanner
                }
                if let error = vm.error {
                    ErrorBanner(message: error, retry: { Task { await vm.load(using: app.client()) } })
                }

                SegmentedRail(items: GuestSection.allCases, label: \.title, selection: $section)

                switch section {
                case .overview: overviewSection
                case .metrics: metricsSection
                case .config: configSection
                case .restore: restoreSection
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 92)
            .animation(Motion.snap, value: section)
        }
        .scrollIndicators(.hidden)
        .background(AuroraBackground(tint: Palette.ember, intensity: 0.5).ignoresSafeArea())
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarMenu }
        .refreshable { await reload() }
        .task {
            await vm.load(using: app.client())
            await vm.loadBackups(using: app.client(), storages: app.snapshot.storages)
            vm.startLive(api: app.client(), interval: app.settings.liveRefreshInterval)
        }
        .onDisappear { vm.stopLive() }
        .sheet(item: $sheet) { item in
            guestSheet(item)
        }
        .alert("Confirmer l'action", isPresented: Binding(
            get: { pendingAction != nil },
            set: { if !$0 { pendingAction = nil } }),
               presenting: pendingAction) { action in
            Button(action.label, role: action.isDestructive ? .destructive : nil) {
                run(action)
            }
            Button("Annuler", role: .cancel) {}
        } message: { action in
            Text(action.confirmationMessage)
        }
        .alert("Supprimer \(displayName) ?", isPresented: $confirmDelete) {
            Button("Supprimer définitivement", role: .destructive) { deleteGuest() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("L'instance \(ref.vmid) et ses disques seront détruits. Cette action est irréversible.")
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    StatusPip(color: Palette.state(vm.state),
                              pulsing: vm.state.isUp, size: 8,
                              hollow: !vm.state.isUp && !vm.state.isPaused)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName)
                            .font(.system(size: 24, weight: .semibold))
                            .tracking(-0.5)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Text(identityLine)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.inkTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Button {
                        if let resource { app.toggleFavorite(resource) }
                    } label: {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 15))
                            .foregroundStyle(isPinned ? Palette.ember : Palette.inkTertiary)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }

                if !vm.tags.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(vm.tags, id: \.self) { TagChip(text: $0).fixedSize() }
                        Spacer(minLength: 0)
                    }
                }

                if vm.state.isUp {
                    if vm.metrics.count > 2 {
                        Sparkline(values: vm.metrics.compactMap { $0["cpu"] },
                                  tint: Palette.ember, filled: true)
                            .frame(height: 34)
                    }

                    VStack(spacing: 16) {
                        VitalRow(label: "Processeur",
                                 value: Format.percent(vm.cpuFraction, decimals: 1), unit: "%",
                                 fraction: vm.cpuFraction,
                                 leadingDetail: "\(vm.cores) vCPU",
                                 tint: Palette.ember, valueSize: 19)

                        VitalRow(label: "Mémoire",
                                 value: Format.bytesParts(vm.status?.mem).value,
                                 unit: Format.bytesParts(vm.status?.mem).unit,
                                 fraction: vm.memFraction,
                                 leadingDetail: "sur \(Format.bytes(vm.status?.maxmem))",
                                 trailingDetail: Format.percent(vm.memFraction),
                                 valueSize: 19)

                        if (vm.status?.maxdisk ?? 0) > 0 {
                            VitalRow(label: "Disque",
                                     value: Format.bytesParts(vm.status?.disk).value,
                                     unit: Format.bytesParts(vm.status?.disk).unit,
                                     fraction: vm.diskFraction,
                                     leadingDetail: "sur \(Format.bytes(vm.status?.maxdisk))",
                                     trailingDetail: Format.percent(vm.diskFraction),
                                     valueSize: 19)
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        HeroStat(value: "\(vm.cores)", label: "vCPU", tint: Palette.inkSecondary)
                        HeroStat(value: Format.bytes(vm.status?.maxmem), label: "mémoire",
                                 tint: Palette.inkSecondary)
                        HeroStat(value: Format.bytes(vm.status?.maxdisk), label: "disque",
                                 tint: Palette.inkSecondary)
                    }
                }
            }
        }
    }

    private var isPinned: Bool { resource.map { app.isFavorite($0) } ?? false }

    private var identityLine: String {
        var parts = ["\(ref.kind.label) \(ref.vmid)", ref.node]
        if vm.state.isUp, let uptime = vm.status?.uptime, uptime > 0 {
            parts.append("depuis \(Format.uptime(uptime))")
        } else {
            parts.append(vm.state.label.lowercased())
        }
        return parts.joined(separator: " · ")
    }

    private var lockBanner: some View {
        GlassCard(padding: 13, tint: Palette.amber) {
            Text("Instance verrouillée (\(vm.status?.lock ?? "")) — une opération est en cours côté Proxmox.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 8)
        }
    }

    // MARK: Control bar

    /// One contextual primary action, two direct secondaries, everything else
    /// behind an overflow. Seven equal buttons would make the user read them all
    /// every time.
    private var primaryAction: GuestPowerAction {
        if vm.state.isPaused { return .resume }
        return vm.state.isUp ? .shutdown : .start
    }

    private var overflowActions: [GuestPowerAction] {
        GuestPowerAction.allCases.filter {
            $0 != primaryAction && $0 != .reboot
                && $0.isAvailable(for: vm.state, kind: ref.kind)
        }
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            Button {
                trigger(primaryAction)
            } label: {
                HStack(spacing: 7) {
                    if busyAction == primaryAction {
                        ProgressView().controlSize(.small)
                            .tint(primaryAction == .start || primaryAction == .resume
                                  ? Color.black : Palette.ink)
                    } else {
                        Image(systemName: primaryAction.symbol)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(primaryAction.label)
                }
            }
            .buttonStyle(PrimaryGuestActionStyle(positive: primaryAction == .start
                                                 || primaryAction == .resume))
            .disabled(vm.isLocked)
            .opacity(vm.isLocked ? 0.5 : 1)

            IconButton(symbol: GuestPowerAction.reboot.symbol,
                       accessibilityName: "Redémarrer",
                       enabled: !vm.isLocked
                        && GuestPowerAction.reboot.isAvailable(for: vm.state, kind: ref.kind),
                       busy: busyAction == .reboot) {
                trigger(.reboot)
            }

            IconButton(symbol: "apple.terminal", tint: Palette.inkSecondary,
                       accessibilityName: "Console",
                       enabled: vm.state.isUp) {
                sheet = .console
            }

            Menu {
                ForEach(overflowActions) { action in
                    Button(role: action.isDestructive ? .destructive : nil) {
                        trigger(action)
                    } label: {
                        Label(action.label, systemImage: action.symbol)
                    }
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 11.5, style: .continuous)
                        .fill(Palette.surfaceHi)
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                }
                .frame(width: 40, height: 40)
            }
            .disabled(overflowActions.isEmpty || vm.isLocked)
        }
    }

    private func trigger(_ action: GuestPowerAction) {
        guard action.isAvailable(for: vm.state, kind: ref.kind), !vm.isLocked else { return }
        if app.settings.confirmDestructiveActions && !action.confirmationMessage.isEmpty {
            pendingAction = action
        } else {
            run(action)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { sheet = .snapshot } label: {
                    Label("Nouveau snapshot", systemImage: "camera.aperture")
                }
                Button { sheet = .backup } label: {
                    Label("Sauvegarder maintenant", systemImage: "externaldrive.badge.timemachine")
                }
                Divider()
                Button { sheet = .clone } label: {
                    Label("Cloner", systemImage: "doc.on.doc")
                }
                Button { sheet = .migrate } label: {
                    Label("Migrer", systemImage: "arrow.left.arrow.right")
                }
                Button { sheet = .resources } label: {
                    Label("Modifier CPU / RAM", systemImage: "slider.horizontal.3")
                }
                Button { sheet = .resize } label: {
                    Label("Agrandir un disque", systemImage: "externaldrive.badge.plus")
                }
                Divider()
                Button {
                    Task {
                        await app.perform("Conversion en modèle", node: ref.node) { api in
                            try await api.convertToTemplate(ref)
                        }
                        await reload()
                    }
                } label: {
                    Label("Convertir en modèle", systemImage: "doc.badge.gearshape")
                }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Supprimer l'instance", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.ember)
            }
        }
    }

    // MARK: Sections

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel("Trafic cumulé")
                    HStack(spacing: 0) {
                        HeroStat(value: Format.bytes(vm.status?.netin), label: "reçu")
                        HeroStat(value: Format.bytes(vm.status?.netout), label: "émis")
                        HeroStat(value: Format.bytes(vm.status?.diskread), label: "lu")
                        HeroStat(value: Format.bytes(vm.status?.diskwrite), label: "écrit")
                    }
                }
            }

            if !vm.agentInterfaces.isEmpty || vm.agentOS != nil {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("Agent invité")
                        if let os = vm.agentOS {
                            Text(os)
                                .font(.system(size: 14))
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        ForEach(vm.agentInterfaces) { iface in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(iface.name)
                                        .font(.mono(13, weight: .medium))
                                        .foregroundStyle(Palette.ink)
                                    if let mac = iface.mac {
                                        Text(mac)
                                            .font(.mono(11.5))
                                            .foregroundStyle(Palette.inkTertiary)
                                    }
                                }
                                ForEach(iface.addresses, id: \.self) { address in
                                    Text(address)
                                        .font(.mono(12.5))
                                        .foregroundStyle(Palette.inkSecondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                }
            }

            if let description = vm.description {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Notes")
                        Text(description)
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            SegmentedRail(items: PVETimeframe.allCases, label: \.label,
                          selection: Binding(
                            get: { vm.timeframe },
                            set: { new in Task { await vm.changeTimeframe(new, api: app.client()) } }))

            ChartCard(title: "Processeur", series: vm.cpuSeries, timeframe: vm.timeframe, normalized: true)
            ChartCard(title: "Mémoire", series: vm.memorySeries, timeframe: vm.timeframe)
            ChartCard(title: "Réseau", series: vm.networkSeries, timeframe: vm.timeframe)
            ChartCard(title: "Disque", series: vm.diskSeries, timeframe: vm.timeframe)
        }
    }

    private var configSection: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            GlassCard {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        SectionLabel("Ressources")
                        Spacer()
                        Button("Modifier") { sheet = .resources }
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.ember)
                    }
                    DetailRow(label: "vCPU", value: "\(vm.cores)")
                    DetailRow(label: "Mémoire", value: "\(vm.memoryMB) Mo")
                    if let cpuType = vm.config["cpu"]?.displayString {
                        DetailRow(label: "Type de CPU", value: cpuType)
                    }
                    DetailRow(label: "Système", value: vm.osType)
                    DetailRow(label: "Démarrage auto", value: vm.onBoot ? "Oui" : "Non",
                              valueColor: vm.onBoot ? Palette.mint : Palette.inkSecondary)
                    DetailRow(label: "Protection", value: vm.isProtected ? "Activée" : "Désactivée",
                              valueColor: vm.isProtected ? Palette.amber : Palette.inkSecondary)
                    if let boot = vm.config["boot"]?.displayString {
                        DetailRow(label: "Ordre de boot", value: boot, monospaced: true)
                    }
                }
            }

            if !vm.diskDevices.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            SectionLabel("Disques", trailing: "\(vm.diskDevices.count)")
                            Spacer()
                            Button("Agrandir") { sheet = .resize }
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.ember)
                        }
                        ForEach(vm.diskDevices, id: \.key) { device in
                            ConfigLine(key: device.key, value: device.value, tint: Palette.inkSecondary)
                        }
                    }
                }
            }

            if !vm.netDevices.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 9) {
                        SectionLabel("Interfaces réseau")
                        ForEach(vm.netDevices, id: \.key) { device in
                            ConfigLine(key: device.key, value: device.value, tint: Palette.inkSecondary)
                        }
                    }
                }
            }

            firewallCard
        }
    }

    private var firewallCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    SectionLabel("Pare-feu", trailing: "\(vm.firewallRules.count) règles")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { vm.firewallEnabled },
                        set: { value in
                            vm.firewallEnabled = value
                            Task {
                                await app.perform(value ? "Pare-feu activé" : "Pare-feu désactivé",
                                                  node: ref.node) { api in
                                    try await api.setGuestFirewall(ref, enabled: value)
                                }
                            }
                        }))
                    .labelsHidden()
                    .tint(Palette.ember)
                }

                if vm.firewallRules.isEmpty {
                    Text("Aucune règle spécifique à cette instance.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.inkTertiary)
                } else {
                    ForEach(vm.firewallRules) { rule in
                        HStack(spacing: 8) {
                            StatusPip(color: rule.enable
                                      ? ((rule.action ?? "").uppercased() == "ACCEPT"
                                         ? Palette.mint : Palette.rose)
                                      : Palette.inkTertiary,
                                      size: 5, hollow: !rule.enable)
                            Text("\(rule.type ?? "in") \(rule.action ?? "—")")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.ink)
                            Text([rule.proto, rule.dport.map { "→ \($0)" }, rule.source]
                                .compactMap { $0 }.joined(separator: " "))
                                .font(.mono(11.5))
                                .foregroundStyle(Palette.inkTertiary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    private var restoreSection: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel("Snapshots", trailing: "\(vm.snapshots.count)")
                    Spacer()
                    Button {
                        Haptics.commit()
                        sheet = .snapshot
                    } label: {
                        Text("Créer")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.ember)
                    }
                }

                GlassCard(padding: 0) {
                    if vm.snapshots.isEmpty {
                        Text("Aucun snapshot pour cette instance.")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.inkTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 26)
                    } else {
                        RowStack(data: vm.snapshots.sorted { ($0.snaptime ?? 0) > ($1.snaptime ?? 0) },
                                 separatorInset: Metrics.rowInset + 27) { snapshot in
                            snapshotRow(snapshot).padding(.horizontal, Metrics.rowInset)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    SectionLabel("Sauvegardes", trailing: "\(vm.backups.count)")
                    Spacer()
                    Button {
                        Haptics.commit()
                        sheet = .backup
                    } label: {
                        Text("Lancer")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.ember)
                    }
                }

                GlassCard(padding: 0) {
                    if vm.backups.isEmpty {
                        Text("Aucune sauvegarde trouvée sur les stockages de ce nœud.")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.inkTertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 26)
                    } else {
                        RowStack(data: vm.backups, separatorInset: Metrics.rowInset + 27) { backup in
                            BackupRow(backup: backup, node: ref.node, kind: ref.kind, vmid: ref.vmid) {
                                Task { await vm.loadBackups(using: app.client(), storages: app.snapshot.storages) }
                            }
                            .padding(.horizontal, Metrics.rowInset)
                        }
                    }
                }
            }
        }
    }

    private func snapshotRow(_ snapshot: PVESnapshot) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: snapshot.vmstate ? "camera.aperture" : "camera")
                .font(.system(size: 13))
                .foregroundStyle(Palette.inkTertiary)
                .frame(width: 16)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(snapshot.name)
                        .font(.system(size: 14.5))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if snapshot.vmstate { TagChip(text: "RAM") }
                }
                Text([snapshot.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                      Format.dateTime(snapshot.date)]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.inkTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

            Menu {
                Button {
                    Task {
                        await app.perform("Restauration de \(snapshot.name)", node: ref.node) { api in
                            try await api.rollbackSnapshot(ref, name: snapshot.name)
                        }
                        await reload()
                    }
                } label: { Label("Restaurer", systemImage: "arrow.uturn.backward") }

                Button(role: .destructive) {
                    Task {
                        await app.perform("Suppression de \(snapshot.name)", node: ref.node) { api in
                            try await api.deleteSnapshot(ref, name: snapshot.name)
                        }
                        await reload()
                    }
                } label: { Label("Supprimer", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.inkTertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 9)
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
            BackupSheet(ref: ref) { await vm.loadBackups(using: app.client(), storages: app.snapshot.storages) }
        case .resources:
            EditResourcesSheet(ref: ref, cores: vm.cores, memoryMB: vm.memoryMB,
                               kind: ref.kind) { await reload() }
        case .resize:
            ResizeDiskSheet(ref: ref, disks: vm.diskDevices.map(\.key)) { await reload() }
        case .console:
            ConsoleView(target: .guest(ref), title: "Console · \(displayName)")
        }
    }

    // MARK: Actions

    private func run(_ action: GuestPowerAction) {
        busyAction = action
        Task {
            await app.power(ref, action: action, name: displayName)
            await vm.load(using: app.client(), full: false)
            busyAction = nil
        }
    }

    private func deleteGuest() {
        Task {
            let ok = await app.perform("Suppression de \(displayName)", node: ref.node) { api in
                try await api.deleteGuest(ref, purge: true, destroyUnreferenced: true)
            }
            if ok { await app.refresh(silent: true) }
        }
    }

    private func reload() async {
        await vm.load(using: app.client())
        await app.refresh(silent: true)
    }
}

enum GuestSheet: Int, Identifiable {
    case snapshot, clone, migrate, backup, resources, resize, console
    var id: Int { rawValue }
}

struct ConfigLine: View {
    var key: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key)
                .font(.mono(12, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
            Text(value)
                .font(.mono(12))
                .foregroundStyle(Palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
    }
}

struct BackupRow: View {
    @Environment(AppModel.self) private var app
    var backup: PVEStorageContent
    var node: String
    var kind: PVEResourceType
    var vmid: Int
    var onChange: () -> Void

    @State private var confirmRestore = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "externaldrive")
                .font(.system(size: 13))
                .foregroundStyle(Palette.inkTertiary)
                .frame(width: 16)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(Format.dateTime(backup.date))
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.ink)
                    if backup.isProtected { TagChip(text: "protégée", tint: Palette.amber) }
                    if let state = backup.verificationState, state.lowercased() != "ok" {
                        TagChip(text: state, tint: Palette.rose)
                    }
                }
                Text("\(Format.bytes(backup.size)) · \(backup.volid.components(separatedBy: ":").first ?? "")")
                    .font(.metric(12))
                    .foregroundStyle(Palette.inkTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

            Menu {
                Button { confirmRestore = true } label: {
                    Label("Restaurer", systemImage: "arrow.uturn.backward.circle")
                }
                Button {
                    Task {
                        await app.perform(backup.isProtected ? "Protection retirée" : "Sauvegarde protégée",
                                          node: node) { api in
                            try await api.setVolumeProtection(node: node, volid: backup.volid,
                                                              isProtected: !backup.isProtected)
                        }
                        onChange()
                    }
                } label: {
                    Label(backup.isProtected ? "Retirer la protection" : "Protéger",
                          systemImage: backup.isProtected ? "lock.open" : "lock")
                }
                Button(role: .destructive) {
                    Task {
                        await app.perform("Suppression de la sauvegarde", node: node) { api in
                            try await api.deleteVolume(node: node, volid: backup.volid)
                        }
                        onChange()
                    }
                } label: { Label("Supprimer", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.inkTertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 9)
        .alert("Restaurer cette sauvegarde ?", isPresented: $confirmRestore) {
            Button("Restaurer", role: .destructive) {
                Task {
                    await app.perform("Restauration \(vmid)", node: node) { api in
                        try await api.restoreBackup(node: node, kind: kind, vmid: vmid,
                                                    archive: backup.volid, storage: nil,
                                                    force: true, startAfter: false)
                    }
                    onChange()
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("L'instance \(vmid) sera écrasée par la sauvegarde du \(Format.dateTime(backup.date)). Les données actuelles seront perdues.")
        }
    }
}
