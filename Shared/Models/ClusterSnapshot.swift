import Foundation

/// Everything one poll of a server produces.
///
/// All derived collections and aggregates are computed **once**, when the
/// snapshot is built, instead of on every property access. Views read these
/// many times per frame, and a large cluster has hundreds of guests.
struct ClusterSnapshot: Sendable, Equatable {
    let resources: [PVEResource]
    let clusterNodes: [PVEClusterNodeStatus]
    let tasks: [PVETask]
    let version: PVEVersion?
    let capturedAt: Date

    let nodes: [PVEResource]
    let onlineNodes: [PVEResource]
    let offlineNodes: [PVEResource]
    let guests: [PVEResource]
    let runningGuests: [PVEResource]
    let stoppedGuests: [PVEResource]
    let templates: [PVEResource]
    let storages: [PVEResource]
    let uniqueStorages: [PVEResource]
    let runningTasks: [PVETask]
    let failedTasks: [PVETask]

    let aggregateCPU: Double
    let totalCores: Double
    let memoryUsed: Double
    let memoryTotal: Double
    let storageUsed: Double
    let storageTotal: Double

    let isQuorate: Bool
    let clusterName: String?
    let alerts: [ClusterAlert]

    var aggregateMemory: Double { memoryTotal > 0 ? memoryUsed / memoryTotal : 0 }
    var aggregateStorage: Double { storageTotal > 0 ? storageUsed / storageTotal : 0 }
    var isEmpty: Bool { capturedAt == .distantPast }

    static let empty = ClusterSnapshot()

    init(resources: [PVEResource] = [],
         clusterNodes: [PVEClusterNodeStatus] = [],
         tasks: [PVETask] = [],
         version: PVEVersion? = nil,
         capturedAt: Date = .distantPast,
         now: Date = Date()) {
        self.resources = resources
        self.clusterNodes = clusterNodes
        self.tasks = tasks
        self.version = version
        self.capturedAt = capturedAt

        let nodes = resources.filter { $0.type == .node }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        let online = nodes.filter { $0.state.isUp }
        let guests = resources.filter { $0.type.isGuest }.sorted { ($0.vmid ?? 0) < ($1.vmid ?? 0) }
        let storages = resources.filter { $0.type == .storage }

        self.nodes = nodes
        self.onlineNodes = online
        self.offlineNodes = nodes.filter { !$0.state.isUp }
        self.guests = guests
        self.runningGuests = guests.filter { $0.state.isUp && !$0.isTemplate }
        self.stoppedGuests = guests.filter { !$0.state.isUp && !$0.isTemplate }
        self.templates = guests.filter(\.isTemplate)
        self.storages = storages
        self.uniqueStorages = Self.deduplicate(storages)
        self.runningTasks = tasks.filter(\.isRunning)
        self.failedTasks = tasks.filter(\.failed)

        // CPU weighted by core count, so a 4-core node doesn't skew a 64-core one.
        let cores = online.reduce(0.0) { $0 + ($1.maxcpu ?? 0) }
        let busyCores = online.reduce(0.0) { $0 + ($1.cpu ?? 0) * ($1.maxcpu ?? 0) }
        self.totalCores = cores
        self.aggregateCPU = cores > 0 ? max(0, min(1, busyCores / cores)) : 0
        self.memoryUsed = online.reduce(0) { $0 + ($1.mem ?? 0) }
        self.memoryTotal = online.reduce(0) { $0 + ($1.maxmem ?? 0) }
        self.storageUsed = uniqueStorages.reduce(0) { $0 + ($1.disk ?? 0) }
        self.storageTotal = uniqueStorages.reduce(0) { $0 + ($1.maxdisk ?? 0) }

        let cluster = clusterNodes.first { $0.type == "cluster" }
        self.isQuorate = cluster?.quorate ?? true
        self.clusterName = cluster?.name

        self.alerts = Self.makeAlerts(nodes: nodes, guests: guests, storages: uniqueStorages,
                                      tasks: tasks, isQuorate: cluster?.quorate ?? true, now: now)
    }

