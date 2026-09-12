import SwiftUI

/// Guest row.
///
/// A dot for state, the name, one line of identity, and the two numbers that
/// matter on the right. No tinted icon tile, no chevron: the whole row is the
/// target, and an arrow on every line of a long list is pure noise.
struct GuestRow: View {
    var guest: PVEResource
    var history: [Double]
    var compact: Bool = false
    var showsNode: Bool = true

    private var isUp: Bool { guest.state.isUp }

    private var metaLine: String {
        var parts = ["\(guest.type.label) \(guest.vmid.map(String.init) ?? "—")"]
        if showsNode, let node = guest.node { parts.append(node) }
        else if isUp, let uptime = guest.uptime, uptime > 0 {
            parts.append(Format.uptime(uptime))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            StatusPip(color: Palette.state(guest.state),
                      size: 7,
                      hollow: !isUp && !guest.state.isPaused)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(guest.displayName)
                        .font(.rowTitle)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if guest.isTemplate {
                        TagChip(text: "modèle")
                    }
                    if let lock = guest.lock, !lock.isEmpty {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.amber)
                    }
                }

                Text(metaLine)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.inkTertiary)
                    .lineLimit(1)

                if !compact, !guest.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(guest.tags.prefix(3), id: \.self) { tag in
                            TagChip(text: tag).fixedSize()
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            if isUp {
                HStack(spacing: 10) {
                    if !compact, history.count > 2 {
                        Sparkline(values: history,
                                  tint: guest.cpuFraction > 0.8 ? Palette.amber : Palette.inkTertiary)
                            .frame(width: 38, height: 18)
                            .padding(.top, 3)
                    }
                    VStack(alignment: .trailing, spacing: 2) {
                        MetricText(value: Format.percent(guest.cpuFraction), unit: nil,
                                   size: 15,
                                   color: guest.cpuFraction > 0.8 ? Palette.amber : Palette.ink)
                        Text(Format.bytes(guest.mem))
                            .font(.metric(12))
                            .foregroundStyle(Palette.inkTertiary)
                    }
                }
            } else {
                Text(guest.state.label.lowercased())
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.inkTertiary)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, compact ? 9 : 11)
        .contentShape(Rectangle())
    }
}

/// Compact node card for the dashboard's horizontal strip.
struct NodeMiniCard: View {
    var node: PVEResource
    var history: [Double]

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    StatusPip(color: Palette.state(node.state),
                              pulsing: node.state.isUp, size: 6,
                              hollow: !node.state.isUp)
                    Text(node.displayName)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    MetricText(value: Format.percent(node.cpuFraction), unit: nil, size: 24)
                    Text("CPU")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.inkTertiary)
                    Spacer(minLength: 0)
                }

                if history.count > 2 {
                    Sparkline(values: history, tint: Palette.ember, filled: true)
                        .frame(height: 26)
                } else {
                    Color.clear.frame(height: 26)
                }

                StatLine(label: "Mémoire",
                         value: "\(Format.bytes(node.mem)) / \(Format.bytes(node.maxmem))",
                         fraction: node.memFraction)

                Text("\(Int(node.maxcpu ?? 0)) cœurs · \(Format.uptime(node.uptime))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.inkTertiary)
                    .lineLimit(1)
            }
        }
        .frame(width: 186)
    }
}

/// One line of the activity feed.
struct TaskRow: View {
    var task: PVETask
    var compact: Bool = false

    private var tint: Color {
        if task.isRunning { return Palette.ember }
        return task.succeeded ? Palette.mint : Palette.rose
    }

    private var symbol: String {
        if task.isRunning { return "circle.dotted" }
        return task.succeeded ? "checkmark" : "xmark"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 15, height: 15)
                .padding(.top, 3)
                .symbolEffect(.rotate, options: .repeating, isActive: task.isRunning)

            VStack(alignment: .leading, spacing: 3) {
                Text(Format.taskType(task.type))
                    .font(.system(size: 14.5))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)

                Text([task.pveTargetId?.isEmpty == false ? task.pveTargetId : nil,
                      task.node,
                      compact ? nil : task.user]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.inkTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(task.isRunning ? "en cours" : Format.ago(task.end ?? task.start))
                    .font(.system(size: 12.5))
                    .foregroundStyle(task.isRunning ? Palette.ember : Palette.inkTertiary)
                if !task.isRunning, let d = task.duration {
                    Text(Format.duration(d))
                        .font(.metric(11.5))
                        .foregroundStyle(Palette.inkTertiary.opacity(0.75))
                }
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// Storage row: name, absolute figures, one bar.
struct StorageRow: View {
    var storage: PVEResource

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(storage.displayName)
                    .font(.rowTitle)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if storage.shared { TagChip(text: "partagé") }
                Spacer(minLength: 8)
                Text("\(Format.bytes(storage.disk)) / \(Format.bytes(storage.maxdisk))")
                    .font(.metric(12.5))
                    .foregroundStyle(Palette.inkSecondary)
            }
            MeterBar(fraction: storage.diskFraction)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}
