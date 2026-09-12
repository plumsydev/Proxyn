import SwiftUI

struct NodesView: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScreenScaffold(
                title: "Nœuds",
                eyebrow: "\(model.snapshot.onlineNodes.count) en ligne sur \(model.snapshot.nodes.count)",
                statusColor: model.snapshot.offlineNodes.isEmpty ? Palette.mint : Palette.rose,
                statusPulsing: model.snapshot.offlineNodes.isEmpty,
                tint: Palette.sky,
                onRefresh: { await model.refresh() }
            ) {
                if model.snapshot.nodes.isEmpty {
                    EmptyStateView(symbol: "server.rack", title: "Aucun nœud",
                                   message: "Le serveur n'a renvoyé aucun nœud. Vérifiez les permissions du compte utilisé.")
                } else {
                    VStack(spacing: Metrics.stackSpacing) {
                        ForEach(model.snapshot.nodes) { node in
                            NavigationLink(value: Route.node(node.displayName)) {
                                NodeCard(node: node, history: model.history(forNode: node.displayName))
                            }
                            .buttonStyle(.pressable)
                            .settleOnScroll()
                        }
                    }

                    if let cluster = model.snapshot.clusterNodes.first(where: { $0.type == "cluster" }) {
                        clusterCard(cluster)
                    }
                }
            }
            .proxynDestinations()
        }
    }

    private func clusterCard(_ cluster: PVEClusterNodeStatus) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("Cluster")
                    .padding(.bottom, 6)
                DetailRow(label: "Nom", value: cluster.name)
                DetailRow(label: "Quorum",
                          value: (cluster.quorate ?? false) ? "établi" : "perdu",
                          valueColor: (cluster.quorate ?? false) ? Palette.mint : Palette.rose)
                DetailRow(label: "Membres", value: "\(cluster.nodes ?? 0)")
                if let version = cluster.version {
                    DetailRow(label: "Version de configuration", value: "\(version)")
                }
            }
        }
    }
}

/// Full-width node card.
struct NodeCard: View {
    var node: PVEResource
    var history: LiveHistory

    var body: some View {
        GlassCard(padding: 17, tint: node.state.isUp ? nil : Palette.rose) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 9) {
                    StatusPip(color: Palette.state(node.state),
                              pulsing: node.state.isUp, size: 7,
                              hollow: !node.state.isUp)
                    Text(node.displayName)
                        .font(.system(size: 18, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    Text(node.state.isUp
                         ? "\(Int(node.maxcpu ?? 0)) cœurs · \(Format.uptime(node.uptime))"
                         : node.state.label.lowercased())
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.inkTertiary)
                }

                if history.cpu.count > 2 {
                    Sparkline(values: history.cpu, tint: Palette.ember, filled: true)
                        .frame(height: 34)
                }

                VStack(spacing: 15) {
                    VitalRow(label: "Processeur",
                             value: Format.percent(node.cpuFraction), unit: "%",
                             fraction: node.cpuFraction,
                             tint: Palette.ember, valueSize: 19)
                    LabeledMeter(label: "Mémoire", fraction: node.memFraction,
                                 detail: "\(Format.bytes(node.mem)) / \(Format.bytes(node.maxmem))")
                    LabeledMeter(label: "Racine", fraction: node.diskFraction,
                                 detail: "\(Format.bytes(node.disk)) / \(Format.bytes(node.maxdisk))")
                }
            }
        }
    }
}
