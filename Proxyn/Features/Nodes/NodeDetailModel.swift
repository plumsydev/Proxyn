import SwiftUI

@MainActor
@Observable
final class NodeDetailModel {
    var node: String
    var status: PVENodeStatus?
    var metrics: [PVEMetricSample] = []
    var storages: [PVEStorage] = []
    var disks: [PVEDisk] = []
    var interfaces: [PVENetworkInterface] = []
    var services: [PVEService] = []
    var tasks: [PVETask] = []
    var updates: [PVEAptUpdate] = []
    var timeframe: PVETimeframe = .hour
    var isLoading = false
    var error: String?
    var busyService: String?

    private var pollTask: Task<Void, Never>?

    init(node: String) { self.node = node }

    func load(using api: ProxmoxClient?, full: Bool = true) async {
        guard let api else { return }
        if status == nil { isLoading = true }
        defer { isLoading = false }

        do {
            async let statusTask = api.nodeStatus(node)
            async let metricsTask = api.nodeMetrics(node, timeframe: timeframe)
            status = try await statusTask
            metrics = (try? await metricsTask) ?? []
            error = nil
        } catch let err as ProxmoxError {
            if case .cancelled = err { return }
            error = err.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }

        guard full else { return }
        async let storagesTask = api.nodeStorages(node)
        async let disksTask = api.nodeDisks(node)
        async let interfacesTask = api.nodeNetwork(node)
        async let servicesTask = api.nodeServices(node)
        async let tasksTask = api.nodeTasks(node, limit: 40)
        async let updatesTask = api.availableUpdates(node)

        storages = (try? await storagesTask) ?? storages
        disks = (try? await disksTask) ?? disks
        interfaces = (try? await interfacesTask) ?? interfaces
        services = (try? await servicesTask) ?? services
        tasks = (try? await tasksTask) ?? tasks
        updates = (try? await updatesTask) ?? updates
    }

    func changeTimeframe(_ new: PVETimeframe, api: ProxmoxClient?) async {
        timeframe = new
        guard let api else { return }
        metrics = (try? await api.nodeMetrics(node, timeframe: new)) ?? []
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

    // MARK: Derived chart series

    var cpuSeries: [MetricSeries] {
        var out = [metrics.series("cpu", label: "CPU", unit: .percent, color: "primary")]
        let io = metrics.series("iowait", label: "IO delay", unit: .percent, color: "secondary")
        if io.points.contains(where: { $0.value > 0 }) { out.append(io) }
        return out
    }

    var memorySeries: [MetricSeries] {
        [metrics.series("memused", label: "Used", unit: .bytes, color: "primary"),
         metrics.series("swapused", label: "Swap", unit: .bytes, color: "secondary")]
            .filter { !$0.points.isEmpty }
    }

    var networkSeries: [MetricSeries] {
        [metrics.series("netin", label: "In", unit: .bytesPerSecond, color: "primary"),
         metrics.series("netout", label: "Out", unit: .bytesPerSecond, color: "secondary")]
    }

    var loadSeries: [MetricSeries] {
        [metrics.series("loadavg", label: "Load", unit: .raw, color: "primary")]
    }

    var runningServices: Int { services.filter(\.isRunning).count }

    var smartWarnings: [PVEDisk] {
        disks.filter { ($0.health ?? "PASSED").uppercased() != "PASSED" && ($0.health ?? "") != "" }
    }
}
