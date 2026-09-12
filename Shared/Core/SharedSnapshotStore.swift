import Foundation

// MARK: - Widget payload

/// Everything the widgets draw, reduced from a cluster snapshot and shared
/// through the app group. Written by the app after each poll and by the widget
/// extension after its own fetch.
struct WidgetSnapshot: Codable, Sendable, Hashable {
    var serverID: UUID?
    var serverName: String = "Proxmox"
    var capturedAt: Date = .distantPast
    var cpu: Double = 0
    var memory: Double = 0
    var storage: Double = 0
    var memoryUsed: Double = 0
    var memoryTotal: Double = 0
    var storageUsed: Double = 0
    var storageTotal: Double = 0
    var cores: Double = 0
    var alerts: Int = 0
    var cpuHistory: [Double] = []
    var guests: [WidgetGuest] = []
    var nodes: [WidgetNode] = []
    var storages: [WidgetStorage] = []
    var tasks: [WidgetTask] = []

    init() {}

    init(snapshot: ClusterSnapshot, serverID: UUID?, serverName: String, previousHistory: [Double]) {
        self.serverID = serverID
        self.serverName = serverName
        capturedAt = snapshot.capturedAt
        cpu = snapshot.aggregateCPU
        memory = snapshot.aggregateMemory
        storage = snapshot.aggregateStorage
        memoryUsed = snapshot.memoryUsed
        memoryTotal = snapshot.memoryTotal
        storageUsed = snapshot.storageUsed
        storageTotal = snapshot.storageTotal
        cores = snapshot.totalCores
        alerts = snapshot.alerts.count
        cpuHistory = Array((previousHistory + [snapshot.aggregateCPU]).suffix(24))

        guests = snapshot.guests.filter { !$0.isTemplate }.compactMap(WidgetGuest.init)
        nodes = snapshot.nodes.map(WidgetNode.init)
        storages = snapshot.uniqueStorages.map(WidgetStorage.init)
        tasks = snapshot.tasks.prefix(12).map(WidgetTask.init)
    }

    // MARK: Derived

    var nodesOnline: Int { nodes.filter(\.online).count }
    var runningGuests: [WidgetGuest] { guests.filter(\.isRunning) }
    var busiestGuests: [WidgetGuest] { runningGuests.sorted { $0.cpu > $1.cpu } }
    var runningTasks: [WidgetTask] { tasks.filter(\.isRunning) }
    var recentFailures: [WidgetTask] {
        tasks.filter { !$0.isRunning && !$0.succeeded && ($0.end ?? .distantPast) > Date().addingTimeInterval(-86_400) }
    }
    var fullestStorages: [WidgetStorage] { storages.sorted { $0.fraction > $1.fraction } }

    func guest(vmid: Int) -> WidgetGuest? { guests.first { $0.vmid == vmid } }

    // Tolerant decoding: a payload written by an older build never blanks the widget.
    enum CodingKeys: String, CodingKey {
        case serverID, serverName, capturedAt, cpu, memory, storage, memoryUsed, memoryTotal
        case storageUsed, storageTotal, cores, alerts, cpuHistory, guests, nodes, storages, tasks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serverID = try? c.decodeIfPresent(UUID.self, forKey: .serverID)
        serverName = (try? c.decodeIfPresent(String.self, forKey: .serverName)) ?? "Proxmox"
        capturedAt = (try? c.decodeIfPresent(Date.self, forKey: .capturedAt)) ?? .distantPast
        cpu = (try? c.decodeIfPresent(Double.self, forKey: .cpu)) ?? 0
        memory = (try? c.decodeIfPresent(Double.self, forKey: .memory)) ?? 0
        storage = (try? c.decodeIfPresent(Double.self, forKey: .storage)) ?? 0
        memoryUsed = (try? c.decodeIfPresent(Double.self, forKey: .memoryUsed)) ?? 0
        memoryTotal = (try? c.decodeIfPresent(Double.self, forKey: .memoryTotal)) ?? 0
        storageUsed = (try? c.decodeIfPresent(Double.self, forKey: .storageUsed)) ?? 0
        storageTotal = (try? c.decodeIfPresent(Double.self, forKey: .storageTotal)) ?? 0
        cores = (try? c.decodeIfPresent(Double.self, forKey: .cores)) ?? 0
        alerts = (try? c.decodeIfPresent(Int.self, forKey: .alerts)) ?? 0
        cpuHistory = (try? c.decodeIfPresent([Double].self, forKey: .cpuHistory)) ?? []
        guests = (try? c.decodeIfPresent([WidgetGuest].self, forKey: .guests)) ?? []
        nodes = (try? c.decodeIfPresent([WidgetNode].self, forKey: .nodes)) ?? []
        storages = (try? c.decodeIfPresent([WidgetStorage].self, forKey: .storages)) ?? []
        tasks = (try? c.decodeIfPresent([WidgetTask].self, forKey: .tasks)) ?? []
    }
}

