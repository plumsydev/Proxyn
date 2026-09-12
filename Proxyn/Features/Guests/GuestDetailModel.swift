import SwiftUI

@MainActor
@Observable
final class GuestDetailModel {
    let ref: GuestRef
    var status: PVEGuestStatus?
    var config: [String: JSONValue] = [:]
    var metrics: [PVEMetricSample] = []
    var snapshots: [PVESnapshot] = []
    var backups: [PVEStorageContent] = []
    var firewallRules: [PVEFirewallRule] = []
    var firewallEnabled = false
    var agentInterfaces: [AgentInterface] = []
    var agentOS: String?
    var timeframe: PVETimeframe = .hour
    var isLoading = false
    var error: String?

    private var pollTask: Task<Void, Never>?

    init(ref: GuestRef) { self.ref = ref }

    // MARK: Loading

    func load(using api: ProxmoxClient?, full: Bool = true) async {
        guard let api else { return }
        if status == nil { isLoading = true }
        defer { isLoading = false }

        do {
            status = try await api.guestStatus(ref)
            error = nil
        } catch let err as ProxmoxError {
            if case .cancelled = err { return }
            error = err.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }

        guard full else { return }

        async let configTask = api.guestConfig(ref)
        async let metricsTask = api.guestMetrics(ref, timeframe: timeframe)
        async let snapshotsTask = api.snapshots(ref)

        config = (try? await configTask) ?? config
        metrics = (try? await metricsTask) ?? metrics
        snapshots = ((try? await snapshotsTask) ?? snapshots).filter { !$0.isCurrent }

        firewallRules = await api.guestFirewallRules(ref) ?? []
        if let options = await api.guestFirewallOptions(ref) {
            firewallEnabled = (options["enable"]?.intValue ?? 0) != 0
        }

        if ref.kind == .qemu, status?.agentEnabled == true {
            agentInterfaces = Self.parseAgentInterfaces(await api.agentNetworkInterfaces(ref))
            if let os = await api.agentOSInfo(ref), case .object(let result)? = os["result"] {
                agentOS = [result["pretty-name"]?.displayString,
                           result["kernel-release"]?.displayString]
                    .compactMap { $0 }.joined(separator: " · ")
            }
        }
    }

    func loadBackups(using api: ProxmoxClient?, storages: [PVEResource]) async {
        guard let api else { return }
        var found: [PVEStorageContent] = []
        let candidates = storages.filter {
            ($0.content ?? "").contains("backup") && $0.node == ref.node
        }
        for storage in candidates {
            guard let name = storage.storage else { continue }
            let items = (try? await api.storageContent(node: ref.node, storage: name, content: "backup")) ?? []
            found.append(contentsOf: items.filter { $0.vmid == ref.vmid })
        }
        backups = found.sorted { ($0.ctime ?? 0) > ($1.ctime ?? 0) }
    }

    func changeTimeframe(_ new: PVETimeframe, api: ProxmoxClient?) async {
        timeframe = new
        guard let api else { return }
        metrics = (try? await api.guestMetrics(ref, timeframe: new)) ?? []
    }

    func startLive(api: ProxmoxClient?, interval: Double) {
        stopLive()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(max(3, interval)))
                guard let self, !Task.isCancelled else { return }
                await self.load(using: api, full: false)
            }
        }
    }

    func stopLive() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: Derived

    var state: PVERunState { status?.state ?? .unknown }
    var isLocked: Bool { !(status?.lock ?? "").isEmpty }

    var cpuFraction: Double { max(0, min(1, status?.cpu ?? 0)) }
    var memFraction: Double {
        guard let max = status?.maxmem, max > 0 else { return 0 }
        return (status?.mem ?? 0) / max
    }
    var diskFraction: Double {
        guard let max = status?.maxdisk, max > 0 else { return 0 }
        return (status?.disk ?? 0) / max
    }

    var cpuSeries: [MetricSeries] {
        [metrics.series("cpu", label: "CPU", unit: .percent, color: "ember")]
    }
    var memorySeries: [MetricSeries] {
        [metrics.series("mem", label: "Utilisée", unit: .bytes, color: "sky"),
         metrics.series("maxmem", label: "Allouée", unit: .bytes, color: "violet")]
    }
    var networkSeries: [MetricSeries] {
        [metrics.series("netin", label: "Entrant", unit: .bytesPerSecond, color: "sky"),
         metrics.series("netout", label: "Sortant", unit: .bytesPerSecond, color: "mint")]
    }
    var diskSeries: [MetricSeries] {
        [metrics.series("diskread", label: "Lecture", unit: .bytesPerSecond, color: "amber"),
         metrics.series("diskwrite", label: "Écriture", unit: .bytesPerSecond, color: "rose")]
    }

    /// Disk entries from the config (`scsi0`, `virtio1`, `rootfs`, `mp0`…).
    var diskDevices: [(key: String, value: String)] {
        let prefixes = ["scsi", "virtio", "sata", "ide", "rootfs", "mp", "efidisk", "tpmstate", "unused"]
        return config
            .filter { key, _ in prefixes.contains { key.hasPrefix($0) } }
            .map { ($0.key, $0.value.displayString) }
            .sorted { $0.0 < $1.0 }
    }

    var netDevices: [(key: String, value: String)] {
        config.filter { $0.key.hasPrefix("net") }
            .map { ($0.key, $0.value.displayString) }
            .sorted { $0.0 < $1.0 }
    }

    var cores: Int {
        let sockets = config["sockets"]?.intValue ?? 1
        return (config["cores"]?.intValue ?? Int(status?.cpus ?? 1)) * max(sockets, 1)
    }

    var memoryMB: Int { config["memory"]?.intValue ?? Int((status?.maxmem ?? 0) / 1_048_576) }

    var osType: String {
        config["ostype"]?.displayString ?? config["ostemplate"]?.displayString ?? "—"
    }

    var description: String? {
        let raw = config["description"]?.displayString
        return (raw?.isEmpty == false) ? raw : nil
    }

    var tags: [String] {
        (config["tags"]?.displayString ?? "")
            .split(whereSeparator: { $0 == ";" || $0 == "," })
            .map { String($0) }.filter { !$0.isEmpty }
    }

    var onBoot: Bool { (config["onboot"]?.intValue ?? 0) != 0 }
    var isProtected: Bool { (config["protection"]?.intValue ?? 0) != 0 }

    // MARK: Agent parsing

    struct AgentInterface: Identifiable, Hashable {
        var name: String
        var mac: String?
        var addresses: [String]
        var id: String { name }
    }

    static func parseAgentInterfaces(_ payload: [String: JSONValue]?) -> [AgentInterface] {
        guard let payload, case .array(let items)? = payload["result"] else { return [] }
        return items.compactMap { item in
            guard case .object(let dict) = item else { return nil }
            let name = dict["name"]?.displayString ?? "—"
            guard name != "lo" else { return nil }
            var addresses: [String] = []
            if case .array(let ips)? = dict["ip-addresses"] {
                for entry in ips {
                    guard case .object(let ip) = entry,
                          let address = ip["ip-address"]?.displayString else { continue }
                    let prefix = ip["prefix"]?.intValue
                    addresses.append(prefix.map { "\(address)/\($0)" } ?? address)
                }
            }
            guard !addresses.isEmpty else { return nil }
            return AgentInterface(name: name,
                                  mac: dict["hardware-address"]?.displayString,
                                  addresses: addresses)
        }
    }
}
