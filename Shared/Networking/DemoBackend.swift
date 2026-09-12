import Foundation

/// A self-contained, stateful fake of the Proxmox API.
///
/// It plugs in at the transport layer of `ProxmoxClient`, so every screen,
/// action and even the widget work against it unchanged — no `if isDemo`
/// scattered through the UI. Values drift over time (sine + jitter seeded per
/// guest) so charts and gauges actually move.
final class DemoBackend {

    static let host = "demo.proxyn.local"

    // MARK: Model

    private struct DemoNode {
        var name: String
        var cores: Double
        var memory: Double
        var rootTotal: Double
        var rootUsed: Double
        var online: Bool
        var seed: Double
        var cpuModel: String
    }

    private struct DemoGuest {
        var vmid: Int
        var name: String
        var kind: String        // qemu | lxc
        var node: String
        var cores: Double
        var maxmem: Double
        var maxdisk: Double
        var running: Bool
        var template: Bool
        var tags: [String]
        var seed: Double
        var startedAt: Date
        var osType: String
        var pool: String?
        var snapshots: [(name: String, description: String, time: Date, vmstate: Bool)]
    }

    private struct DemoStorage {
        var name: String
        var node: String
        var type: String
        var content: String
        var total: Double
        var used: Double
        var shared: Bool
    }

    private var nodes: [DemoNode]
    private var guests: [DemoGuest]
    private var storages: [DemoStorage]
    private var tasks: [[String: Any]] = []
    private var taskLogs: [String: [String]] = [:]
    private let bootedAt = Date()

    // MARK: Setup

