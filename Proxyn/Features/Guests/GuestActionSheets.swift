import SwiftUI

/// Shared chrome for the action sheets: dark canvas, title, cancel + confirm.
struct SheetScaffold<Content: View>: View {
    var title: String
    var subtitle: String?
    var confirmLabel: String
    var confirmEnabled: Bool = true
    var destructive: Bool = false
    var busy: Bool = false
    var onConfirm: () -> Void
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.sheetCanvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        content
                    }
                    .padding(18)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                // Pinned so the primary action stays reachable at any detent.
                .safeAreaInset(edge: .bottom) {
                    Button(action: onConfirm) {
                        HStack(spacing: 8) {
                            if busy { ProgressView().controlSize(.small).tint(.black) }
                            Text(confirmLabel)
                        }
                    }
                    .buttonStyle(ProminentButtonStyle(tint: destructive ? Palette.rose : Palette.ember))
                    .disabled(!confirmEnabled || busy)
                    .opacity(confirmEnabled ? 1 : 0.5)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
                    .background {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .overlay(Rectangle().fill(Palette.canvas.opacity(0.6)))
                            .overlay(alignment: .top) { Divider1px() }
                            .ignoresSafeArea(edges: .bottom)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }.foregroundStyle(Palette.inkSecondary)
                }
            }
        }
        .presentationBackground(Palette.sheetCanvas)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Snapshot

struct SnapshotSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let ref: GuestRef
    var onDone: () async -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var includeRAM = false
    @State private var busy = false

    private var suggestedName: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return "proxyn-\(f.string(from: Date()))"
    }

    var body: some View {
        SheetScaffold(
            title: "Nouveau snapshot",
            subtitle: "Un snapshot fige l'état des disques de l'instance #\(ref.vmid). Il est instantané mais reste stocké sur le même support que la VM — ce n'est pas une sauvegarde.",
            confirmLabel: "Créer le snapshot",
            confirmEnabled: !name.isEmpty,
            busy: busy,
            onConfirm: create
        ) {
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    ProxynField(label: "Nom", placeholder: suggestedName, text: $name,
                                symbol: "tag.fill", monospaced: true)
                    ProxynField(label: "Description", placeholder: "Avant mise à jour…",
                                text: $description, symbol: "text.alignleft",
                                autocapitalization: .sentences)
                    if ref.kind == .qemu {
                        Divider1px()
                        ToggleRow(title: "Inclure la RAM",
                                  subtitle: "Enregistre l'état mémoire pour reprendre exactement où la VM en était. Plus lent et plus volumineux.",
                                  symbol: "memorychip.fill",
                                  isOn: $includeRAM)
                    }
                }
            }
        }
        .onAppear { if name.isEmpty { name = suggestedName } }
    }

    private func create() {
        busy = true
        Task {
            let clean = name.replacingOccurrences(of: " ", with: "-")
            await app.perform("Snapshot \(clean)", node: ref.node) { api in
                try await api.createSnapshot(ref, name: clean,
                                            description: description, includeRAM: includeRAM)
            }
            await onDone()
            busy = false
            dismiss()
        }
    }
}

// MARK: - Clone

