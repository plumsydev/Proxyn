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
            switch route {
            case .guest(let ref, let name):
                GuestDetailView(ref: ref, name: name)
            case .node(let name):
                NodeDetailView(node: name)
            case .storage(let node, let storage):
                StorageDetailView(node: node, storage: storage)
            case .task(let node, let upid, let title):
                TaskLogView(node: node, upid: upid, title: title)
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