    init() {
        let gb = 1_073_741_824.0
        nodes = [
            DemoNode(name: "pve-alpha", cores: 16, memory: 64 * gb, rootTotal: 96 * gb,
                     rootUsed: 31 * gb, online: true, seed: 0.3,
                     cpuModel: "AMD Ryzen 9 5950X 16-Core Processor"),
            DemoNode(name: "pve-beta", cores: 12, memory: 32 * gb, rootTotal: 64 * gb,
                     rootUsed: 22 * gb, online: true, seed: 1.7,
                     cpuModel: "Intel(R) Xeon(R) E-2276G CPU @ 3.80GHz"),
            DemoNode(name: "pve-edge", cores: 4, memory: 16 * gb, rootTotal: 32 * gb,
                     rootUsed: 19 * gb, online: true, seed: 3.1,
                     cpuModel: "Intel(R) N100")
        ]

        func snaps(_ items: [(String, String, TimeInterval, Bool)]) -> [(String, String, Date, Bool)] {
            items.map { ($0.0, $0.1, Date().addingTimeInterval(-$0.2), $0.3) }
        }

        guests = [
            DemoGuest(vmid: 100, name: "opnsense", kind: "qemu", node: "pve-alpha", cores: 4,
                      maxmem: 4 * gb, maxdisk: 32 * gb, running: true, template: false,
                      tags: ["network", "critical"], seed: 0.4,
                      startedAt: Date().addingTimeInterval(-1_840_000), osType: "l26", pool: "infra",
                      snapshots: snaps([("pre-upgrade-24.7", "Before OPNsense 24.7 upgrade", 259_200, false)])),
            DemoGuest(vmid: 101, name: "truenas", kind: "qemu", node: "pve-alpha", cores: 6,
                      maxmem: 24 * gb, maxdisk: 64 * gb, running: true, template: false,
                      tags: ["storage"], seed: 1.2,
                      startedAt: Date().addingTimeInterval(-1_820_000), osType: "l26", pool: "infra",
                      snapshots: []),
            DemoGuest(vmid: 102, name: "home-assistant", kind: "qemu", node: "pve-alpha", cores: 2,
                      maxmem: 4 * gb, maxdisk: 48 * gb, running: true, template: false,
                      tags: ["home"], seed: 2.6,
                      startedAt: Date().addingTimeInterval(-604_800), osType: "l26", pool: "home",
                      snapshots: snaps([("2025.6.3", "Known good release", 86_400, true),
                                        ("2025.5.1", "", 1_900_000, false)])),
            DemoGuest(vmid: 103, name: "win11-lab", kind: "qemu", node: "pve-beta", cores: 8,
                      maxmem: 16 * gb, maxdisk: 256 * gb, running: false, template: false,
                      tags: ["lab"], seed: 3.9,
                      startedAt: Date(), osType: "win11", pool: nil, snapshots: []),
            DemoGuest(vmid: 104, name: "k3s-master", kind: "qemu", node: "pve-beta", cores: 4,
                      maxmem: 8 * gb, maxdisk: 80 * gb, running: true, template: false,
                      tags: ["k8s"], seed: 0.9,
                      startedAt: Date().addingTimeInterval(-920_000), osType: "l26", pool: "cluster",
                      snapshots: []),
            DemoGuest(vmid: 105, name: "k3s-worker-1", kind: "qemu", node: "pve-beta", cores: 4,
                      maxmem: 8 * gb, maxdisk: 80 * gb, running: true, template: false,
                      tags: ["k8s"], seed: 1.6,
                      startedAt: Date().addingTimeInterval(-919_000), osType: "l26", pool: "cluster",
                      snapshots: []),
            DemoGuest(vmid: 106, name: "k3s-worker-2", kind: "qemu", node: "pve-edge", cores: 2,
                      maxmem: 6 * gb, maxdisk: 80 * gb, running: true, template: false,
                      tags: ["k8s"], seed: 2.3,
                      startedAt: Date().addingTimeInterval(-918_000), osType: "l26", pool: "cluster",
                      snapshots: []),
            DemoGuest(vmid: 110, name: "nginx-proxy", kind: "lxc", node: "pve-alpha", cores: 2,
                      maxmem: 1 * gb, maxdisk: 8 * gb, running: true, template: false,
                      tags: ["web", "network"], seed: 4.1,
                      startedAt: Date().addingTimeInterval(-1_800_000), osType: "debian", pool: "infra",
                      snapshots: []),
            DemoGuest(vmid: 111, name: "postgres", kind: "lxc", node: "pve-alpha", cores: 4,
                      maxmem: 8 * gb, maxdisk: 120 * gb, running: true, template: false,
                      tags: ["database", "critical"], seed: 0.1,
                      startedAt: Date().addingTimeInterval(-1_790_000), osType: "debian", pool: "infra",
                      snapshots: snaps([("pre-pg16", "Before PostgreSQL 16 upgrade", 432_000, false)])),
            DemoGuest(vmid: 112, name: "gitea", kind: "lxc", node: "pve-beta", cores: 2,
                      maxmem: 2 * gb, maxdisk: 40 * gb, running: true, template: false,
                      tags: ["dev"], seed: 2.9,
                      startedAt: Date().addingTimeInterval(-1_200_000), osType: "debian", pool: nil,
                      snapshots: []),
            DemoGuest(vmid: 113, name: "jellyfin", kind: "lxc", node: "pve-beta", cores: 6,
                      maxmem: 6 * gb, maxdisk: 32 * gb, running: true, template: false,
                      tags: ["media"], seed: 1.1,
                      startedAt: Date().addingTimeInterval(-320_000), osType: "debian", pool: "home",
                      snapshots: []),
            DemoGuest(vmid: 114, name: "wireguard", kind: "lxc", node: "pve-edge", cores: 1,
                      maxmem: 512 * 1_048_576, maxdisk: 4 * gb, running: true, template: false,
                      tags: ["network"], seed: 3.4,
                      startedAt: Date().addingTimeInterval(-1_700_000), osType: "debian", pool: "infra",
                      snapshots: []),
            DemoGuest(vmid: 115, name: "uptime-kuma", kind: "lxc", node: "pve-edge", cores: 1,
                      maxmem: 1 * gb, maxdisk: 8 * gb, running: true, template: false,
                      tags: ["monitoring"], seed: 4.7,
                      startedAt: Date().addingTimeInterval(-1_650_000), osType: "debian", pool: nil,
                      snapshots: []),
            DemoGuest(vmid: 120, name: "vaultwarden", kind: "lxc", node: "pve-alpha", cores: 1,
                      maxmem: 1 * gb, maxdisk: 8 * gb, running: false, template: false,
                      tags: ["security"], seed: 2.2,
                      startedAt: Date(), osType: "debian", pool: nil, snapshots: []),
            DemoGuest(vmid: 900, name: "debian-12-modele", kind: "qemu", node: "pve-alpha", cores: 2,
                      maxmem: 2 * gb, maxdisk: 16 * gb, running: false, template: true,
                      tags: [], seed: 0.5, startedAt: Date(), osType: "l26", pool: nil, snapshots: [])
        ]

        storages = [
            DemoStorage(name: "local", node: "pve-alpha", type: "dir", content: "iso,vztmpl,backup",
                        total: 96 * gb, used: 31 * gb, shared: false),
            DemoStorage(name: "local-lvm", node: "pve-alpha", type: "lvmthin", content: "images,rootdir",
                        total: 890 * gb, used: 412 * gb, shared: false),
            DemoStorage(name: "local", node: "pve-beta", type: "dir", content: "iso,vztmpl,backup",
                        total: 64 * gb, used: 22 * gb, shared: false),
            DemoStorage(name: "local-lvm", node: "pve-beta", type: "lvmthin", content: "images,rootdir",
                        total: 460 * gb, used: 288 * gb, shared: false),
            DemoStorage(name: "local", node: "pve-edge", type: "dir", content: "iso,vztmpl,backup",
                        total: 32 * gb, used: 19 * gb, shared: false),
            DemoStorage(name: "nas-nfs", node: "pve-alpha", type: "nfs", content: "images,iso,backup",
                        total: 8192 * gb, used: 5310 * gb, shared: true),
            DemoStorage(name: "pbs-offsite", node: "pve-alpha", type: "pbs", content: "backup",
                        total: 4096 * gb, used: 3820 * gb, shared: true)
        ]

        seedTasks()
    }

    // MARK: Deterministic wobble

    private func wave(_ seed: Double, period: Double, amplitude: Double, base: Double) -> Double {
        let t = Date().timeIntervalSince1970
        let a = sin(t / period + seed * 2.1)
        let b = sin(t / (period * 0.37) + seed * 5.7) * 0.45
        let c = sin(t / (period * 0.11) + seed * 11.3) * 0.18
        return max(0, base + (a + b + c) / 1.63 * amplitude)
    }

    private func nodeCPU(_ node: DemoNode) -> Double {
        guard node.online else { return 0 }
        return min(0.97, wave(node.seed, period: 95, amplitude: 0.16, base: 0.24 + node.seed * 0.03))
    }

    private func nodeMemUsed(_ node: DemoNode) -> Double {
        let allocated = guests
            .filter { $0.node == node.name && $0.running }
            .reduce(0.0) { $0 + self.guestMem($1) }
        return min(node.memory * 0.97, allocated + node.memory * 0.12)
    }

    private func guestCPU(_ guest: DemoGuest) -> Double {
        guard guest.running else { return 0 }
        let base = guest.kind == "qemu" ? 0.12 : 0.07
        return min(0.99, wave(guest.seed, period: 62, amplitude: 0.13, base: base + guest.seed * 0.02))
    }

