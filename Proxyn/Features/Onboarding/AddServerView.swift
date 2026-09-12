import SwiftUI

/// Adds or edits a server. Credentials are verified against the real API before
/// anything is saved.
///
/// Certificates follow trust-on-first-use: if the system doesn't trust the
/// server's certificate, its SHA-256 fingerprint is shown and, once the user
/// confirms it matches the one in the Proxmox web UI, it is pinned.
struct AddServerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var editing: ServerProfile?

    @State private var name = ""
    @State private var host = ""
    @State private var port = "8006"
    @State private var useHTTPS = true
    @State private var method: PVEAuthMethod = .ticket
    @State private var username = "root"
    @State private var realm = "pam"
    @State private var password = ""
    @State private var tokenID = ""
    @State private var tokenSecret = ""
    @State private var skipVerification = false
    @State private var pinnedFingerprint: String?

    @State private var connecting = false
    @State private var errorMessage: String?
    @State private var certificateToTrust: String?
    @State private var totpChallenge: String?
    @State private var totpCode = ""

    @FocusState private var focusedField: Field?

    enum Field { case name, host, port, username, realm, password, tokenID, secret }

    private var trimmedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private var portNumber: Int? {
        guard let value = Int(port), (1...65_535).contains(value) else { return nil }
        return value
    }

    private var canConnect: Bool {
        guard !trimmedHost.isEmpty, portNumber != nil, !username.isEmpty, !realm.isEmpty else { return false }
        switch method {
        case .ticket: return !password.isEmpty
        case .apiToken: return !tokenID.isEmpty && !tokenSecret.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Homelab"))
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .host }
                    TextField("Address", text: $host, prompt: Text("192.168.1.10 or pve.example.com"))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .host)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .username }
                    LabeledContent("Port") {
                        TextField("Port", text: $port, prompt: Text("8006"))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .port)
                    }
                    Toggle("Use HTTPS", isOn: $useHTTPS)
                } header: {
                    Text("Server")
                } footer: {
                    if !useHTTPS {
                        Text("Without HTTPS, your password and everything you do are sent unencrypted.")
                            .foregroundStyle(Palette.warning)
                    }
                }

                Section {
                    Picker("Sign in with", selection: $method) {
                        ForEach(PVEAuthMethod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                    Picker("Realm", selection: $realm) {
                        Text("Linux PAM (pam)").tag("pam")
                        Text("Proxmox VE (pve)").tag("pve")
                        if !["pam", "pve"].contains(realm) { Text(realm).tag(realm) }
                    }

                    if method == .ticket {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { connect(totp: nil) }
                    } else {
                        TextField("Token ID", text: $tokenID, prompt: Text("proxyn"))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .tokenID)
                        SecureField("Secret", text: $tokenSecret)
                            .focused($focusedField, equals: .secret)
                            .submitLabel(.go)
                            .onSubmit { connect(totp: nil) }
                    }
                } header: {
                    Text("Authentication")
                } footer: {
                    Text(method == .apiToken
                         ? "\(method.explanation) Create one under Datacenter → Permissions → API Tokens."
                         : method.explanation)
                }

                Section {
                    if let pinnedFingerprint {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Trusted certificate", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(Palette.positive)
                            Text(pinnedFingerprint)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Button("Forget Certificate", role: .destructive) { self.pinnedFingerprint = nil }
                    }
                    Toggle("Skip Certificate Verification", isOn: $skipVerification)
                } header: {
                    Text("Security")
                } footer: {
                    Text("Leave verification on. For self-signed certificates, Proxyn will ask you to confirm the fingerprint once and remember it.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.critical)
                    }
                }
            }
            .navigationTitle(editing == nil ? "Add Server" : "Edit Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if connecting {
                        ProgressView()
                    } else {
                        Button(editing == nil ? "Connect" : "Save") { connect(totp: nil) }
                            .fontWeight(.semibold)
                            .disabled(!canConnect)
                    }
                }
            }
            .disabled(connecting)
            .interactiveDismissDisabled(connecting)
            .onAppear(perform: loadEditing)
            .alert("Trust This Certificate?",
                   isPresented: Binding(get: { certificateToTrust != nil },
                                        set: { if !$0 { certificateToTrust = nil } }),
                   presenting: certificateToTrust) { fingerprint in
                Button("Trust") {
                    pinnedFingerprint = fingerprint
                    connect(totp: nil)
                }
                Button("Cancel", role: .cancel) {}
            } message: { fingerprint in
                Text("\(trimmedHost) presented a certificate that isn't signed by a trusted authority. Only continue if this SHA-256 fingerprint matches the one shown in the Proxmox web interface under Node → System → Certificates.\n\n\(fingerprint)")
            }
            .alert("Two-Factor Authentication",
                   isPresented: Binding(get: { totpChallenge != nil },
                                        set: { if !$0 { totpChallenge = nil; totpCode = "" } })) {
                TextField("6-digit code", text: $totpCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                Button("Verify") {
                    let pending = totpChallenge.map { (challenge: $0, code: totpCode) }
                    connect(totp: pending)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter the code from your authenticator app.")
            }
        }
    }

    // MARK: Logic

    private func loadEditing() {
        guard let editing else { return }
        name = editing.name
        host = editing.host
        port = String(editing.port)
        useHTTPS = editing.useHTTPS
        method = editing.authMethod
        username = editing.username
        realm = editing.realm
        tokenID = editing.tokenID
        skipVerification = editing.skipCertificateVerification
        pinnedFingerprint = editing.pinnedCertificateSHA256
        if let secret = editing.secret {
            if editing.authMethod == .ticket { password = secret } else { tokenSecret = secret }
        }
    }

    private func buildProfile() -> ServerProfile {
        var profile = editing ?? ServerProfile()
        profile.name = name.trimmingCharacters(in: .whitespaces)
        profile.host = trimmedHost
        profile.port = portNumber ?? 8006
        profile.useHTTPS = useHTTPS
        profile.authMethod = method
        profile.username = username.trimmingCharacters(in: .whitespaces)
        profile.realm = realm
        profile.tokenID = tokenID.trimmingCharacters(in: .whitespaces)
        profile.skipCertificateVerification = skipVerification
        profile.pinnedCertificateSHA256 = pinnedFingerprint
        return profile
    }

    private func connect(totp: (challenge: String, code: String)?) {
        guard canConnect, !connecting else { return }
        focusedField = nil
        connecting = true
        errorMessage = nil

        let profile = buildProfile()
        let secret = method == .ticket ? password : tokenSecret
        let challenge = totp?.challenge
        let code = (totp?.code ?? "").trimmingCharacters(in: .whitespaces)

        Task {
            defer { connecting = false }
            // The secret is written only once the connection has succeeded, so
            // a failed attempt never overwrites a working saved password.
            let probe = ProxmoxClient(profile: profile, secretOverride: secret)
            do {
                if method == .ticket {
                    if let challenge, !code.isEmpty {
                        try await probe.login(totpCode: code, tfaChallenge: challenge)
                    } else {
                        try await probe.login()
                    }
                }
                _ = try await probe.version()

                profile.secret = secret
                Haptics.success()
                if editing == nil { model.addServer(profile) } else { model.updateServer(profile) }
                dismiss()
            } catch let error as ProxmoxError {
                switch error {
                case .needsTOTP(let newChallenge):
                    totpChallenge = newChallenge
                case .untrustedCertificate(_, let fingerprint), .certificateChanged(_, let fingerprint):
                    if let fingerprint {
                        certificateToTrust = fingerprint
                    } else {
                        errorMessage = error.localizedDescription
                    }
                default:
                    Haptics.failure()
                    errorMessage = error.localizedDescription
                }
            } catch {
                Haptics.failure()
                errorMessage = error.localizedDescription
            }
        }
    }
}
