import SwiftUI

enum Route: Hashable {
    case guest(ref: GuestRef, name: String)
    case node(String)
    case storage(node: String, storage: String)
    case task(node: String, upid: String, title: String)
    case allGuests
    case allTasks
}

extension View {
    /// Registered once per navigation stack so any screen can push any other.
    func proxynDestinations() -> some View {
        self
            .navigationDestination(for: Route.self) { route in
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
                    GuestsView(embedded: true)
                case .allTasks:
                    ActivityView(embedded: true)
                }
            }
    }
}

/// Background + tab-bar clearance applied to every tab root.
struct TabPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}
