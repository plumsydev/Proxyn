import Foundation

/// Compact payload written by the app and read by the widget extension, so the
/// Home Screen has something to draw instantly while its own fetch runs.
struct WidgetSnapshot: Codable, Sendable, Hashable {
    var serverName: String = "Proxmox"
    var capturedAt: Date = .distantPast
    var cpu: Double = 0
    var memory: Double = 0
    var storage: Double = 0
    var memoryUsed: Double = 0
    var memoryTotal: Double = 0
    var cores: Double = 0
    var nodesOnline: Int = 0
    var nodesTotal: Int = 0
    var guestsRunning: Int = 0
    var guestsTotal: Int = 0
    var alerts: Int = 0
    var cpuHistory: [Double] = []
    var topGuests: [WidgetGuest] = []

    static let placeholder = WidgetSnapshot(
        serverName: "homelab", capturedAt: Date(), cpu: 0.34, memory: 0.61, storage: 0.47,
        memoryUsed: 40 * 1024 * 1024 * 1024, memoryTotal: 64 * 1024 * 1024 * 1024, cores: 24,
        nodesOnline: 3, nodesTotal: 3, guestsRunning: 12, guestsTotal: 18, alerts: 0,
        cpuHistory: [0.2, 0.3, 0.25, 0.4, 0.38, 0.5, 0.42, 0.34, 0.36, 0.31, 0.4, 0.34],
        topGuests: [
            .init(name: "nas", vmid: 101, running: true, cpu: 0.42, memory: 0.66, kind: "lxc"),
            .init(name: "home-assistant", vmid: 104, running: true, cpu: 0.18, memory: 0.51, kind: "qemu"),
            .init(name: "plex", vmid: 110, running: true, cpu: 0.61, memory: 0.73, kind: "lxc"),
            .init(name: "docker", vmid: 120, running: false, cpu: 0, memory: 0, kind: "qemu")
        ])
}

struct WidgetGuest: Codable, Sendable, Hashable, Identifiable {
    var name: String
    var vmid: Int
    var running: Bool
    var cpu: Double
    var memory: Double
    var kind: String
    var id: Int { vmid }
}

enum SharedSnapshotStore {
    private static let snapshotKey = "proxyn.widget.snapshot"
    private static let serversKey = "proxyn.widget.servers"
    private static let selectedKey = "proxyn.widget.selected"

    static func save(snapshot: ClusterSnapshot, serverName: String) {
        var out = WidgetSnapshot()
        out.serverName = serverName
        out.capturedAt = snapshot.capturedAt
        out.cpu = snapshot.aggregateCPU
        out.memory = snapshot.aggregateMemory
        out.storage = snapshot.aggregateStorage
        out.memoryUsed = snapshot.memoryUsed
        out.memoryTotal = snapshot.memoryTotal
        out.cores = snapshot.totalCores
        out.nodesOnline = snapshot.onlineNodes.count
        out.nodesTotal = snapshot.nodes.count
        out.guestsRunning = snapshot.runningGuests.count
        out.guestsTotal = snapshot.guests.filter { !$0.isTemplate }.count
        out.alerts = snapshot.alerts.count
        out.topGuests = snapshot.guests
            .filter { !$0.isTemplate }
            .sorted { ($0.state.isUp ? 1 : 0, $0.cpuFraction) > ($1.state.isUp ? 1 : 0, $1.cpuFraction) }
            .prefix(6)
            .map { WidgetGuest(name: $0.displayName, vmid: $0.vmid ?? 0, running: $0.state.isUp,
                               cpu: $0.cpuFraction, memory: $0.memFraction, kind: $0.type.rawValue) }

        var existing = load()?.cpuHistory ?? []
        existing.append(snapshot.aggregateCPU)
        if existing.count > 24 { existing.removeFirst(existing.count - 24) }
        out.cpuHistory = existing

        if let data = try? JSONEncoder().encode(out) {
            AppGroup.defaults.set(data, forKey: snapshotKey)
        }
    }

    static func load() -> WidgetSnapshot? {
        guard let data = AppGroup.defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func saveServers(_ servers: [ServerProfile], selected: UUID?) {
        if let data = try? JSONEncoder().encode(servers) {
            AppGroup.defaults.set(data, forKey: serversKey)
        }
        AppGroup.defaults.set(selected?.uuidString, forKey: selectedKey)
    }

    static func loadServers() -> (servers: [ServerProfile], selected: UUID?) {
        let data = AppGroup.defaults.data(forKey: serversKey)
        let servers = data.flatMap { try? JSONDecoder().decode([ServerProfile].self, from: $0) } ?? []
        let selected = AppGroup.defaults.string(forKey: selectedKey).flatMap(UUID.init(uuidString:))
        return (servers, selected)
    }
}
