import WidgetKit
import Foundation

/// Loads the widget payload: the shared snapshot when it's recent, otherwise a
/// live fetch using the profile and Keychain secret shared by the app.
enum WidgetData {
    /// Several widget kinds refresh together; within this window they share
    /// one fetch instead of each hitting the server.
    static let freshness: TimeInterval = 5 * 60

    static func load() async -> WidgetSnapshot? {
        let cached = SharedSnapshotStore.load()
        let server = SharedSnapshotStore.selectedServer()

        if let cached, cached.serverID == server?.id,
           Date().timeIntervalSince(cached.capturedAt) < freshness {
            return cached
        }
        return await fetch(server: server, previous: cached) ?? cached
    }

    /// Accounts protected by a one-time code can't sign in unattended; those
    /// keep showing the app's last snapshot.
    private static func fetch(server: ServerProfile?, previous: WidgetSnapshot?) async -> WidgetSnapshot? {
        guard let server else { return nil }
        let client = ProxmoxClient(profile: server)

        guard let resources = try? await client.clusterResources() else { return nil }
        let tasks = (try? await client.clusterTasks()) ?? []

        let snapshot = ClusterSnapshot(resources: resources, tasks: tasks, capturedAt: Date())
        let history = previous?.serverID == server.id ? (previous?.cpuHistory ?? []) : []
        let widget = WidgetSnapshot(snapshot: snapshot, serverID: server.id,
                                    serverName: server.displayName, previousHistory: history)
        SharedSnapshotStore.save(widget)
        return widget
    }

    static var nextRefresh: Date { Date().addingTimeInterval(15 * 60) }
}

struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot?

    var isStale: Bool {
        guard let snapshot else { return true }
        return date.timeIntervalSince(snapshot.capturedAt) > 30 * 60
    }
}

/// Shared provider for the non-configurable widgets.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        if context.isPreview {
            completion(SnapshotEntry(date: Date(), snapshot: SharedSnapshotStore.load() ?? .preview))
            return
        }
        Task { completion(SnapshotEntry(date: Date(), snapshot: await WidgetData.load())) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        Task {
            let entry = SnapshotEntry(date: Date(), snapshot: await WidgetData.load())
            completion(Timeline(entries: [entry], policy: .after(WidgetData.nextRefresh)))
        }
    }
}

// MARK: - Gallery preview data

extension WidgetSnapshot {
    /// Shown in the widget gallery before the user has added a server.
    static let preview: WidgetSnapshot = {
        var s = WidgetSnapshot()
        s.serverName = "homelab"
        s.capturedAt = Date()
        s.cpu = 0.27; s.memory = 0.46; s.storage = 0.69
        s.memoryUsed = 52 * 1_073_741_824; s.memoryTotal = 112 * 1_073_741_824
        s.storageUsed = 9.7 * 1_099_511_627_776; s.storageTotal = 14 * 1_099_511_627_776
        s.cores = 32
        s.cpuHistory = [0.21, 0.24, 0.22, 0.29, 0.34, 0.31, 0.27, 0.25, 0.30, 0.36, 0.33, 0.27]
        s.guests = [
            .preview(100, "opnsense", "pve-alpha", "qemu", "running", cpu: 0.12, used: 2.4, total: 4),
            .preview(101, "truenas", "pve-alpha", "qemu", "running", cpu: 0.41, used: 18, total: 24),
            .preview(102, "home-assistant", "pve-alpha", "qemu", "running", cpu: 0.08, used: 2.1, total: 4),
            .preview(113, "jellyfin", "pve-beta", "lxc", "running", cpu: 0.33, used: 3.9, total: 6),
            .preview(111, "postgres", "pve-alpha", "lxc", "running", cpu: 0.19, used: 5.2, total: 8),
            .preview(103, "win11-lab", "pve-beta", "qemu", "stopped", cpu: 0, used: 0, total: 16)
        ]
        s.nodes = [
            .preview("pve-alpha", cpu: 0.28, memory: 0.47, cores: 16),
            .preview("pve-beta", cpu: 0.22, memory: 0.54, cores: 12),
            .preview("pve-edge", cpu: 0.41, memory: 0.38, cores: 4)
        ]
        s.storages = [
            .preview("pbs-offsite", node: "pve-alpha", shared: true, used: 3.7, total: 4.0, type: "pbs"),
            .preview("nas-nfs", node: "pve-alpha", shared: true, used: 5.2, total: 8.0, type: "nfs"),
            .preview("local-lvm", node: "pve-beta", shared: false, used: 0.28, total: 0.45, type: "lvmthin")
        ]
        s.tasks = [
            .preview("vzdump", target: "111", node: "pve-alpha", minutesAgo: 0, running: true, ok: true),
            .preview("qmsnapshot", target: "102", node: "pve-alpha", minutesAgo: 42, running: false, ok: true),
            .preview("qmigrate", target: "104", node: "pve-beta", minutesAgo: 180, running: false, ok: true),
            .preview("vzdump", target: "114", node: "pve-edge", minutesAgo: 540, running: false, ok: false)
        ]
        return s
    }()
}

private extension WidgetTask {
    static func preview(_ type: String, target: String, node: String, minutesAgo: Double,
                        running: Bool, ok: Bool) -> WidgetTask {
        let end = Date().addingTimeInterval(-minutesAgo * 60)
        let json = """
        {"upid": "UPID:\(node):\(type):\(target):\(minutesAgo)", "type": "\(type)", "id": "\(target)",
         "node": "\(node)", "status": "\(running ? "running" : "stopped")",
         "exitstatus": "\(ok ? "OK" : "ERROR")", "starttime": \(end.addingTimeInterval(-60).timeIntervalSince1970)
         \(running ? "" : ", \"endtime\": \(end.timeIntervalSince1970)")}
        """
        let task = (try? JSONDecoder().decode(PVETask.self, from: Data(json.utf8)))
        return task.map(WidgetTask.init) ?? WidgetTask.placeholder
    }
}

private extension WidgetGuest {
    static func preview(_ vmid: Int, _ name: String, _ node: String, _ kind: String, _ status: String,
                        cpu: Double, used: Double, total: Double) -> WidgetGuest {
        let resource = PVEResource(id: "\(kind)/\(vmid)", type: PVEResourceType(raw: kind), node: node,
                                   name: name, status: status, vmid: vmid, cpu: cpu, maxcpu: 4,
                                   mem: used * 1_073_741_824, maxmem: total * 1_073_741_824,
                                   uptime: status == "running" ? 1_840_000 : 0)
        // Every preview resource carries a vmid and a node, so this never fails.
        return WidgetGuest(resource) ?? WidgetGuest.placeholder
    }
}

private extension WidgetNode {
    static func preview(_ name: String, cpu: Double, memory: Double, cores: Double) -> WidgetNode {
        WidgetNode(PVEResource(id: "node/\(name)", type: .node, node: name, name: name, status: "online",
                               cpu: cpu, maxcpu: cores, mem: memory * 100, maxmem: 100, uptime: 1_840_000))
    }
}

private extension WidgetStorage {
    static func preview(_ name: String, node: String, shared: Bool, used: Double, total: Double,
                        type: String) -> WidgetStorage {
        WidgetStorage(PVEResource(id: "storage/\(node)/\(name)", type: .storage, node: node,
                                  disk: used * 1_099_511_627_776, maxdisk: total * 1_099_511_627_776,
                                  storage: name, pluginType: type, shared: shared))
    }
}
