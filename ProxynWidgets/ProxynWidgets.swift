import WidgetKit
import SwiftUI

// MARK: - Timeline

struct ClusterEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
    var isStale: Bool
}

struct ClusterProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClusterEntry {
        ClusterEntry(date: Date(), snapshot: .placeholder, isStale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (ClusterEntry) -> Void) {
        let cached = SharedSnapshotStore.load() ?? .placeholder
        completion(ClusterEntry(date: Date(), snapshot: cached, isStale: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClusterEntry>) -> Void) {
        Task {
            let cached = SharedSnapshotStore.load()
            let fresh = await fetch() ?? cached ?? .placeholder
            let stale = Date().timeIntervalSince(fresh.capturedAt) > 900
            let entry = ClusterEntry(date: Date(), snapshot: fresh, isStale: stale)
            // WidgetKit budgets refreshes; 15 minutes is the practical floor.
            completion(Timeline(entries: [entry],
                                policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }

    /// Widgets talk to Proxmox directly using the profile the app saved to the
    /// shared container, so the Home Screen stays current even if the app hasn't
    /// been opened.
    private func fetch() async -> WidgetSnapshot? {
        let (servers, selected) = SharedSnapshotStore.loadServers()
        guard let profile = servers.first(where: { $0.id == selected }) ?? servers.first else {
            return nil
        }
        let client = ProxmoxClient(profile: profile)
        guard let resources = try? await client.clusterResources() else { return nil }

        var snap = ClusterSnapshot()
        snap.resources = resources
        snap.capturedAt = Date()

        var out = SharedSnapshotStore.load() ?? WidgetSnapshot()
        out.serverName = profile.displayName
        out.capturedAt = snap.capturedAt
        out.cpu = snap.aggregateCPU
        out.memory = snap.aggregateMemory
        out.storage = snap.aggregateStorage
        out.memoryUsed = snap.memoryUsed
        out.memoryTotal = snap.memoryTotal
        out.cores = snap.totalCores
        out.nodesOnline = snap.onlineNodes.count
        out.nodesTotal = snap.nodes.count
        out.guestsRunning = snap.runningGuests.count
        out.guestsTotal = snap.guests.filter { !$0.isTemplate }.count
        out.alerts = snap.alerts.count
        out.topGuests = snap.guests
            .filter { !$0.isTemplate }
            .sorted { ($0.state.isUp ? 1 : 0, $0.cpuFraction) > ($1.state.isUp ? 1 : 0, $1.cpuFraction) }
            .prefix(6)
            .map { WidgetGuest(name: $0.displayName, vmid: $0.vmid ?? 0, running: $0.state.isUp,
                               cpu: $0.cpuFraction, memory: $0.memFraction, kind: $0.type.rawValue) }
        var history = out.cpuHistory
        history.append(snap.aggregateCPU)
        if history.count > 24 { history.removeFirst(history.count - 24) }
        out.cpuHistory = history
        return out
    }
}

// MARK: - Widgets

struct ClusterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProxynCluster", provider: ClusterProvider()) { entry in
            ClusterWidgetView(entry: entry)
                .containerBackground(for: .widget) { Palette.canvas }
        }
        .configurationDisplayName("Cluster")
        .description("Charge CPU, mémoire et stockage de votre cluster Proxmox.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct ClusterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ClusterEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline:
            Text("\(entry.snapshot.guestsRunning) actives · CPU \(pct(entry.snapshot.cpu))")
        case .systemSmall: small
        case .systemMedium: medium
        default: large
        }
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 6)

            Text(pct(entry.snapshot.cpu))
                .font(.system(size: 34, weight: .medium))
                .monospacedDigit()
                .tracking(-1)
                .foregroundStyle(Palette.ink)
            Text("charge CPU")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.inkTertiary)

            Spacer(minLength: 8)