struct WidgetGuest: Codable, Sendable, Hashable, Identifiable {
    var vmid: Int
    var name: String
    var node: String
    var kind: String
    var status: String
    var cpu: Double
    var cores: Double
    var memoryUsed: Double
    var memoryTotal: Double
    var uptime: Double

    var id: Int { vmid }
    var isRunning: Bool { status == "running" }
    var isPaused: Bool { status == "paused" || status == "suspended" }
    var memory: Double { memoryTotal > 0 ? min(1, memoryUsed / memoryTotal) : 0 }
    var kindLabel: String { kind == "lxc" ? "CT" : "VM" }
    var symbol: String { kind == "lxc" ? "shippingbox" : "desktopcomputer" }

    static let placeholder = WidgetGuest(vmid: 100, name: "guest", node: "node", kind: "qemu",
                                         status: "stopped", cpu: 0, cores: 1, memoryUsed: 0,
                                         memoryTotal: 0, uptime: 0)

    init(vmid: Int, name: String, node: String, kind: String, status: String, cpu: Double,
         cores: Double, memoryUsed: Double, memoryTotal: Double, uptime: Double) {
        self.vmid = vmid; self.name = name; self.node = node; self.kind = kind; self.status = status
        self.cpu = cpu; self.cores = cores; self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal; self.uptime = uptime
    }

    init?(_ resource: PVEResource) {
        guard let vmid = resource.vmid, let node = resource.node else { return nil }
        self.vmid = vmid
        name = resource.displayName
        self.node = node
        kind = resource.type.rawValue
        status = resource.status ?? "unknown"
        cpu = resource.cpuFraction
        cores = resource.maxcpu ?? 0
        memoryUsed = resource.mem ?? 0
        memoryTotal = resource.maxmem ?? 0
        uptime = resource.uptime ?? 0
    }
}

struct WidgetNode: Codable, Sendable, Hashable, Identifiable {
    var name: String
    var online: Bool
    var cpu: Double
    var memory: Double
    var cores: Double
    var uptime: Double
    var id: String { name }

    init(_ resource: PVEResource) {
        name = resource.displayName
        online = resource.state.isUp
        cpu = resource.cpuFraction
        memory = resource.memFraction
        cores = resource.maxcpu ?? 0
        uptime = resource.uptime ?? 0
    }
}

struct WidgetStorage: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var name: String
    var node: String
    var shared: Bool
    var used: Double
    var total: Double
    var type: String

    var fraction: Double { total > 0 ? min(1, used / total) : 0 }
    var free: Double { max(0, total - used) }

    init(_ resource: PVEResource) {
        id = resource.id
        name = resource.storage ?? resource.displayName
        node = resource.node ?? ""
        shared = resource.shared
        used = resource.disk ?? 0
        total = resource.maxdisk ?? 0
        type = resource.pluginType ?? ""
    }
}

struct WidgetTask: Codable, Sendable, Hashable, Identifiable {
    var upid: String
    var type: String
    var target: String
    var node: String
    var isRunning: Bool
    var succeeded: Bool
    var start: Date?
    var end: Date?
    var id: String { upid }
    var title: String { Format.taskType(type) }

    static let placeholder = WidgetTask(upid: "UPID:placeholder", type: "vzdump", target: "",
                                        node: "", isRunning: false, succeeded: true, start: nil, end: nil)

