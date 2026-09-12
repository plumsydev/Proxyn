import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Configuration

struct GuestEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Guest"
    static let defaultQuery = GuestQuery()

    /// `vmid` as a string: VM IDs are unique across a Proxmox cluster and
    /// survive migrations between nodes.
    var id: String
    var name: String
    var detail: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
    }

    init(_ guest: WidgetGuest) {
        id = String(guest.vmid)
        name = guest.name
        detail = "\(guest.kindLabel) \(guest.vmid) · \(guest.node)"
    }
}

struct GuestQuery: EntityStringQuery {
    private var guests: [WidgetGuest] {
        (SharedSnapshotStore.load()?.guests ?? []).sorted { $0.vmid < $1.vmid }
    }

    func entities(for identifiers: [String]) async throws -> [GuestEntity] {
        guests.filter { identifiers.contains(String($0.vmid)) }.map(GuestEntity.init)
    }

    func entities(matching string: String) async throws -> [GuestEntity] {
        guests.filter { $0.name.localizedCaseInsensitiveContains(string) || String($0.vmid).hasPrefix(string) }
            .map(GuestEntity.init)
    }

    func suggestedEntities() async throws -> [GuestEntity] {
        guests.map(GuestEntity.init)
    }
}

struct GuestWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Guest"
    static let description = IntentDescription("Choose the virtual machine or container to show.")

    @Parameter(title: "Guest")
    var guest: GuestEntity?
}

// MARK: - Start action

/// Starting is the only action offered from a widget: it's safe to trigger by
/// accident. Stopping or rebooting stays in the app, behind a confirmation.
struct StartGuestIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Guest"
    static let description = IntentDescription("Starts a stopped virtual machine or container.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let isDiscoverable = false

    @Parameter(title: "Guest ID")
    var vmid: Int

    init() {}

    init(vmid: Int) {
        self.vmid = vmid
    }

    func perform() async throws -> some IntentResult {
        guard let server = SharedSnapshotStore.selectedServer(),
              let guest = SharedSnapshotStore.load()?.guest(vmid: vmid),
              let kind = PVEResourceType(rawValue: guest.kind) else {
            return .result()
        }
        let ref = GuestRef(node: guest.node, kind: kind, vmid: vmid)
        try await ProxmoxClient(profile: server).guestPower(ref, action: .start)

        // Show the new state straight away; the next refresh confirms it.
        SharedSnapshotStore.update { snapshot in
            if let index = snapshot.guests.firstIndex(where: { $0.vmid == vmid }) {
                snapshot.guests[index].status = "running"
            }
        }
        return .result()
    }
}

// MARK: - Timeline

struct GuestEntry: TimelineEntry {
    var date: Date
    var guest: WidgetGuest?
    var isConfigured: Bool
    var snapshotDate: Date?
}

struct GuestProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> GuestEntry {
        GuestEntry(date: Date(), guest: WidgetSnapshot.preview.guests.first, isConfigured: true, snapshotDate: Date())
    }

    func snapshot(for configuration: GuestWidgetIntent, in context: Context) async -> GuestEntry {
        if context.isPreview && configuration.guest == nil {
            return placeholder(in: context)
        }
        return await entry(for: configuration)
    }

    func timeline(for configuration: GuestWidgetIntent, in context: Context) async -> Timeline<GuestEntry> {
        Timeline(entries: [await entry(for: configuration)], policy: .after(WidgetData.nextRefresh))
    }

    private func entry(for configuration: GuestWidgetIntent) async -> GuestEntry {
        guard let id = configuration.guest?.id, let vmid = Int(id) else {
            return GuestEntry(date: Date(), guest: nil, isConfigured: false, snapshotDate: nil)
        }
        let snapshot = await WidgetData.load()
        return GuestEntry(date: Date(), guest: snapshot?.guest(vmid: vmid), isConfigured: true,
                          snapshotDate: snapshot?.capturedAt)
    }
}

// MARK: - Widget

struct GuestWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ProxynGuest", intent: GuestWidgetIntent.self, provider: GuestProvider()) { entry in
            GuestWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetLocale()
                .widgetURL(entry.guest.map { DeepLink.guest(vmid: $0.vmid).url } ?? DeepLink.overview.url)
        }
        .configurationDisplayName("Guest")
        .description("Status of a virtual machine or container, with a button to start it.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct GuestWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: GuestEntry

    var body: some View {
        if let guest = entry.guest {
            switch family {
            case .systemMedium: medium(guest)
            case .accessoryCircular: circular(guest)
            case .accessoryRectangular: rectangular(guest)
            default: small(guest)
            }
        } else {
            WidgetEmptyState(symbol: "square.stack.3d.up",
                             message: entry.isConfigured
                                ? "This guest no longer exists."
                                : "Touch and hold, then Edit Widget to choose a guest.")
        }
    }

    private func statusLine(_ guest: WidgetGuest) -> String {
        if guest.isRunning { return "Running · \(Format.uptime(guest.uptime))" }
        if guest.isPaused { return "Paused" }
        return "Stopped"
    }

    private func header(_ guest: WidgetGuest) -> some View {
        WidgetHeader(symbol: guest.symbol, title: "\(guest.kindLabel) \(guest.vmid)") {
            WidgetStateDot(running: guest.isRunning, paused: guest.isPaused)
        }
    }

    private func startButton(_ guest: WidgetGuest) -> some View {
        Button(intent: StartGuestIntent(vmid: guest.vmid)) {
            Label("Start", systemImage: "play.fill")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 7)
        .foregroundStyle(Color(uiColor: .systemBackground))
        .background(Palette.accent, in: .capsule)
        .widgetAccentable()
    }

    // MARK: Home Screen

    private func small(_ guest: WidgetGuest) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(guest)
            Spacer(minLength: 4)
            Text(guest.name)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(statusLine(guest))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if guest.isRunning {
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.percent(guest.cpu))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .widgetAccentable()
                    Text("CPU")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                }
                WidgetMeter(label: "Memory", value: Format.bytes(guest.memoryUsed), fraction: guest.memory)
                    .padding(.top, 4)
            } else if !guest.isPaused {
                startButton(guest)
            }
        }
    }

    private func medium(_ guest: WidgetGuest) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                header(guest)
                Spacer(minLength: 4)
                Text(guest.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text("\(statusLine(guest)) · \(guest.node)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if !guest.isRunning && !guest.isPaused {
                    startButton(guest)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                Spacer(minLength: 0)
                WidgetMeter(label: "CPU", value: guest.isRunning ? Format.percent(guest.cpu) : "—",
                            fraction: guest.isRunning ? guest.cpu : 0, tint: Palette.accent)
                WidgetMeter(label: "Memory",
                            value: guest.isRunning ? Format.bytes(guest.memoryUsed) : Format.bytes(guest.memoryTotal),
                            fraction: guest.isRunning ? guest.memory : 0)
                Text("\(Int(guest.cores)) vCPU · \(Format.bytes(guest.memoryTotal))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Lock Screen

    private func circular(_ guest: WidgetGuest) -> some View {
        Gauge(value: guest.isRunning ? guest.cpu : 0) {
            Image(systemName: guest.symbol)
        } currentValueLabel: {
            Image(systemName: guest.isRunning ? "play.fill" : "stop.fill")
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }

    private func rectangular(_ guest: WidgetGuest) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(guest.name)
                .font(.headline)
                .lineLimit(1)
                .widgetAccentable()
            Text(statusLine(guest))
            if guest.isRunning {
                Text("CPU \(Format.percent(guest.cpu)) · \(Format.bytes(guest.memoryUsed))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
}
