import SwiftUI

/// Browses one storage's volumes, grouped by content type, with search,
/// deletion, protection and download-from-URL.
struct StorageDetailView: View {
    @Environment(AppModel.self) private var app
    let node: String
    let storage: String

    @State private var items: [PVEStorageContent] = []
    @State private var filter: ContentFilter = .all
    @State private var query = ""
    @State private var loading = true
    @State private var error: String?
    @State private var showDownload = false
    @State private var pendingDelete: PVEStorageContent?

    enum ContentFilter: String, CaseIterable, Identifiable {
        case all, backup, iso, vztmpl, images, rootdir, snippets
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All Content"
            case .backup: return "Backups"
            case .iso: return "ISO Images"
            case .vztmpl: return "Container Templates"
            case .images: return "VM Disks"
            case .rootdir: return "Container Volumes"
            case .snippets: return "Snippets"
            }
        }

        var symbol: String {
            switch self {
            case .all: return "tray.full"
            case .backup: return "externaldrive.badge.timemachine"
            case .iso: return "opticaldisc"
            case .vztmpl: return "shippingbox"
            case .images: return "internaldrive"
            case .rootdir: return "folder"
            case .snippets: return "doc.text"
            }
        }
    }

    private var resource: PVEResource? {
        app.snapshot.storages.first { $0.storage == storage && ($0.node == node || $0.shared) }
    }

    private var guestNames: [Int: String] {
        Dictionary(app.snapshot.guests.compactMap { g in g.vmid.map { ($0, g.displayName) } },
                   uniquingKeysWith: { first, _ in first })
    }

    private var visibleItems: [PVEStorageContent] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return items
            .filter { filter == .all || $0.content == filter.rawValue }
            .filter { q.isEmpty || $0.volid.localizedCaseInsensitiveContains(q) || String($0.vmid ?? -1) == q }
            .sorted { ($0.ctime ?? 0) > ($1.ctime ?? 0) }
    }

    /// Only content types actually present, in a stable order.
    private var groups: [(ContentFilter, [PVEStorageContent])] {
        let grouped = Dictionary(grouping: visibleItems) { ContentFilter(rawValue: $0.content ?? "") ?? .all }
        return ContentFilter.allCases.compactMap { kind in
            guard let items = grouped[kind], !items.isEmpty else { return nil }
            return (kind, items)
        }
    }

    private var availableFilters: [ContentFilter] {
        let present = Set(items.compactMap { ContentFilter(rawValue: $0.content ?? "") })
        return [.all] + ContentFilter.allCases.filter { $0 != .all && present.contains($0) }
    }

    var body: some View {
        List {
            if let resource {
                Section {
                    UsageRow(title: "Used",
                             value: Format.bytes(resource.disk),
                             detail: "of \(Format.bytes(resource.maxdisk))",
                             fraction: resource.diskFraction)
                        .padding(.vertical, 4)
                    LabeledContent("Type", value: resource.pluginType?.uppercased() ?? "—")
                    LabeledContent("Node", value: resource.shared ? "Shared" : node)
                    LabeledContent("Free", value: Format.bytes((resource.maxdisk ?? 0) - (resource.disk ?? 0)))
                }
            }

            if let error {
                Section {
                    InlineErrorRow(message: error) { Task { await load() } }
                }
            }

            if loading && items.isEmpty {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            } else if visibleItems.isEmpty {
                if !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ContentUnavailableView("Empty", systemImage: filter.symbol,
                                           description: Text("No \(filter == .all ? "content" : filter.title.lowercased()) on \(storage)."))
                }
            } else {
                ForEach(groups, id: \.0) { kind, volumes in
                    Section {
                        ForEach(volumes) { volume in
                            VolumeRow(volume: volume, symbol: kind.symbol,
                                      guestName: volume.vmid.flatMap { guestNames[$0] })
                                .swipeActions(edge: .trailing) {
                                    Button("Delete", systemImage: "trash") { pendingDelete = volume }
                                        .tint(Palette.critical)
                                }
                                .contextMenu { contextMenu(for: volume) }
                        }
                    } header: {
                        Text(kind.title)
                    } footer: {
                        Text("\(volumes.count) item\(volumes.count == 1 ? "" : "s") · \(Format.bytes(volumes.reduce(0) { $0 + ($1.size ?? 0) }))")
                    }
                }
            }
        }
        .proxynList()
        .navigationTitle(storage)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "File name or guest ID")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Content", selection: $filter) {
                        ForEach(availableFilters) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                } label: {
                    Label("Filter", systemImage: filter == .all
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
                Button("Download from URL", systemImage: "arrow.down.circle") { showDownload = true }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showDownload) {
            DownloadURLSheet(node: node, storage: storage) { await load() }
        }
        .confirmationDialog("Delete this file?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingDelete) { volume in
            Button("Delete", role: .destructive) { delete(volume) }
        } message: { volume in
            Text("\(volume.filename) (\(Format.bytes(volume.size))) will be removed permanently.")
        }
    }

    @ViewBuilder
    private func contextMenu(for volume: PVEStorageContent) -> some View {
        if volume.content == "backup" {
            Button(volume.isProtected ? "Remove Protection" : "Protect",
                   systemImage: volume.isProtected ? "lock.open" : "lock") {
                Task {
                    await app.perform(volume.isProtected ? "Remove protection" : "Protect backup",
                                      node: node) { api in
                        try await api.setVolumeProtection(node: node, volid: volume.volid,
                                                          isProtected: !volume.isProtected)
                    }
                    await load()
                }
            }
        }
        Button("Copy Volume ID", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = volume.volid
        }
        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = volume }
    }

    private func delete(_ volume: PVEStorageContent) {
        Task {
            await app.perform("Delete \(volume.filename)", node: node) { api in
                try await api.deleteVolume(node: node, volid: volume.volid)
            }
            await load()
        }
    }

    private func load() async {
        guard let api = app.client() else { return }
        loading = true
        defer { loading = false }
        do {
            items = try await api.storageContent(node: node, storage: storage)
            error = nil
            if !availableFilters.contains(filter) { filter = .all }
        } catch let failure as ProxmoxError {
            if case .cancelled = failure { return }
            error = failure.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A file name can be very long (vzdump names are ~50 characters): it gets the
/// full row width and truncates in the middle, keeping the distinctive date and
/// extension visible. Metadata sits on its own line underneath.
private struct VolumeRow: View {
    var volume: PVEStorageContent
    var symbol: String
    var guestName: String?

    /// Backups and guest disks are titled by the guest they belong to; the
    /// generated file name goes underneath, where its length can't crowd out
    /// the information that tells rows apart.
    private var title: String {
        guard let vmid = volume.vmid, vmid > 0,
              volume.content == "backup" || volume.content == "images" || volume.content == "rootdir"
        else { return volume.filename }
        return guestName.map { "\($0) (\(vmid))" } ?? "Guest \(vmid)"
    }

    private var metadata: String {
        var parts = [Format.bytes(volume.size)]
        if let date = volume.date { parts.append(Format.dateTime(date)) }
        if title != volume.filename, volume.content != "backup" { parts.append(volume.filename) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if volume.isProtected {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Protected")
                    }
                }
                Text(metadata)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 1)
    }
}

/// Makes the node download an ISO or container template directly — nothing
/// passes through the phone.
struct DownloadURLSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let node: String
    let storage: String
    var onDone: () async -> Void

    @State private var url = ""
    @State private var filename = ""
    @State private var content = "iso"
    @State private var working = false

    private var isValidURL: Bool {
        guard let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased() else { return false }
        return ["http", "https"].contains(scheme) && parsed.host != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/image.iso", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("File name", text: $filename)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Type", selection: $content) {
                        Text("ISO Image").tag("iso")
                        Text("Container Template").tag("vztmpl")
                    }
                } footer: {
                    Text("\(node) downloads the file straight into \(storage).")
                }
            }
            .navigationTitle("Download from URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if working {
                        ProgressView()
                    } else {
                        Button("Download", action: submit)
                            .fontWeight(.semibold)
                            .disabled(!isValidURL || filename.isEmpty)
                    }
                }
            }
            .onChange(of: url) { _, value in
                if filename.isEmpty, let last = URL(string: value)?.lastPathComponent, last.contains(".") {
                    filename = last
                }
            }
        }
    }

    private func submit() {
        working = true
        Task {
            let ok = await app.perform("Download \(filename)", node: node) { api in
                try await api.downloadToStorage(node: node, storage: storage, url: url,
                                                content: content, filename: filename)
            }
            await onDone()
            working = false
            if ok { dismiss() }
        }
    }
}
