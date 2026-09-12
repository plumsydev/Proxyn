import Foundation

enum Format {
    static func bytes(_ value: Double?, decimals: Int? = nil) -> String {
        guard let value, value.isFinite else { return "—" }
        let units = ["o", "Ko", "Mo", "Go", "To", "Po"]
        var v = abs(value)
        var idx = 0
        while v >= 1024, idx < units.count - 1 { v /= 1024; idx += 1 }
        let d = decimals ?? (v < 10 && idx > 0 ? 1 : 0)
        return String(format: "%.\(d)f %@", v, units[idx])
    }

    /// Splits a byte value so the UI can typeset the number and unit differently.
    static func bytesParts(_ value: Double?) -> (value: String, unit: String) {
        guard let value, value.isFinite else { return ("—", "") }
        let units = ["o", "Ko", "Mo", "Go", "To", "Po"]
        var v = abs(value)
        var idx = 0
        while v >= 1024, idx < units.count - 1 { v /= 1024; idx += 1 }
        let d = v < 10 && idx > 0 ? 1 : 0
        return (String(format: "%.\(d)f", v), units[idx])
    }

    static func percent(_ fraction: Double?, decimals: Int = 0) -> String {
        guard let fraction, fraction.isFinite else { return "—" }
        return String(format: "%.\(decimals)f%%", fraction * 100)
    }

    static func compactNumber(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        let a = abs(value)
        switch a {
        case 0..<1_000: return String(format: a < 10 && a != a.rounded() ? "%.1f" : "%.0f", value)
        case 1_000..<1_000_000: return String(format: "%.1fk", value / 1_000)
        case 1_000_000..<1_000_000_000: return String(format: "%.1fM", value / 1_000_000)
        default: return String(format: "%.1fG", value / 1_000_000_000)
        }
    }

    static func uptime(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let s = Int(seconds)
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)j \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func uptimeLong(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "—" }
        let s = Int(seconds)
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60, sec = s % 60
        var parts: [String] = []
        if d > 0 { parts.append("\(d) j") }
        if h > 0 { parts.append("\(h) h") }
        if m > 0 { parts.append("\(m) min") }
        if parts.isEmpty { parts.append("\(sec) s") }
        return parts.joined(separator: " ")
    }

    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        let s = Int(seconds)
        if s < 60 { return "\(s) s" }
        if s < 3600 { return "\(s / 60) min \(s % 60) s" }
        return "\(s / 3600) h \((s % 3600) / 60) min"
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = Locale(identifier: "fr_FR")
        return f
    }()

    static func ago(_ date: Date?) -> String {
        guard let date else { return "—" }
        return relative.localizedString(for: date, relativeTo: Date())
    }

    private static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM · HH:mm"
        return f
    }()

    static func dateTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return dateTime.string(from: date)
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func clock(_ date: Date?) -> String {
        guard let date else { return "—" }
        return clock.string(from: date)
    }

    /// `UPID:pve:0000ABCD:...:qmstart:100:root@pam:` → "Démarrage VM"
    static func taskType(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Tâche" }
        let map: [String: String] = [
            "qmstart": "Démarrage VM", "qmstop": "Arrêt forcé VM", "qmshutdown": "Arrêt VM",
            "qmreboot": "Redémarrage VM", "qmreset": "Reset VM", "qmsuspend": "Suspension VM",
            "qmresume": "Reprise VM", "qmclone": "Clonage VM", "qmigrate": "Migration VM",
            "qmsnapshot": "Snapshot VM", "qmdelsnapshot": "Suppr. snapshot", "qmrollback": "Rollback VM",
            "qmcreate": "Création VM", "qmdestroy": "Suppression VM", "qmconfig": "Config VM",
            "qmtemplate": "Template VM", "qmmove": "Déplacement disque",
            "vzstart": "Démarrage LXC", "vzstop": "Arrêt forcé LXC", "vzshutdown": "Arrêt LXC",
            "vzreboot": "Redémarrage LXC", "vzcreate": "Création LXC", "vzdestroy": "Suppression LXC",
            "vzclone": "Clonage LXC", "vzmigrate": "Migration LXC", "vzsnapshot": "Snapshot LXC",
            "vzdelsnapshot": "Suppr. snapshot", "vzrollback": "Rollback LXC", "vzdump": "Sauvegarde",
            "vzrestore": "Restauration", "imgcopy": "Copie image", "imgdel": "Suppr. image",
            "download": "Téléchargement", "aptupdate": "MàJ dépôts", "aptupgrade": "Mise à jour",
            "srvstart": "Démarrage service", "srvstop": "Arrêt service", "srvrestart": "Redémarrage service",
            "startall": "Démarrage groupé", "stopall": "Arrêt groupé", "migrateall": "Migration groupée",
            "vncproxy": "Console", "termproxy": "Terminal", "spiceproxy": "SPICE",
            "resize": "Redimensionnement", "unknownimgdel": "Nettoyage", "cephcreatemon": "Ceph",
            "pull_file": "Lecture fichier", "push_file": "Écriture fichier", "backupjob": "Job sauvegarde"
        ]
        return map[raw] ?? raw.capitalized
    }

    static func shortUPID(_ upid: String) -> String {
        let parts = upid.split(separator: ":")
        guard parts.count > 5 else { return upid }
        return String(parts[5])
    }
}