    private func guestMem(_ guest: DemoGuest) -> Double {
        guard guest.running else { return 0 }
        let fraction = min(0.95, 0.42 + wave(guest.seed + 0.7, period: 180, amplitude: 0.12, base: 0.1))
        return guest.maxmem * fraction
    }

    private func counter(_ seed: Double, rate: Double) -> Double {
        Date().timeIntervalSince(bootedAt) * rate * (0.6 + seed.truncatingRemainder(dividingBy: 1))
    }

    // MARK: Task seeding

    private func seedTasks() {
        let now = Date().timeIntervalSince1970
        let samples: [(String, String, String, Double, Double, String)] = [
            ("vzdump", "pve-alpha", "111", 3600, 3421, "OK"),
            ("qmsnapshot", "pve-alpha", "102", 7200, 7195, "OK"),
            ("vzstart", "pve-edge", "115", 10800, 10798, "OK"),
            ("qmigrate", "pve-beta", "104", 14400, 14280, "OK"),
            ("vzdump", "pve-beta", "113", 21600, 21100, "OK"),
            ("aptupdate", "pve-edge", "", 28800, 28795, "OK"),
            ("vzdump", "pve-edge", "114", 36000, 35400,
             "job errored: unable to open file '/mnt/pbs/…' - No space left on device")
        ]
        for (index, item) in samples.enumerated() {
            let start = now - item.3
            let upid = "UPID:\(item.1):0000\(1000 + index):00ABCDEF:\(Int(start)):\(item.0):\(item.2):root@pam:"
            tasks.append([
                "upid": upid, "node": item.1, "type": item.0, "id": item.2,
                "user": "root@pam", "status": "stopped", "exitstatus": item.5,
                "starttime": start, "endtime": now - item.4
            ])
            taskLogs[upid] = [
                "INFO: starting \(item.0) for \(item.2.isEmpty ? "node" : "guest " + item.2)",
                "INFO: using storage 'pbs-offsite'",
                "INFO: creating archive",
                "INFO: transferred 4.21 GiB in 38s (113 MiB/s)",
                item.5 == "OK" ? "TASK OK" : "ERROR: \(item.5)",
                item.5 == "OK" ? "" : "TASK ERROR: \(item.5)"
            ].filter { !$0.isEmpty }
        }
    }

    private func pushTask(type: String, node: String, id: String, duration: Double = 6) -> String {
        let start = Date().timeIntervalSince1970
        let upid = "UPID:\(node):0000\(Int.random(in: 2000...9999)):00ABCDEF:\(Int(start)):\(type):\(id):root@pam:"
        tasks.insert([
            "upid": upid, "node": node, "type": type, "id": id, "user": "root@pam",
            "status": "stopped", "exitstatus": "OK",
            "starttime": start, "endtime": start + duration
        ], at: 0)
        taskLogs[upid] = [
            "INFO: starting \(type) on \(id.isEmpty ? node : id)",
            "INFO: checking prerequisites",
            "INFO: applying changes",
            "TASK OK"
        ]
        return upid
    }

    // MARK: Routing

    func response(method: String, path: String, query: [String: String],
                  form: [String: String]) -> Data? {
        let clean = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let parts = clean.split(separator: "/").map(String.init)

        if parts.count >= 5, parts[0] == "nodes", parts[2] == "tasks",
           let response = taskResponse(path: clean) {
            return response
        }

        if method != "GET" {
            return mutate(method: method, parts: parts, form: form)
        }

        switch parts.first {
        case "version":
            return envelope(["version": "8.3.2", "release": "8.3", "repoid": "d4b9f1e2"])
        case "cluster":
            return cluster(parts: Array(parts.dropFirst()), query: query)
        case "pools":
            return envelope([["poolid": "infra", "comment": "Core infrastructure"],
                             ["poolid": "home", "comment": "Home automation and media"],
                             ["poolid": "cluster", "comment": "Kubernetes nodes"]])
        case "nodes":
            return nodeRoute(parts: Array(parts.dropFirst()), query: query)
        case "access":
            return envelope([String: Any]())
        default:
            return envelope(NSNull())
        }
    }

    // MARK: /cluster

    private func cluster(parts: [String], query: [String: String]) -> Data? {
        switch parts.first {
        case "resources":
            return envelope(resourceList(filter: query["type"]))
        case "status":
            var out: [[String: Any]] = [[
                "type": "cluster", "id": "cluster", "name": "homelab",
                "nodes": nodes.count, "quorate": 1, "version": 7
            ]]
            for (index, node) in nodes.enumerated() {
                out.append(["type": "node", "id": "node/\(node.name)", "name": node.name,
                            "online": node.online ? 1 : 0, "local": index == 0 ? 1 : 0,
                            "ip": "192.168.10.\(11 + index)", "level": ""])
            }
            return envelope(out)
        case "tasks":
            return envelope(tasks)
        case "backup":
            return envelope([[
                "id": "backup-demo-01", "schedule": "sun 02:00", "storage": "pbs-offsite",
                "enabled": 1, "comment": "Weekly full backup", "mode": "snapshot",
                "all": 1, "next": Date().addingTimeInterval(186_000).timeIntervalSince1970
            ], [
                "id": "backup-demo-02", "schedule": "mon..fri 23:30", "storage": "nas-nfs",
                "enabled": 1, "comment": "Critical services, nightly", "mode": "snapshot",
                "vmid": "100,111,120", "all": 0,
                "next": Date().addingTimeInterval(42_000).timeIntervalSince1970
            ]])
        case "replication":
            return envelope([[
                "id": "104-0", "guest": 104, "source": "pve-beta", "target": "pve-alpha",
                "schedule": "*/15", "disable": 0,
                "last_sync": Date().addingTimeInterval(-540).timeIntervalSince1970,
                "next_sync": Date().addingTimeInterval(360).timeIntervalSince1970,
                "duration": 12.4
            ]])
        case "nextid":
            let used = Set(guests.map(\.vmid))
            var candidate = 100
            while used.contains(candidate) { candidate += 1 }
            return envelope(candidate)
        default:
            return envelope(NSNull())
        }
    }

