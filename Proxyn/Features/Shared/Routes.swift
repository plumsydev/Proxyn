import SwiftUI

enum Route: Hashable {
    case guest(ref: GuestRef, name: String)
    case node(String)
    case storage(node: String, storage: String)
    case task(node: String, upid: String, title: String)
    case allGuests
    case allTasks
    case schedules
    case servers
}

extension View {
    /// Registered once per navigation stack so any screen can push any other.
    func proxynDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            // Detail screens own @State models created from their parameters.
            // The explicit identity makes SwiftUI build a fresh screen when a
            // route is replaced in place (a deep link to another guest, say)
            // instead of keeping the previous screen's state.
            switch route {
            case .guest(let ref, let name):
                GuestDetailView(ref: ref, name: name)
                    .id(ref.id)
            case .node(let name):
                NodeDetailView(node: name)
                    .id(name)
            case .storage(let node, let storage):
                StorageDetailView(node: node, storage: storage)
                    .id("\(node)/\(storage)")
            case .task(let node, let upid, let title):
                TaskLogView(node: node, upid: upid, title: title)
                    .id(upid)
            case .allGuests:
                GuestListContent()
            case .allTasks:
                ActivityListContent()
            case .schedules:
                SchedulesView()
            case .servers:
                ServerListView()
            }
        }
    }
}
