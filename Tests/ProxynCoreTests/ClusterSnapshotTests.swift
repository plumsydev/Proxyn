import Foundation
import Testing
@testable import ProxynCore

@Suite("Cluster snapshot")
struct ClusterSnapshotTests {

    private func resource(_ id: String, type: PVEResourceType, node: String = "pve1",
                          status: String = "online", cpu: Double = 0, maxcpu: Double = 0,
                          mem: Double = 0, maxmem: Double = 0, disk: Double = 0, maxdisk: Double = 0,
                          storage: String? = nil, shared: Bool = false, vmid: Int? = nil) -> PVEResource {
        PVEResource(id: id, type: type, node: node, name: id, status: status, vmid: vmid,
                    cpu: cpu, maxcpu: maxcpu, mem: mem, maxmem: maxmem, disk: disk, maxdisk: maxdisk,
                    storage: storage, shared: shared)
    }

    @Test("Cluster CPU is weighted by core count")
    func weightedCPU() {
        let snapshot = ClusterSnapshot(resources: [
            resource("node/big", type: .node, node: "big", cpu: 0.10, maxcpu: 64),
            resource("node/small", type: .node, node: "small", cpu: 1.00, maxcpu: 4)
        ], capturedAt: Date())

        // (0.10 × 64 + 1.00 × 4) / 68 ≈ 0.153 — a plain average would claim 55%.
        #expect(abs(snapshot.aggregateCPU - 0.1529) < 0.001)
        #expect(snapshot.totalCores == 68)
    }

    @Test("Offline nodes are excluded from capacity and raise a critical alert")
    func offlineNode() {
        let snapshot = ClusterSnapshot(resources: [
            resource("node/a", type: .node, node: "a", cpu: 0.5, maxcpu: 8, mem: 4, maxmem: 8),
            resource("node/b", type: .node, node: "b", status: "offline", maxcpu: 8, maxmem: 8)
        ], capturedAt: Date())

        #expect(snapshot.memoryTotal == 8)
        #expect(snapshot.offlineNodes.count == 1)
        #expect(snapshot.alerts.first?.level == .critical)
        #expect(snapshot.alerts.first?.id == "node-offline-node/b")
    }

    @Test("A shared storage reported by every node is counted once")
    func sharedStorageDeduplicated() {
        let snapshot = ClusterSnapshot(resources: [
            resource("storage/pve1/nas", type: .storage, node: "pve1", status: "available",
                     disk: 100, maxdisk: 1000, storage: "nas", shared: true),
            resource("storage/pve2/nas", type: .storage, node: "pve2", status: "available",
                     disk: 100, maxdisk: 1000, storage: "nas", shared: true),
            resource("storage/pve1/local", type: .storage, node: "pve1", status: "available",
                     disk: 50, maxdisk: 100, storage: "local")
        ], capturedAt: Date())

        #expect(snapshot.uniqueStorages.count == 2)
        #expect(snapshot.storageTotal == 1100)
    }

    @Test("Alert identity is stable across polls so the UI doesn't re-animate them")
    func stableAlertIdentity() {
        let resources = [
            resource("storage/pve1/full", type: .storage, status: "available",
                     disk: 95, maxdisk: 100, storage: "full")
        ]
        let first = ClusterSnapshot(resources: resources, capturedAt: Date())
        let second = ClusterSnapshot(resources: resources, capturedAt: Date().addingTimeInterval(5))
        #expect(first.alerts.map(\.id) == second.alerts.map(\.id))
        #expect(first.alerts.count == 1)
    }

    @Test("Only failures from the last 24 hours become alerts")
    func staleFailuresIgnored() throws {
        let now = Date()
        let json = """
        [{"upid": "UPID:a", "type": "vzdump", "status": "stopped", "exitstatus": "ERROR",
          "starttime": \(now.addingTimeInterval(-3_600).timeIntervalSince1970),
          "endtime": \(now.addingTimeInterval(-3_000).timeIntervalSince1970)},
         {"upid": "UPID:b", "type": "vzdump", "status": "stopped", "exitstatus": "ERROR",
          "starttime": \(now.addingTimeInterval(-400_000).timeIntervalSince1970),
          "endtime": \(now.addingTimeInterval(-399_000).timeIntervalSince1970)}]
        """.data(using: .utf8)!
        let tasks = try JSONDecoder().decode([PVETask].self, from: json)

        let snapshot = ClusterSnapshot(tasks: tasks, capturedAt: now, now: now)
        #expect(snapshot.failedTasks.count == 2)
        #expect(snapshot.alerts.map(\.id) == ["task-UPID:a"])
    }

    @Test("Widget payload caps its CPU history")
    func widgetHistoryIsCapped() {
        let snapshot = ClusterSnapshot(capturedAt: Date())
        let widget = WidgetSnapshot(snapshot: snapshot, serverID: nil, serverName: "lab",
                                    previousHistory: Array(repeating: 0.5, count: 40))
        #expect(widget.cpuHistory.count == 24)
        #expect(widget.cpuHistory.last == 0)
    }

    @Test("Deep links survive a round trip through their URL")
    func deepLinks() {
        let links: [DeepLink] = [.overview, .activity, .guest(vmid: 104), .node("pve-alpha"),
                                 .storage(node: "pve-beta", storage: "local-lvm")]
        for link in links {
            #expect(DeepLink(url: link.url) == link)
        }
        #expect(DeepLink(url: URL(string: "https://example.com")!) == nil)
    }

    @Test("An older widget payload still decodes")
    func widgetPayloadIsTolerant() throws {
        let legacy = #"{"serverName": "lab", "cpu": 0.4}"#.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: legacy)
        #expect(snapshot.serverName == "lab")
        #expect(snapshot.guests.isEmpty)
    }
}
