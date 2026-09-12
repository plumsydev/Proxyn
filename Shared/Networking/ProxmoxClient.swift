import Foundation

/// Result of a successful `/access/ticket` exchange.
struct PVESession: Sendable, Hashable {
    var ticket: String
    var csrfToken: String
    var username: String
    var clusterName: String?
    var issued: Date = Date()

    /// PVE tickets are valid for two hours; we renew well before the edge.
    var isFresh: Bool { Date().timeIntervalSince(issued) < 90 * 60 }
}

/// Thread-safe Proxmox VE API client. One instance per configured server.
actor ProxmoxClient {
    let profile: ServerProfile

    private let session: URLSession
    private let trustDelegate: TLSTrustDelegate
    private var pveSession: PVESession?
    private var inFlightLogin: Task<PVESession, Error>?
    private let demo: DemoBackend?
    /// Used while validating a server before it is saved, so a failed attempt
    /// never replaces a working secret in the Keychain.
    private let secretOverride: String?

    private var secret: String? { secretOverride ?? profile.secret }

    init(profile: ServerProfile, secretOverride: String? = nil) {
        self.profile = profile
        self.secretOverride = secretOverride
        let delegate = TLSTrustDelegate(skipVerification: profile.skipCertificateVerification,
                                        pinnedFingerprint: profile.pinnedCertificateSHA256)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        self.trustDelegate = delegate
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.demo = profile.isDemo ? DemoBackend() : nil
    }

    private static let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Proxyn/\(version)"
    }()

    // MARK: - Session state

    var currentSession: PVESession? { pveSession }
    var observedFingerprint: String? { trustDelegate.lastSeenFingerprint }
    var isAuthenticated: Bool {
        profile.isDemo || profile.authMethod == .apiToken || (pveSession?.isFresh ?? false)
    }

    func invalidateSession() { pveSession = nil }

    /// Cookie + CSRF pair used to bootstrap the embedded noVNC / xterm console.
    func consoleCredentials() async throws -> PVESession {
        if profile.isDemo {
            throw ProxmoxError.forbidden(
                "The console isn't available in the demo cluster. Connect a real Proxmox server to open a shell or noVNC.")
        }
        guard profile.authMethod == .ticket else { throw ProxmoxError.forbidden(
            "The console requires password sign-in. Proxmox doesn't allow API tokens to open console sessions."
        ) }
        return try await ensureSession()
    }

    // MARK: - Authentication

    @discardableResult
    func login(totpCode: String? = nil, tfaChallenge: String? = nil) async throws -> PVESession {
        guard profile.authMethod == .ticket else {
            throw ProxmoxError.forbidden("Ce serveur utilise un jeton d'API.")
        }
        guard let secret, !secret.isEmpty else { throw ProxmoxError.missingSecret }

        var form: [String: String] = ["username": profile.fullUsername]
        if let totpCode, let tfaChallenge {
            form["password"] = "totp:\(totpCode)"
            form["tfa-challenge"] = tfaChallenge
        } else {
            form["password"] = secret
        }

        let data = try await raw(method: "POST", path: "/access/ticket", query: [:], form: form,
                                 authenticated: false)
        let payload = try decodeObject(data)

        let ticket = payload["ticket"]?.displayString ?? ""
        let needsTFA = (payload["NeedTFA"]?.intValue ?? 0) == 1 || ticket.contains("!tfa!")
        if needsTFA, totpCode == nil {
            throw ProxmoxError.needsTOTP(challenge: ticket)
        }
        guard !ticket.isEmpty, let csrf = payload["CSRFPreventionToken"]?.displayString else {
            throw ProxmoxError.badCredentials(nil)
        }

        let made = PVESession(ticket: ticket,
                              csrfToken: csrf,
                              username: payload["username"]?.displayString ?? profile.fullUsername,
                              clusterName: payload["clustername"]?.displayString)
        pveSession = made
        return made
    }

    @discardableResult
    private func ensureSession() async throws -> PVESession {
        if let pveSession, pveSession.isFresh { return pveSession }
        if let inFlightLogin { return try await inFlightLogin.value }
        let task = Task { try await self.login() }
        inFlightLogin = task
        defer { inFlightLogin = nil }
        return try await task.value
    }

    // MARK: - Verbs

    func get<T: Decodable>(_ path: String, query: [String: String] = [:], as type: T.Type) async throws -> T {
        let data = try await raw(method: "GET", path: path, query: query, form: [:], authenticated: true)
        return try decodeEnvelope(data, as: type)
    }

    /// Optional variant: endpoints that legitimately 404/501 depending on the
    /// node's configuration (Ceph, SDN, guest agent…) return nil instead of throwing.
    func getOptional<T: Decodable>(_ path: String, query: [String: String] = [:], as type: T.Type) async -> T? {
        try? await get(path, query: query, as: type)
    }

    @discardableResult
    func post(_ path: String, form: [String: String] = [:]) async throws -> String? {
        let data = try await raw(method: "POST", path: path, query: [:], form: form, authenticated: true)
        return try? decodeEnvelope(data, as: String.self)
    }

    /// POST variant for endpoints that answer with an object (vncproxy, termproxy…).
    func postObject(_ path: String, form: [String: String] = [:]) async throws -> [String: JSONValue] {
        let data = try await raw(method: "POST", path: path, query: [:], form: form, authenticated: true)
        return try decodeObject(data)
    }

    @discardableResult
    func put(_ path: String, form: [String: String] = [:]) async throws -> String? {
        let data = try await raw(method: "PUT", path: path, query: [:], form: form, authenticated: true)
        return try? decodeEnvelope(data, as: String.self)
    }

    @discardableResult
    func delete(_ path: String, form: [String: String] = [:]) async throws -> String? {
        let data = try await raw(method: "DELETE", path: path, query: [:], form: form, authenticated: true)
        return try? decodeEnvelope(data, as: String.self)
    }

    // MARK: - Transport

    private func raw(method: String, path: String, query: [String: String],
                     form: [String: String], authenticated: Bool,
                     isRetry: Bool = false) async throws -> Data {
        if let demo {
            // A short delay keeps loading states and spinners honest.
            try? await Task.sleep(for: .milliseconds(Int.random(in: 90...190)))
            if let data = demo.response(method: method, path: path, query: query, form: form) {
                return data
            }
            throw ProxmoxError.httpStatus(501, "Not available in the demo cluster.")
        }

        guard let apiURL = profile.apiURL,
              var components = URLComponents(url: apiURL.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path),
                                             resolvingAgainstBaseURL: false)
        else { throw ProxmoxError.invalidURL }

        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw ProxmoxError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if !form.isEmpty {
            request.setValue("application/x-www-form-urlencoded; charset=UTF-8",
                             forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formEncode(form).data(using: .utf8)
        }

        if authenticated {
            switch profile.authMethod {
            case .apiToken:
                guard let secret, !secret.isEmpty else { throw ProxmoxError.missingSecret }
                request.setValue("PVEAPIToken=\(profile.tokenIdentifier)=\(secret)",
                                 forHTTPHeaderField: "Authorization")
            case .ticket:
                let s = try await ensureSession()
                request.setValue("PVEAuthCookie=\(s.ticket)", forHTTPHeaderField: "Cookie")
                if method != "GET" {
                    request.setValue(s.csrfToken, forHTTPHeaderField: "CSRFPreventionToken")
                }
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw mapTransportError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProxmoxError.transport("The server sent an invalid HTTP response.")
        }

        if !(200..<300).contains(http.statusCode) {
            Log.network.error("\(method, privacy: .public) \(path, privacy: .public) → HTTP \(http.statusCode)")
        }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            if authenticated, profile.authMethod == .ticket, !isRetry {
                pveSession = nil
                return try await self.raw(method: method, path: path, query: query, form: form,
                                          authenticated: authenticated, isRetry: true)
            }
            throw authenticated ? ProxmoxError.notAuthenticated
                                : ProxmoxError.badCredentials(Self.errorMessage(from: data))
        case 403:
            throw ProxmoxError.forbidden(Self.errorMessage(from: data))
        case 595, 596, 599:
            throw ProxmoxError.transport(Self.errorMessage(from: data) ?? "The node is unreachable from the cluster.")
        default:
            throw ProxmoxError.httpStatus(http.statusCode, Self.errorMessage(from: data))
        }
    }

    /// When our trust delegate cancels a TLS challenge, URLSession reports a
    /// plain `cancelled` error. The delegate's recorded outcome is what tells a
    /// certificate rejection apart from a genuine cancellation.
    private func mapTransportError(_ error: Error) -> ProxmoxError {
        switch trustDelegate.lastOutcome {
        case .untrusted:
            return .untrustedCertificate(host: profile.host, fingerprint: trustDelegate.lastSeenFingerprint)
        case .pinMismatch:
            return .certificateChanged(host: profile.host, fingerprint: trustDelegate.lastSeenFingerprint)
        case .trusted, .none:
            break
        }

        guard let urlError = error as? URLError else {
            return .transport(error.localizedDescription)
        }
        switch urlError.code {
        case .cancelled:
            return .cancelled
        case .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            return .untrustedCertificate(host: profile.host, fingerprint: trustDelegate.lastSeenFingerprint)
        case .cannotFindHost, .dnsLookupFailed:
            return .transport("Couldn't find \(profile.host). Check the address.")
        case .cannotConnectToHost:
            return .transport("Couldn't connect to \(profile.host) on port \(profile.port).")
        case .timedOut:
            return .transport("The server didn't respond in time.")
        case .notConnectedToInternet, .networkConnectionLost:
            return .transport("You're offline.")
        case .secureConnectionFailed:
            return .transport("A secure connection to \(profile.host) couldn't be established.")
        default:
            Log.network.error("Transport error: \(urlError.localizedDescription, privacy: .public)")
            return .transport(urlError.localizedDescription)
        }
    }

    // MARK: - Encoding / decoding helpers

    static func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params
            .sorted { $0.key < $1.key }
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }

    private func decodeEnvelope<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        do {
            return try JSONDecoder().decode(PVEEnvelope<T>.self, from: data).data
        } catch {
            // Some endpoints answer `{"data": null}`; surface that as an empty value
            // when the caller asked for a collection.
            if let empty = Self.emptyValue(for: T.self) { return empty }
            throw ProxmoxError.decoding(String(describing: error))
        }
    }

    private func decodeObject(_ data: Data) throws -> [String: JSONValue] {
        do {
            return try JSONDecoder().decode(PVEEnvelope<[String: JSONValue]>.self, from: data).data
        } catch {
            throw ProxmoxError.decoding(Self.errorMessage(from: data) ?? String(describing: error))
        }
    }

    private static func emptyValue<T>(for type: T.Type) -> T? {
        if let array = [JSONValue]() as? T, type is [JSONValue].Type { return array }
        return nil
    }

    static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (text?.isEmpty == false && text!.count < 400) ? text : nil
        }
        if let errors = object["errors"] as? [String: Any], !errors.isEmpty {
            return errors.map { "\($0.key) : \($0.value)" }.sorted().joined(separator: "\n")
        }
        if let message = object["message"] as? String { return message }
        return nil
    }
}
