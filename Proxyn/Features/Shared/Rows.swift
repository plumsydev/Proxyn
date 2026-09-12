import SwiftUI

/// Guest row: state, name, identity, and the two figures that matter.
struct GuestRow: View {
    var guest: PVEResource
    var showsNode: Bool = true
    var isFavorite: Bool = false

    @Environment(\.dynamicTypeSize) private var typeSize

    private var identity: String {
        var parts = ["\(guest.type.label) \(guest.vmid.map(String.init) ?? "—")"]
        if showsNode, let node = guest.node { parts.append(node) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))

        layout {
            HStack(spacing: 12) {
                StatusDot(state: guest.state)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(guest.displayName)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        if isFavorite {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Pinned")
                        }
                        if let lock = guest.lock, !lock.isEmpty {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(Palette.warning)
                                .accessibilityLabel("Locked: \(lock)")
                        }
                    }
                    Text(guest.isTemplate ? "\(identity) · Template" : identity)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)

            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }

            if guest.state.isUp {
                VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                    Text(Format.percent(guest.cpuFraction))
                        .font(.metricBody)
                        .foregroundStyle(guest.cpuFraction >= 0.9 ? Palette.warning : .primary)
                        .contentTransition(.numericText())
                    Text(Format.bytes(guest.mem))
                        .font(.metricCaption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("CPU \(Format.percent(guest.cpuFraction)), memory \(Format.bytes(guest.mem))")
            } else if !guest.isTemplate {
                Text(guest.state.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct NodeRow: View {
    var node: PVEResource
    var history: [Double]

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(state: node.state)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(node.state.isUp ? "up \(Format.uptime(node.uptime))" : node.state.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            if node.state.isUp {
                if history.count > 2 {
                    Sparkline(values: history, tint: Palette.accent)
                        .frame(width: 44, height: 18)
                }
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.percent(node.cpuFraction))
                        .font(.metricBody)
                        .contentTransition(.numericText())
                    Text("\(Format.percent(node.memFraction)) mem")
                        .font(.metricCaption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("CPU \(Format.percent(node.cpuFraction)), memory \(Format.percent(node.memFraction))")
            }
        }
        .padding(.vertical, 2)
    }
}

struct TaskRow: View {
    var task: PVETask
    var showsUser: Bool = true

    private var subtitle: String {
        [task.pveTargetId.flatMap { $0.isEmpty ? nil : $0 },
         task.node,
         showsUser ? task.user : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if task.isRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: task.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(task.succeeded ? Palette.positive : Palette.critical)
                }
            }
            .frame(width: 20)
            .accessibilityLabel(task.isRunning ? "Running" : (task.succeeded ? "Succeeded" : "Failed"))

            VStack(alignment: .leading, spacing: 2) {
                Text(Format.taskType(task.type))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            Text(task.isRunning ? Format.duration(task.duration) : Format.ago(task.end ?? task.start))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 2)
    }
}

/// Storage row. Every piece of text gets its own line or a guaranteed share of
/// one, so long storage names and large figures can't push anything off-screen.
struct StorageRow: View {
    var storage: PVEResource
    /// Storages such as `local` exist once per node; outside a per-node
    /// grouping the node is what tells them apart.
    var showsNode: Bool = true

    private var detail: String {
        var parts = ["\(Format.bytes(storage.disk)) of \(Format.bytes(storage.maxdisk))"]
        if let type = storage.pluginType { parts.append(type.uppercased()) }
        if showsNode {
            if storage.shared { parts.append("shared") } else if let node = storage.node { parts.append(node) }
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(storage.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(Format.percent(storage.diskFraction))
                    .font(.metricBody)
                    .foregroundStyle(storage.diskFraction >= 0.9 ? Palette.critical : .primary)
                    .fixedSize()
            }
            CapacityBar(fraction: storage.diskFraction)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(storage.displayName)
        .accessibilityValue("\(Format.percent(storage.diskFraction)) used, \(detail)")
    }
}

struct AlertRow: View {
    var alert: ClusterAlert

    private var tint: Color {
        switch alert.level {
        case .critical: return Palette.critical
        case .warning: return Palette.warning
        case .info: return .secondary
        }
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.body.weight(.medium))
                Text(alert.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: alert.symbol)
                .foregroundStyle(tint)
        }
        .padding(.vertical, 2)
    }
}

/// Section header with a trailing navigation link.
struct SectionHeader: View {
    var title: String
    var linkTitle: String
    var route: Route

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            NavigationLink(value: route) {
                Text(linkTitle)
                    .font(.subheadline)
            }
        }
    }
}
