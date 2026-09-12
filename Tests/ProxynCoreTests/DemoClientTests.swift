import Foundation
import Testing
@testable import ProxynCore

/// Exercises the real client end to end against the in-process demo backend:
/// routing, envelopes, decoding and state changes.
@Suite("Client against the demo backend")
struct DemoClientTests {
    private let client = ProxmoxClient(profile: .demo())

    @Test("Cluster resources decode into a populated snapshot")
    func resources() async throws {
        let resources = try await client.clusterResources()
        let snapshot = ClusterSnapshot(resources: resources, capturedAt: Date())
        #expect(snapshot.nodes.count == 3)
        #expect(snapshot.guests.count >= 10)
        #expect(!snapshot.uniqueStorages.isEmpty)
        #expect(snapshot.aggregateCPU > 0)
    }

    @Test("Starting a stopped guest returns a task that completes and changes its state")
    func startGuest() async throws {
        let ref = GuestRef(node: "pve-beta", kind: .qemu, vmid: 103)
        #expect(try await client.guestStatus(ref).state == .stopped)

        let upid = try #require(try await client.guestPower(ref, action: .start))
        #expect(upid.hasPrefix("UPID:"))

        let task = try await client.taskStatus(node: "pve-beta", upid: upid)
        #expect(task.succeeded)
        #expect(try await client.guestStatus(ref).state == .running)

        let log = try await client.taskLog(node: "pve-beta", upid: upid)
        #expect(log.last?.t == "TASK OK")
    }

    @Test("A snapshot taken through the client shows up in the snapshot list")
    func takeSnapshot() async throws {
        let ref = GuestRef(node: "pve-alpha", kind: .lxc, vmid: 110)
        try await client.createSnapshot(ref, name: "test-snap", description: "from tests", includeRAM: false)
        let names = try await client.snapshots(ref).map(\.name)
        #expect(names.contains("test-snap"))
    }

    @Test("Every guest power action's availability matches its state")
    func actionAvailability() {
        #expect(GuestPowerAction.start.isAvailable(for: .stopped, kind: .qemu))
        #expect(!GuestPowerAction.start.isAvailable(for: .running, kind: .qemu))
        #expect(GuestPowerAction.resume.isAvailable(for: .paused, kind: .qemu))
        #expect(!GuestPowerAction.reset.isAvailable(for: .running, kind: .lxc), "containers can't be reset")
    }
}
