import Foundation

/// Everything one poll of a server produces. The UI only ever reads a snapshot,
/// which makes partial failures easy: a stale snapshot stays on screen while the
/// error banner explains what broke.
struct ClusterSnapshot: Sendable, Equatable {
    var resources: [PVEResource] = []
    var clusterNodes: [PVEClusterNodeStatus] = []
    var tasks: [PVETask] = []
    var version: PVEVersion?
    var capturedAt: Date = .distantPast
    var isPartial: Bool = false

    var nodes: [PVEResource] { resources.filter { $0.type == .node } }

    var guests: [PVEResource] {
        resources.filter { $0.type.isGuest }.sorted { ($0.vmid ?? 0) < ($1.vmid ?? 0) }
    }

    var storages: [PVEResource] { resources.filter { $0.type == .storage } }

    var pools: [String] {
        Array(Set(resources.compactMap(\.pool).filter { !$0.isEmpty })).sorted()
    }

    var allTags: [String] {
        Array(Set(guests.flatMap(\.tags))).sorted()
    }

    var runningGuests: [PVEResource] { guests.filter { $0.state.isUp && !$0.isTemplate } }
    var stoppedGuests: [PVEResource] { guests.filter { !$0.state.isUp && !$0.isTemplate } }
    var templates: [PVEResource] { guests.filter(\.isTemplate) }

    var onlineNodes: [PVEResource] { nodes.filter { $0.state.isUp } }
    var offlineNodes: [PVEResource] { nodes.filter { !$0.state.isUp } }

    var isQuorate: Bool {
        guard let cluster = clusterNodes.first(where: { $0.type == "cluster" }) else { return true }
        return cluster.quorate ?? true
    }

    var clusterName: String? {
        clusterNodes.first(where: { $0.type == "cluster" })?.name
    }

    // MARK: Aggregates

    /// CPU load across the cluster, weighted by each node's core count so a
    /// 4-core node doesn't skew a 64-core one.
    var aggregateCPU: Double {
        let online = onlineNodes
        let totalCores = online.reduce(0.0) { $0 + ($1.maxcpu ?? 1) }
        guard totalCores > 0 else { return 0 }
        let used = online.reduce(0.0) { $0 + ($1.cpu ?? 0) * ($1.maxcpu ?? 1) }
        return max(0, min(1, used / totalCores))
    }

    var totalCores: Double { onlineNodes.reduce(0) { $0 + ($1.maxcpu ?? 0) } }

    var memoryUsed: Double { onlineNodes.reduce(0) { $0 + ($1.mem ?? 0) } }
    var memoryTotal: Double { onlineNodes.reduce(0) { $0 + ($1.maxmem ?? 0) } }
    var aggregateMemory: Double { memoryTotal > 0 ? memoryUsed / memoryTotal : 0 }

    /// Shared storages are counted once even when every node reports them.
    var storageUsed: Double { uniqueStorages.reduce(0) { $0 + ($1.disk ?? 0) } }
    var storageTotal: Double { uniqueStorages.reduce(0) { $0 + ($1.maxdisk ?? 0) } }
    var aggregateStorage: Double { storageTotal > 0 ? storageUsed / storageTotal : 0 }

    var uniqueStorages: [PVEResource] {
        var seen = Set<String>()
        var out: [PVEResource] = []
        for s in storages where s.status != "unavailable" {
            let key = s.shared ? (s.storage ?? s.id) : s.id
            if seen.insert(key).inserted { out.append(s) }
        }
        return out
    }

    var runningTasks: [PVETask] { tasks.filter(\.isRunning) }
    var failedTasks: [PVETask] { tasks.filter(\.failed) }

    /// Health issues worth surfacing at the top of the dashboard.
    var alerts: [ClusterAlert] {
        var out: [ClusterAlert] = []
        if !isQuorate {
            out.append(.init(level: .critical, symbol: "exclamationmark.octagon.fill",
                             title: "Quorum perdu",
                             detail: "Le cluster n'a plus le quorum : les actions sont bloquées."))
        }
        for node in offlineNodes {
            out.append(.init(level: .critical, symbol: "bolt.horizontal.circle.fill",
                             title: "Nœud \(node.displayName) hors ligne",
                             detail: "Aucune réponse du nœud."))
        }
        for storage in uniqueStorages where storage.diskFraction > 0.9 {
            out.append(.init(level: .warning, symbol: "internaldrive.fill",
                             title: "Stockage \(storage.displayName) à \(Format.percent(storage.diskFraction))",
                             detail: "Il reste \(Format.bytes((storage.maxdisk ?? 0) - (storage.disk ?? 0)))."))
        }
        for node in onlineNodes where node.memFraction > 0.92 {
            out.append(.init(level: .warning, symbol: "memorychip.fill",
                             title: "RAM saturée sur \(node.displayName)",
                             detail: "\(Format.percent(node.memFraction)) de la mémoire utilisée."))
        }
        for guest in guests where guest.lock != nil && !(guest.lock ?? "").isEmpty {
            out.append(.init(level: .info, symbol: "lock.fill",
                             title: "\(guest.displayName) verrouillé",
                             detail: "Verrou : \(guest.lock ?? "")"))
        }
        let recentFailures = failedTasks.prefix(3)
        for task in recentFailures {
            out.append(.init(level: .warning, symbol: "xmark.octagon.fill",
                             title: "\(Format.taskType(task.type)) en échec",
                             detail: task.exitStatus ?? "Terminée en erreur"))
        }
        return out
    }
}

struct ClusterAlert: Identifiable, Hashable, Sendable {
    enum Level: Int, Sendable, Comparable {
        case info, warning, critical
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }
    var id = UUID()
    var level: Level
    var symbol: String
    var title: String
    var detail: String
}

/// Rolling window of aggregate values, refreshed at the poll interval. This is
/// what makes the dashboard feel live between RRD updates (Proxmox only writes
/// RRD every minute).
struct LiveHistory: Sendable, Equatable {
    private(set) var cpu: [Double] = []
    private(set) var memory: [Double] = []
    private(set) var netIn: [Double] = []
    private(set) var netOut: [Double] = []
    private(set) var stamps: [Date] = []
    var capacity = 90

    mutating func append(cpu c: Double, memory m: Double, netIn i: Double, netOut o: Double, at date: Date = Date()) {
        cpu.append(c); memory.append(m); netIn.append(i); netOut.append(o); stamps.append(date)
        if cpu.count > capacity {
            cpu.removeFirst(); memory.removeFirst(); netIn.removeFirst()
            netOut.removeFirst(); stamps.removeFirst()
        }
    }

    mutating func reset() {
        cpu = []; memory = []; netIn = []; netOut = []; stamps = []
    }

    var isEmpty: Bool { cpu.isEmpty }
}
