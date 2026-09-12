import Foundation

// MARK: - Cluster resources

enum PVEResourceType: String, Codable, Sendable, CaseIterable {
    case node, qemu, lxc, storage, pool, sdn, unknown

    init(raw: String?) { self = PVEResourceType(rawValue: raw ?? "") ?? .unknown }

    var isGuest: Bool { self == .qemu || self == .lxc }

    var symbol: String {
        switch self {
        case .node: return "server.rack"
        case .qemu: return "desktopcomputer"
        case .lxc: return "shippingbox"
        case .storage: return "internaldrive"
        case .pool: return "folder"
        case .sdn: return "network"
        case .unknown: return "questionmark.circle"
        }
    }

    var label: String {
        switch self {
        case .node: return "Node"
        case .qemu: return "VM"
        case .lxc: return "CT"
        case .storage: return "Storage"
        case .pool: return "Pool"
        case .sdn: return "SDN"
        case .unknown: return "—"
        }
    }
}

enum PVERunState: String, Sendable {
    case running, stopped, paused, suspended, unknown, online, offline

    init(raw: String?) {
        switch (raw ?? "").lowercased() {
        case "running": self = .running
        case "stopped": self = .stopped
        case "paused": self = .paused
        case "suspended", "prelaunch": self = .suspended
        case "online": self = .online
        case "offline": self = .offline
        default: self = .unknown
        }
    }

    var isUp: Bool { self == .running || self == .online }
    var isPaused: Bool { self == .paused || self == .suspended }

    var label: String {
        switch self {
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .paused: return "Paused"
        case .suspended: return "Suspended"
        case .online: return "Online"
        case .offline: return "Offline"
        case .unknown: return "Unknown"
        }
    }
}

/// One row of `GET /cluster/resources` — the single call that powers most of the app.
struct PVEResource: Identifiable, Hashable, Sendable, Decodable {
    var id: String
    var type: PVEResourceType
    var node: String?
    var name: String?
    var status: String?
    var vmid: Int?
    var cpu: Double?
    var maxcpu: Double?
    var mem: Double?
    var maxmem: Double?
    var disk: Double?
    var maxdisk: Double?
    var uptime: Double?
    var isTemplate: Bool
    var tags: [String]
    var pool: String?
    var storage: String?
    var pluginType: String?
    var content: String?
    var shared: Bool
    var hastate: String?
    var lock: String?
    var diskread: Double?
    var diskwrite: Double?
    var netin: Double?
    var netout: Double?
    var level: String?

    var state: PVERunState { PVERunState(raw: status) }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let storage { return storage }
        if let node, type == .node { return node }
        if let vmid { return "VM \(vmid)" }
        return id
    }

    var cpuFraction: Double { max(0, min(1, cpu ?? 0)) }
    var memFraction: Double {
        guard let maxmem, maxmem > 0, let mem else { return 0 }
        return max(0, min(1, mem / maxmem))
    }
    var diskFraction: Double {
        guard let maxdisk, maxdisk > 0, let disk else { return 0 }
        return max(0, min(1, disk / maxdisk))
    }

    /// Stable key used for routing: `pve1/qemu/100`
    var routeKey: String { "\(node ?? "-")/\(type.rawValue)/\(vmid.map(String.init) ?? name ?? id)" }

    enum CodingKeys: String, CodingKey {
        case id, type, node, name, status, vmid, cpu, maxcpu, mem, maxmem, disk, maxdisk
        case uptime, template, tags, pool, storage, plugintype, content, shared, hastate
        case lock, diskread, diskwrite, netin, netout, level
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = c.looseString(.type)
        type = PVEResourceType(raw: rawType)
        node = c.looseString(.node)
        name = c.looseString(.name)
        status = c.looseString(.status)
        vmid = c.looseInt(.vmid)
        cpu = c.looseDouble(.cpu)
        maxcpu = c.looseDouble(.maxcpu)
        mem = c.looseDouble(.mem)
        maxmem = c.looseDouble(.maxmem)
        disk = c.looseDouble(.disk)
        maxdisk = c.looseDouble(.maxdisk)
        uptime = c.looseDouble(.uptime)
        isTemplate = c.looseBool(.template) ?? false
        tags = (c.looseString(.tags) ?? "")
            .split(whereSeparator: { $0 == ";" || $0 == "," })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        pool = c.looseString(.pool)
        storage = c.looseString(.storage)
        pluginType = c.looseString(.plugintype)
        content = c.looseString(.content)
        shared = c.looseBool(.shared) ?? false
        hastate = c.looseString(.hastate)
        lock = c.looseString(.lock)
        diskread = c.looseDouble(.diskread)
        diskwrite = c.looseDouble(.diskwrite)
        netin = c.looseDouble(.netin)
        netout = c.looseDouble(.netout)
        level = c.looseString(.level)

        if let explicit = c.looseString(.id), !explicit.isEmpty {
            id = explicit
        } else if let vmid {
            id = "\(rawType ?? "guest")/\(vmid)"
        } else {
            id = "\(rawType ?? "res")/\(node ?? "")/\(storage ?? name ?? UUID().uuidString)"
        }
    }

    init(id: String, type: PVEResourceType, node: String? = nil, name: String? = nil,
         status: String? = nil, vmid: Int? = nil, cpu: Double? = nil, maxcpu: Double? = nil,
         mem: Double? = nil, maxmem: Double? = nil, disk: Double? = nil, maxdisk: Double? = nil,
         uptime: Double? = nil, isTemplate: Bool = false, tags: [String] = [], pool: String? = nil,
         storage: String? = nil, pluginType: String? = nil, content: String? = nil,
         shared: Bool = false, hastate: String? = nil, lock: String? = nil,
         diskread: Double? = nil, diskwrite: Double? = nil, netin: Double? = nil,
         netout: Double? = nil, level: String? = nil) {
        self.id = id; self.type = type; self.node = node; self.name = name
        self.status = status; self.vmid = vmid; self.cpu = cpu; self.maxcpu = maxcpu
        self.mem = mem; self.maxmem = maxmem; self.disk = disk; self.maxdisk = maxdisk
        self.uptime = uptime; self.isTemplate = isTemplate; self.tags = tags; self.pool = pool
        self.storage = storage; self.pluginType = pluginType; self.content = content
        self.shared = shared; self.hastate = hastate; self.lock = lock
        self.diskread = diskread; self.diskwrite = diskwrite; self.netin = netin
        self.netout = netout; self.level = level
    }
}