    private func resourceList(filter: String?) -> [[String: Any]] {
        var out: [[String: Any]] = []

        if filter == nil || filter == "node" {
            for node in nodes {
                let cpu = nodeCPU(node)
                out.append([
                    "id": "node/\(node.name)", "type": "node", "node": node.name,
                    "status": node.online ? "online" : "offline",
                    "cpu": cpu, "maxcpu": node.cores,
                    "mem": nodeMemUsed(node), "maxmem": node.memory,
                    "disk": node.rootUsed, "maxdisk": node.rootTotal,
                    "uptime": node.online ? 1_842_000 + Date().timeIntervalSince(bootedAt) : 0,
                    "level": ""
                ])
            }
        }

        if filter == nil || filter == "qemu" || filter == "lxc" {
            for guest in guests where filter == nil || filter == guest.kind {
                var row: [String: Any] = [
                    "id": "\(guest.kind)/\(guest.vmid)", "type": guest.kind, "node": guest.node,
                    "name": guest.name, "vmid": guest.vmid,
                    "status": guest.running ? "running" : "stopped",
                    "template": guest.template ? 1 : 0,
                    "cpu": guestCPU(guest), "maxcpu": guest.cores,
                    "mem": guestMem(guest), "maxmem": guest.maxmem,
                    "disk": guest.running ? guest.maxdisk * 0.41 : 0, "maxdisk": guest.maxdisk,
                    "uptime": guest.running ? Date().timeIntervalSince(guest.startedAt) : 0,
                    "netin": guest.running ? counter(guest.seed, rate: 142_000) : 0,
                    "netout": guest.running ? counter(guest.seed + 0.3, rate: 96_000) : 0,
                    "diskread": guest.running ? counter(guest.seed + 0.6, rate: 58_000) : 0,
                    "diskwrite": guest.running ? counter(guest.seed + 0.9, rate: 41_000) : 0
                ]
                if !guest.tags.isEmpty { row["tags"] = guest.tags.joined(separator: ";") }
                if let pool = guest.pool { row["pool"] = pool }
                out.append(row)
            }
        }

        if filter == nil || filter == "storage" {
            for storage in storages {
                out.append([
                    "id": "storage/\(storage.node)/\(storage.name)", "type": "storage",
                    "node": storage.node, "storage": storage.name, "status": "available",
                    "plugintype": storage.type, "content": storage.content,
                    "shared": storage.shared ? 1 : 0,
                    "disk": storage.used, "maxdisk": storage.total
                ])
            }
        }

        return out
    }

    // MARK: /nodes

