import SwiftUI

/// Add / edit a server. Credentials are validated against the real API before
/// anything is saved, and TLS problems are surfaced with the actual fingerprint
/// so the user can pin it instead of blindly trusting everything.
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
    @State private var allowInsecure = true
    @State private var pinnedFingerprint: String?

    @State private var testing = false
    @State private var result: TestResult?
    @State private var totpCode = ""
    @State private var totpChallenge: String?
    @State private var observedFingerprint: String?

    private enum TestResult: Equatable {
        case success(String)
        case failure(String)
        var isSuccess: Bool { if case .success = self { return true }; return false }
    }

    private var canSubmit: Bool {
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch method {
        case .ticket: return !username.isEmpty && !password.isEmpty
        case .apiToken: return !username.isEmpty && !tokenID.isEmpty && !tokenSecret.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.sheetCanvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        endpointCard
                        authCard
                        securityCard
                        if let result { resultCard(result) }
                        submitButton
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(editing == nil ? "Nouveau serveur" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.sheetCanvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        }
        .presentationBackground(Palette.sheetCanvas)
        .onAppear(perform: loadEditing)
    }

    // MARK: Cards

    private var endpointCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("Point d'accès")

                ProxynField(label: "Nom", placeholder: "homelab", text: $name,
                            symbol: "tag.fill", autocapitalization: .words)

                ProxynField(label: "Hôte ou IP", placeholder: "192.168.1.10", text: $host,
                            symbol: "network", keyboard: .URL, monospaced: true)

                HStack(spacing: 12) {
                    ProxynField(label: "Port", placeholder: "8006", text: $port,
                                symbol: "number", keyboard: .numberPad, monospaced: true)
                        .frame(width: 130)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("PROTOCOLE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(Palette.inkTertiary)
                        SegmentedRail(items: [StringOption("https", "HTTPS"), StringOption("http", "HTTP")],
                                      label: \.title,
                                      selection: Binding(
                                        get: { StringOption(useHTTPS ? "https" : "http", useHTTPS ? "HTTPS" : "HTTP") },
                                        set: { useHTTPS = $0.value == "https" }))
                    }
                }
            }
        }
    }

    private var authCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel("Authentification")

                SegmentedRail(items: PVEAuthMethod.allCases,
                              label: \.title,
                              symbol: { $0.symbol },
                              selection: $method)

                Text(method.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    ProxynField(label: "Utilisateur", placeholder: "root", text: $username,
                                symbol: "person.fill", monospaced: true)
                    ProxynField(label: "Realm", placeholder: "pam", text: $realm,
                                symbol: "building.columns.fill", monospaced: true)
                        .frame(width: 118)
                }

                if method == .ticket {
                    ProxynField(label: "Mot de passe", placeholder: "••••••••", text: $password,
                                symbol: "key.fill", isSecure: true, submitLabel: .go, onSubmit: test)
                } else {
                    ProxynField(label: "ID du jeton", placeholder: "proxyn", text: $tokenID,
                                symbol: "number.square.fill", monospaced: true)
                    ProxynField(label: "Secret", placeholder: "xxxxxxxx-xxxx-…", text: $tokenSecret,
                                symbol: "key.horizontal.fill", isSecure: true, monospaced: true,
                                submitLabel: .go, onSubmit: test)
                    Text("Créez le jeton dans Datacenter → Permissions → API Tokens, en décochant « Privilege Separation » ou en lui donnant les droits voulus.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let totpChallenge, !totpChallenge.isEmpty {
                    Divider1px()
                    ProxynField(label: "Code à usage unique", placeholder: "123456", text: $totpCode,
                                symbol: "lock.rotation", keyboard: .numberPad, monospaced: true,
                                submitLabel: .go, onSubmit: test)
                }
            }
        }
    }

    private var securityCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Transport")

                ToggleRow(title: "Accepter le certificat auto-signé",
                          subtitle: "Indispensable pour la plupart des installations Proxmox, qui utilisent un certificat généré localement.",
                          symbol: "lock.trianglebadge.exclamationmark.fill",
                          isOn: $allowInsecure)

                if let fingerprint = observedFingerprint ?? pinnedFingerprint {
                    Divider1px()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: pinnedFingerprint != nil ? "checkmark.seal.fill" : "seal")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(pinnedFingerprint != nil ? Palette.mint : Palette.inkTertiary)
                            Text(pinnedFingerprint != nil ? "Certificat épinglé" : "Empreinte SHA-256 détectée")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Button(pinnedFingerprint != nil ? "Retirer" : "Épingler") {
                                Haptics.commit()
                                withAnimation(Motion.snap) {
                                    pinnedFingerprint = pinnedFingerprint == nil ? fingerprint : nil
                                }
                            }
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Palette.ember)
                        }
                        Text(fingerprint)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func resultCard(_ result: TestResult) -> some View {
        let ok = result.isSuccess
        let message: String = {
            switch result {
            case .success(let m), .failure(let m): return m
            }
        }()
        return HStack(alignment: .top, spacing: 11) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ok ? Palette.mint : Palette.rose)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill((ok ? Palette.mint : Palette.rose).opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder((ok ? Palette.mint : Palette.rose).opacity(0.3), lineWidth: 1)))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var submitButton: some View {
        Button(action: test) {
            HStack(spacing: 8) {
                if testing {
                    ProgressView().controlSize(.small).tint(.black)
                }
                Text(testing ? "Connexion…" : (editing == nil ? "Tester et connecter" : "Enregistrer"))
            }
        }
        .buttonStyle(ProminentButtonStyle())
        .disabled(!canSubmit || testing)
        .opacity(canSubmit ? 1 : 0.5)
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
        allowInsecure = editing.allowInsecureTLS
        pinnedFingerprint = editing.pinnedCertificateSHA256
        if let secret = editing.secret {
            if editing.authMethod == .ticket { password = secret } else { tokenSecret = secret }
        }
    }

    private func buildProfile() -> ServerProfile {
        var profile = editing ?? ServerProfile()
        profile.name = name.isEmpty ? host : name
        profile.host = host.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        profile.port = Int(port) ?? 8006
        profile.useHTTPS = useHTTPS
        profile.authMethod = method
        profile.username = username.trimmingCharacters(in: .whitespaces)
        profile.realm = realm.trimmingCharacters(in: .whitespaces).isEmpty ? "pam" : realm
        profile.tokenID = tokenID.trimmingCharacters(in: .whitespaces)
        profile.allowInsecureTLS = allowInsecure
        profile.pinnedCertificateSHA256 = pinnedFingerprint
        return profile
    }

    private func test() {
        guard canSubmit, !testing else { return }
        testing = true
        withAnimation(Motion.snap) { result = nil }

        Task {
            let profile = buildProfile()
            profile.secret = method == .ticket ? password : tokenSecret
            let client = ProxmoxClient(profile: profile)

            do {
                if method == .ticket {
                    if let challenge = totpChallenge, !totpCode.isEmpty {
                        try await client.login(totpCode: totpCode.trimmingCharacters(in: .whitespaces),
                                               tfaChallenge: challenge)
                    } else {
                        try await client.login()
                    }
                }
                let version = try await client.version()
                let nodes = (try? await client.nodes()) ?? []
                observedFingerprint = await client.observedFingerprint

                Haptics.success()
                let detail = "Proxmox VE \(version.version ?? "?") · \(nodes.count) nœud\(nodes.count > 1 ? "s" : "")"
                withAnimation(Motion.snap) { result = .success("Connexion établie — \(detail)") }

                try? await Task.sleep(for: .milliseconds(520))
                if editing == nil {
                    model.addServer(profile)
                } else {
                    model.updateServer(profile)
                }
                dismiss()
            } catch let error as ProxmoxError {
                observedFingerprint = await client.observedFingerprint
                switch error {
                case .needsTOTP(let challenge):
                    Haptics.warning()
                    withAnimation(Motion.snap) {
                        totpChallenge = challenge
                        result = .failure("Double authentification activée : saisissez le code à usage unique ci-dessus.")
                    }
                case .tlsRejected:
                    Haptics.failure()
                    withAnimation(Motion.snap) {
                        result = .failure("Le certificat TLS a été refusé. Activez « Accepter le certificat auto-signé » puis réessayez.")
                    }
                default:
                    Haptics.failure()
                    withAnimation(Motion.snap) { result = .failure(error.localizedDescription) }
                }
            } catch {
                Haptics.failure()
                withAnimation(Motion.snap) { result = .failure(error.localizedDescription) }
            }
            testing = false
        }
    }
}
