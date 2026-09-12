import SwiftUI
import Observation

enum ConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case needsTOTP(challenge: String)
    case failed(String)

    var isConnected: Bool { self == .connected }
}

/// Single source of truth. Owns the server list, the live poll loop, the current
/// snapshot and every mutating action the UI can trigger.
@MainActor
@Observable
final class AppModel {

    // MARK: Persisted state

    private(set) var settings: AppSettings {
        didSet { persist() }
    }

    var servers: [ServerProfile] { settings.servers }

    var selectedServer: ServerProfile? {
        guard let id = settings.selectedServerID else { return settings.servers.first }
        return settings.servers.first { $0.id == id } ?? settings.servers.first
    }

    // MARK: Live state

    var snapshot = ClusterSnapshot()
    var history = LiveHistory()
    var connection: ConnectionState = .idle
    var isRefreshing = false
    var lastError: String?
    var toasts: [Toast] = []
    var pendingTOTP: String?
    var hasCompletedSplash = false

    /// Per-guest rolling metrics so detail screens animate between RRD updates.
    private(set) var guestHistory: [String: LiveHistory] = [:]
    private(set) var nodeHistory: [String: LiveHistory] = [:]

    private var clients: [UUID: ProxmoxClient] = [:]
    private var pollTask: Task<Void, Never>?
    private var watchers: [String: Task<Void, Never>] = [:]
    private var previousCounters: [String: (netin: Double, netout: Double, at: Date)] = [:]

    private static let storageKey = "proxyn.settings.v1"

    // MARK: Init

    init(preview: Bool = false) {
        if preview {
            settings = AppSettings()
            return
        }
        if let data = AppGroup.defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
        Haptics.enabled = settings.hapticsEnabled
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        AppGroup.defaults.set(data, forKey: Self.storageKey)
        SharedSnapshotStore.saveServers(settings.servers, selected: settings.selectedServerID)
    }

    // MARK: Settings mutation

    func update(_ transform: (inout AppSettings) -> Void) {
        var copy = settings
        transform(&copy)
        settings = copy
        Haptics.enabled = settings.hapticsEnabled
    }

    func addServer(_ profile: ServerProfile) {
        update {
            $0.servers.append(profile)
            $0.selectedServerID = profile.id
        }
        clients[profile.id] = nil
        Task { await connectAndRefresh(reset: true) }
    }

    func updateServer(_ profile: ServerProfile) {
        update { settings in
            if let idx = settings.servers.firstIndex(where: { $0.id == profile.id }) {
                settings.servers[idx] = profile
            }
        }
        clients[profile.id] = nil
        if profile.id == selectedServer?.id {
            Task { await connectAndRefresh(reset: true) }
        }
    }

    func deleteServer(_ profile: ServerProfile) {
        Keychain.remove(profile.secretKey)
        clients[profile.id] = nil
        update { settings in
            settings.servers.removeAll { $0.id == profile.id }
            if settings.selectedServerID == profile.id {
                settings.selectedServerID = settings.servers.first?.id
            }
        }
        if servers.isEmpty {
            snapshot = ClusterSnapshot()
            connection = .idle
            stopPolling()
        } else {
            Task { await connectAndRefresh(reset: true) }
        }
    }

    func selectServer(_ profile: ServerProfile) {
        guard profile.id != selectedServer?.id else { return }
        Haptics.commit()
        update { $0.selectedServerID = profile.id }
        snapshot = ClusterSnapshot()
        history.reset()
        guestHistory.removeAll()
        nodeHistory.removeAll()
        Task { await connectAndRefresh(reset: true) }
    }

    func toggleFavorite(_ resource: PVEResource) {
        let key = resource.routeKey
        Haptics.tap()
        update { settings in
            if let idx = settings.favoriteGuestIDs.firstIndex(of: key) {
                settings.favoriteGuestIDs.remove(at: idx)
            } else {
                settings.favoriteGuestIDs.append(key)
            }
        }
    }

    func isFavorite(_ resource: PVEResource) -> Bool {
        settings.favoriteGuestIDs.contains(resource.routeKey)
    }

    // MARK: Client access

    func client() -> ProxmoxClient? {
        guard let profile = selectedServer else { return nil }
        return client(for: profile)
    }

