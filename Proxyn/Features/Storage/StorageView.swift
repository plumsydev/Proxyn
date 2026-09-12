import SwiftUI

struct StorageView: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()

    private var snapshot: ClusterSnapshot { model.snapshot }

    /// Shared storage first, then one section per node.
    private var groups: [(title: String, storages: [PVEResource])] {
        let shared = snapshot.uniqueStorages.filter(\.shared)
        let local = Dictionary(grouping: snapshot.uniqueStorages.filter { !$0.shared }) { $0.node ?? "—" }
        var out: [(String, [PVEResource])] = []
        if !shared.isEmpty { out.append(("Shared", shared)) }
        for node in local.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            out.append((node, local[node] ?? []))
        }
        return out
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if snapshot.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if snapshot.uniqueStorages.isEmpty {
                    ContentUnavailableView("No Storage", systemImage: "internaldrive",
                                           description: Text("This account can't see any storage."))
                } else {
                    Section {
                        UsageRow(title: "Used",
                                 value: Format.bytes(snapshot.storageUsed),
                                 detail: "of \(Format.bytes(snapshot.storageTotal))",
                                 fraction: snapshot.aggregateStorage)
                            .padding(.vertical, 4)
                    } footer: {
                        Text("\(Format.bytes(snapshot.storageTotal - snapshot.storageUsed)) free across \(snapshot.uniqueStorages.count) storages. Shared storage is counted once.")
                    }

                    ForEach(groups, id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.storages) { storage in
                                NavigationLink(value: Route.storage(node: storage.node ?? "",
                                                                    storage: storage.storage ?? storage.displayName)) {
                                    StorageRow(storage: storage, showsNode: false)
                                }
                            }
                        }
                    }
                }
            }
            .proxynList()
            .navigationTitle("Storage")
            .refreshable { await model.refresh() }
            .proxynDestinations()
            .handlesDeepLinks(for: .storage, path: $path)
        }
    }
}
