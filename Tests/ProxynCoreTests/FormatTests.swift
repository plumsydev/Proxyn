import Foundation
import Testing
@testable import ProxynCore

@Suite("Formatting")
struct FormatTests {

    @Test("Sizes use binary units, like the Proxmox web interface")
    func binaryUnits() {
        #expect(Format.bytesParts(512).unit == "B")
        #expect(Format.bytesParts(512 * 1_048_576) == (value: "512", unit: "MiB"))
        #expect(Format.bytesParts(64 * 1_073_741_824) == (value: "64", unit: "GiB"))
        #expect(Format.bytesParts(4 * 1_099_511_627_776).unit == "TiB")
        #expect(Format.bytes(nil) == "—")
    }

    @Test("Small values in a large unit keep one decimal")
    func smallValuesKeepADecimal() {
        let parts = Format.bytesParts(1.5 * 1_073_741_824)
        #expect(parts.unit == "GiB")
        #expect(parts.value.count == 3, "e.g. 1.5 or 1,5 depending on region")
    }

    @Test("Durations read compactly")
    func durations() {
        #expect(Format.uptime(59) == "1m")
        #expect(Format.uptime(7_260) == "2h 1m")
        #expect(Format.uptime(90_000) == "1d 1h")
        #expect(Format.duration(42) == "42s")
        #expect(Format.duration(179) == "2m 59s")
        #expect(Format.duration(3_840) == "1h 04m")
    }

    @Test("Percentages round and never show non-finite values")
    func percentages() {
        #expect(Format.percent(0.426) == "43%")
        #expect(Format.percent(.nan) == "—")
    }

    @Test("Task types map to readable names, unknown ones are title-cased")
    func taskNames() {
        #expect(Format.taskType("qmstart") == "Start VM")
        #expect(Format.taskType("vzdump") == "Backup")
        #expect(Format.taskType("some_new_task") == "Some New Task")
        #expect(Format.taskType(nil) == "Task")
    }

    @Test("PVE version strings are shortened")
    func pveVersion() {
        #expect(Format.pveVersion("pve-manager/8.3.2/d4b9f1e2") == "8.3.2")
        #expect(Format.pveVersion("8.3") == "8.3")
    }

    @Test("Form bodies are percent-encoded, including characters valid in URLs")
    func formEncoding() {
        let body = ProxmoxClient.formEncode(["password": "a&b=c d+é", "username": "root@pam"])
        #expect(body == "password=a%26b%3Dc%20d%2B%C3%A9&username=root%40pam")
    }
}
