import Foundation

enum AppGroup {
    static let identifier = "group.com.proxyn.app"

    /// Falls back to `.standard` when the app-group entitlement isn't
    /// provisioned, so the app still works on a bare development profile.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

enum PVEAuthMethod: String, Codable, Sendable, CaseIterable, Identifiable {
    case ticket
    case apiToken

    var id: String { rawValue }

    var title: String { self == .ticket ? "Password" : "API Token" }

    var explanation: String {
        switch self {
        case .ticket:
            return "Full access, including the web console. Supports two-factor authentication."
        case .apiToken:
            return "Scoped access you can revoke at any time. The web console isn't available with tokens."
        }
    }
}

/// A saved Proxmox endpoint. The secret itself lives in the Keychain.
///
/// Decoding is tolerant: every field has a default, so adding a property in a
/// later version never makes an existing install lose its servers.
struct ServerProfile: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String = ""
    var host: String = ""
    var port: Int = 8006
    var useHTTPS: Bool = true
    var authMethod: PVEAuthMethod = .ticket
    var username: String = "root"
    var realm: String = "pam"
    var tokenID: String = ""
    /// Accept any certificate. Off by default; pinning is the recommended path.
    var skipCertificateVerification: Bool = false
    var pinnedCertificateSHA256: String?
    var createdAt: Date = Date()
    var lastConnectedAt: Date?

    init(id: UUID = UUID(), name: String = "", host: String = "", port: Int = 8006,
         useHTTPS: Bool = true, authMethod: PVEAuthMethod = .ticket, username: String = "root",
         realm: String = "pam", tokenID: String = "", skipCertificateVerification: Bool = false,
         pinnedCertificateSHA256: String? = nil, createdAt: Date = Date(),
         lastConnectedAt: Date? = nil) {
        self.id = id; self.name = name; self.host = host; self.port = port
        self.useHTTPS = useHTTPS; self.authMethod = authMethod; self.username = username
        self.realm = realm; self.tokenID = tokenID
        self.skipCertificateVerification = skipCertificateVerification
        self.pinnedCertificateSHA256 = pinnedCertificateSHA256
        self.createdAt = createdAt; self.lastConnectedAt = lastConnectedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, useHTTPS, authMethod, username, realm, tokenID
        case skipCertificateVerification, pinnedCertificateSHA256, createdAt, lastConnectedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ServerProfile()
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? fallback.id
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 8006
        useHTTPS = try c.decodeIfPresent(Bool.self, forKey: .useHTTPS) ?? true
        authMethod = try c.decodeIfPresent(PVEAuthMethod.self, forKey: .authMethod) ?? .ticket
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? "root"
        realm = try c.decodeIfPresent(String.self, forKey: .realm) ?? "pam"
        tokenID = try c.decodeIfPresent(String.self, forKey: .tokenID) ?? ""
        skipCertificateVerification = try c.decodeIfPresent(Bool.self, forKey: .skipCertificateVerification) ?? false
        pinnedCertificateSHA256 = try c.decodeIfPresent(String.self, forKey: .pinnedCertificateSHA256)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastConnectedAt = try c.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
    }

    var displayName: String { name.isEmpty ? host : name }
    var fullUsername: String { "\(username)@\(realm)" }
    /// `root@pam!mytoken`
    var tokenIdentifier: String { "\(fullUsername)!\(tokenID)" }

    /// The built-in demo cluster is served by `DemoBackend` instead of the
    /// network, so every screen can be explored without a real server — which
    /// is also what App Review uses.
    var isDemo: Bool { host == DemoBackend.host }

    static func demo() -> ServerProfile {
        ServerProfile(name: "Demo Cluster", host: DemoBackend.host, port: 8006,
                      authMethod: .apiToken, username: "demo", realm: "pve", tokenID: "proxyn")
    }

    var baseURL: URL? {
        var c = URLComponents()
        c.scheme = useHTTPS ? "https" : "http"
        c.host = host.trimmingCharacters(in: .whitespaces)
        c.port = port
        return c.url
    }

    var apiURL: URL? { baseURL?.appendingPathComponent("api2/json") }

    var addressLine: String {
        "\(useHTTPS ? "https" : "http")://\(host):\(port)"
    }

    var identityLine: String {
        authMethod == .ticket ? fullUsername : tokenIdentifier
    }

    // MARK: Secret

    var secretKey: String { "secret.\(id.uuidString)" }

    var secret: String? {
        get { Keychain.get(secretKey) }
        nonmutating set {
            if let newValue, !newValue.isEmpty { Keychain.set(newValue, for: secretKey) }
            else { Keychain.remove(secretKey) }
        }
    }
}

enum AppearancePreference: String, Codable, Sendable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// Everything persisted outside the Keychain. Tolerant decoding, as above.
struct AppSettings: Codable, Sendable, Hashable {
    var servers: [ServerProfile] = []
    var selectedServerID: UUID?
    var hapticsEnabled: Bool = true
    var confirmDestructiveActions: Bool = true
    var showTemplates: Bool = false
    var favoriteGuestIDs: [String] = []
    var refreshInterval: Double = 5
    var appearance: AppearancePreference = .system

    init() {}

    enum CodingKeys: String, CodingKey {
        case servers, selectedServerID, hapticsEnabled, confirmDestructiveActions
        case showTemplates, favoriteGuestIDs, refreshInterval, appearance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        servers = (try? c.decodeIfPresent([ServerProfile].self, forKey: .servers)) ?? []
        selectedServerID = try? c.decodeIfPresent(UUID.self, forKey: .selectedServerID)
        hapticsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled)) ?? true
        confirmDestructiveActions = (try? c.decodeIfPresent(Bool.self, forKey: .confirmDestructiveActions)) ?? true
        showTemplates = (try? c.decodeIfPresent(Bool.self, forKey: .showTemplates)) ?? false
        favoriteGuestIDs = (try? c.decodeIfPresent([String].self, forKey: .favoriteGuestIDs)) ?? []
        refreshInterval = (try? c.decodeIfPresent(Double.self, forKey: .refreshInterval)) ?? 5
        appearance = (try? c.decodeIfPresent(AppearancePreference.self, forKey: .appearance)) ?? .system
    }
}