    /// Shared storages are reported once per node; count them once.
    private static func deduplicate(_ storages: [PVEResource]) -> [PVEResource] {
        var seen = Set<String>()
        var out: [PVEResource] = []
        for storage in storages where storage.status != "unavailable" {
            let key = storage.shared ? (storage.storage ?? storage.id) : storage.id
            if seen.insert(key).inserted { out.append(storage) }
        }
        return out.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private static func makeAlerts(nodes: [PVEResource], guests: [PVEResource],
                                   storages: [PVEResource], tasks: [PVETask],
                                   isQuorate: Bool, now: Date) -> [ClusterAlert] {
        var out: [ClusterAlert] = []

        if !isQuorate {
            out.append(.init(id: "quorum", level: .critical, symbol: "exclamationmark.octagon",
                             title: "Cluster has lost quorum",
                             detail: "Configuration changes are blocked until quorum is restored."))
        }
        for node in nodes where !node.state.isUp {
            out.append(.init(id: "node-offline-\(node.id)", level: .critical, symbol: "server.rack",
                             title: "\(node.displayName) is offline",
                             detail: "The node isn't responding to the cluster."))
        }
        for storage in storages where storage.diskFraction >= 0.9 {
            let free = Format.bytes((storage.maxdisk ?? 0) - (storage.disk ?? 0))
            out.append(.init(id: "storage-full-\(storage.id)", level: .warning, symbol: "internaldrive",
                             title: "\(storage.displayName) is \(Format.percent(storage.diskFraction)) full",
                             detail: "\(free) remaining."))
        }
        for node in nodes where node.state.isUp && node.memFraction >= 0.92 {
            out.append(.init(id: "node-memory-\(node.id)", level: .warning, symbol: "memorychip",
                             title: "\(node.displayName) is low on memory",
                             detail: "\(Format.percent(node.memFraction)) of RAM in use."))
        }
        // Only failures from the last day: the cluster task log keeps old ones
        // around for a long time, and a permanent alert is one nobody reads.
        let recentFailures = tasks
            .filter { $0.failed && ($0.end ?? $0.start ?? .distantPast) > now.addingTimeInterval(-86_400) }
            .prefix(3)
        for task in recentFailures {
            out.append(.init(id: "task-\(task.upid)", level: .warning, symbol: "xmark.octagon",
                             title: "\(Format.taskType(task.type)) failed",
                             detail: task.exitStatus ?? "The task ended with an error."))
        }
        return out.sorted { $0.level > $1.level }
    }
}

struct ClusterAlert: Identifiable, Hashable, Sendable {
    enum Level: Int, Sendable, Comparable {
        case info, warning, critical
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    /// Derived from what the alert is about, never random — a fresh UUID on
    /// every poll would make SwiftUI treat each alert as new and re-animate it.
    let id: String
    let level: Level
    let symbol: String
    let title: String
    let detail: String
}

/// Rolling window of values sampled at the poll interval. Proxmox writes RRD
/// data once a minute; this is what keeps the UI moving between writes.
struct LiveHistory: Sendable, Equatable {
    private(set) var cpu: [Double] = []
    private(set) var memory: [Double] = []
    private(set) var netIn: [Double] = []
    private(set) var netOut: [Double] = []
    var capacity = 90

    mutating func append(cpu c: Double, memory m: Double, netIn i: Double = 0, netOut o: Double = 0) {
        cpu.append(c); memory.append(m); netIn.append(i); netOut.append(o)
        if cpu.count > capacity {
            cpu.removeFirst(); memory.removeFirst(); netIn.removeFirst(); netOut.removeFirst()
        }
    }

    mutating func reset() { self = LiveHistory(capacity: capacity) }

    var isEmpty: Bool { cpu.isEmpty }
}
