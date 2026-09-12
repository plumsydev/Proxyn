import SwiftUI

struct GuestsView: View {
    @Environment(AppModel.self) private var model
    var embedded: Bool = false

    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var filter: GuestFilter = .all
    @State private var sort: GuestSort = .vmid
    @State private var groupByNode = false

    enum GuestFilter: Int, CaseIterable, Identifiable, Hashable {
        case all, running, stopped, vms, containers
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .all: return "Tout"
            case .running: return "Actives"
            case .stopped: return "Arrêtées"
            case .vms: return "VM"
            case .containers: return "LXC"
            }
        }
    }

    enum GuestSort: String, CaseIterable, Identifiable, Hashable {
        case vmid, name, cpu, memory, uptime
        var id: String { rawValue }
        var title: String {
            switch self {
            case .vmid: return "ID"
            case .name: return "Nom"
            case .cpu: return "CPU"
            case .memory: return "RAM"
            case .uptime: return "Uptime"
            }
        }
        var symbol: String {
            switch self {
            case .vmid: return "number"
            case .name: return "textformat.abc"
            case .cpu: return "cpu"
            case .memory: return "memorychip"
            case .uptime: return "clock"
            }
        }
    }

    private var filtered: [PVEResource] {
        var items = model.snapshot.guests
        if !model.settings.showTemplates { items = items.filter { !$0.isTemplate } }

        switch filter {
        case .all: break
        case .running: items = items.filter { $0.state.isUp }
        case .stopped: items = items.filter { !$0.state.isUp }
        case .vms: items = items.filter { $0.type == .qemu }
        case .containers: items = items.filter { $0.type == .lxc }
        }

        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            items = items.filter { guest in
                guest.displayName.lowercased().contains(q)
                || String(guest.vmid ?? 0).contains(q)
                || (guest.node ?? "").lowercased().contains(q)
                || guest.tags.contains { $0.lowercased().contains(q) }
                || (guest.pool ?? "").lowercased().contains(q)
            }
        }

        switch sort {
        case .vmid: items.sort { ($0.vmid ?? 0) < ($1.vmid ?? 0) }
        case .name: items.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .cpu: items.sort { $0.cpuFraction > $1.cpuFraction }
        case .memory: items.sort { $0.memFraction > $1.memFraction }
        case .uptime: items.sort { ($0.uptime ?? 0) > ($1.uptime ?? 0) }
        }

        // Favourites always float to the top.
        let favorites = items.filter { model.isFavorite($0) }
        return favorites + items.filter { !model.isFavorite($0) }
    }

    private var grouped: [(node: String, guests: [PVEResource])] {
        Dictionary(grouping: filtered) { $0.node ?? "—" }
            .map { (node: $0.key, guests: $0.value) }
            .sorted { $0.node < $1.node }
    }

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                NavigationStack(path: $path) {
                    content.proxynDestinations()
                }
            }
        }
    }

    private var content: some View {
        ScreenScaffold(
            title: "Instances",
            eyebrow: "\(model.snapshot.runningGuests.count) actives · \(model.snapshot.guests.filter { !$0.isTemplate }.count) au total",
            statusColor: Palette.mint,
            statusPulsing: !model.snapshot.runningGuests.isEmpty,
            onRefresh: { await model.refresh() },
            trailing: {
                CircleIconButton(symbol: groupByNode ? "rectangle.3.group" : "list.bullet") {
                    withAnimation(Motion.snap) { groupByNode.toggle() }
                }
                Menu {
                    Picker("Trier par", selection: $sort) {
                        ForEach(GuestSort.allCases) { option in
                            Label(option.title, systemImage: option.symbol).tag(option)
                        }
                    }
                    Divider()
                    Toggle("Afficher les modèles", isOn: Binding(
                        get: { model.settings.showTemplates },
                        set: { value in model.update { $0.showTemplates = value } }))
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
            },
            content: {
                SearchField(text: $query, placeholder: "Nom, ID, nœud, étiquette…")

                SegmentedRail(items: GuestFilter.allCases, label: \.title, selection: $filter)

                if filtered.isEmpty {
                    EmptyStateView(
                        symbol: query.isEmpty ? "cube.transparent" : "magnifyingglass",
                        title: query.isEmpty ? "Aucune instance" : "Aucun résultat",
                        message: query.isEmpty
                        ? "Ce cluster ne contient aucune VM ni conteneur correspondant au filtre."
                        : "Aucune instance ne correspond à « \(query) ».")
                } else if groupByNode {
                    ForEach(grouped, id: \.node) { group in
                        VStack(alignment: .leading, spacing: 9) {
                            SectionLabel(group.node, trailing: "\(group.guests.count)")
                            guestCard(group.guests)
                        }
                    }
                } else {
                    guestCard(filtered)
                }
            })
    }

    private func guestCard(_ guests: [PVEResource]) -> some View {
        GlassCard(padding: 0) {
            RowStack(data: guests, separatorInset: Metrics.rowInset + 18) { guest in
                if let ref = GuestRef(resource: guest) {
                    NavigationLink(value: Route.guest(ref: ref, name: guest.displayName)) {
                        GuestRow(guest: guest,
                                 history: model.history(forGuest: guest.id).cpu,
                                 compact: model.settings.compactGuestRows,
                                 showsNode: !groupByNode)
                            .padding(.horizontal, Metrics.rowInset)
                    }
                    .buttonStyle(.pressable)
                    .contextMenu { contextMenu(for: guest, ref: ref) }
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for guest: PVEResource, ref: GuestRef) -> some View {
        Button {
            model.toggleFavorite(guest)
        } label: {
            Label(model.isFavorite(guest) ? "Retirer des épinglées" : "Épingler",
                  systemImage: model.isFavorite(guest) ? "pin.slash" : "pin")
        }
        Divider()
        ForEach(GuestPowerAction.allCases.filter { $0.isAvailable(for: guest.state, kind: guest.type) }) { action in
            Button(role: action.isDestructive ? .destructive : nil) {
                Task { await model.power(ref, action: action, name: guest.displayName) }
            } label: {
                Label(action.label, systemImage: action.symbol)
            }
        }
    }
}
