import SwiftUI

/// Shared chrome for action sheets: a form with Cancel and a confirm button in
/// the navigation bar, and a progress state while the request is in flight.
private struct ActionForm<Content: View>: View {
    var title: String
    var confirmTitle: String
    var canConfirm: Bool
    var isWorking: Bool
    var onConfirm: () -> Void
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form { content }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isWorking {
                            ProgressView()
                        } else {
                            Button(confirmTitle, action: onConfirm)
                                .fontWeight(.semibold)
                                .disabled(!canConfirm)
                        }
                    }
                }
                .disabled(isWorking)
                .interactiveDismissDisabled(isWorking)
        }
    }
}

// MARK: - Snapshot

struct SnapshotSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let ref: GuestRef
    var onDone: () async -> Void

    @State private var name = SnapshotSheet.suggestedName()
    @State private var notes = ""
    @State private var includeRAM = false
    @State private var working = false

    /// Proxmox snapshot names: letters, digits, `-` and `_`, starting with a letter.
    private var isValidName: Bool {
        name.range(of: "^[A-Za-z][A-Za-z0-9_-]{1,39}$", options: .regularExpression) != nil
    }

    static func suggestedName() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmm"
        return "snap-\(f.string(from: Date()))"
    }

    var body: some View {
        ActionForm(title: "Take Snapshot", confirmTitle: "Take",
                   canConfirm: isValidName, isWorking: working, onConfirm: submit) {
            Section {
                TextField("Name", text: $name)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Description", text: $notes, axis: .vertical)
                    .lineLimit(1...4)
            } footer: {
                if !isValidName {
                    Text("Use letters, numbers, hyphens and underscores, starting with a letter.")
                        .foregroundStyle(Palette.critical)
                }
            }

            if ref.kind == .qemu {
                Section {
                    Toggle("Include RAM", isOn: $includeRAM)
                } footer: {
                    Text("Saves the running memory so the VM resumes exactly where it was. Slower and larger.")
                }
            }
        }
    }

    private func submit() {
        working = true
        Task {
            let ok = await app.perform("Snapshot \(name)", node: ref.node) { api in
                try await api.createSnapshot(ref, name: name, description: notes, includeRAM: includeRAM)
            }
            await onDone()
            working = false
            if ok { dismiss() }
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
    @State private var working = false

    private var takenIDs: Set<Int> { Set(app.snapshot.guests.compactMap(\.vmid)) }

    private var idError: String? {
        guard let id = Int(newID) else { return newID.isEmpty ? nil : "Enter a number." }
        if id < 100 || id > 999_999_999 { return "IDs range from 100 to 999999999." }
        if takenIDs.contains(id) { return "ID \(id) is already in use." }
        return nil
    }

    private var storages: [String] {
        Array(Set(app.snapshot.storages
            .filter { ($0.content ?? "").contains("images") || ($0.content ?? "").contains("rootdir") }
            .compactMap(\.storage))).sorted()
    }

    var body: some View {
        ActionForm(title: "Clone", confirmTitle: "Clone",
                   canConfirm: Int(newID) != nil && idError == nil, isWorking: working, onConfirm: submit) {
            Section {
                TextField("New ID", text: $newID)
                    .keyboardType(.numberPad)
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                if let idError { Text(idError).foregroundStyle(Palette.critical) }
            }

            Section {
                Picker("Mode", selection: $fullClone) {
                    Text("Full Clone").tag(true)
                    Text("Linked Clone").tag(false)
                }
                Picker("Target Node", selection: $targetNode) {
                    Text("Same Node (\(ref.node))").tag("")
                    ForEach(app.snapshot.onlineNodes.map(\.displayName).filter { $0 != ref.node }, id: \.self) {
                        Text($0).tag($0)
                    }
                }
                if fullClone {
                    Picker("Storage", selection: $storage) {
                        Text("Same as Source").tag("")
                        ForEach(storages, id: \.self) { Text($0).tag($0) }
                    }
                }
            } footer: {
                Text(fullClone
                     ? "A full clone copies every disk and is independent of the source."
                     : "A linked clone shares disks with the source template. It's fast but depends on it.")
            }
        }
        .task {
            if newID.isEmpty, let next = try? await app.client()?.nextVMID() { newID = String(next) }
            if name.isEmpty { name = "\(currentName)-clone" }
        }
    }

    private func submit() {
        guard let id = Int(newID) else { return }
        working = true
        Task {
            let ok = await app.perform("Clone to \(id)", node: ref.node) { api in
                try await api.cloneGuest(ref, newID: id, name: name, full: fullClone,
                                         targetNode: targetNode.isEmpty ? nil : targetNode,
                                         storage: storage.isEmpty ? nil : storage)
            }
            working = false
            if ok { dismiss() }
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
    @State private var working = false

    private var candidates: [String] {
        app.snapshot.onlineNodes.map(\.displayName).filter { $0 != ref.node }
    }

    var body: some View {
        ActionForm(title: "Migrate", confirmTitle: "Migrate",
                   canConfirm: !target.isEmpty, isWorking: working, onConfirm: submit) {
            if candidates.isEmpty {
                Section {
                    ContentUnavailableView("No Other Nodes", systemImage: "server.rack",
                                           description: Text("Migration needs at least one other online node in the cluster."))
                }
            } else {
                Section {
                    Picker("Target Node", selection: $target) {
                        ForEach(candidates, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section {
                    Toggle(ref.kind == .qemu ? "Live Migration" : "Restart Migration", isOn: $online)
                    Toggle("Include Local Disks", isOn: $withLocalDisks)
                } footer: {
                    Text(ref.kind == .qemu
                         ? "A live migration keeps the VM running while its memory is transferred."
                         : "The container is stopped, moved and started again on the target node.")
                }
            }
        }
        .onAppear { if target.isEmpty { target = candidates.first ?? "" } }
    }

    private func submit() {
        working = true
        Task {
            let ok = await app.perform("Migrate to \(target)", node: ref.node) { api in
                try await api.migrateGuest(ref, to: target, online: online, withLocalDisks: withLocalDisks)
            }
            working = false
            if ok { dismiss() }
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
    @State private var compression = "zstd"
    @State private var notes = ""
    @State private var isProtected = false
    @State private var working = false

    private var storages: [String] {
        Array(Set(app.snapshot.storages
            .filter { ($0.content ?? "").contains("backup") && ($0.node == ref.node || $0.shared) }
            .compactMap(\.storage))).sorted()
    }

    var body: some View {
        ActionForm(title: "Back Up Now", confirmTitle: "Back Up",
                   canConfirm: !storage.isEmpty, isWorking: working, onConfirm: submit) {
            if storages.isEmpty {
                Section {
                    ContentUnavailableView("No Backup Storage", systemImage: "externaldrive",
                                           description: Text("No storage on \(ref.node) accepts backups."))
                }
            } else {
                Section {
                    Picker("Storage", selection: $storage) {
                        ForEach(storages, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Mode", selection: $mode) {
                        Text("Snapshot").tag("snapshot")
                        Text("Suspend").tag("suspend")
                        Text("Stop").tag("stop")
                    }
                    Picker("Compression", selection: $compression) {
                        Text("Zstandard").tag("zstd")
                        Text("LZO").tag("lzo")
                        Text("Gzip").tag("gzip")
                        Text("None").tag("0")
                    }
                } footer: {
                    Text("Snapshot mode backs up without downtime. Stop mode gives the most consistent result.")
                }

                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                    Toggle("Protected", isOn: $isProtected)
                } footer: {
                    Text("Protected backups are skipped by automatic pruning.")
                }
            }
        }
        .onAppear { if storage.isEmpty { storage = storages.first ?? "" } }
    }

    private func submit() {
        working = true
        Task {
            let ok = await app.perform("Back up \(ref.kind.label) \(ref.vmid)", node: ref.node) { api in
                try await api.backupNow(node: ref.node, vmid: ref.vmid, storage: storage, mode: mode,
                                        compress: compression, notes: notes.isEmpty ? nil : notes,
                                        isProtected: isProtected)
            }
            await onDone()
            working = false
            if ok { dismiss() }
        }
    }
}

// MARK: - CPU & memory

struct EditResourcesSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let ref: GuestRef
    let originalCores: Int
    let originalMemoryMB: Int
    var onDone: () async -> Void

    @State private var cores: Int
    @State private var memoryMB: Int
    @State private var working = false

    init(ref: GuestRef, cores: Int, memoryMB: Int, onDone: @escaping () async -> Void) {
        self.ref = ref
        self.originalCores = max(1, cores)
        self.originalMemoryMB = max(128, memoryMB)
        self.onDone = onDone
        _cores = State(initialValue: max(1, cores))
        _memoryMB = State(initialValue: max(128, memoryMB))
    }

    private var nodeResource: PVEResource? {
        app.snapshot.nodes.first { $0.displayName == ref.node }
    }

    private var maxCores: Int { max(originalCores, Int(nodeResource?.maxcpu ?? 64)) }

    private var memoryOptions: [Int] {
        let presets = [512, 1024, 2048, 4096, 6144, 8192, 12288, 16384, 24576, 32768, 49152, 65536, 131072]
        let limit = Int((nodeResource?.maxmem ?? 1_099_511_627_776) / 1_048_576)
        return Array(Set(presets.filter { $0 <= limit } + [originalMemoryMB])).sorted()
    }

    var body: some View {
        ActionForm(title: "CPU and Memory", confirmTitle: "Save",
                   canConfirm: cores != originalCores || memoryMB != originalMemoryMB,
                   isWorking: working, onConfirm: submit) {
            Section {
                Stepper(value: $cores, in: 1...maxCores) {
                    LabeledContent("Cores", value: "\(cores)")
                }
                Picker("Memory", selection: $memoryMB) {
                    ForEach(memoryOptions, id: \.self) { mb in
                        Text(Format.bytes(Double(mb) * 1_048_576)).tag(mb)
                    }
                }
            } footer: {
                Text(ref.kind == .lxc
                     ? "Changes apply to the running container immediately."
                     : "Without CPU and memory hotplug, changes take effect the next time the VM starts.")
            }
        }
    }

    private func submit() {
        working = true
        Task {
            let ok = await app.perform("Update resources", node: ref.node) { api in
                try await api.updateGuestConfig(ref, values: ["cores": String(cores), "memory": String(memoryMB)])
            }
            await onDone()
            working = false
            if ok { dismiss() }
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
    @State private var gigabytes = 10
    @State private var working = false

    private var resizable: [String] { disks.filter { !$0.hasPrefix("unused") && !$0.hasPrefix("efidisk") && !$0.hasPrefix("tpmstate") } }

    var body: some View {
        ActionForm(title: "Resize Disk", confirmTitle: "Resize",
                   canConfirm: !disk.isEmpty && gigabytes > 0, isWorking: working, onConfirm: submit) {
            Section {
                Picker("Disk", selection: $disk) {
                    ForEach(resizable, id: \.self) { Text($0).tag($0) }
                }
                Stepper(value: $gigabytes, in: 1...4096) {
                    LabeledContent("Add", value: "\(gigabytes) GiB")
                }
            } footer: {
                Text("Proxmox can only grow a disk. Extend the partition and filesystem inside the guest afterwards.")
            }
        }
        .onAppear { if disk.isEmpty { disk = resizable.first ?? "" } }
    }

    private func submit() {
        working = true
        Task {
            let ok = await app.perform("Resize \(disk)", node: ref.node) { api in
                try await api.resizeDisk(ref, disk: disk, sizeIncrement: "+\(gigabytes)G")
            }
            await onDone()
            working = false
            if ok { dismiss() }
        }
    }
}
