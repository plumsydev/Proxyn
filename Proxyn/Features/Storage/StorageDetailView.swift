import SwiftUI

/// Content browser for one storage: ISOs, templates, disk images and backups,
/// with delete / protect / restore actions and an URL downloader.
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

    enum ContentFilter: String, CaseIterable, Identifiable, Hashable {
        case all, backup, images, iso, vztmpl
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "Tout"
            case .backup: return "Backups"
            case .images: return "Disques"
            case .iso: return "ISO"
            case .vztmpl: return "Modèles"
            }
        }
        var apiValue: String? { self == .all ? nil : rawValue }
    }

    private var resource: PVEResource? {
        app.snapshot.storages.first { $0.storage == storage && ($0.node == node || $0.shared) }
    }

    private var filtered: [PVEStorageContent] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var list = items
        if filter != .all { list = list.filter { $0.content == filter.rawValue } }
        if !q.isEmpty {
            list = list.filter {
                $0.volid.lowercased().contains(q) || String($0.vmid ?? 0).contains(q)
            }
        }
        return list.sorted { ($0.ctime ?? 0) > ($1.ctime ?? 0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let resource { headerCard(resource) }

                SearchField(text: $query, placeholder: "Nom de volume, ID…")
                SegmentedRail(items: ContentFilter.allCases, label: \.title, selection: $filter)

                if let error { ErrorBanner(message: error, retry: { Task { await load() } }) }

                if loading && items.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 64) }
                    }
                } else if filtered.isEmpty {
                    EmptyStateView(symbol: "tray", title: "Rien ici",
                                   message: "Aucun volume ne correspond à ce filtre sur \(storage).")
                } else {
                    GlassCard(padding: 12) {
                        VStack(spacing: 0) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                                contentRow(item)
                                if index < filtered.count - 1 { Divider1px().padding(.leading, 44) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 92)
            .animation(Motion.snap, value: filter)
        }
        .scrollIndicators(.hidden)
        .background(AuroraBackground(tint: Palette.sky, intensity: 0.45).ignoresSafeArea())
        .navigationTitle(storage)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showDownload = true } label: {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.ember)
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showDownload) {
            DownloadURLSheet(node: node, storage: storage) { await load() }
        }
        .alert("Supprimer ce volume ?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { item in
            Button("Supprimer", role: .destructive) {
                Task {
                    await app.perform("Suppression de \(item.filename)", node: node) { api in
                        try await api.deleteVolume(node: node, volid: item.volid)
                    }
                    await load()
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: { item in
            Text("\(item.filename) (\(Format.bytes(item.size))) sera définitivement effacé du stockage.")
        }
    }

    private func headerCard(_ resource: PVEResource) -> some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Occupé")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Palette.inkTertiary)
                    MetricText(value: Format.bytesParts(resource.disk).value,
                               unit: Format.bytesParts(resource.disk).unit,
                               size: 36, weight: .medium)
                }

                MeterBar(fraction: resource.diskFraction, height: 4)

                Divider1px()

                HStack(spacing: 0) {
                    HeroStat(value: Format.percent(resource.diskFraction), label: "occupé",
                             tint: Palette.load(resource.diskFraction) == Palette.rose
                                   ? Palette.rose : Palette.ink)
                    HeroStat(value: Format.bytes((resource.maxdisk ?? 0) - (resource.disk ?? 0)),
                             label: "libre", tint: Palette.mint)
                    HeroStat(value: "\(items.count)", label: "volumes", tint: Palette.inkSecondary)
                    HeroStat(value: resource.pluginType ?? "—", label: "type",
                             tint: Palette.inkSecondary)
                }
            }
        }
    }

    private func contentRow(_ item: PVEStorageContent) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol(for: item))
                .font(.system(size: 13))
                .foregroundStyle(tint(for: item))
                .frame(width: 16)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.filename)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Text(Format.bytes(item.size))
                        .font(.metric(12))
                        .foregroundStyle(Palette.inkTertiary)
                    if let vmid = item.vmid, vmid > 0 {
                        Text("· \(vmid)")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.inkTertiary)
                    }
                    if let date = item.date {
                        Text("· \(Format.ago(date))")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.inkTertiary)
                    }
                    if item.isProtected {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8.5))
                            .foregroundStyle(Palette.amber)
                    }
                }
                .lineLimit(1)
            }
            Spacer(minLength: 4)

            Menu {
                if item.content == "backup" {
                    Button {
                        Task {
                            await app.perform(item.isProtected ? "Protection retirée" : "Sauvegarde protégée",
                                              node: node) { api in
                                try await api.setVolumeProtection(node: node, volid: item.volid,
                                                                  isProtected: !item.isProtected)
                            }
                            await load()
                        }
                    } label: {
                        Label(item.isProtected ? "Retirer la protection" : "Protéger",
                              systemImage: item.isProtected ? "lock.open" : "lock")
                    }
                }
                Button {
                    UIPasteboard.general.string = item.volid
                    Haptics.success()
                    app.toast(.info, "Volume copié", detail: item.volid)
                } label: { Label("Copier le volid", systemImage: "doc.on.clipboard") }

                Button(role: .destructive) { pendingDelete = item } label: {
                    Label("Supprimer", systemImage: "trash")
                }
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

    private func symbol(for item: PVEStorageContent) -> String {
        switch item.content {
        case "backup": return "externaldrive.fill.badge.timemachine"
        case "iso": return "opticaldisc.fill"
        case "vztmpl": return "shippingbox.fill"
        case "images", "rootdir": return "internaldrive.fill"
        case "snippets": return "doc.text.fill"
        default: return "doc.fill"
        }
    }

    private func tint(for item: PVEStorageContent) -> Color {
        item.content == "backup" ? Palette.inkSecondary : Palette.inkTertiary
    }

    private func load() async {
        guard let api = app.client() else { return }
        loading = true
        defer { loading = false }
        do {
            items = try await api.storageContent(node: node, storage: storage)
            error = nil
        } catch let err as ProxmoxError {
            if case .cancelled = err { return }
            error = err.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Pulls an ISO or LXC template straight onto the storage from a URL — the one
/// upload path that works without shipping the file from the phone.
struct DownloadURLSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let node: String
    let storage: String
    var onDone: () async -> Void

    @State private var url = ""
    @State private var filename = ""
    @State private var content = "iso"
    @State private var busy = false

    private let contents = [StringOption("iso", "Image ISO"), StringOption("vztmpl", "Modèle LXC")]

    var body: some View {
        SheetScaffold(
            title: "Télécharger",
            subtitle: "Proxmox téléchargera le fichier directement depuis l'URL vers \(storage) — rien ne transite par votre iPhone.",
            confirmLabel: "Télécharger",
            confirmEnabled: !url.isEmpty && !filename.isEmpty,
            busy: busy,
            onConfirm: start
        ) {
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    ProxynField(label: "URL", placeholder: "https://…/debian.iso", text: $url,
                                symbol: "link", keyboard: .URL, monospaced: true)
                    ProxynField(label: "Nom de fichier", placeholder: "debian-12.iso", text: $filename,
                                symbol: "doc.fill", monospaced: true)
                    PickerRow(title: "Type", symbol: "square.stack.3d.up.fill", options: contents,
                              label: \.title,
                              selection: Binding(
                                get: { contents.first { $0.value == content } ?? contents[0] },
                                set: { content = $0.value }))
                }
            }
        }
        .onChange(of: url) { _, value in
            if filename.isEmpty, let last = value.split(separator: "/").last, last.contains(".") {
                filename = String(last)
            }
        }
    }

    private func start() {
        busy = true
        Task {
            await app.perform("Téléchargement de \(filename)", node: node) { api in
                try await api.downloadToStorage(node: node, storage: storage, url: url,
                                                content: content, filename: filename)
            }
            await onDone()
            busy = false
            dismiss()
        }
    }
}