struct CloneSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let ref: GuestRef
    let currentName: String

    @State private var newID = ""
    @State private var name = ""
    @State private var fullClone = true
    @State private var targetNode = ""
    @State private var storage = ""
    @State private var busy = false

    private var nodes: [StringOption] {
        [StringOption("", "Même nœud")] + app.snapshot.nodes.map { StringOption($0.displayName) }
    }

    private var storages: [StringOption] {
        [StringOption("", "Par défaut")] + app.snapshot.uniqueStorages
            .filter { ($0.content ?? "").contains("images") || ($0.content ?? "").contains("rootdir") }
            .compactMap { $0.storage }
            .map { StringOption($0) }
    }

    var body: some View {
        SheetScaffold(
            title: "Cloner",
            subtitle: "Duplique \(currentName) (#\(ref.vmid)). Un clone lié partage les disques du modèle et démarre instantanément ; un clone complet copie tout.",
            confirmLabel: "Lancer le clonage",
            confirmEnabled: Int(newID) != nil,
            busy: busy,
            onConfirm: clone
        ) {
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        ProxynField(label: "Nouvel ID", placeholder: "100", text: $newID,
                                    symbol: "number", keyboard: .numberPad, monospaced: true)
                            .frame(width: 130)
                        ProxynField(label: "Nom", placeholder: "\(currentName)-copie", text: $name,
                                    symbol: "tag.fill")
                    }
                    Divider1px()
                    ToggleRow(title: "Clone complet",
                              subtitle: fullClone
                              ? "Copie intégrale des disques. Indépendant de l'original."
                              : "Clone lié : rapide et peu coûteux, mais dépend de l'original (modèles uniquement).",
                              symbol: "doc.on.doc.fill", isOn: $fullClone)
                    Divider1px()
                    PickerRow(title: "Nœud cible", symbol: "server.rack", options: nodes,
                              label: \.title,
                              selection: Binding(
                                get: { nodes.first { $0.value == targetNode } ?? nodes[0] },
                                set: { targetNode = $0.value }))
                    if fullClone {
                        PickerRow(title: "Stockage", symbol: "internaldrive.fill", options: storages,
                                  label: \.title,
                                  selection: Binding(
                                    get: { storages.first { $0.value == storage } ?? storages[0] },
                                    set: { storage = $0.value }))
                    }
                }
            }
        }
        .task {
            if newID.isEmpty, let next = try? await app.client()?.nextVMID() {
                newID = String(next)
            }
            if name.isEmpty { name = "\(currentName)-copie" }
        }
    }

    private func clone() {
        guard let id = Int(newID) else { return }
        busy = true
        Task {
            await app.perform("Clonage vers #\(id)", node: ref.node) { api in
                try await api.cloneGuest(ref, newID: id, name: name, full: fullClone,
                                         targetNode: targetNode.isEmpty ? nil : targetNode,
                                         storage: storage.isEmpty ? nil : storage)
            }
            busy = false
            dismiss()
        }
    }
}

// MARK: - Migrate

struct MigrateSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let ref: GuestRef

    @State private var target = ""
    @State private var online = true
    @State private var withLocalDisks = false
    @State private var busy = false

    private var candidates: [StringOption] {
        app.snapshot.onlineNodes
            .map(\.displayName)
            .filter { $0 != ref.node }
            .map { StringOption($0) }
    }

    var body: some View {
        SheetScaffold(
            title: "Migrer",
            subtitle: candidates.isEmpty
            ? "Aucun autre nœud en ligne dans ce cluster."
            : "Déplace l'instance #\(ref.vmid) depuis \(ref.node) vers un autre nœud du cluster.",
            confirmLabel: "Migrer",
            confirmEnabled: !target.isEmpty,
            busy: busy,
            onConfirm: migrate
        ) {
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    if candidates.isEmpty {
                        Text("La migration nécessite au moins deux nœuds en ligne.")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.inkTertiary)
                    } else {
                        PickerRow(title: "Nœud de destination", symbol: "arrow.right.circle.fill",
                                  options: candidates, label: \.title,
                                  selection: Binding(
                                    get: { candidates.first { $0.value == target } ?? candidates[0] },
                                    set: { target = $0.value }))
                        Divider1px()
                        ToggleRow(title: ref.kind == .qemu ? "Migration à chaud" : "Redémarrage autorisé",
                                  subtitle: ref.kind == .qemu
                                  ? "La VM reste allumée pendant le transfert de sa mémoire."
                                  : "Le conteneur est brièvement redémarré sur le nœud cible.",
                                  symbol: "bolt.fill", isOn: $online)
                        ToggleRow(title: "Inclure les disques locaux",
                                  subtitle: "Nécessaire si l'instance utilise un stockage non partagé.",
                                  symbol: "internaldrive.fill", isOn: $withLocalDisks)
                    }
                }
            }
        }
        .onAppear { if target.isEmpty { target = candidates.first?.value ?? "" } }
    }

    private func migrate() {
        guard !target.isEmpty else { return }
        busy = true
        Task {
            await app.perform("Migration vers \(target)", node: ref.node) { api in
                try await api.migrateGuest(ref, to: target, online: online,
                                           withLocalDisks: withLocalDisks)
            }
            busy = false
            dismiss()
        }
    }
}

