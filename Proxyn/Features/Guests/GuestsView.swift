import SwiftUI

struct GuestsView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            GuestListContent()
                .proxynDestinations()
                .handlesDeepLinks(for: .guests, path: $path)
        }
    }
}

/// The searchable guest list. Used as the Guests tab and pushed from
/// Overview's "See All".
struct GuestListContent: View {
    @Environment(AppModel.self) private var model

    @State private var query = ""
    @State private var status: StatusFilter = .all
    @State private var kind: KindFilter = .all
    @State private var sort: SortOrder = .id
    @AppStorage("guests.groupByNode") private var groupByNode = false
    @State private var pendingPower: PendingPowerAction?

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "All", running = "Running", stopped = "Stopped"
        var id: String { rawValue }
    }

    enum KindFilter: String, CaseIterable, Identifiable {
        case all = "All Types", vm = "Virtual Machines", container = "Containers"
        var id: String { rawValue }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case id = "ID", name = "Name", cpu = "CPU", memory = "Memory"
        var id: String { rawValue }
    }

    private var snapshot: ClusterSnapshot { model.snapshot }

    private var filtered: [PVEResource] {
        var items = snapshot.guests
        if !model.settings.showTemplates { items.removeAll(where: \.isTemplate) }

        switch status {
        case .all: break
        case .running: items = items.filter { $0.state.isUp }
        case .stopped: items = items.filter { !$0.state.isUp }
        }
        switch kind {
        case .all: break
        case .vm: items = items.filter { $0.type == .qemu }
        case .container: items = items.filter { $0.type == .lxc }
        }

        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            items = items.filter { guest in
                guest.displayName.localizedCaseInsensitiveContains(q)
                    || String(guest.vmid ?? 0).hasPrefix(q)
                    || (guest.node ?? "").localizedCaseInsensitiveContains(q)
                    || (guest.pool ?? "").localizedCaseInsensitiveContains(q)
                    || guest.tags.contains { $0.localizedCaseInsensitiveContains(q) }
            }
        }

        switch sort {
        case .id: items.sort { ($0.vmid ?? 0) < ($1.vmid ?? 0) }
        case .name: items.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .cpu: items.sort { $0.cpuFraction > $1.cpuFraction }
        case .memory: items.sort { ($0.mem ?? 0) > ($1.mem ?? 0) }
        }
        return items
    }

    var body: some View {
        let items = filtered
        let pinned = items.filter { model.isFavorite($0) }
        let others = items.filter { !model.isFavorite($0) }

        List {
            Section {
                Picker("Status", selection: $status) {
                    ForEach(StatusFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if items.isEmpty {
                emptyState
            } else {
                if !pinned.isEmpty {
                    Section("Pinned") {
                        ForEach(pinned) { row(for: $0) }
                    }
                }
                if groupByNode {
                    ForEach(Dictionary(grouping: others) { $0.node ?? "—" }.sorted { $0.key < $1.key },
                            id: \.key) { node, guests in
                        Section(node) {
                            ForEach(guests) { row(for: $0, showsNode: false) }
                        }
                    }
                } else if !others.isEmpty {
                    Section {
                        ForEach(others) { row(for: $0) }
                    } footer: {
                        Text(countSummary(items))
                    }
                }
            }
        }
        .proxynList()
        .navigationTitle("Guests")
        .searchable(text: $query, prompt: "Name, ID, node or tag")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { optionsMenu }
        }
        .refreshable { await model.refresh() }
        .powerConfirmation($pendingPower)
        .animation(Motion.standard, value: status)
        .animation(Motion.standard, value: kind)
    }

    private func countSummary(_ items: [PVEResource]) -> String {
        let running = items.filter { $0.state.isUp }.count
        return "\(items.count) guest\(items.count == 1 ? "" : "s") · \(running) running"
    }

    @ViewBuilder
    private var emptyState: some View {
        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if snapshot.isEmpty {
            HStack { Spacer(); ProgressView(); Spacer() }
        } else {
            ContentUnavailableView("No Guests", systemImage: "square.stack.3d.up",
                                   description: Text("No virtual machines or containers match these filters."))
        }
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Type", selection: $kind) {
                ForEach(KindFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Sort By", selection: $sort) {
                ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            Divider()
            Toggle("Group by Node", isOn: $groupByNode)
            Toggle("Show Templates", isOn: Binding(
                get: { model.settings.showTemplates },
                set: { value in model.update { $0.showTemplates = value } }))
        } label: {
            Label("Filter and Sort",
                  systemImage: kind == .all
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill")
        }
    }

    @ViewBuilder
    private func row(for guest: PVEResource, showsNode: Bool = true) -> some View {
        if let ref = GuestRef(resource: guest) {
            NavigationLink(value: Route.guest(ref: ref, name: guest.displayName)) {
                GuestRow(guest: guest, showsNode: showsNode, isFavorite: model.isFavorite(guest))
            }
            .swipeActions(edge: .leading) {
                if let primary = primaryAction(for: guest) {
                    Button(primary.label, systemImage: primary.symbol) {
                        Task { await model.power(ref, action: primary, name: guest.displayName) }
                    }
                    .tint(Palette.positive)
                }
            }
            .swipeActions(edge: .trailing) {
                Button(model.isFavorite(guest) ? "Unpin" : "Pin",
                       systemImage: model.isFavorite(guest) ? "pin.slash" : "pin") {
                    model.toggleFavorite(guest)
                }
                .tint(Palette.accent)
            }
            .contextMenu {
                Button(model.isFavorite(guest) ? "Unpin" : "Pin",
                       systemImage: model.isFavorite(guest) ? "pin.slash" : "pin") {
                    model.toggleFavorite(guest)
                }
                Divider()
                ForEach(GuestPowerAction.allCases.filter { $0.isAvailable(for: guest.state, kind: guest.type) }) { action in
                    Button(action.label, systemImage: action.symbol,
                           role: action.isDestructive ? .destructive : nil) {
                        request(action, ref: ref, name: guest.displayName)
                    }
                }
            }
        }
    }

    /// Swiping only ever starts or resumes a guest — an accidental swipe must
    /// never take a running machine down. Everything else goes through a
    /// confirmation.
    private func primaryAction(for guest: PVEResource) -> GuestPowerAction? {
        guard !guest.isTemplate else { return nil }
        if guest.state.isPaused { return .resume }
        return guest.state.isUp ? nil : .start
    }

    private func request(_ action: GuestPowerAction, ref: GuestRef, name: String) {
        if model.settings.confirmDestructiveActions, action.requiresConfirmation {
            pendingPower = PendingPowerAction(ref: ref, action: action, name: name)
        } else {
            Task { await model.power(ref, action: action, name: name) }
        }
    }
}

struct PendingPowerAction: Identifiable {
    var ref: GuestRef
    var action: GuestPowerAction
    var name: String
    var id: String { "\(ref.id)-\(action.rawValue)" }
}

extension GuestPowerAction {
    var requiresConfirmation: Bool { self != .start && self != .resume }
}

extension View {
    /// Shared confirmation for guest power actions.
    func powerConfirmation(_ pending: Binding<PendingPowerAction?>) -> some View {
        modifier(PowerConfirmation(pending: pending))
    }
}

private struct PowerConfirmation: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var pending: PendingPowerAction?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            pending.map { "\($0.action.label) \($0.name)?" } ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { item in
            Button(item.action.label, role: item.action.isDestructive || item.action == .shutdown ? .destructive : nil) {
                Task { await model.power(item.ref, action: item.action, name: item.name) }
            }
        } message: { item in
            Text(item.action.confirmationMessage)
        }
    }
}