// MARK: - Node status (`/nodes/{node}/status`)

struct PVENodeStatus: Decodable, Sendable, Hashable {
    var uptime: Double?
    var cpu: Double?
    var cpuCount: Int?
    var cpuModel: String?
    var loadAverage: [Double]
    var memTotal: Double?
    var memUsed: Double?
    var swapTotal: Double?
    var swapUsed: Double?
    var rootTotal: Double?
    var rootUsed: Double?
    var kernelVersion: String?
    var pveVersion: String?
    var ioWait: Double?

    enum CodingKeys: String, CodingKey {
        case uptime, cpu, cpuinfo, loadavg, memory, swap, rootfs, kversion, pveversion, wait
    }
    enum CPUInfoKeys: String, CodingKey { case cpus, model, sockets }
    enum MemKeys: String, CodingKey { case total, used, free }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uptime = c.looseDouble(.uptime)
        cpu = c.looseDouble(.cpu)
        ioWait = c.looseDouble(.wait)
        kernelVersion = c.looseString(.kversion)
        pveVersion = c.looseString(.pveversion)

        if let info = try? c.nestedContainer(keyedBy: CPUInfoKeys.self, forKey: .cpuinfo) {
            cpuCount = info.looseInt(.cpus)
            cpuModel = info.looseString(.model)
        }
        if let raw = try? c.decodeIfPresent([JSONValue].self, forKey: .loadavg) {
            loadAverage = raw.compactMap(\.doubleValue)
        } else { loadAverage = [] }

        if let m = try? c.nestedContainer(keyedBy: MemKeys.self, forKey: .memory) {
            memTotal = m.looseDouble(.total); memUsed = m.looseDouble(.used)
        }
        if let s = try? c.nestedContainer(keyedBy: MemKeys.self, forKey: .swap) {
            swapTotal = s.looseDouble(.total); swapUsed = s.looseDouble(.used)
        }
        if let r = try? c.nestedContainer(keyedBy: MemKeys.self, forKey: .rootfs) {
            rootTotal = r.looseDouble(.total); rootUsed = r.looseDouble(.used)
        }
    }
}

// MARK: - Guest status (`/nodes/{n}/{qemu|lxc}/{id}/status/current`)

struct PVEGuestStatus: Decodable, Sendable, Hashable {
    var status: String?
    var name: String?
    var uptime: Double?
    var cpu: Double?
    var cpus: Double?
    var mem: Double?
    var maxmem: Double?
    var disk: Double?
    var maxdisk: Double?
    var diskread: Double?
    var diskwrite: Double?
    var netin: Double?
    var netout: Double?
    var pid: Int?
    var ha: String?
    var lock: String?
    var qmpstatus: String?
    var agentEnabled: Bool
    var balloon: Double?
    var freemem: Double?
    var runningMachine: String?
    var spice: Bool

