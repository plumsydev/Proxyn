import Foundation

/// High-level, typed endpoint surface. Everything the UI touches goes through here.
extension ProxmoxClient {

    // MARK: Cluster

    func version() async throws -> PVEVersion {
        try await get("/version", as: PVEVersion.self)
    }

    func clusterResources(type: PVEResourceType? = nil) async throws -> [PVEResource] {
        var q: [String: String] = [:]
        if let type { q["type"] = type.rawValue }
        return try await get("/cluster/resources", query: q, as: [PVEResource].self)
    }

    func clusterStatus() async throws -> [PVEClusterNodeStatus] {
        try await get("/cluster/status", as: [PVEClusterNodeStatus].self)
    }

    func clusterTasks() async throws -> [PVETask] {
        try await get("/cluster/tasks", as: [PVETask].self)
    }

    func backupJobs() async throws -> [PVEBackupJob] {
        try await get("/cluster/backup", as: [PVEBackupJob].self)
    }

    func replicationJobs() async throws -> [PVEReplicationJob] {
        try await get("/cluster/replication", as: [PVEReplicationJob].self)
    }

    func pools() async throws -> [PVEPool] {
        try await get("/pools", as: [PVEPool].self)
    }

    func nextVMID() async throws -> Int {
        let value = try await get("/cluster/nextid", as: JSONValue.self)
        return value.intValue ?? 100
    }

    // MARK: Nodes

    func nodes() async throws -> [PVEResource] {
        try await get("/nodes", as: [PVEResource].self)
    }

    func nodeStatus(_ node: String) async throws -> PVENodeStatus {
        try await get("/nodes/\(node)/status", as: PVENodeStatus.self)
    }

    func nodeMetrics(_ node: String, timeframe: PVETimeframe) async throws -> [PVEMetricSample] {
        try await get("/nodes/\(node)/rrddata",
                      query: ["timeframe": timeframe.rawValue, "cf": "AVERAGE"],
                      as: [PVEMetricSample].self)
    }

    func nodeTasks(_ node: String, limit: Int = 60, errorsOnly: Bool = false) async throws -> [PVETask] {
        var q = ["limit": String(limit), "start": "0"]
        if errorsOnly { q["errors"] = "1" }
        return try await get("/nodes/\(node)/tasks", query: q, as: [PVETask].self)
    }

    func nodeNetwork(_ node: String) async throws -> [PVENetworkInterface] {
        try await get("/nodes/\(node)/network", as: [PVENetworkInterface].self)
    }

    func nodeDisks(_ node: String) async throws -> [PVEDisk] {
        try await get("/nodes/\(node)/disks/list", as: [PVEDisk].self)
    }

    func nodeServices(_ node: String) async throws -> [PVEService] {
        try await get("/nodes/\(node)/services", as: [PVEService].self)
    }

    @discardableResult
    func serviceCommand(_ node: String, service: String, command: String) async throws -> String? {
        try await post("/nodes/\(node)/services/\(service)/\(command)")
    }

    @discardableResult
    func nodePower(_ node: String, command: String) async throws -> String? {
        try await post("/nodes/\(node)/status", form: ["command": command])
    }

    func nodeStorages(_ node: String) async throws -> [PVEStorage] {
        try await get("/nodes/\(node)/storage", as: [PVEStorage].self)
    }

    func availableUpdates(_ node: String) async throws -> [PVEAptUpdate] {
        try await get("/nodes/\(node)/apt/update", as: [PVEAptUpdate].self)
    }

    @discardableResult
    func refreshRepositories(_ node: String) async throws -> String? {
        try await post("/nodes/\(node)/apt/update", form: ["notify": "0", "quiet": "1"])
    }

    func nodeDNS(_ node: String) async -> [String: JSONValue]? {
        await getOptional("/nodes/\(node)/dns", as: [String: JSONValue].self)
    }

    func nodeTime(_ node: String) async -> [String: JSONValue]? {
        await getOptional("/nodes/\(node)/time", as: [String: JSONValue].self)
    }

    @discardableResult
    func startAllGuests(_ node: String) async throws -> String? {
        try await post("/nodes/\(node)/startall")
    }

    @discardableResult
    func stopAllGuests(_ node: String) async throws -> String? {
        try await post("/nodes/\(node)/stopall")
    }