// MARK: - Backup

struct BackupSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let ref: GuestRef
    var onDone: () async -> Void

    @State private var storage = ""
    @State private var mode = "snapshot"
    @State private var compress = "zstd"
    @State private var notes = ""
    @State private var isProtected = false
    @State private var busy = false

    private var storages: [StringOption] {
        app.snapshot.storages
            .filter { ($0.content ?? "").contains("backup") && ($0.node == ref.node || $0.shared) }
            .compactMap { $0.storage }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .map { StringOption($0) }
    }

    private let modes = [StringOption("snapshot", "Snapshot (sans interruption)"),
                         StringOption("suspend", "Suspend"),
                         StringOption("stop", "Stop (cohérence maximale)")]
    private let compressions = [StringOption("zstd", "ZSTD (rapide)"),
                                StringOption("lzo", "LZO"),
                                StringOption("gzip", "GZIP"),
                                StringOption("0", "Aucune")]

    var body: some View {
        SheetScaffold(
            title: "Sauvegarder",
            subtitle: "Crée une archive vzdump de l'instance #\(ref.vmid) sur un stockage de sauvegarde.",
            confirmLabel: "Lancer la sauvegarde",
            confirmEnabled: !storage.isEmpty,
            busy: busy,
            onConfirm: backup
        ) {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    if storages.isEmpty {
                        Text("Aucun stockage acceptant le contenu « backup » n'est disponible sur \(ref.node).")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.inkTertiary)
                    } else {
                        PickerRow(title: "Stockage", symbol: "externaldrive.fill", options: storages,
                                  label: \.title,
                                  selection: Binding(
                                    get: { storages.first { $0.value == storage } ?? storages[0] },
                                    set: { storage = $0.value }))
                        PickerRow(title: "Mode", symbol: "camera.aperture", options: modes,
                                  label: \.title,
                                  selection: Binding(
                                    get: { modes.first { $0.value == mode } ?? modes[0] },
                                    set: { mode = $0.value }))
                        PickerRow(title: "Compression", symbol: "rectangle.compress.vertical",
                                  options: compressions, label: \.title,
                                  selection: Binding(
                                    get: { compressions.first { $0.value == compress } ?? compressions[0] },
                                    set: { compress = $0.value }))
                        Divider1px()
                        ProxynField(label: "Note", placeholder: "Avant migration…", text: $notes,
                                    symbol: "text.alignleft", autocapitalization: .sentences)
                        ToggleRow(title: "Protéger la sauvegarde",
                                  subtitle: "Exclue de la rotation automatique des anciennes sauvegardes.",
                                  symbol: "lock.fill", isOn: $isProtected)
                    }
                }
            }
        }
        .onAppear { if storage.isEmpty { storage = storages.first?.value ?? "" } }
    }

    private func backup() {
        guard !storage.isEmpty else { return }
        busy = true
        Task {
            await app.perform("Sauvegarde #\(ref.vmid)", node: ref.node) { api in
                try await api.backupNow(node: ref.node, vmid: ref.vmid, storage: storage,
                                        mode: mode, compress: compress,
                                        notes: notes.isEmpty ? nil : notes,
                                        isProtected: isProtected)
            }
            await onDone()
            busy = false
            dismiss()
        }
    }
}

// MARK: - CPU / RAM