    private func nodeRoute(parts: [String], query: [String: String]) -> Data? {
        guard let nodeName = parts.first else {
            return envelope(nodes.map { node in
                ["node": node.name, "id": "node/\(node.name)", "type": "node",
                 "status": node.online ? "online" : "offline",
                 "cpu": nodeCPU(node), "maxcpu": node.cores,
                 "mem": nodeMemUsed(node), "maxmem": node.memory,
                 "uptime": 1_842_000, "level": ""] as [String: Any]
            })
        }
        guard let node = nodes.first(where: { $0.name == nodeName }) else {
            return envelope(NSNull())
        }
        let rest = Array(parts.dropFirst())

        switch rest.first {
        case "status":
            return envelope([
                "uptime": 1_842_000 + Date().timeIntervalSince(bootedAt),
                "cpu": nodeCPU(node), "wait": wave(node.seed, period: 40, amplitude: 0.012, base: 0.006),
                "loadavg": [String(format: "%.2f", nodeCPU(node) * node.cores),
                            String(format: "%.2f", nodeCPU(node) * node.cores * 0.9),
                            String(format: "%.2f", nodeCPU(node) * node.cores * 0.8)],
                "cpuinfo": ["cpus": Int(node.cores), "model": node.cpuModel, "sockets": 1],
                "memory": ["total": node.memory, "used": nodeMemUsed(node),
                           "free": node.memory - nodeMemUsed(node)],
                "swap": ["total": 8_589_934_592.0, "used": 412_000_000.0, "free": 8_177_934_592.0],
                "rootfs": ["total": node.rootTotal, "used": node.rootUsed,
                           "free": node.rootTotal - node.rootUsed],
                "kversion": "Linux 6.8.12-4-pve #1 SMP PREEMPT_DYNAMIC PVE",
                "pveversion": "pve-manager/8.3.2/d4b9f1e2"
            ])

        case "rrddata":
            return envelope(nodeRRD(node, timeframe: query["timeframe"] ?? "hour"))

        case "tasks":
            return envelope(tasks.filter { ($0["node"] as? String) == nodeName })

        case "network":
            return envelope([
                ["iface": "lo", "type": "loopback", "active": 1, "autostart": 1,
                 "address": "127.0.0.1", "cidr": "127.0.0.1/8"],
                ["iface": "enp3s0", "type": "eth", "active": 1, "autostart": 1,
                 "comments": "2.5 GbE uplink"],
                ["iface": "vmbr0", "type": "bridge", "active": 1, "autostart": 1,
                 "cidr": "192.168.10.\(11 + (nodes.firstIndex { $0.name == nodeName } ?? 0))/24",
                 "gateway": "192.168.10.1", "bridge_ports": "enp3s0"],
                ["iface": "vmbr1", "type": "bridge", "active": 1, "autostart": 1,
                 "bridge_ports": "none", "comments": "Isolated lab network"]
            ])

        case "disks":
            return envelope([
                ["devpath": "/dev/nvme0n1", "vendor": "Samsung", "model": "SSD 990 PRO 2TB",
                 "serial": "S6Z1NJ0T000000", "size": 2_000_398_934_016.0, "type": "nvme",
                 "health": "PASSED", "wearout": 97, "used": "LVM"],
                ["devpath": "/dev/sda", "vendor": "Seagate", "model": "IronWolf ST8000VN004",
                 "serial": "WSD0AB12", "size": 8_001_563_222_016.0, "type": "hdd",
                 "health": "PASSED", "rpm": 7200, "used": "ZFS"],
                ["devpath": "/dev/sdb", "vendor": "Crucial", "model": "CT500MX500SSD1",
                 "serial": "2023E6B1F", "size": 500_107_862_016.0, "type": "ssd",
                 "health": nodeName == "pve-edge" ? "OLD AGE" : "PASSED", "wearout": 42, "used": "partitions"]
            ])

        case "services":
            return envelope([
                ["service": "pveproxy", "name": "pveproxy", "desc": "PVE API Proxy Server", "state": "running", "unit-state": "enabled"],
                ["service": "pvedaemon", "name": "pvedaemon", "desc": "PVE API Daemon", "state": "running", "unit-state": "enabled"],
                ["service": "pvestatd", "name": "pvestatd", "desc": "PVE Status Daemon", "state": "running", "unit-state": "enabled"],
                ["service": "pve-cluster", "name": "pve-cluster", "desc": "Cluster file system", "state": "running", "unit-state": "enabled"],
                ["service": "corosync", "name": "corosync", "desc": "Corosync Cluster Engine", "state": "running", "unit-state": "enabled"],
                ["service": "pve-firewall", "name": "pve-firewall", "desc": "Proxmox VE firewall", "state": "running", "unit-state": "enabled"],
                ["service": "sshd", "name": "sshd", "desc": "OpenBSD Secure Shell server", "state": "running", "unit-state": "enabled"],
                ["service": "zfs-zed", "name": "zfs-zed", "desc": "ZFS Event Daemon", "state": nodeName == "pve-edge" ? "stopped" : "running", "unit-state": "enabled"]
            ])

        case "storage":
            if rest.count >= 3, rest[2] == "content" {
                return envelope(storageContent(node: nodeName, storage: rest[1], filter: query["content"]))
            }
            return envelope(storages.filter { $0.node == nodeName || $0.shared }.map { storage in
                ["storage": storage.name, "node": nodeName, "type": storage.type,
                 "content": storage.content, "active": 1, "enabled": 1,
                 "shared": storage.shared ? 1 : 0,
                 "total": storage.total, "used": storage.used,
                 "avail": storage.total - storage.used,
                 "used_fraction": storage.used / storage.total] as [String: Any]
            })

        case "apt":
            return envelope([
                ["Package": "pve-manager", "Title": "Proxmox Virtual Environment Management Tools",
                 "Version": "8.3.4", "OldVersion": "8.3.2", "Priority": "optional", "Section": "admin"],
                ["Package": "proxmox-kernel-6.8", "Title": "Proxmox Kernel Image",
                 "Version": "6.8.12-6", "OldVersion": "6.8.12-4", "Priority": "optional", "Section": "kernel"],
                ["Package": "libpve-storage-perl", "Title": "Proxmox VE storage management library",
                 "Version": "8.3.3", "OldVersion": "8.3.1", "Priority": "optional", "Section": "perl"],
                ["Package": "zfsutils-linux", "Title": "command-line tools to manage OpenZFS",
                 "Version": "2.2.7-pve1", "OldVersion": "2.2.6-pve1", "Priority": "optional", "Section": "admin"]
            ])

        case "qemu", "lxc":
            return guestRoute(kind: rest[0], node: nodeName, rest: Array(rest.dropFirst()), query: query)

        default:
            return envelope(NSNull())
        }
    }