    // MARK: Guests

    func guests(on node: String, kind: PVEResourceType) async throws -> [PVEResource] {
        try await get("/nodes/\(node)/\(kind.rawValue)", as: [PVEResource].self)
    }

    func guestStatus(_ ref: GuestRef) async throws -> PVEGuestStatus {
        try await get("\(ref.basePath)/status/current", as: PVEGuestStatus.self)
    }

    func guestConfig(_ ref: GuestRef) async throws -> [String: JSONValue] {
        try await get("\(ref.basePath)/config", as: [String: JSONValue].self)
    }

    func guestPending(_ ref: GuestRef) async -> [JSONValue]? {
        await getOptional("\(ref.basePath)/pending", as: [JSONValue].self)
    }

    @discardableResult
    func updateGuestConfig(_ ref: GuestRef, values: [String: String]) async throws -> String? {
        try await put("\(ref.basePath)/config", form: values)
    }

    func guestMetrics(_ ref: GuestRef, timeframe: PVETimeframe) async throws -> [PVEMetricSample] {
        try await get("\(ref.basePath)/rrddata",
                      query: ["timeframe": timeframe.rawValue, "cf": "AVERAGE"],
                      as: [PVEMetricSample].self)
    }

    @discardableResult
    func guestPower(_ ref: GuestRef, action: GuestPowerAction, force: Bool = false) async throws -> String? {
        var form: [String: String] = [:]
        if force, action == .shutdown || action == .stop { form["forceStop"] = "1" }
        if action == .shutdown { form["timeout"] = "90" }
        return try await post("\(ref.basePath)/status/\(action.endpoint)", form: form)
    }

    func snapshots(_ ref: GuestRef) async throws -> [PVESnapshot] {
        try await get("\(ref.basePath)/snapshot", as: [PVESnapshot].self)
    }

    @discardableResult
    func createSnapshot(_ ref: GuestRef, name: String, description: String?, includeRAM: Bool) async throws -> String? {
        var form = ["snapname": name]
        if let description, !description.isEmpty { form["description"] = description }
        if includeRAM, ref.kind == .qemu { form["vmstate"] = "1" }
        return try await post("\(ref.basePath)/snapshot", form: form)
    }

    @discardableResult
    func deleteSnapshot(_ ref: GuestRef, name: String) async throws -> String? {
        try await delete("\(ref.basePath)/snapshot/\(name)")
    }

    @discardableResult
    func rollbackSnapshot(_ ref: GuestRef, name: String) async throws -> String? {
        try await post("\(ref.basePath)/snapshot/\(name)/rollback")
    }

    @discardableResult
    func cloneGuest(_ ref: GuestRef, newID: Int, name: String?, full: Bool,
                    targetNode: String?, storage: String?) async throws -> String? {
        var form = ["newid": String(newID)]
        if let name, !name.isEmpty { form["name"] = name }
        if full { form["full"] = "1" }
        if let targetNode, !targetNode.isEmpty { form["target"] = targetNode }
        if full, let storage, !storage.isEmpty { form["storage"] = storage }
        return try await post("\(ref.basePath)/clone", form: form)
    }

    @discardableResult
    func migrateGuest(_ ref: GuestRef, to target: String, online: Bool,
                      withLocalDisks: Bool) async throws -> String? {
        var form = ["target": target]
        if online { form["online"] = "1" }
        if withLocalDisks {
            form[ref.kind == .qemu ? "with-local-disks" : "restart"] = "1"
        }
        return try await post("\(ref.basePath)/migrate", form: form)
    }

    func migrationPreflight(_ ref: GuestRef, target: String) async -> [String: JSONValue]? {
        await getOptional("\(ref.basePath)/migrate", query: ["target": target], as: [String: JSONValue].self)
    }

    @discardableResult
    func resizeDisk(_ ref: GuestRef, disk: String, sizeIncrement: String) async throws -> String? {
        try await put("\(ref.basePath)/resize", form: ["disk": disk, "size": sizeIncrement])
    }

    @discardableResult
    func deleteGuest(_ ref: GuestRef, purge: Bool, destroyUnreferenced: Bool) async throws -> String? {
        var form: [String: String] = [:]
        if purge { form["purge"] = "1" }
        if destroyUnreferenced { form["destroy-unreferenced-disks"] = "1" }
        return try await delete(ref.basePath, form: form)
    }