struct EditResourcesSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let ref: GuestRef
    let kind: PVEResourceType
    var onDone: () async -> Void

    @State private var cores: Double
    @State private var memoryMB: Double
    @State private var busy = false

    init(ref: GuestRef, cores: Int, memoryMB: Int, kind: PVEResourceType,
         onDone: @escaping () async -> Void) {
        self.ref = ref
        self.kind = kind
        self.onDone = onDone
        _cores = State(initialValue: Double(max(1, cores)))
        _memoryMB = State(initialValue: Double(max(64, memoryMB)))
    }

    var body: some View {
        SheetScaffold(
            title: "Ressources",
            subtitle: "Les changements sont appliqués immédiatement pour un conteneur. Pour une VM sans hotplug, ils prennent effet au prochain démarrage.",
            confirmLabel: "Appliquer",
            busy: busy,
            onConfirm: apply
        ) {
            GlassCard {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Label("Cœurs virtuels", systemImage: "cpu.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.inkSecondary)
                            Spacer()
                            Text("\(Int(cores))")
                                .font(.display(20, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.ember)
                                .contentTransition(.numericText())
                        }
                        Slider(value: $cores, in: 1...Double(maxCores), step: 1)
                            .tint(Palette.ember)
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Label("Mémoire", systemImage: "memorychip.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.inkSecondary)
                            Spacer()
                            Text(Format.bytes(memoryMB * 1_048_576))
                                .font(.display(20, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.sky)
                                .contentTransition(.numericText())
                        }
                        Slider(value: $memoryMB, in: 128...Double(maxMemoryMB), step: 128)
                            .tint(Palette.sky)
                        HStack {
                            ForEach([1024, 2048, 4096, 8192, 16384], id: \.self) { preset in
                                if preset <= maxMemoryMB {
                                    Button {
                                        Haptics.select()
                                        withAnimation(Motion.snap) { memoryMB = Double(preset) }
                                    } label: {
                                        Text(preset >= 1024 ? "\(preset / 1024) Go" : "\(preset) Mo")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .buttonStyle(QuietButtonStyle(tint: Palette.inkSecondary))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var maxCores: Int {
        Int(app.snapshot.nodes.first { $0.displayName == ref.node }?.maxcpu ?? 32)
    }

    private var maxMemoryMB: Int {
        let bytes = app.snapshot.nodes.first { $0.displayName == ref.node }?.maxmem ?? (64 * 1_073_741_824)
        return max(1024, Int(bytes / 1_048_576))
    }

    private func apply() {
        busy = true
        Task {
            let values = ["memory": String(Int(memoryMB)), "cores": String(Int(cores))]
            await app.perform("Ressources mises à jour", node: ref.node) { api in
                try await api.updateGuestConfig(ref, values: values)
            }
            await onDone()
            busy = false
            dismiss()
        }
    }
}

// MARK: - Resize disk

struct ResizeDiskSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let ref: GuestRef
    let disks: [String]
    var onDone: () async -> Void

    @State private var disk = ""
    @State private var increaseGB: Double = 10
    @State private var busy = false

    private var options: [StringOption] {
        disks.filter { !$0.hasPrefix("unused") }.map { StringOption($0) }
    }

    var body: some View {
        SheetScaffold(
            title: "Agrandir un disque",
            subtitle: "Proxmox ne sait qu'agrandir un disque virtuel : la taille indiquée est ajoutée à l'existant. Il faudra ensuite étendre la partition dans l'invité.",
            confirmLabel: "Ajouter \(Int(increaseGB)) Go",
            confirmEnabled: !disk.isEmpty,
            busy: busy,
            onConfirm: resize
        ) {
            GlassCard {
                VStack(alignment: .leading, spacing: 18) {
                    if options.isEmpty {
                        Text("Aucun disque redimensionnable détecté.")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.inkTertiary)
                    } else {
                        PickerRow(title: "Disque", symbol: "internaldrive.fill", options: options,
                                  label: \.title,
                                  selection: Binding(
                                    get: { options.first { $0.value == disk } ?? options[0] },
                                    set: { disk = $0.value }))
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text("Espace ajouté")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Palette.inkSecondary)
                                Spacer()
                                Text("+\(Int(increaseGB)) Go")
                                    .font(.display(20, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.amber)
                                    .contentTransition(.numericText())
                            }
                            Slider(value: $increaseGB, in: 1...500, step: 1)
                                .tint(Palette.amber)
                        }
                    }
                }
            }
        }
        .onAppear { if disk.isEmpty { disk = options.first?.value ?? "" } }
    }

    private func resize() {
        guard !disk.isEmpty else { return }
        busy = true
        Task {
            await app.perform("Agrandissement de \(disk)", node: ref.node) { api in
                try await api.resizeDisk(ref, disk: disk, sizeIncrement: "+\(Int(increaseGB))G")
            }
            await onDone()
            busy = false
            dismiss()
        }
    }
}
