import SwiftUI

enum AppTab: String, Hashable, CaseIterable {
    case overview, nodes, guests, storage, activity
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showSplash = true

    var body: some View {
        ZStack {
            Group {
                if model.servers.isEmpty {
                    OnboardingView()
                        .transition(.opacity)
                } else {
                    MainTabView()
                        .transition(.opacity)
                }
            }
            .animation(Motion.standard, value: model.servers.isEmpty)

            if showSplash {
                SplashView {
                    withAnimation(.easeOut(duration: 0.25)) { showSplash = false }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .task {
            guard !model.servers.isEmpty else { return }
            await model.connect()
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @SceneStorage("selectedTab") private var tab: AppTab = .overview
    @State private var focusedTask: TaskFocus?
    @State private var totpCode = ""

    private var isAskingForTOTP: Binding<Bool> {
        Binding(
            get: { if case .needsTOTP = model.connection { return true } else { return false } },
            set: { if !$0 { totpCode = "" } })
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Overview", systemImage: "gauge.with.dots.needle.33percent", value: AppTab.overview) {
                OverviewView()
            }
            Tab("Nodes", systemImage: "server.rack", value: AppTab.nodes) {
                NodesView()
            }
            Tab("Guests", systemImage: "square.stack.3d.up", value: AppTab.guests) {
                GuestsView()
            }
            Tab("Storage", systemImage: "internaldrive", value: AppTab.storage) {
                StorageView()
            }
            Tab("Activity", systemImage: "list.bullet.rectangle", value: AppTab.activity) {
                ActivityView()
            }
            .badge(model.snapshot.runningTasks.count)
        }
        .tabViewStyle(.sidebarAdaptable)
        .onOpenURL { url in
            guard let link = DeepLink(url: url) else { return }
            switch link {
            case .overview: tab = .overview
            case .guest: tab = .guests
            case .node: tab = .nodes
            case .storage: tab = .storage
            case .activity: tab = .activity
            }
            model.pendingDeepLink = link
        }
        .overlay(alignment: .top) {
            ToastOverlay(
                toasts: model.toasts,
                onTap: { toast in
                    if let upid = toast.upid, let node = toast.node {
                        focusedTask = TaskFocus(node: node, upid: upid, title: toast.title)
                    }
                    model.dismiss(toast)
                },
                onDismiss: { model.dismiss($0) })
        }
        .sheet(item: $focusedTask) { focus in
            NavigationStack {
                TaskLogView(node: focus.node, upid: focus.upid, title: focus.title)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { focusedTask = nil }
                        }
                    }
            }
        }
        .alert("Two-Factor Authentication", isPresented: isAskingForTOTP) {
            TextField("6-digit code", text: $totpCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
            Button("Verify") {
                let code = totpCode
                totpCode = ""
                Task { await model.submitTOTP(code) }
            }
            Button("Cancel", role: .cancel) {
                model.cancelTOTP()
            }
        } message: {
            Text("Enter the code from your authenticator app for \(model.selectedServer?.fullUsername ?? "this account").")
        }
    }
}

struct TaskFocus: Identifiable, Hashable {
    var id: String { upid }
    var node: String
    var upid: String
    var title: String
}

extension View {
    /// Pushes the destination of a pending widget deep link onto this tab's
    /// stack, once the snapshot it depends on has loaded.
    func handlesDeepLinks(for tab: AppTab, path: Binding<NavigationPath>) -> some View {
        modifier(DeepLinkHandler(tab: tab, path: path))
    }
}

private struct DeepLinkHandler: ViewModifier {
    @Environment(AppModel.self) private var model
    var tab: AppTab
    @Binding var path: NavigationPath

    func body(content: Content) -> some View {
        content
            .onChange(of: model.pendingDeepLink, initial: true) { _, _ in resolve() }
            .onChange(of: model.snapshot.capturedAt) { _, _ in resolve() }
    }

    private func resolve() {
        guard let link = model.pendingDeepLink, owner(of: link) == tab else { return }
        if case .overview = link { path = NavigationPath(); model.pendingDeepLink = nil; return }
        if case .activity = link { path = NavigationPath(); model.pendingDeepLink = nil; return }
        guard let route = model.route(for: link) else { return }
        var fresh = NavigationPath()
        fresh.append(route)
        path = fresh
        model.pendingDeepLink = nil
    }

    private func owner(of link: DeepLink) -> AppTab {
        switch link {
        case .overview: return .overview
        case .guest: return .guests
        case .node: return .nodes
        case .storage: return .storage
        case .activity: return .activity
        }
    }
}
