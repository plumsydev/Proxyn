import SwiftUI

struct NodesView: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()

    private var snapshot: ClusterSnapshot { model.snapshot }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if snapshot.isEmpty {
                    emptyState
                } else {
                    Section {
                        ForEach(snapshot.nodes) { node in
                            NavigationLink(value: Route.node(node.displayName)) {
                                NodeCardRow(node: node, history: model.history(forNode: node.displayName))
                            }
                        }
                    } footer: {
                        Text("\(snapshot.onlineNodes.count) of \(snapshot.nodes.count) online · \(Int(snapshot.totalCores)) cores · \(Format.bytes(snapshot.memoryTotal)) memory")
                    }

                    if let cluster = snapshot.clusterNodes.first(where: { $0.type == "cluster" }) {
                        Section("Cluster") {
                            LabeledContent("Name", value: cluster.name)
                            LabeledContent("Quorum") {
                                Text((cluster.quorate ?? false) ? "Established" : "Lost")
                                    .foregroundStyle((cluster.quorate ?? false) ? Palette.positive : Palette.critical)
                            }
                            LabeledContent("Members", value: "\(cluster.nodes ?? snapshot.nodes.count)")
                            if let version = snapshot.version?.version {
                                LabeledContent("Proxmox VE", value: version)
                            }
                        }
                    }
                }
            }
            .proxynList()
            .navigationTitle("Nodes")
            .refreshable { await model.refresh() }
            .proxynDestinations()
            .handlesDeepLinks(for: .nodes, path: $path)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.connection == .connecting {
            HStack { Spacer(); ProgressView(); Spacer() }
        } else {
            ContentUnavailableView("No Nodes", systemImage: "server.rack",
                                   description: Text("Nothing to show yet. Check the connection on the Overview tab."))
        }
    }
}

/// Richer node row for the Nodes tab: identity, then the three capacities.
private struct NodeCardRow: View {
    var node: PVEResource
    var history: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                StatusDot(state: node.state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(node.state.isUp
                         ? "\(Int(node.maxcpu ?? 0)) cores · up \(Format.uptime(node.uptime))"
                         : node.state.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                if node.state.isUp, history.count > 2 {
                    Sparkline(values: history, tint: Palette.accent)
                        .frame(width: 72, height: 26)
                }
            }

            if node.state.isUp {
                VStack(spacing: 10) {
                    UsageRow(title: "CPU", value: Format.percent(node.cpuFraction), detail: nil,
                             fraction: node.cpuFraction, tint: Palette.accent)
                    UsageRow(title: "Memory", value: Format.bytes(node.mem),
                             detail: "of \(Format.bytes(node.maxmem))", fraction: node.memFraction)
                    UsageRow(title: "Root disk", value: Format.bytes(node.disk),
                             detail: "of \(Format.bytes(node.maxdisk))", fraction: node.diskFraction)
                }
                .font(.subheadline)
                .padding(.leading, 20)
            }
        }
        .padding(.vertical, 6)
    }
}