    var state: PVERunState { PVERunState(raw: qmpstatus ?? status) }

    enum CodingKeys: String, CodingKey {
        case status, name, uptime, cpu, cpus, mem, maxmem, disk, maxdisk, diskread, diskwrite
        case netin, netout, pid, ha, lock, qmpstatus, agent, balloon, freemem
        case runningMachine = "running-machine", spice
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = c.looseString(.status)
        name = c.looseString(.name)
        uptime = c.looseDouble(.uptime)
        cpu = c.looseDouble(.cpu)
        cpus = c.looseDouble(.cpus)
        mem = c.looseDouble(.mem)
        maxmem = c.looseDouble(.maxmem)
        disk = c.looseDouble(.disk)
        maxdisk = c.looseDouble(.maxdisk)
        diskread = c.looseDouble(.diskread)
        diskwrite = c.looseDouble(.diskwrite)
        netin = c.looseDouble(.netin)
        netout = c.looseDouble(.netout)
        pid = c.looseInt(.pid)
        ha = (try? c.decodeIfPresent(JSONValue.self, forKey: .ha))?.displayString
        lock = c.looseString(.lock)
        qmpstatus = c.looseString(.qmpstatus)
        agentEnabled = c.looseBool(.agent) ?? false
        balloon = c.looseDouble(.balloon)
        freemem = c.looseDouble(.freemem)
        runningMachine = c.looseString(.runningMachine)
        spice = c.looseBool(.spice) ?? false
    }
}

// MARK: - Storage

struct PVEStorage: Identifiable, Decodable, Sendable, Hashable {
    var storage: String
    var node: String?
    var type: String?
    var content: String?
    var active: Bool
    var enabled: Bool
    var shared: Bool
    var total: Double?
    var used: Double?
    var avail: Double?
    var usedFraction: Double?

    var id: String { "\(node ?? "-")/\(storage)" }
    var contentTypes: [String] {
        (content ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
    }
    var fraction: Double {
        if let usedFraction { return max(0, min(1, usedFraction)) }
        guard let total, total > 0, let used else { return 0 }
        return max(0, min(1, used / total))
    }

    enum CodingKeys: String, CodingKey {
        case storage, node, type, content, active, enabled, shared, total, used, avail
        case usedFraction = "used_fraction"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        storage = c.looseString(.storage) ?? "—"
        node = c.looseString(.node)
        type = c.looseString(.type)
        content = c.looseString(.content)
        active = c.looseBool(.active) ?? true
        enabled = c.looseBool(.enabled) ?? true
        shared = c.looseBool(.shared) ?? false
        total = c.looseDouble(.total)
        used = c.looseDouble(.used)
        avail = c.looseDouble(.avail)
        usedFraction = c.looseDouble(.usedFraction)
    }
}

struct PVEStorageContent: Identifiable, Decodable, Sendable, Hashable {
    var volid: String
    var content: String?
    var format: String?
    var size: Double?
    var used: Double?
    var vmid: Int?
    var ctime: Double?
    var notes: String?
    var verificationState: String?
    var isProtected: Bool

    var id: String { volid }
    var filename: String { volid.split(separator: "/").last.map(String.init) ?? volid }
    var date: Date? { ctime.map { Date(timeIntervalSince1970: $0) } }

    enum CodingKeys: String, CodingKey {
        case volid, content, format, size, used, vmid, ctime, notes, verification, protected
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        volid = c.looseString(.volid) ?? "—"
        content = c.looseString(.content)
        format = c.looseString(.format)
        size = c.looseDouble(.size)
        used = c.looseDouble(.used)
        vmid = c.looseInt(.vmid)
        ctime = c.looseDouble(.ctime)
        notes = c.looseString(.notes)
        isProtected = c.looseBool(.protected) ?? false
        if let v = try? c.decodeIfPresent(JSONValue.self, forKey: .verification),
           case .object(let dict) = v {
            verificationState = dict["state"]?.displayString
        } else {
            verificationState = c.looseString(.verification)
        }
    }
}

// MARK: - Tasks

struct PVETask: Identifiable, Decodable, Sendable, Hashable {
    var upid: String
    var node: String?
    var type: String?
    var id: String { upid }
    var user: String?
    var status: String?
    var exitStatus: String?
    var startTime: Double?
    var endTime: Double?
    var pveTargetId: String?