    init(upid: String, type: String, target: String, node: String, isRunning: Bool,
         succeeded: Bool, start: Date?, end: Date?) {
        self.upid = upid; self.type = type; self.target = target; self.node = node
        self.isRunning = isRunning; self.succeeded = succeeded; self.start = start; self.end = end
    }

    init(_ task: PVETask) {
        upid = task.upid
        type = task.type ?? ""
        target = task.pveTargetId ?? ""
        node = task.node ?? ""
        isRunning = task.isRunning
        succeeded = task.succeeded
        start = task.start
        end = task.end
    }
}

// MARK: - Store

enum SharedSnapshotStore {
    private static let snapshotKey = "proxyn.widget.snapshot.v2"
    private static let serversKey = "proxyn.widget.servers"
    private static let selectedKey = "proxyn.widget.selected"

    static func save(_ snapshot: WidgetSnapshot, defaults: UserDefaults = AppGroup.defaults) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func save(snapshot: ClusterSnapshot, serverID: UUID?, serverName: String,
                     defaults: UserDefaults = AppGroup.defaults) {
        let previous = load(defaults: defaults)
        let history = previous?.serverID == serverID ? (previous?.cpuHistory ?? []) : []
        save(WidgetSnapshot(snapshot: snapshot, serverID: serverID, serverName: serverName,
                            previousHistory: history),
             defaults: defaults)
    }

    static func load(defaults: UserDefaults = AppGroup.defaults) -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Reflects an action taken from a widget before the next fetch confirms it.
    static func update(defaults: UserDefaults = AppGroup.defaults, _ change: (inout WidgetSnapshot) -> Void) {
        guard var snapshot = load(defaults: defaults) else { return }
        change(&snapshot)
        save(snapshot, defaults: defaults)
    }

    static func clear(defaults: UserDefaults = AppGroup.defaults) {
        defaults.removeObject(forKey: snapshotKey)
    }

    /// Profiles only — secrets stay in the Keychain.
    static func saveServers(_ servers: [ServerProfile], selected: UUID?,
                            defaults: UserDefaults = AppGroup.defaults) {
        if let data = try? JSONEncoder().encode(servers) {
            defaults.set(data, forKey: serversKey)
        }
        defaults.set(selected?.uuidString, forKey: selectedKey)
    }

    static func loadServers(defaults: UserDefaults = AppGroup.defaults) -> (servers: [ServerProfile], selected: UUID?) {
        let servers = defaults.data(forKey: serversKey)
            .flatMap { try? JSONDecoder().decode([ServerProfile].self, from: $0) } ?? []
        let selected = defaults.string(forKey: selectedKey).flatMap(UUID.init(uuidString:))
        return (servers, selected)
    }

    static func selectedServer(defaults: UserDefaults = AppGroup.defaults) -> ServerProfile? {
        let (servers, selected) = loadServers(defaults: defaults)
        return servers.first { $0.id == selected } ?? servers.first
    }
}

// MARK: - Deep links

/// URLs widgets use to open a specific screen: `proxyn://guest/100`,
/// `proxyn://node/pve1`, `proxyn://storage/pve1/local`, `proxyn://activity`.
enum DeepLink: Equatable, Sendable {
    case overview
    case guest(vmid: Int)
    case node(String)
    case storage(node: String, storage: String)
    case activity

    static let scheme = "proxyn"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .overview: components.host = "overview"
        case .guest(let vmid): components.host = "guest"; components.path = "/\(vmid)"
        case .node(let name): components.host = "node"; components.path = "/\(name)"
        case .storage(let node, let storage): components.host = "storage"; components.path = "/\(node)/\(storage)"
        case .activity: components.host = "activity"
        }
        return components.url ?? URL(string: "proxyn://overview")!
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch url.host {
        case "overview": self = .overview
        case "activity": self = .activity
        case "guest":
            guard let vmid = parts.first.flatMap(Int.init) else { return nil }
            self = .guest(vmid: vmid)
        case "node":
            guard let name = parts.first else { return nil }
            self = .node(name)
        case "storage":
            guard parts.count >= 2 else { return nil }
            self = .storage(node: parts[0], storage: parts[1])
        default:
            return nil
        }
    }
}