    @discardableResult
    func convertToTemplate(_ ref: GuestRef) async throws -> String? {
        try await post("\(ref.basePath)/template")
    }

    func guestFirewallRules(_ ref: GuestRef) async -> [PVEFirewallRule]? {
        await getOptional("\(ref.basePath)/firewall/rules", as: [PVEFirewallRule].self)
    }

    func guestFirewallOptions(_ ref: GuestRef) async -> [String: JSONValue]? {
        await getOptional("\(ref.basePath)/firewall/options", as: [String: JSONValue].self)
    }

    @discardableResult
    func setGuestFirewall(_ ref: GuestRef, enabled: Bool) async throws -> String? {
        try await put("\(ref.basePath)/firewall/options", form: ["enable": enabled ? "1" : "0"])
    }

    // MARK: QEMU guest agent

    func agentNetworkInterfaces(_ ref: GuestRef) async -> [String: JSONValue]? {
        guard ref.kind == .qemu else { return nil }
        return await getOptional("\(ref.basePath)/agent/network-get-interfaces", as: [String: JSONValue].self)
    }

    func agentOSInfo(_ ref: GuestRef) async -> [String: JSONValue]? {
        guard ref.kind == .qemu else { return nil }
        return await getOptional("\(ref.basePath)/agent/get-osinfo", as: [String: JSONValue].self)
    }

    @discardableResult
    func agentCommand(_ ref: GuestRef, command: String) async throws -> String? {
        try await post("\(ref.basePath)/agent/\(command)")
    }

    // MARK: Console

    func vncProxy(_ ref: GuestRef, websocket: Bool = true) async throws -> [String: JSONValue] {
        var form: [String: String] = [:]
        if websocket { form["websocket"] = "1" }
        if ref.kind == .qemu { form["generate-password"] = "0" }
        return try await postObject("\(ref.basePath)/vncproxy", form: form)
    }

    func termProxy(_ ref: GuestRef) async throws -> [String: JSONValue] {
        try await postObject("\(ref.basePath)/termproxy", form: [:])
    }

    func nodeTermProxy(_ node: String) async throws -> [String: JSONValue] {
        try await postObject("/nodes/\(node)/termproxy", form: [:])
    }

    // MARK: Storage

    func storageContent(node: String, storage: String, content: String? = nil) async throws -> [PVEStorageContent] {
        var q: [String: String] = [:]
        if let content { q["content"] = content }
        return try await get("/nodes/\(node)/storage/\(storage)/content", query: q, as: [PVEStorageContent].self)
    }

    func storageStatus(node: String, storage: String) async -> [String: JSONValue]? {
        await getOptional("/nodes/\(node)/storage/\(storage)/status", as: [String: JSONValue].self)
    }

    @discardableResult
    func deleteVolume(node: String, volid: String) async throws -> String? {
        let encoded = volid.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? volid
        return try await delete("/nodes/\(node)/storage/\(volid.components(separatedBy: ":").first ?? "")/content/\(encoded)")
    }

    @discardableResult
    func setVolumeProtection(node: String, volid: String, isProtected: Bool) async throws -> String? {
        let store = volid.components(separatedBy: ":").first ?? ""
        let encoded = volid.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? volid
        return try await put("/nodes/\(node)/storage/\(store)/content/\(encoded)",
                             form: ["protected": isProtected ? "1" : "0"])
    }

    @discardableResult
    func downloadToStorage(node: String, storage: String, url: String,
                           content: String, filename: String) async throws -> String? {
        // Certificate verification stays on (the Proxmox default): the node is
        // fetching an arbitrary file from the internet.
        try await post("/nodes/\(node)/storage/\(storage)/download-url",
                       form: ["content": content, "filename": filename, "url": url])
    }

    // MARK: Backup / restore

    @discardableResult
    func backupNow(node: String, vmid: Int, storage: String, mode: String,
                   compress: String, notes: String?, isProtected: Bool) async throws -> String? {
        var form = [
            "vmid": String(vmid), "storage": storage, "mode": mode,
            "compress": compress, "remove": "0"
        ]
        if let notes, !notes.isEmpty { form["notes-template"] = notes }
        if isProtected { form["protected"] = "1" }
        return try await post("/nodes/\(node)/vzdump", form: form)
    }