    var start: Date? { startTime.map { Date(timeIntervalSince1970: $0) } }
    var end: Date? { endTime.map { Date(timeIntervalSince1970: $0) } }
    var isRunning: Bool { (status ?? "").lowercased() == "running" || endTime == nil }
    var succeeded: Bool { (exitStatus ?? status ?? "").uppercased().hasPrefix("OK") }
    var failed: Bool { !isRunning && !succeeded }

    var duration: TimeInterval? {
        guard let startTime else { return nil }
        return (endTime ?? Date().timeIntervalSince1970) - startTime
    }

    enum CodingKeys: String, CodingKey {
        case upid, node, type, user, status, exitstatus, starttime, endtime, id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        upid = c.looseString(.upid) ?? UUID().uuidString
        node = c.looseString(.node)
        type = c.looseString(.type)
        user = c.looseString(.user)
        status = c.looseString(.status)
        exitStatus = c.looseString(.exitstatus)
        startTime = c.looseDouble(.starttime)
        endTime = c.looseDouble(.endtime)
        pveTargetId = c.looseString(.id)
    }
}

struct PVETaskLogLine: Decodable, Sendable, Identifiable, Hashable {
    var n: Int
    var t: String
    var id: Int { n }

    enum CodingKeys: String, CodingKey { case n, t }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n = c.looseInt(.n) ?? 0
        t = c.looseString(.t) ?? ""
    }
}

// MARK: - Snapshots / backups / misc

struct PVESnapshot: Identifiable, Decodable, Sendable, Hashable {
    var name: String
    var description: String?
    var snaptime: Double?
    var parent: String?
    var vmstate: Bool
    var id: String { name }
    var date: Date? { snaptime.map { Date(timeIntervalSince1970: $0) } }
    var isCurrent: Bool { name == "current" }

    enum CodingKeys: String, CodingKey { case name, description, snaptime, parent, vmstate }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.looseString(.name) ?? "—"
        description = c.looseString(.description)
        snaptime = c.looseDouble(.snaptime)
        parent = c.looseString(.parent)
        vmstate = c.looseBool(.vmstate) ?? false
    }
}

struct PVENetworkInterface: Identifiable, Decodable, Sendable, Hashable {
    var iface: String
    var type: String?
    var active: Bool
    var autostart: Bool
    var address: String?
    var netmask: String?
    var gateway: String?
    var cidr: String?
    var bridgePorts: String?
    var comments: String?
    var id: String { iface }

    enum CodingKeys: String, CodingKey {
        case iface, type, active, autostart, address, netmask, gateway, cidr
        case bridge_ports, comments
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        iface = c.looseString(.iface) ?? "—"
        type = c.looseString(.type)
        active = c.looseBool(.active) ?? false
        autostart = c.looseBool(.autostart) ?? false
        address = c.looseString(.address)
        netmask = c.looseString(.netmask)
        gateway = c.looseString(.gateway)
        cidr = c.looseString(.cidr)
        bridgePorts = c.looseString(.bridge_ports)
        comments = c.looseString(.comments)
    }
}

struct PVEDisk: Identifiable, Decodable, Sendable, Hashable {
    var devpath: String
    var model: String?
    var serial: String?
    var size: Double?
    var type: String?
    var health: String?
    var wearout: Double?
    var used: String?
    var vendor: String?
    var rpm: Double?
    var id: String { devpath }

    enum CodingKeys: String, CodingKey {
        case devpath, model, serial, size, type, health, wearout, used, vendor, rpm
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        devpath = c.looseString(.devpath) ?? "—"
        model = c.looseString(.model)
        serial = c.looseString(.serial)
        size = c.looseDouble(.size)
        type = c.looseString(.type)
        health = c.looseString(.health)
        wearout = c.looseDouble(.wearout)
        used = c.looseString(.used)
        vendor = c.looseString(.vendor)
        rpm = c.looseDouble(.rpm)
    }
}

struct PVEService: Identifiable, Decodable, Sendable, Hashable {
    var service: String
    var name: String?
    var desc: String?
    var state: String?
    var unitState: String?
    var id: String { service }
    var isRunning: Bool { (state ?? "").lowercased() == "running" }

    enum CodingKeys: String, CodingKey {
        case service, name, desc, state
        case unitState = "unit-state"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        service = c.looseString(.service) ?? "—"
        name = c.looseString(.name)
        desc = c.looseString(.desc)
        state = c.looseString(.state)
        unitState = c.looseString(.unitState)
    }
}

struct PVEClusterNodeStatus: Decodable, Sendable, Hashable, Identifiable {
    var name: String
    var type: String?
    var online: Bool
    var ip: String?
    var local: Bool
    var quorate: Bool?
    var nodes: Int?
    var version: Int?
    var id: String { "\(type ?? "node")-\(name)" }