    func client(for profile: ServerProfile) -> ProxmoxClient {
        if let existing = clients[profile.id] { return existing }
        let made = ProxmoxClient(profile: profile)
        clients[profile.id] = made
        return made
    }

    // MARK: Connection & polling

    func connectAndRefresh(reset: Bool = false) async {
        guard let profile = selectedServer else {
            connection = .idle
            return
        }
        if reset { snapshot = ClusterSnapshot(); history.reset() }
        connection = .connecting
        let api = client(for: profile)

        do {
            if profile.authMethod == .ticket {
                let authed = await api.isAuthenticated
                if !authed { try await api.login() }
            }
            connection = .connected
            pendingTOTP = nil
            update { settings in
                if let idx = settings.servers.firstIndex(where: { $0.id == profile.id }) {
                    settings.servers[idx].lastConnectedAt = Date()
                }
            }
            await refresh()
            startPolling()
        } catch let error as ProxmoxError {
            if case .needsTOTP(let challenge) = error {
                connection = .needsTOTP(challenge: challenge)
                pendingTOTP = challenge
            } else {
                connection = .failed(error.localizedDescription)
                lastError = error.localizedDescription
            }
        } catch {
            connection = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func submitTOTP(_ code: String) async {
        guard let profile = selectedServer, let challenge = pendingTOTP else { return }
        let api = client(for: profile)
        connection = .connecting
        do {
            try await api.login(totpCode: code, tfaChallenge: challenge)
            pendingTOTP = nil
            connection = .connected
            await refresh()
            startPolling()
            Haptics.success()
        } catch {
            Haptics.failure()
            connection = .needsTOTP(challenge: challenge)
            lastError = (error as? ProxmoxError)?.localizedDescription ?? error.localizedDescription
        }
    }

    func startPolling() {
        stopPolling()
        let interval = max(2, settings.liveRefreshInterval)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard let self, !Task.isCancelled else { return }
                await self.refresh(silent: true)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    @discardableResult
    func refresh(silent: Bool = false) async -> Bool {
        guard let api = client() else { return false }
        if !silent { isRefreshing = true }
        defer { if !silent { isRefreshing = false } }

        do {
            async let resourcesTask = api.clusterResources()
            async let statusTask = api.clusterStatus()
            async let tasksTask = api.clusterTasks()

            let loaded = try await resourcesTask
            var snap = ClusterSnapshot()
            snap.resources = loaded
            snap.clusterNodes = (try? await statusTask) ?? []
            snap.tasks = (try? await tasksTask) ?? []
            snap.version = snapshot.version
            snap.capturedAt = Date()

            if snapshot.version == nil {
                snap.version = try? await api.version()
            }

            applySnapshot(snap)
            lastError = nil
            if connection != .connected { connection = .connected }
            return true
        } catch let error as ProxmoxError {
            if case .cancelled = error { return false }
            if error.isAuthFailure {
                await api.invalidateSession()
                connection = .failed(error.localizedDescription)
            }
            lastError = error.localizedDescription
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func applySnapshot(_ snap: ClusterSnapshot) {
        // Derive instantaneous network throughput from the cumulative counters.
        var totalIn = 0.0, totalOut = 0.0
        let now = Date()
        for guest in snap.guests where guest.state.isUp {
            let key = guest.id
            let inBytes = guest.netin ?? 0
            let outBytes = guest.netout ?? 0
            if let prev = previousCounters[key] {
                let dt = now.timeIntervalSince(prev.at)
                if dt > 0.5, inBytes >= prev.netin, outBytes >= prev.netout {
                    totalIn += (inBytes - prev.netin) / dt
                    totalOut += (outBytes - prev.netout) / dt
                }
            }
            previousCounters[key] = (inBytes, outBytes, now)
        }

        withAnimation(Motion.meter) {
            snapshot = snap
        }
        history.append(cpu: snap.aggregateCPU, memory: snap.aggregateMemory,
                       netIn: totalIn, netOut: totalOut, at: now)

        for node in snap.nodes {
            var h = nodeHistory[node.displayName] ?? LiveHistory()
            h.append(cpu: node.cpuFraction, memory: node.memFraction, netIn: 0, netOut: 0, at: now)
            nodeHistory[node.displayName] = h
        }
        for guest in snap.guests {
            var h = guestHistory[guest.id] ?? LiveHistory()
            h.append(cpu: guest.cpuFraction, memory: guest.memFraction, netIn: 0, netOut: 0, at: now)
            guestHistory[guest.id] = h
        }

        SharedSnapshotStore.save(snapshot: snap, serverName: selectedServer?.displayName ?? "Proxmox")
    }

    func history(forGuest id: String) -> LiveHistory { guestHistory[id] ?? LiveHistory() }
    func history(forNode name: String) -> LiveHistory { nodeHistory[name] ?? LiveHistory() }

    // MARK: Toasts

    func toast(_ kind: Toast.Kind, _ title: String, detail: String? = nil,
               upid: String? = nil, node: String? = nil) {
        let toast = Toast(kind: kind, title: title, detail: detail, upid: upid, node: node)
        withAnimation(Motion.snap) { toasts.append(toast) }
        if kind != .progress {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(kind == .failure ? 6 : 3.2))
                self?.dismiss(toast)
            }
        }
    }

    func dismiss(_ toast: Toast) {
        withAnimation(Motion.snap) { toasts.removeAll { $0.id == toast.id } }
    }

    private func replaceToast(upid: String, with new: Toast) {
        withAnimation(Motion.snap) {
            toasts.removeAll { $0.upid == upid }
            toasts.append(new)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(new.kind == .failure ? 6 : 3.2))
            self?.dismiss(new)
        }
    }

    // MARK: Running a mutating action

    /// Wraps an API call: optimistic toast, UPID tracking, error surfacing, and
    /// an immediate refresh once the task settles.
    @discardableResult
    func perform(_ title: String, node: String?, work: @escaping (ProxmoxClient) async throws -> String?) async -> Bool {
        guard let api = client() else { return false }
        Haptics.commit()
        do {
            let upid = try await work(api)
            if let upid, upid.hasPrefix("UPID"), let node {
                toast(.progress, title, detail: "En cours…", upid: upid, node: node)
                watch(upid: upid, node: node, title: title)
            } else {
                toast(.success, title, detail: "Terminé")
                Haptics.success()
            }
            await refresh(silent: true)
            return true
        } catch let error as ProxmoxError {
            Haptics.failure()
            toast(.failure, title, detail: error.localizedDescription)
            return false
        } catch {
            Haptics.failure()
            toast(.failure, title, detail: error.localizedDescription)
            return false
        }
    }

    private func watch(upid: String, node: String, title: String) {
        watchers[upid]?.cancel()
        watchers[upid] = Task { [weak self] in
            guard let self else { return }
            let api = self.client()
            for _ in 0..<180 {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                guard let api else { return }
                guard let status = try? await api.taskStatus(node: node, upid: upid) else { continue }
                if !status.isRunning {
                    if status.succeeded {
                        self.replaceToast(upid: upid, with: Toast(kind: .success, title: title,
                                                                  detail: "Terminé en \(Format.duration(status.duration))"))
                        Haptics.success()
                    } else {
                        self.replaceToast(upid: upid, with: Toast(kind: .failure, title: title,
                                                                  detail: status.exitStatus ?? "Échec",
                                                                  upid: upid, node: node))
                        Haptics.failure()
                    }
                    await self.refresh(silent: true)
                    self.watchers[upid] = nil
                    return
                }
                await self.refresh(silent: true)
            }
            self.watchers[upid] = nil
        }
    }

    // MARK: Guest actions

    func power(_ ref: GuestRef, action: GuestPowerAction, name: String) async {
        await perform("\(action.label) · \(name)", node: ref.node) { api in
            try await api.guestPower(ref, action: action)
        }
    }
}

extension AppModel {
    /// Called when the scene becomes active again: reconnect if the ticket went
    /// stale while we were backgrounded, then restart the poll loop.
    func resumeLive() async {
        guard selectedServer != nil else { return }
        switch connection {
        case .connected:
            await refresh(silent: true)
            startPolling()
        case .needsTOTP:
            break
        default:
            await connectAndRefresh()
        }
    }
}
