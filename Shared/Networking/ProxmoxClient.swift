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

    init(profile: ServerProfile) {
        self.profile = profile
        let delegate = TLSTrustDelegate(allowInsecure: profile.allowInsecureTLS,
                                        pinnedFingerprint: profile.pinnedCertificateSHA256)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": "Proxyn/1.0 (iOS)"]
        self.trustDelegate = delegate
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.demo = profile.isDemo ? DemoBackend() : nil
    }

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
                "La console n'est pas disponible dans le cluster de démonstration — connectez un vrai serveur Proxmox pour ouvrir un terminal ou noVNC.")
        }
        guard profile.authMethod == .ticket else { throw ProxmoxError.forbidden(
            "La console nécessite une connexion par identifiants (les jetons d'API ne peuvent pas ouvrir de console)."
        ) }
        return try await ensureSession()
    }

    // MARK: - Authentication

    @discardableResult
    func login(totpCode: String? = nil, tfaChallenge: String? = nil) async throws -> PVESession {
        guard profile.authMethod == .ticket else {
            throw ProxmoxError.forbidden("Ce serveur utilise un jeton d'API.")
        }
        guard let secret = profile.secret, !secret.isEmpty else { throw ProxmoxError.missingSecret }

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
            throw ProxmoxError.httpStatus(501, "Endpoint non simulé en mode démo.")
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
                guard let secret = profile.secret, !secret.isEmpty else { throw ProxmoxError.missingSecret }
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
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                throw ProxmoxError.cancelled
            case .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
                 .secureConnectionFailed, .clientCertificateRejected:
                throw ProxmoxError.tlsRejected(host: profile.host,
                                               fingerprint: trustDelegate.lastSeenFingerprint)
            case .cannotFindHost, .cannotConnectToHost:
                throw ProxmoxError.transport("Impossible de joindre \(profile.host):\(profile.port).")
            case .timedOut:
                throw ProxmoxError.transport("Le serveur n'a pas répondu à temps.")
            case .notConnectedToInternet:
                throw ProxmoxError.transport("Aucune connexion réseau.")
            default:
                throw ProxmoxError.transport(error.localizedDescription)
            }
        } catch {
            throw ProxmoxError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProxmoxError.transport("Réponse HTTP invalide.")
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
            throw ProxmoxError.transport(Self.errorMessage(from: data) ?? "Le nœud est injoignable dans le cluster.")
        default:
            throw ProxmoxError.httpStatus(http.statusCode, Self.errorMessage(from: data))
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
