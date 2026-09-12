import SwiftUI
import WidgetKit

// MARK: - Nodes

struct NodesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProxynNodes", provider: SnapshotProvider()) { entry in
            NodesWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetLocale()
                .widgetURL(DeepLink.overview.url)
        }
        .configurationDisplayName("Nodes")
        .description("CPU and memory for every node in the cluster.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct NodesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SnapshotEntry

    var body: some View {
        if let s = entry.snapshot, !s.nodes.isEmpty {
            let limit = family == .systemLarge ? 8 : 3
            VStack(alignment: .leading, spacing: 10) {
                WidgetHeader(symbol: "server.rack", title: "Nodes") {
                    Text("\(s.nodesOnline)/\(s.nodes.count) online")
                        .font(.caption2)
                        .foregroundStyle(s.nodesOnline == s.nodes.count ? Color.secondary : Palette.critical)
                }

                Spacer(minLength: 0)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: family == .systemLarge ? 12 : 8) {
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        Text("CPU")
                        Text("Memory")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                    ForEach(s.nodes.prefix(limit)) { node in
                        GridRow {
                            Link(destination: DeepLink.node(node.name).url) {
                                HStack(spacing: 6) {
                                    WidgetStateDot(running: node.online, size: 6)
                                    Text(node.name)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                }
                            }
                            if node.online {
                                NodeValue(fraction: node.cpu, tint: Palette.accent)
                                NodeValue(fraction: node.memory)
                            } else {
                                Text("Offline")
                                    .font(.caption)
                                    .foregroundStyle(Palette.critical)
                                    .gridCellColumns(2)
                            }
                        }
                    }
                }

                if s.nodes.count > limit {
                    Text("+\(s.nodes.count - limit) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if family == .systemLarge {
                    HStack {
                        Text("\(Int(s.cores)) cores · \(Format.bytes(s.memoryTotal)) memory")
                        Spacer(minLength: 4)
                        WidgetUpdatedLabel(date: s.capturedAt)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        } else {
            WidgetEmptyState(symbol: "server.rack", message: "Open Proxyn to add a server.")
        }
    }
}

private struct NodeValue: View {
    var fraction: Double
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 6) {
            WidgetBar(fraction: fraction, tint: tint, height: 3)
            Text(Format.percent(fraction))
                .font(.caption)
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }
    }
}

// MARK: - Storage

struct StorageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProxynStorage", provider: SnapshotProvider()) { entry in
            StorageWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetLocale()
        }
        .configurationDisplayName("Storage")
        .description("How full your storages are, fullest first.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StorageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SnapshotEntry

    var body: some View {
        if let s = entry.snapshot, let fullest = s.fullestStorages.first {
            if family == .systemSmall {
                small(fullest)
                    .widgetURL(DeepLink.storage(node: fullest.node, storage: fullest.name).url)
            } else {
                medium(s)
            }
        } else {
            WidgetEmptyState(symbol: "internaldrive", message: "Open Proxyn to add a server.")
        }
    }

    private func label(_ storage: WidgetStorage) -> String {
        storage.shared ? storage.type.uppercased() : "\(storage.type.uppercased()) · \(storage.node)"
    }

    private func small(_ storage: WidgetStorage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(symbol: "internaldrive", title: "Storage")
            Spacer(minLength: 4)
            Text(storage.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            WidgetFigure(value: Format.percent(storage.fraction),
                         caption: "\(Format.bytes(storage.free)) free",
                         size: 32,
                         color: storage.fraction >= 0.9 ? Palette.critical : .primary)
            WidgetBar(fraction: storage.fraction)
                .padding(.top, 8)
        }
    }

    private func medium(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(symbol: "internaldrive", title: "Storage") {
                Text("\(Format.bytes(s.storageUsed)) of \(Format.bytes(s.storageTotal))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            ForEach(s.fullestStorages.prefix(3)) { storage in
                Link(destination: DeepLink.storage(node: storage.node, storage: storage.name).url) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(storage.name)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Text(label(storage))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(Format.percent(storage.fraction))
                                .font(.caption.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(storage.fraction >= 0.9 ? Palette.critical : .primary)
                        }
                        WidgetBar(fraction: storage.fraction, height: 3)
                    }
                }
            }
        }
    }
}

// MARK: - Activity

struct ActivityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProxynActivity", provider: SnapshotProvider()) { entry in
            ActivityWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetLocale()
                .widgetURL(DeepLink.activity.url)
        }
        .configurationDisplayName("Activity")
        .description("Running tasks and anything that failed recently.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ActivityWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SnapshotEntry

    var body: some View {
        if let s = entry.snapshot {
            if family == .systemSmall { small(s) } else { medium(s) }
        } else {
            WidgetEmptyState(symbol: "list.bullet.rectangle", message: "Open Proxyn to add a server.")
        }
    }

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(symbol: "list.bullet.rectangle", title: "Activity")
            Spacer(minLength: 4)

            if !s.runningTasks.isEmpty {
                WidgetFigure(value: "\(s.runningTasks.count)",
                             caption: s.runningTasks.count == 1 ? "task running" : "tasks running")
                Text(s.runningTasks.first.map(describe) ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 6)
            } else if !s.recentFailures.isEmpty {
                WidgetFigure(value: "\(s.recentFailures.count)",
                             caption: "failed today", color: Palette.critical)
                Text(s.recentFailures.first.map(describe) ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 6)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(Palette.positive)
                    .widgetAccentable()
                Text("All quiet")
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
                if let last = s.tasks.first {
                    Text(describe(last))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private func medium(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(symbol: "list.bullet.rectangle", title: "Activity") {
                if !s.runningTasks.isEmpty {
                    Text("\(s.runningTasks.count) running")
                        .font(.caption2)
                        .foregroundStyle(Palette.accent)
                } else if !s.recentFailures.isEmpty {
                    Text("\(s.recentFailures.count) failed")
                        .font(.caption2)
                        .foregroundStyle(Palette.critical)
                }
            }

            if s.tasks.isEmpty {
                Spacer(minLength: 0)
                Label("No recent tasks", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 7) {
                    ForEach(s.tasks.prefix(4)) { task in
                        HStack(spacing: 8) {
                            Image(systemName: task.isRunning ? "circle.dotted"
                                  : (task.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill"))
                                .font(.caption)
                                .foregroundStyle(task.isRunning ? Palette.accent
                                                 : (task.succeeded ? Palette.positive : Palette.critical))
                                .frame(width: 14)
                            Text(task.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Text([task.target, task.node].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if !task.isRunning {
                                Text(Format.ago(task.end ?? task.start))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func describe(_ task: WidgetTask) -> String {
        [task.title, task.target.isEmpty ? nil : task.target].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Bundle

@main
struct ProxynWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClusterWidget()
        GuestWidget()
        NodesWidget()
        StorageWidget()
        ActivityWidget()
    }
}