            WidgetBar(fraction: entry.snapshot.cpu, tint: Palette.ember)
            HStack {
                Text("\(entry.snapshot.guestsRunning)/\(entry.snapshot.guestsTotal) actives")
                Spacer()
                Text("RAM \(pct(entry.snapshot.memory))")
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.inkTertiary)
            .padding(.top, 6)
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(pct(entry.snapshot.cpu))
                        .font(.system(size: 34, weight: .medium))
                        .monospacedDigit()
                        .tracking(-1)
                        .foregroundStyle(Palette.ink)
                    Text("charge CPU")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.inkTertiary)
                }
                .padding(.top, 6)

                WidgetSparkline(values: entry.snapshot.cpuHistory, tint: Palette.ember)
                    .frame(height: 42)
                    .padding(.top, 12)
            }

            Spacer(minLength: 8)

            VStack(spacing: 7) {
                WidgetMeterRow(label: "Mémoire", fraction: entry.snapshot.memory,
                               detail: pct(entry.snapshot.memory))
                WidgetMeterRow(label: "Stockage", fraction: entry.snapshot.storage,
                               detail: pct(entry.snapshot.storage))
            }

            HStack(spacing: 14) {
                Text("\(entry.snapshot.nodesOnline)/\(entry.snapshot.nodesTotal) nœuds")
                Text("\(entry.snapshot.guestsRunning) actives")
                Text("\(Int(entry.snapshot.cores)) cœurs")
                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.inkTertiary)
            .padding(.top, 8)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(pct(entry.snapshot.cpu))
                        .font(.system(size: 38, weight: .medium))
                        .monospacedDigit()
                        .tracking(-1)
                        .foregroundStyle(Palette.ink)
                    Text("charge CPU")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.inkTertiary)
                }
                .padding(.top, 6)

                WidgetSparkline(values: entry.snapshot.cpuHistory, tint: Palette.ember)
                    .frame(height: 46)
                    .padding(.top, 14)
            }

            VStack(spacing: 8) {
                WidgetMeterRow(label: "Mémoire", fraction: entry.snapshot.memory,
                               detail: Format.bytes(entry.snapshot.memoryUsed))
                WidgetMeterRow(label: "Stockage", fraction: entry.snapshot.storage,
                               detail: pct(entry.snapshot.storage))
            }
            .padding(.top, 12)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
                .padding(.vertical, 12)

            VStack(spacing: 9) {
                ForEach(entry.snapshot.topGuests.prefix(5)) { guest in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(guest.running ? Palette.mint : Color.clear)
                            .overlay(Circle().strokeBorder(guest.running ? .clear : Palette.inkTertiary,
                                                           lineWidth: 1))
                            .frame(width: 5, height: 5)
                        Text(guest.name)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(guest.running ? pct(guest.cpu) : "—")
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(Palette.inkTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(entry.isStale ? Palette.amber : Palette.mint)
                .frame(width: 5, height: 5)
            Text(entry.snapshot.serverName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if entry.snapshot.alerts > 0 {
                Text("\(entry.snapshot.alerts)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.rose)
            }
        }
        .padding(.bottom, 2)
    }

    // MARK: Lock Screen

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Circle()
                .trim(from: 0, to: max(0.02, entry.snapshot.cpu))
                .stroke(style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3.5)
            VStack(spacing: -2) {
                Text("\(Int(entry.snapshot.cpu * 100))")
                    .font(.system(size: 16, weight: .medium))
                    .monospacedDigit()
                Text("CPU").font(.system(size: 8))
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.snapshot.serverName)
                .font(.system(size: 12, weight: .medium))
            Text("CPU \(pct(entry.snapshot.cpu))  ·  RAM \(pct(entry.snapshot.memory))")
                .font(.system(size: 13))
                .monospacedDigit()
            Text("\(entry.snapshot.guestsRunning)/\(entry.snapshot.guestsTotal) instances actives")
                .font(.system(size: 11))
                .opacity(0.7)
        }
    }

    private func pct(_ value: Double) -> String { "\(Int((value * 100).rounded())) %" }
}

// MARK: - Widget pieces

struct WidgetBar: View {
    var fraction: Double
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * max(0.02, min(1, fraction)))
            }
        }
        .frame(height: 3)
    }
}

struct WidgetMeterRow: View {
    var label: String
    var fraction: Double
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.inkSecondary)
                Spacer(minLength: 6)
                Text(detail)
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
            }
            WidgetBar(fraction: fraction,
                      tint: fraction > 0.9 ? Palette.rose : Color.white.opacity(0.5))
        }
    }
}

struct WidgetSparkline: View {
    var values: [Double]
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            let pts = values.isEmpty ? [0, 0] : values
            let hi = max(pts.max() ?? 1, 0.05)
            let stepX = geo.size.width / CGFloat(max(pts.count - 1, 1))
            Path { path in
                for (i, v) in pts.enumerated() {
                    let y = geo.size.height - CGFloat(v / hi) * geo.size.height
                    let p = CGPoint(x: CGFloat(i) * stepX, y: y)
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Bundle

@main
struct ProxynWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClusterWidget()
    }
}