    private func storageContent(node: String, storage: String, filter: String?) -> [[String: Any]] {
        guard let store = storages.first(where: { $0.name == storage && ($0.node == node || $0.shared) })
        else { return [] }

        var out: [[String: Any]] = []
        let now = Date().timeIntervalSince1970

        if store.content.contains("backup") {
            for guest in guests.filter({ !$0.template }).prefix(8) {
                for age in [1, 2, 7] {
                    out.append([
                        "volid": "\(storage):backup/vzdump-\(guest.kind)-\(guest.vmid)-2026_09_\(String(format: "%02d", 12 - age))-02_00_0\(age).tar.zst",
                        "content": "backup", "format": "tar.zst",
                        "size": guest.maxdisk * Double.random(in: 0.18...0.42),
                        "vmid": guest.vmid,
                        "ctime": now - Double(age) * 86_400,
                        "protected": age == 7 && guest.vmid == 111 ? 1 : 0,
                        "verification": ["state": "ok", "upid": ""],
                        "notes": guest.name
                    ])
                }
            }
        }
        if store.content.contains("iso") {
            for iso in ["debian-12.8.0-amd64-netinst.iso", "ubuntu-24.04.1-live-server-amd64.iso",
                        "Win11_24H2_French_x64.iso", "proxmox-ve_8.3-1.iso"] {
                out.append(["volid": "\(storage):iso/\(iso)", "content": "iso", "format": "iso",
                            "size": Double.random(in: 0.6...5.8) * 1_073_741_824,
                            "ctime": now - Double.random(in: 100_000...9_000_000)])
            }
        }
        if store.content.contains("vztmpl") {
            for tmpl in ["debian-12-standard_12.7-1_amd64.tar.zst",
                         "alpine-3.21-default_20250101_amd64.tar.xz",
                         "ubuntu-24.04-standard_24.04-2_amd64.tar.zst"] {
                out.append(["volid": "\(storage):vztmpl/\(tmpl)", "content": "vztmpl", "format": "tzst",
                            "size": Double.random(in: 0.08...0.42) * 1_073_741_824,
                            "ctime": now - Double.random(in: 500_000...9_000_000)])
            }
        }
        if store.content.contains("images") {
            for guest in guests.filter({ $0.node == node || store.shared }).prefix(6) {
                out.append(["volid": "\(storage):vm-\(guest.vmid)-disk-0", "content": "images",
                            "format": "raw", "size": guest.maxdisk, "vmid": guest.vmid,
                            "used": guest.maxdisk * 0.41])
            }
        }

        if let filter { return out.filter { ($0["content"] as? String) == filter } }
        return out
    }

    // MARK: Guest endpoints

    private func guestRoute(kind: String, node: String, rest: [String],
                            query: [String: String]) -> Data? {
        guard let vmidString = rest.first else {
            return envelope(guests.filter { $0.node == node && $0.kind == kind }.map { guest in
                ["vmid": guest.vmid, "name": guest.name,
                 "status": guest.running ? "running" : "stopped",
                 "cpu": guestCPU(guest), "maxcpu": guest.cores,
                 "mem": guestMem(guest), "maxmem": guest.maxmem,
                 "maxdisk": guest.maxdisk,
                 "uptime": guest.running ? Date().timeIntervalSince(guest.startedAt) : 0,
                 "template": guest.template ? 1 : 0] as [String: Any]
            })
        }
        guard let vmid = Int(vmidString),
              let guest = guests.first(where: { $0.vmid == vmid }) else {
            return envelope(NSNull())
        }
        let tail = Array(rest.dropFirst())

        switch tail.first {
        case "status":
            return envelope([
                "status": guest.running ? "running" : "stopped",
                "qmpstatus": guest.running ? "running" : "stopped",
                "name": guest.name, "cpus": guest.cores,
                "cpu": guestCPU(guest),
                "mem": guestMem(guest), "maxmem": guest.maxmem,
                "disk": guest.running ? guest.maxdisk * 0.41 : 0, "maxdisk": guest.maxdisk,
                "uptime": guest.running ? Date().timeIntervalSince(guest.startedAt) : 0,
                "netin": guest.running ? counter(guest.seed, rate: 142_000) : 0,
                "netout": guest.running ? counter(guest.seed + 0.3, rate: 96_000) : 0,
                "diskread": guest.running ? counter(guest.seed + 0.6, rate: 58_000) : 0,
                "diskwrite": guest.running ? counter(guest.seed + 0.9, rate: 41_000) : 0,
                "agent": guest.kind == "qemu" ? 1 : 0,
                "pid": guest.running ? 4000 + guest.vmid : 0,
                "ha": ["managed": 0]
            ])

        case "config":
            return envelope(guestConfig(guest))

        case "rrddata":
            return envelope(guestRRD(guest, timeframe: query["timeframe"] ?? "hour"))

        case "snapshot":
            var out: [[String: Any]] = guest.snapshots.map {
                ["name": $0.name, "description": $0.description,
                 "snaptime": $0.time.timeIntervalSince1970, "vmstate": $0.vmstate ? 1 : 0]
            }
            out.append(["name": "current", "description": "You are here"])
            return envelope(out)

        case "firewall":
            if tail.count > 1, tail[1] == "options" {
                return envelope(["enable": guest.tags.contains("network") ? 1 : 0,
                                 "policy_in": "DROP", "policy_out": "ACCEPT"])
            }
            return envelope([
                ["pos": 0, "type": "in", "action": "ACCEPT", "enable": 1, "proto": "tcp",
                 "dport": "22", "source": "192.168.10.0/24", "comment": "SSH LAN"],
                ["pos": 1, "type": "in", "action": "ACCEPT", "enable": 1, "proto": "tcp",
                 "dport": "443", "comment": "HTTPS"],
                ["pos": 2, "type": "in", "action": "DROP", "enable": 1, "comment": "Default deny"]
            ])

        case "agent":
            if tail.count > 1, tail[1] == "network-get-interfaces" {
                return envelope(["result": [
                    ["name": "eth0", "hardware-address": "BC:24:11:\(String(format: "%02X", guest.vmid % 255)):A4:1F",
                     "ip-addresses": [
                        ["ip-address": "192.168.10.\(100 + guest.vmid % 100)",
                         "ip-address-type": "ipv4", "prefix": 24]
                     ]]
                ]])
            }
            if tail.count > 1, tail[1] == "get-osinfo" {
                return envelope(["result": ["pretty-name": guest.osType == "win11"
                                            ? "Windows 11 Pro" : "Debian GNU/Linux 12 (bookworm)",
                                            "kernel-release": "6.1.0-28-amd64"]])
            }
            return envelope(NSNull())

        default:
            return envelope(NSNull())
        }
    }

