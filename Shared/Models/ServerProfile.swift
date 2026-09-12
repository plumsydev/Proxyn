import Foundation

enum AppGroup {
    static let identifier = "group.com.proxyn.app"

    /// Falls back to `.standard` when the app-group entitlement isn't provisioned,
    /// so the app still works on a bare development signing profile.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

enum PVEAuthMethod: String, Codable, Sendable, CaseIterable, Identifiable {
    case ticket      // username + password (+ optional TOTP), full API surface
    case apiToken    // PVEAPIToken, no console, no TOTP prompt
    var id: String { rawValue }

    var title: String { self == .ticket ? "Identifiants" : "Jeton d'API" }
    var subtitle: String {
        self == .ticket
        ? "Accès complet : console, terminal, toutes les actions."
        : "Recommandé pour un accès restreint. La console web reste indisponible."
    }
    var symbol: String { self == .ticket ? "person.badge.key.fill" : "key.horizontal.fill" }
}

/// A saved Proxmox endpoint. Secrets live in the Keychain keyed by `secretKey`.
struct ServerProfile: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var useHTTPS: Bool
    var authMethod: PVEAuthMethod
    var username: String
    var realm: String
    var tokenID: String
    var allowInsecureTLS: Bool
    var pinnedCertificateSHA256: String?
    var accentHex: String
    var createdAt: Date
    var lastConnectedAt: Date?
    var defaultNode: String?
    var pollIntervalSeconds: Double

    init(id: UUID = UUID(), name: String = "", host: String = "", port: Int = 8006,
         useHTTPS: Bool = true, authMethod: PVEAuthMethod = .ticket, username: String = "root",
         realm: String = "pam", tokenID: String = "", allowInsecureTLS: Bool = true,
         pinnedCertificateSHA256: String? = nil, accentHex: String = "FF7A2F",
         createdAt: Date = Date(), lastConnectedAt: Date? = nil, defaultNode: String? = nil,
         pollIntervalSeconds: Double = 5) {
        self.id = id; self.name = name; self.host = host; self.port = port
        self.useHTTPS = useHTTPS; self.authMethod = authMethod; self.username = username
        self.realm = realm; self.tokenID = tokenID; self.allowInsecureTLS = allowInsecureTLS
        self.pinnedCertificateSHA256 = pinnedCertificateSHA256; self.accentHex = accentHex
        self.createdAt = createdAt; self.lastConnectedAt = lastConnectedAt
        self.defaultNode = defaultNode; self.pollIntervalSeconds = pollIntervalSeconds
    }

    var displayName: String { name.isEmpty ? host : name }

    /// The built-in demo cluster is served by `DemoBackend` instead of the
    /// network, so every screen can be explored without a real server.
    var isDemo: Bool { host == DemoBackend.host }

    static func demo() -> ServerProfile {
        var profile = ServerProfile(name: "homelab (démo)", host: DemoBackend.host, port: 8006,
                                    authMethod: .apiToken, username: "demo", realm: "pve",
                                    tokenID: "proxyn")
        profile.pollIntervalSeconds = 3
        return profile
    }

    var fullUsername: String { "\(username)@\(realm)" }

    /// `root@pam!mytoken`
    var tokenIdentifier: String { "\(fullUsername)!\(tokenID)" }

    var baseURL: URL? {
        var c = URLComponents()
        c.scheme = useHTTPS ? "https" : "http"
        c.host = host.trimmingCharacters(in: .whitespaces)
        c.port = port
        return c.url
    }

    var apiURL: URL? { baseURL?.appendingPathComponent("api2/json") }

    var secretKey: String { "secret.\(id.uuidString)" }
    var totpKey: String { "totp.\(id.uuidString)" }

    var secret: String? {
        get { Keychain.get(secretKey) }
        nonmutating set {
            if let newValue, !newValue.isEmpty { Keychain.set(newValue, for: secretKey) }
            else { Keychain.remove(secretKey) }
        }
    }

    var subtitleLine: String {
        let scheme = useHTTPS ? "https" : "http"
        return "\(scheme)://\(host):\(port) · \(authMethod == .ticket ? fullUsername : tokenIdentifier)"
    }
}

/// Everything the app persists outside of the Keychain.
struct AppSettings: Codable, Sendable, Hashable {
    var servers: [ServerProfile] = []
    var selectedServerID: UUID?
    var hapticsEnabled: Bool = true
    var reduceMotion: Bool = false
    var showTemplates: Bool = false
    var defaultTimeframe: String = PVETimeframe.hour.rawValue
    var confirmDestructiveActions: Bool = true
    var favoriteGuestIDs: [String] = []
    var liveRefreshInterval: Double = 5
    var backgroundRefreshEnabled: Bool = true
    var compactGuestRows: Bool = false
    var chartStyle: String = "area"
}