    enum CodingKeys: String, CodingKey {
        case name, type, online, ip, local, quorate, nodes, version
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.looseString(.name) ?? "—"
        type = c.looseString(.type)
        online = c.looseBool(.online) ?? false
        ip = c.looseString(.ip)
        local = c.looseBool(.local) ?? false
        quorate = c.looseBool(.quorate)
        nodes = c.looseInt(.nodes)
        version = c.looseInt(.version)
    }
}

struct PVEBackupJob: Identifiable, Decodable, Sendable, Hashable {
    var jobId: String
    var schedule: String?
    var storage: String?
    var enabled: Bool
    var comment: String?
    var mailto: String?
    var mode: String?
    var vmid: String?
    var all: Bool
    var next: Double?
    var id: String { jobId }
    var nextRun: Date? { next.map { Date(timeIntervalSince1970: $0) } }

    enum CodingKeys: String, CodingKey {
        case id, schedule, storage, enabled, comment, mailto, mode, vmid, all, next
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        jobId = c.looseString(.id) ?? UUID().uuidString
        schedule = c.looseString(.schedule)
        storage = c.looseString(.storage)
        enabled = c.looseBool(.enabled) ?? true
        comment = c.looseString(.comment)
        mailto = c.looseString(.mailto)
        mode = c.looseString(.mode)
        vmid = c.looseString(.vmid)
        all = c.looseBool(.all) ?? false
        next = c.looseDouble(.next)
    }
}

struct PVEVersion: Decodable, Sendable, Hashable {
    var version: String?
    var release: String?
    var repoid: String?
    enum CodingKeys: String, CodingKey { case version, release, repoid }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.looseString(.version)
        release = c.looseString(.release)
        repoid = c.looseString(.repoid)
    }
}

struct PVEAptUpdate: Identifiable, Decodable, Sendable, Hashable {
    var package: String
    var title: String?
    var version: String?
    var oldVersion: String?
    var priority: String?
    var section: String?
    var id: String { package }

    enum CodingKeys: String, CodingKey {
        case Package, Title, Version, OldVersion, Priority, Section
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        package = c.looseString(.Package) ?? "—"
        title = c.looseString(.Title)
        version = c.looseString(.Version)
        oldVersion = c.looseString(.OldVersion)
        priority = c.looseString(.Priority)
        section = c.looseString(.Section)
    }
}

struct PVEFirewallRule: Identifiable, Decodable, Sendable, Hashable {
    var pos: Int
    var type: String?
    var action: String?
    var enable: Bool
    var source: String?
    var dest: String?
    var proto: String?
    var dport: String?
    var sport: String?
    var comment: String?
    var iface: String?
    var id: Int { pos }

    enum CodingKeys: String, CodingKey {
        case pos, type, action, enable, source, dest, proto, dport, sport, comment, iface
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pos = c.looseInt(.pos) ?? 0
        type = c.looseString(.type)
        action = c.looseString(.action)
        enable = c.looseBool(.enable) ?? true
        source = c.looseString(.source)
        dest = c.looseString(.dest)
        proto = c.looseString(.proto)
        dport = c.looseString(.dport)
        sport = c.looseString(.sport)
        comment = c.looseString(.comment)
        iface = c.looseString(.iface)
    }
}

struct PVEPool: Identifiable, Decodable, Sendable, Hashable {
    var poolid: String
    var comment: String?
    var id: String { poolid }
    enum CodingKeys: String, CodingKey { case poolid, comment }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        poolid = c.looseString(.poolid) ?? "—"
        comment = c.looseString(.comment)
    }
}

struct PVEReplicationJob: Identifiable, Decodable, Sendable, Hashable {
    var jobId: String
    var source: String?
    var target: String?
    var schedule: String?
    var guest: Int?
    var disabled: Bool
    var lastSync: Double?
    var nextSync: Double?
    var duration: Double?
    var error: String?
    var id: String { jobId }

    enum CodingKeys: String, CodingKey {
        case id, source, target, schedule, guest, disable, last_sync, next_sync, duration, error
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        jobId = c.looseString(.id) ?? UUID().uuidString
        source = c.looseString(.source)
        target = c.looseString(.target)
        schedule = c.looseString(.schedule)
        guest = c.looseInt(.guest)
        disabled = c.looseBool(.disable) ?? false
        lastSync = c.looseDouble(.last_sync)
        nextSync = c.looseDouble(.next_sync)
        duration = c.looseDouble(.duration)
        error = c.looseString(.error)
    }
}