    private func guestConfig(_ guest: DemoGuest) -> [String: Any] {
        var config: [String: Any] = [
            "name": guest.name,
            "cores": Int(guest.cores),
            "memory": Int(guest.maxmem / 1_048_576),
            "onboot": guest.tags.contains("critical") ? 1 : 0,
            "protection": guest.tags.contains("critical") ? 1 : 0,
            "tags": guest.tags.joined(separator: ";"),
            "net0": "virtio=BC:24:11:\(String(format: "%02X", guest.vmid % 255)):A4:1F,bridge=vmbr0,firewall=1"
        ]
        if guest.kind == "qemu" {
            config["sockets"] = 1
            config["ostype"] = guest.osType
            config["cpu"] = "host"
            config["bios"] = guest.osType == "win11" ? "ovmf" : "seabios"
            config["machine"] = "q35"
            config["boot"] = "order=scsi0;ide2;net0"
            config["scsihw"] = "virtio-scsi-single"
            config["scsi0"] = "local-lvm:vm-\(guest.vmid)-disk-0,discard=on,iothread=1,size=\(Int(guest.maxdisk / 1_073_741_824))G"
            config["agent"] = "1"
            if guest.osType == "win11" {
                config["efidisk0"] = "local-lvm:vm-\(guest.vmid)-disk-1,efitype=4m,pre-enrolled-keys=1,size=4M"
                config["tpmstate0"] = "local-lvm:vm-\(guest.vmid)-disk-2,size=4M,version=v2.0"
            }
        } else {
            config["ostemplate"] = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
            config["arch"] = "amd64"
            config["unprivileged"] = 1
            config["features"] = "nesting=1"
            config["rootfs"] = "local-lvm:subvol-\(guest.vmid)-disk-0,size=\(Int(guest.maxdisk / 1_073_741_824))G"
            config["swap"] = 512
        }
        if guest.vmid == 111 {
            config["description"] = "Primary PostgreSQL 16 instance.\nLogical dump to nas-nfs every night at 01:00.\nAnnounce before restarting."
            config["mp0"] = "nas-nfs:subvol-111-disk-1,mp=/var/lib/postgresql,size=200G"
        }
        return config
    }

    // MARK: RRD generators

    private func rrdTimes(_ timeframe: String) -> (step: Double, count: Int) {
        switch timeframe {
        case "day": return (300, 288)
        case "week": return (1800, 336)
        case "month": return (7200, 360)
        case "year": return (86400, 365)
        default: return (60, 70)
        }
    }

    private func nodeRRD(_ node: DemoNode, timeframe: String) -> [[String: Any]] {
        let (step, count) = rrdTimes(timeframe)
        let now = Date().timeIntervalSince1970
        return (0..<count).map { index in
            let t = now - Double(count - index) * step
            let phase = t / (step * 12) + node.seed
            let cpu = max(0.02, min(0.95, 0.26 + sin(phase) * 0.13 + sin(phase * 3.3) * 0.06
                                    + Double.random(in: -0.015...0.015)))
            let mem = nodeMemUsed(node) * (0.88 + sin(phase * 0.4) * 0.08)
            return [
                "time": t,
                "cpu": cpu,
                "maxcpu": node.cores,
                "iowait": max(0, 0.008 + sin(phase * 2.1) * 0.006),
                "loadavg": cpu * node.cores,
                "memused": mem, "memtotal": node.memory,
                "swapused": 412_000_000.0, "swaptotal": 8_589_934_592.0,
                "rootused": node.rootUsed, "roottotal": node.rootTotal,
                "netin": max(0, 4_200_000 + sin(phase * 1.7) * 3_100_000 + Double.random(in: -400_000...400_000)),
                "netout": max(0, 2_600_000 + sin(phase * 2.3 + 1) * 1_900_000 + Double.random(in: -300_000...300_000))
            ]
        }
    }

    private func guestRRD(_ guest: DemoGuest, timeframe: String) -> [[String: Any]] {
        let (step, count) = rrdTimes(timeframe)
        let now = Date().timeIntervalSince1970
        guard guest.running else {
            return (0..<count).map { index in
                ["time": now - Double(count - index) * step, "cpu": 0, "mem": 0,
                 "maxmem": guest.maxmem, "netin": 0, "netout": 0, "diskread": 0, "diskwrite": 0,
                 "maxdisk": guest.maxdisk]
            }
        }
        return (0..<count).map { index in
            let t = now - Double(count - index) * step
            let phase = t / (step * 9) + guest.seed
            let cpu = max(0, min(0.99, 0.14 + sin(phase) * 0.1 + sin(phase * 4.1) * 0.05
                                 + Double.random(in: -0.012...0.012)))
            return [
                "time": t,
                "cpu": cpu, "maxcpu": guest.cores,
                "mem": guest.maxmem * max(0.1, min(0.95, 0.48 + sin(phase * 0.6) * 0.1)),
                "maxmem": guest.maxmem,
                "disk": guest.maxdisk * 0.41, "maxdisk": guest.maxdisk,
                "netin": max(0, 900_000 + sin(phase * 1.9) * 780_000 + Double.random(in: -90_000...90_000)),
                "netout": max(0, 620_000 + sin(phase * 2.6) * 510_000 + Double.random(in: -70_000...70_000)),
                "diskread": max(0, 340_000 + sin(phase * 3.1) * 300_000),
                "diskwrite": max(0, 220_000 + sin(phase * 2.2 + 2) * 190_000)
            ]
        }
    }

    // MARK: Mutations

