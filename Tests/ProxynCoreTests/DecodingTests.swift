import Foundation
import Testing
@testable import ProxynCore

@Suite("Tolerant decoding")
struct DecodingTests {

    @Test("A resource decodes whether numbers arrive as numbers, strings or booleans")
    func resourceWithMixedTypes() throws {
        let json = """
        {"data": [
          {"id": "qemu/100", "type": "qemu", "node": "pve", "vmid": "100", "name": "web",
           "status": "running", "cpu": "0.25", "maxcpu": 4, "mem": 1073741824, "maxmem": "4294967296",
           "template": false, "tags": "prod;web", "shared": "1"},
          {"type": "lxc", "node": "pve", "vmid": 101, "status": "stopped", "template": 1}
        ]}
        """.data(using: .utf8)!

        let resources = try JSONDecoder().decode(PVEEnvelope<[PVEResource]>.self, from: json).data

        #expect(resources.count == 2)
        let vm = resources[0]
        #expect(vm.vmid == 100)
        #expect(vm.cpuFraction == 0.25)
        #expect(vm.memFraction == 0.25)
        #expect(vm.tags == ["prod", "web"])
        #expect(vm.shared)
        #expect(vm.state == .running)

        let ct = resources[1]
        #expect(ct.isTemplate)
        #expect(ct.id == "lxc/101", "an id is synthesised when Proxmox omits it")
        #expect(ct.displayName == "VM 101")
    }

    @Test("Fractions are clamped to 0…1 even when Proxmox reports overcommit")
    func fractionsAreClamped() throws {
        let json = #"{"data": {"type": "node", "cpu": 1.7, "mem": 9, "maxmem": 8}}"#.data(using: .utf8)!
        let node = try JSONDecoder().decode(PVEEnvelope<PVEResource>.self, from: json).data
        #expect(node.cpuFraction == 1)
        #expect(node.memFraction == 1)
    }

    @Test("Node status reads nested memory, CPU info and string load averages")
    func nodeStatus() throws {
        let json = """
        {"data": {"uptime": 3600, "cpu": 0.1, "wait": "0.02",
          "cpuinfo": {"cpus": 16, "model": "EPYC"},
          "loadavg": ["1.50", "1.25", 1],
          "memory": {"total": 100, "used": 40},
          "pveversion": "pve-manager/8.3.2/abcdef"}}
        """.data(using: .utf8)!
        let status = try JSONDecoder().decode(PVEEnvelope<PVENodeStatus>.self, from: json).data
        #expect(status.cpuCount == 16)
        #expect(status.loadAverage == [1.5, 1.25, 1])
        #expect(status.memUsed == 40)
        #expect(status.ioWait == 0.02)
    }

    @Test("Saved settings from an older version decode with defaults instead of failing")
    func settingsAreForwardCompatible() throws {
        let legacy = """
        {"servers": [{"host": "10.0.0.5", "name": "lab", "someRemovedField": true}],
         "hapticsEnabled": false}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: legacy)
        #expect(settings.servers.count == 1)
        #expect(settings.servers[0].port == 8006)
        #expect(settings.servers[0].authMethod == .ticket)
        #expect(settings.servers[0].skipCertificateVerification == false)
        #expect(settings.hapticsEnabled == false)
        #expect(settings.refreshInterval == 5)
        #expect(settings.appearance == .system)
    }

    @Test("A guest snapshot list keeps its order and flags the current state")
    func snapshots() throws {
        let json = #"{"data": [{"name": "before-upgrade", "snaptime": 1700000000, "vmstate": 1}, {"name": "current"}]}"#
            .data(using: .utf8)!
        let snapshots = try JSONDecoder().decode(PVEEnvelope<[PVESnapshot]>.self, from: json).data
        #expect(snapshots[0].vmstate)
        #expect(snapshots[1].isCurrent)
    }
}
