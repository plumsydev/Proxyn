import SwiftUI
import Observation
import WidgetKit

enum ConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case needsTOTP(challenge: String)
    case failed(ProxmoxError)

    var isConnected: Bool { self == .connected }

    var failure: ProxmoxError? {
        if case .failed(let error) = self { return error }
        return nil
    }
}

/// Single source of truth: server list, live polling, the current snapshot, and
/// every mutating action the UI can trigger.
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

    var preferredColorScheme: ColorScheme? {
        switch settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    // MARK: Live state

    private(set) var snapshot = ClusterSnapshot.empty
    private(set) var history = LiveHistory()
    private(set) var connection: ConnectionState = .idle
    private(set) var lastRefreshError: ProxmoxError?
    private(set) var toasts: [Toast] = []

    private var guestHistory: [String: LiveHistory] = [:]
    private var nodeHistory: [String: LiveHistory] = [:]
    private var previousCounters: [String: (netin: Double, netout: Double, at: Date)] = [:]

    private var clients: [UUID: ProxmoxClient] = [:]
    private var pollTask: Task<Void, Never>?
    private var watchers: [String: Task<Void, Never>] = [:]

    private static let storageKey = "proxyn.settings.v2"

    // MARK: Init

    init(preview: Bool = false) {
        if !preview,
           let data = AppGroup.defaults.data(forKey: Self.storageKey),
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

    func update(_ transform: (inout AppSettings) -> Void) {
        var copy = settings
        transform(&copy)
        guard copy != settings else { return }
        let intervalChanged = copy.refreshInterval != settings.refreshInterval
        settings = copy
        Haptics.enabled = settings.hapticsEnabled
        if intervalChanged, connection.isConnected { startPolling() }
    }

    // MARK: Servers

    func addServer(_ profile: ServerProfile) {
        update {
            $0.servers.append(profile)
            $0.selectedServerID = profile.id
        }
        clients[profile.id] = nil
        Task { await connect(reset: true) }
    }

    func updateServer(_ profile: ServerProfile) {
        update { settings in
            if let index = settings.servers.firstIndex(where: { $0.id == profile.id }) {
                settings.servers[index] = profile
            }
        }
        clients[profile.id] = nil
        if profile.id == selectedServer?.id {
            Task { await connect(reset: true) }
        }
    }

    func deleteServer(_ profile: ServerProfile) {
        profile.secret = nil
        clients[profile.id] = nil
        update { settings in
            settings.servers.removeAll { $0.id == profile.id }
            settings.favoriteGuestIDs.removeAll { $0.hasPrefix("\(profile.id.uuidString)|") }
            if settings.selectedServerID == profile.id {
                settings.selectedServerID = settings.servers.first?.id
            }
        }
        if servers.isEmpty {
            stopPolling()
            resetLiveState()
            connection = .idle
            SharedSnapshotStore.clear()
            WidgetCenter.shared.reloadAllTimelines()
        } else {
            Task { await connect(reset: true) }
        }
    }

    func selectServer(_ profile: ServerProfile) {
        guard profile.id != selectedServer?.id else { return }
        Haptics.select()
        update { $0.selectedServerID = profile.id }
        Task { await connect(reset: true) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The certificate of the active server changed and the user accepted the
    /// new one.
    func trustCurrentCertificate(_ fingerprint: String) {
        guard var profile = selectedServer else { return }
        profile.pinnedCertificateSHA256 = fingerprint
        updateServer(profile)
    }

    // MARK: Favourites

    private func favoriteKey(_ resource: PVEResource) -> String {
        "\(selectedServer?.id.uuidString ?? "-")|\(resource.routeKey)"
    }

    func isFavorite(_ resource: PVEResource) -> Bool {
        settings.favoriteGuestIDs.contains(favoriteKey(resource))
    }

    func toggleFavorite(_ resource: PVEResource) {
        let key = favoriteKey(resource)
        Haptics.tap()
        update { settings in
            if let index = settings.favoriteGuestIDs.firstIndex(of: key) {
                settings.favoriteGuestIDs.remove(at: index)
            } else {
                settings.favoriteGuestIDs.append(key)
            }
        }
    }

    // MARK: Clients

    func client() -> ProxmoxClient? {
        selectedServer.map(client(for:))
    }

    func client(for profile: ServerProfile) -> ProxmoxClient {
        if let existing = clients[profile.id] { return existing }
        let made = ProxmoxClient(profile: profile)
        clients[profile.id] = made
        return made
    }

    // MARK: Connection

    func connect(reset: Bool = false) async {
        guard let profile = selectedServer else {
            connection = .idle
            return
        }
        if reset { resetLiveState() }
        connection = .connecting
        let api = client(for: profile)

        do {
            if profile.authMethod == .ticket, !(await api.isAuthenticated) {
                try await api.login()
            }
            await didConnect(profile)
        } catch let error as ProxmoxError {
            handleConnectionError(error)
        } catch {
            handleConnectionError(.transport(error.localizedDescription))
        }
    }

    func submitTOTP(_ code: String) async {
        guard let profile = selectedServer, case .needsTOTP(let challenge) = connection else { return }
        connection = .connecting
        do {
            try await client(for: profile).login(totpCode: code, tfaChallenge: challenge)
            Haptics.success()
            await didConnect(profile)
        } catch let error as ProxmoxError {
            Haptics.failure()
            if case .badCredentials = error {
                // Wrong code: keep the prompt up with a fresh challenge.
                connection = .idle
                await connect()
                toast(.failure, "That code didn't work")
            } else {
                handleConnectionError(error)
            }
        } catch {
            handleConnectionError(.transport(error.localizedDescription))
        }
    }

    func cancelTOTP() {
        connection = .failed(.notAuthenticated)
    }

    private func didConnect(_ profile: ServerProfile) async {
        connection = .connected
        update { settings in
            if let index = settings.servers.firstIndex(where: { $0.id == profile.id }) {
                settings.servers[index].lastConnectedAt = Date()
            }
        }
        await refresh()
        startPolling()
    }

    private func handleConnectionError(_ error: ProxmoxError) {
        if case .needsTOTP(let challenge) = error {
            connection = .needsTOTP(challenge: challenge)
        } else {
            Log.auth.error("Connection failed: \(error.localizedDescription, privacy: .public)")
            connection = .failed(error)
        }
    }

    /// Scene became active: refresh immediately, reconnecting if needed.
    func resume() async {
        guard selectedServer != nil else { return }
        switch connection {
        case .connected:
            await refresh()
            startPolling()
        case .needsTOTP, .connecting:
            break
        case .idle, .failed:
            await connect()
        }
    }

    /// Scene went to the background: stop polling and let the widget pick up
    /// the latest snapshot.
    func suspend() {
        stopPolling()
        if !snapshot.isEmpty {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: Deep links

    /// Set when a widget opens the app; the tab that owns the destination
    /// pushes it once the data it needs is available.
    var pendingDeepLink: DeepLink?

    func route(for link: DeepLink) -> Route? {
        switch link {
        case .overview, .activity:
            return nil
        case .guest(let vmid):
            guard let guest = snapshot.guests.first(where: { $0.vmid == vmid }),
                  let ref = GuestRef(resource: guest) else { return nil }
            return .guest(ref: ref, name: guest.displayName)
        case .node(let name):
            return .node(name)
        case .storage(let node, let storage):
            return .storage(node: node, storage: storage)
        }
    }

    // MARK: Polling

    func startPolling() {
        stopPolling()
        let interval = max(2, settings.refreshInterval)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard let self, !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard let api = client(), let profile = selectedServer else { return }

        do {
            async let resourcesRequest = api.clusterResources()
            async let statusRequest = api.clusterStatus()
            async let tasksRequest = api.clusterTasks()

            let resources = try await resourcesRequest
            let status = (try? await statusRequest) ?? []
            let tasks = (try? await tasksRequest) ?? []
            var version = snapshot.version
            if version == nil { version = try? await api.version() }

            apply(ClusterSnapshot(resources: resources, clusterNodes: status, tasks: tasks,
                                  version: version, capturedAt: Date()),
                  serverName: profile.displayName)
            lastRefreshError = nil
            if connection != .connected { connection = .connected }
        } catch let error as ProxmoxError {
            if case .cancelled = error { return }
            lastRefreshError = error
            if error.isAuthFailure {
                await api.invalidateSession()
                connection = .failed(error)
            }
        } catch {
            lastRefreshError = .transport(error.localizedDescription)
        }
    }

    private func apply(_ new: ClusterSnapshot, serverName: String) {
        let now = new.capturedAt

        // Instantaneous throughput from the cumulative counters.
        var totalIn = 0.0, totalOut = 0.0
        var counters: [String: (netin: Double, netout: Double, at: Date)] = [:]
        for guest in new.runningGuests {
            let inBytes = guest.netin ?? 0, outBytes = guest.netout ?? 0
            if let previous = previousCounters[guest.id] {
                let elapsed = now.timeIntervalSince(previous.at)
                if elapsed > 0.5, inBytes >= previous.netin, outBytes >= previous.netout {
                    totalIn += (inBytes - previous.netin) / elapsed
                    totalOut += (outBytes - previous.netout) / elapsed
                }
            }
            counters[guest.id] = (inBytes, outBytes, now)
        }
        previousCounters = counters

        history.append(cpu: new.aggregateCPU, memory: new.aggregateMemory, netIn: totalIn, netOut: totalOut)

        // Rebuilt from the snapshot each time, so histories of deleted guests
        // and removed nodes don't accumulate for the lifetime of the app.
        var nodes: [String: LiveHistory] = [:]
        for node in new.nodes {
            var h = nodeHistory[node.displayName] ?? LiveHistory()
            h.append(cpu: node.cpuFraction, memory: node.memFraction)
            nodes[node.displayName] = h
        }
        nodeHistory = nodes

        var guests: [String: LiveHistory] = [:]
        for guest in new.guests {
            var h = guestHistory[guest.id] ?? LiveHistory()
            h.append(cpu: guest.cpuFraction, memory: guest.memFraction)
            guests[guest.id] = h
        }
        guestHistory = guests

        withAnimation(Motion.value) { snapshot = new }
        SharedSnapshotStore.save(snapshot: new, serverID: selectedServer?.id, serverName: serverName)
    }

    private func resetLiveState() {
        snapshot = .empty
        history.reset()
        guestHistory = [:]
        nodeHistory = [:]
        previousCounters = [:]
        lastRefreshError = nil
    }

    func history(forGuest id: String) -> [Double] { guestHistory[id]?.cpu ?? [] }
    func history(forNode name: String) -> [Double] { nodeHistory[name]?.cpu ?? [] }

    // MARK: Toasts

    func toast(_ kind: Toast.Kind, _ title: String, detail: String? = nil,
               upid: String? = nil, node: String? = nil) {
        let toast = Toast(kind: kind, title: title, detail: detail, upid: upid, node: node)
        withAnimation(Motion.standard) {
            toasts.removeAll { $0.upid != nil && $0.upid == upid }
            toasts.append(toast)
            if toasts.count > 3 { toasts.removeFirst(toasts.count - 3) }
        }
        guard kind != .progress else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(kind == .failure ? 6 : 3))
            self?.dismiss(toast)
        }
    }

    func dismiss(_ toast: Toast) {
        withAnimation(Motion.standard) { toasts.removeAll { $0.id == toast.id } }
    }

    // MARK: Actions

    /// Runs a mutating API call: progress toast, UPID tracking until the task
    /// settles, error surfacing, refresh.
    @discardableResult
    func perform(_ title: String, node: String?,
                 work: @escaping (ProxmoxClient) async throws -> String?) async -> Bool {
        guard let api = client() else { return false }
        Haptics.commit()
        do {
            let upid = try await work(api)
            if let upid, upid.hasPrefix("UPID"), let node {
                toast(.progress, title, upid: upid, node: node)
                watch(upid: upid, node: node, title: title)
            } else {
                toast(.success, title)
                Haptics.success()
            }
            await refresh()
            return true
        } catch {
            let message = (error as? ProxmoxError)?.localizedDescription ?? error.localizedDescription
            Log.network.error("\(title, privacy: .public) failed: \(message, privacy: .public)")
            Haptics.failure()
            toast(.failure, title, detail: message)
            return false
        }
    }

    private func watch(upid: String, node: String, title: String) {
        watchers[upid]?.cancel()
        watchers[upid] = Task { [weak self] in
            defer { self?.watchers[upid] = nil }
            // Long operations (migrations, backups) can run for a long time;
            // stop watching after an hour and let the Activity tab take over.
            for attempt in 0..<1_200 {
                try? await Task.sleep(for: .seconds(attempt < 10 ? 1.5 : 3))
                guard let self, !Task.isCancelled, let api = self.client() else { return }
                guard let status = try? await api.taskStatus(node: node, upid: upid) else { continue }
                guard !status.isRunning else { continue }

                withAnimation(Motion.standard) { self.toasts.removeAll { $0.upid == upid } }
                if status.succeeded {
                    self.toast(.success, title, detail: "Finished in \(Format.duration(status.duration))")
                    Haptics.success()
                } else {
                    self.toast(.failure, title, detail: status.exitStatus ?? "Failed",
                               upid: upid, node: node)
                    Haptics.failure()
                }
                await self.refresh()
                return
            }
        }
    }

    func power(_ ref: GuestRef, action: GuestPowerAction, name: String) async {
        await perform("\(action.label) \(name)", node: ref.node) { api in
            try await api.guestPower(ref, action: action)
        }
    }
}
