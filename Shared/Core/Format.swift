import Foundation

/// The app ships in English only. Formatters use English for words but the
/// device's region for conventions (24-hour clock, date order, decimal mark),
/// so a French user gets "Sep 11, 14:02" rather than "Sep 11, 2:02 PM" — and
/// never a French word inside an English sentence.
enum AppLocale {
    static let current: Locale = {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let region = Locale.current.region?.identifier ?? "US"
        return Locale(identifier: "\(language)_\(region)")
    }()
}

enum Format {

    // MARK: Sizes

    private static let byteUnits = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]

    /// Binary units, matching what the Proxmox web interface displays.
    static func bytes(_ value: Double?) -> String {
        let parts = bytesParts(value)
        return parts.unit.isEmpty ? parts.value : "\(parts.value) \(parts.unit)"
    }

    /// Number and unit separately, so the UI can set the unit smaller.
    static func bytesParts(_ value: Double?) -> (value: String, unit: String) {
        guard let value, value.isFinite else { return ("—", "") }
        var v = abs(value)
        var index = 0
        while v >= 1024, index < byteUnits.count - 1 {
            v /= 1024
            index += 1
        }
        let digits = (index > 0 && v < 10) ? 1 : 0
        return (number(v, fractionDigits: digits), byteUnits[index])
    }

    static func rate(_ bytesPerSecond: Double?) -> String {
        bytes(bytesPerSecond) + "/s"
    }

    // MARK: Numbers

    static func number(_ value: Double, fractionDigits: Int) -> String {
        value.formatted(.number
            .precision(.fractionLength(fractionDigits))
            .locale(AppLocale.current))
    }

    static func percent(_ fraction: Double?, decimals: Int = 0) -> String {
        guard let fraction, fraction.isFinite else { return "—" }
        return number(fraction * 100, fractionDigits: decimals) + "%"
    }

    static func compactNumber(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.number.notation(.compactName).precision(.significantDigits(3))
            .locale(AppLocale.current))
    }

    // MARK: Durations

    /// "21d 7h", "7h 12m", "4m".
    static func uptime(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let s = Int(seconds)
        let days = s / 86_400, hours = (s % 86_400) / 3_600, minutes = (s % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(minutes, 1))m"
    }

    private static let longDuration: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.day, .hour, .minute]
        f.unitsStyle = .full
        f.maximumUnitCount = 2
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = AppLocale.current
        f.calendar = calendar
        return f
    }()

    /// "21 days, 7 hours".
    static func uptimeLong(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        return longDuration.string(from: max(seconds, 60)) ?? uptime(seconds)
    }

    /// "42s", "2m 59s", "1h 04m".
    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        if s < 3_600 { return "\(s / 60)m \(String(format: "%02d", s % 60))s" }
        return "\(s / 3_600)h \(String(format: "%02d", (s % 3_600) / 60))m"
    }

    // MARK: Dates

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = AppLocale.current
        return f
    }()

    static func ago(_ date: Date?) -> String {
        guard let date else { return "—" }
        if abs(date.timeIntervalSinceNow) < 45 { return "just now" }
        return relative.localizedString(for: date, relativeTo: Date())
    }

    static func dateTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute()
            .locale(AppLocale.current))
    }

    static func clock(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.dateTime.hour().minute().second().locale(AppLocale.current))
    }

    static func dayHeading(_ date: Date?) -> String {
        guard let date else { return "Unknown date" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(AppLocale.current))
    }

    // MARK: Proxmox task names

    /// `qmstart` → "Start VM". Unknown types are title-cased rather than hidden.
    static func taskType(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Task" }
        let names: [String: String] = [
            "qmstart": "Start VM", "qmstop": "Stop VM", "qmshutdown": "Shut Down VM",
            "qmreboot": "Reboot VM", "qmreset": "Reset VM", "qmsuspend": "Suspend VM",
            "qmresume": "Resume VM", "qmpause": "Pause VM", "qmclone": "Clone VM",
            "qmigrate": "Migrate VM", "qmsnapshot": "Take Snapshot", "qmdelsnapshot": "Delete Snapshot",
            "qmrollback": "Roll Back Snapshot", "qmcreate": "Create VM", "qmdestroy": "Destroy VM",
            "qmconfig": "Update VM Config", "qmtemplate": "Convert to Template", "qmmove": "Move Disk",
            "qmresize": "Resize Disk",
            "vzstart": "Start Container", "vzstop": "Stop Container", "vzshutdown": "Shut Down Container",
            "vzreboot": "Reboot Container", "vzcreate": "Create Container", "vzdestroy": "Destroy Container",
            "vzclone": "Clone Container", "vzmigrate": "Migrate Container", "vzsnapshot": "Take Snapshot",
            "vzdelsnapshot": "Delete Snapshot", "vzrollback": "Roll Back Snapshot",
            "vzdump": "Backup", "vzrestore": "Restore", "qmrestore": "Restore",
            "imgcopy": "Copy Image", "imgdel": "Delete Image", "download": "Download",
            "aptupdate": "Update Package Lists", "aptupgrade": "Upgrade Packages",
            "srvstart": "Start Service", "srvstop": "Stop Service", "srvrestart": "Restart Service",
            "srvreload": "Reload Service",
            "startall": "Start All Guests", "stopall": "Stop All Guests", "migrateall": "Migrate All Guests",
            "vncproxy": "Console", "vncshell": "Shell", "termproxy": "Terminal", "spiceproxy": "SPICE",
            "resize": "Resize Disk", "backupjob": "Scheduled Backup", "reboot": "Reboot Node",
            "shutdown": "Shut Down Node", "hamigrate": "HA Migrate", "hastart": "HA Start",
            "hastop": "HA Stop"
        ]
        if let name = names[raw] { return name }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func shortUPID(_ upid: String) -> String {
        let parts = upid.split(separator: ":")
        guard parts.count > 5 else { return upid }
        return String(parts[5])
    }

    /// `pve-manager/8.3.2/d4b9f1e2` → `8.3.2`
    static func pveVersion(_ raw: String?) -> String {
        guard let raw else { return "—" }
        let parts = raw.split(separator: "/")
        return parts.count > 1 ? String(parts[1]) : raw
    }
}