    private func mutate(method: String, parts: [String], form: [String: String]) -> Data? {
        // /nodes/{node}/{kind}/{vmid}/…
        if parts.count >= 5, parts[0] == "nodes",
           parts[2] == "qemu" || parts[2] == "lxc",
           let vmid = Int(parts[3]),
           let index = guests.firstIndex(where: { $0.vmid == vmid }) {
            let node = parts[1]
            let action = parts[4]

            switch action {
            case "status":
                let command = parts.count > 5 ? parts[5] : ""
                switch command {
                case "start", "resume":
                    guests[index].running = true
                    guests[index].startedAt = Date()
                case "stop", "shutdown":
                    guests[index].running = false
                case "reboot", "reset":
                    guests[index].startedAt = Date()
                case "suspend":
                    guests[index].running = false
                default: break
                }
                let prefix = parts[2] == "qemu" ? "qm" : "vz"
                return envelope(pushTask(type: "\(prefix)\(command)", node: node, id: String(vmid)))

            case "snapshot":
                if method == "POST", let name = form["snapname"] {
                    guests[index].snapshots.append((name, form["description"] ?? "",
                                                    Date(), form["vmstate"] == "1"))
                    return envelope(pushTask(type: "qmsnapshot", node: node, id: String(vmid)))
                }
                if method == "DELETE", parts.count > 5 {
                    guests[index].snapshots.removeAll { $0.name == parts[5] }
                    return envelope(pushTask(type: "qmdelsnapshot", node: node, id: String(vmid)))
                }
                if method == "POST", parts.count > 6, parts[6] == "rollback" {
                    return envelope(pushTask(type: "qmrollback", node: node, id: String(vmid)))
                }
                return envelope(NSNull())

            case "clone":
                if let newID = Int(form["newid"] ?? "") {
                    var copy = guests[index]
                    copy.vmid = newID
                    copy.name = form["name"] ?? "\(copy.name)-copie"
                    copy.running = false
                    copy.template = false
                    copy.snapshots = []
                    copy.seed = Double(newID % 97) / 10
                    if let target = form["target"], !target.isEmpty { copy.node = target }
                    guests.append(copy)
                    return envelope(pushTask(type: "qmclone", node: node, id: String(vmid), duration: 24))
                }
                return envelope(NSNull())

            case "migrate":
                if let target = form["target"], nodes.contains(where: { $0.name == target }) {
                    guests[index].node = target
                    return envelope(pushTask(type: "qmigrate", node: node, id: String(vmid), duration: 31))
                }
                return envelope(NSNull())

            case "template":
                guests[index].template = true
                guests[index].running = false
                return envelope(pushTask(type: "qmtemplate", node: node, id: String(vmid)))

            case "config":
                if let cores = form["cores"], let value = Double(cores) { guests[index].cores = value }
                if let memory = form["memory"], let value = Double(memory) {
                    guests[index].maxmem = value * 1_048_576
                }
                return envelope(NSNull())

            case "resize":
                if let size = form["size"], size.hasPrefix("+"),
                   let gb = Double(size.dropFirst().dropLast()) {
                    guests[index].maxdisk += gb * 1_073_741_824
                }
                return envelope(NSNull())

            case "firewall":
                return envelope(NSNull())

            default:
                return envelope(pushTask(type: "unknown", node: node, id: String(vmid)))
            }
        }

        // DELETE /nodes/{node}/{kind}/{vmid}
        if method == "DELETE", parts.count == 4, parts[0] == "nodes",
           parts[2] == "qemu" || parts[2] == "lxc", let vmid = Int(parts[3]) {
            guests.removeAll { $0.vmid == vmid }
            return envelope(pushTask(type: parts[2] == "qemu" ? "qmdestroy" : "vzdestroy",
                                     node: parts[1], id: String(vmid)))
        }

        if parts.count >= 3, parts[0] == "nodes" {
            let node = parts[1]
            switch parts[2] {
            case "vzdump":
                return envelope(pushTask(type: "vzdump", node: node,
                                         id: form["vmid"] ?? "", duration: 42))
            case "startall":
                for index in guests.indices where guests[index].node == node && !guests[index].template {
                    guests[index].running = true
                    guests[index].startedAt = Date()
                }
                return envelope(pushTask(type: "startall", node: node, id: ""))
            case "stopall":
                for index in guests.indices where guests[index].node == node {
                    guests[index].running = false
                }
                return envelope(pushTask(type: "stopall", node: node, id: ""))
            case "apt":
                return envelope(pushTask(type: "aptupdate", node: node, id: ""))
            case "services":
                return envelope(pushTask(type: "srvrestart", node: node, id: ""))
            case "status":
                return envelope(pushTask(type: "reboot", node: node, id: ""))
            case "storage":
                return envelope(pushTask(type: "download", node: node, id: "", duration: 60))
            case "qemu", "lxc":
                // Restore into a new/existing guest.
                return envelope(pushTask(type: "vzrestore", node: node,
                                         id: form["vmid"] ?? "", duration: 55))
            default:
                return envelope(NSNull())
            }
        }

        return envelope(NSNull())
    }

    // MARK: Task status / log

    func taskResponse(path: String) -> Data? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 5, parts[2] == "tasks" else { return nil }
        let upid = parts[3].removingPercentEncoding ?? parts[3]
        guard let task = tasks.first(where: { ($0["upid"] as? String) == upid }) else { return nil }

        if parts[4] == "status" { return envelope(task) }
        if parts[4] == "log" {
            let lines = taskLogs[upid] ?? ["INFO: no output", "TASK OK"]
            return envelope(lines.enumerated().map { ["n": $0.offset + 1, "t": $0.element] })
        }
        return nil
    }

    // MARK: JSON helpers

    private func envelope(_ value: Any) -> Data? {
        try? JSONSerialization.data(withJSONObject: ["data": value], options: [])
    }
}