    @discardableResult
    func restoreBackup(node: String, kind: PVEResourceType, vmid: Int, archive: String,
                       storage: String?, force: Bool, startAfter: Bool) async throws -> String? {
        var form: [String: String] = ["vmid": String(vmid)]
        if force { form["force"] = "1" }
        if kind == .qemu {
            form["archive"] = archive
        } else {
            form["ostemplate"] = archive
            form["restore"] = "1"
        }
        if let storage, !storage.isEmpty { form["storage"] = storage }
        if startAfter { form["start"] = "1" }
        return try await post("/nodes/\(node)/\(kind.rawValue)", form: form)
    }

    func backupFileConfig(node: String, volume: String) async -> String? {
        let result: [String: JSONValue]? = await getOptional(
            "/nodes/\(node)/vzdump/extractconfig", query: ["volume": volume], as: [String: JSONValue].self)
        return result?.map { "\($0.key)=\($0.value.displayString)" }.sorted().joined(separator: "\n")
    }

    // MARK: Tasks

    func taskStatus(node: String, upid: String) async throws -> PVETask {
        let encoded = upid.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? upid
        return try await get("/nodes/\(node)/tasks/\(encoded)/status", as: PVETask.self)
    }

    func taskLog(node: String, upid: String, start: Int = 0, limit: Int = 500) async throws -> [PVETaskLogLine] {
        let encoded = upid.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? upid
        return try await get("/nodes/\(node)/tasks/\(encoded)/log",
                             query: ["start": String(start), "limit": String(limit)],
                             as: [PVETaskLogLine].self)
    }

    @discardableResult
    func stopTask(node: String, upid: String) async throws -> String? {
        let encoded = upid.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? upid
        return try await delete("/nodes/\(node)/tasks/\(encoded)")
    }
}

// MARK: - Guest addressing

/// `node + kind + vmid` — the tuple every guest endpoint needs.
struct GuestRef: Hashable, Sendable, Identifiable {
    var node: String
    var kind: PVEResourceType
    var vmid: Int

    var id: String { "\(node)/\(kind.rawValue)/\(vmid)" }
    var basePath: String { "/nodes/\(node)/\(kind.rawValue)/\(vmid)" }

    init(node: String, kind: PVEResourceType, vmid: Int) {
        self.node = node
        self.kind = kind
        self.vmid = vmid
    }

    init?(resource: PVEResource) {
        guard resource.type.isGuest, let node = resource.node, let vmid = resource.vmid else { return nil }
        self.init(node: node, kind: resource.type, vmid: vmid)
    }
}

enum GuestPowerAction: String, CaseIterable, Sendable, Identifiable {
    case start, shutdown, stop, reboot, suspend, resume, reset
    var id: String { rawValue }

    var endpoint: String { rawValue }

    var label: String {
        switch self {
        case .start: return "Start"
        case .shutdown: return "Shut Down"
        case .stop: return "Force Stop"
        case .reboot: return "Reboot"
        case .suspend: return "Suspend"
        case .resume: return "Resume"
        case .reset: return "Reset"
        }
    }

    var symbol: String {
        switch self {
        case .start: return "play"
        case .shutdown: return "power"
        case .stop: return "stop"
        case .reboot: return "arrow.clockwise"
        case .suspend: return "pause"
        case .resume: return "playpause"
        case .reset: return "bolt.horizontal"
        }
    }

    var isDestructive: Bool { self == .stop || self == .reset }

    var confirmationMessage: String {
        switch self {
        case .stop: return "Cuts power to the guest immediately. Unsaved data may be lost."
        case .reset: return "Performs a hard reset, like pressing the reset button."
        case .reboot: return "The guest operating system will restart."
        case .shutdown: return "Sends an ACPI shutdown request to the guest."
        default: return ""
        }
    }

    func isAvailable(for state: PVERunState, kind: PVEResourceType) -> Bool {
        switch self {
        case .start: return !state.isUp && !state.isPaused
        case .shutdown, .reboot, .stop: return state.isUp || state.isPaused
        case .suspend: return state.isUp
        case .resume: return state.isPaused
        case .reset: return state.isUp && kind == .qemu
        }
    }
}
