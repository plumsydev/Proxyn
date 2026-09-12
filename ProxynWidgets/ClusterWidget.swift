import SwiftUI
import WidgetKit

struct ClusterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProxynCluster", provider: SnapshotProvider()) { entry in
            ClusterWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetLocale()
                .widgetURL(DeepLink.overview.url)
        }
        .configurationDisplayName("Cluster")
        .description("CPU, memory and storage across your Proxmox cluster.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct ClusterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SnapshotEntry

    var body: some View {
        if let s = entry.snapshot {
            switch family {
            case .systemSmall: small(s)
            case .systemMedium: medium(s)
            case .systemLarge: large(s)
            case .accessoryCircular: circular(s)
            case .accessoryRectangular: rectangular(s)
            case .accessoryInline: inline(s)
            default: small(s)
            }
        } else {
            WidgetEmptyState(symbol: "server.rack", message: "Open Proxyn to add a server.")
        }
    }

    private func header(_ s: WidgetSnapshot) -> some View {
        WidgetHeader(symbol: "gauge.with.dots.needle.33percent", title: s.serverName) {
            if s.alerts > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(Palette.warning)
            } else if entry.isStale {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Home Screen

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(s)
            Spacer(minLength: 4)
            WidgetFigure(value: Format.percent(s.cpu), caption: "CPU · \(Int(s.cores)) cores")
            WidgetSparkline(values: s.cpuHistory)
                .frame(height: 22)
                .padding(.vertical, 6)
            HStack {
                Text("RAM \(Format.percent(s.memory))")
                Spacer(minLength: 4)
                Text("\(s.runningGuests.count) running")
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private func medium(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(s)
            Spacer(minLength: 6)
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetFigure(value: Format.percent(s.cpu), caption: "CPU · \(Int(s.cores)) cores")
                    WidgetSparkline(values: s.cpuHistory)
                        .frame(height: 24)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    WidgetMeter(label: "Memory", value: Format.percent(s.memory), fraction: s.memory)
                    WidgetMeter(label: "Storage", value: Format.percent(s.storage), fraction: s.storage)
                    Text("\(s.nodesOnline)/\(s.nodes.count) nodes · \(s.runningGuests.count) running")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func large(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(s)

            HStack(alignment: .bottom, spacing: 16) {
                WidgetFigure(value: Format.percent(s.cpu), caption: "CPU · \(Int(s.cores)) cores", size: 40)
                    .fixedSize()
                WidgetSparkline(values: s.cpuHistory)
                    .frame(height: 46)
            }

            HStack(spacing: 16) {
                WidgetMeter(label: "Memory", value: Format.bytes(s.memoryUsed), fraction: s.memory)
                WidgetMeter(label: "Storage", value: Format.bytes(s.storageUsed), fraction: s.storage)
            }

            Divider()

            Text("Busiest guests")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(s.busiestGuests.prefix(5)) { guest in
                    Link(destination: DeepLink.guest(vmid: guest.vmid).url) {
                        HStack(spacing: 8) {
                            WidgetStateDot(running: true, size: 6)
                            Text(guest.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            WidgetBar(fraction: guest.cpu, tint: Palette.accent, height: 3)
                                .frame(width: 44)
                            Text(Format.percent(guest.cpu))
                                .font(.caption)
                                .monospacedDigit()
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                }
                if s.runningGuests.isEmpty {
                    Text("No guests are running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Text("\(s.nodesOnline) of \(s.nodes.count) nodes online")
                Spacer(minLength: 12)
                WidgetUpdatedLabel(date: s.capturedAt)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Lock Screen

    private func circular(_ s: WidgetSnapshot) -> some View {
        Gauge(value: max(0, min(1, s.cpu))) {
            Text("CPU")
        } currentValueLabel: {
            Text("\(Int((s.cpu * 100).rounded()))")
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }

    private func rectangular(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(s.serverName)
                .font(.headline)
                .widgetAccentable()
                .lineLimit(1)
            HStack(spacing: 8) {
                Text("CPU \(Format.percent(s.cpu))")
                Text("RAM \(Format.percent(s.memory))")
            }
            .monospacedDigit()
            Text("\(s.runningGuests.count) of \(s.guests.count) running")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func inline(_ s: WidgetSnapshot) -> some View {
        Label("\(s.serverName) · CPU \(Format.percent(s.cpu))", systemImage: "server.rack")
    }
}
