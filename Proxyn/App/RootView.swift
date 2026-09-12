import SwiftUI

enum AppTab: Int, CaseIterable, Identifiable, Hashable {
    case overview, nodes, guests, storage, activity
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .overview: return "Vue"
        case .nodes: return "Nœuds"
        case .guests: return "Instances"
        case .storage: return "Stockage"
        case .activity: return "Activité"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "chart.bar.doc.horizontal.fill"
        case .nodes: return "server.rack"
        case .guests: return "cube.transparent.fill"
        case .storage: return "internaldrive.fill"
        case .activity: return "waveform.path.ecg"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showSplash = true

    var body: some View {
        ZStack {
            Group {
                if model.servers.isEmpty {
                    OnboardingView()
                        .transition(.opacity.combined(with: .scale(scale: 1.03)))
                } else {
                    MainShell()
                        .transition(.opacity)
                }
            }
            .opacity(showSplash ? 0 : 1)
            .scaleEffect(showSplash ? 0.97 : 1)
            .animation(.easeOut(duration: 0.45), value: showSplash)

            if showSplash {
                SplashView { withAnimation(.easeOut(duration: 0.3)) { showSplash = false } }
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(Motion.glide, value: model.servers.isEmpty)
        .task {
            guard !model.servers.isEmpty else { return }
            await model.connectAndRefresh()
        }
    }
}

struct MainShell: View {
    @Environment(AppModel.self) private var model
    @State private var tab: AppTab = .overview
    @State private var showServerSwitcher = false
    @State private var showSettings = false
    @State private var taskFocus: TaskFocus?

    var body: some View {
        @Bindable var model = model

        ZStack {
            Palette.canvas.ignoresSafeArea()

            // A plain TabView is UIKit-backed and swallows safe-area insets, so
            // the floating bar would sit on top of the home indicator. Keeping
            // the five stacks alive in a ZStack preserves per-tab navigation
            // state and lets the bar be a real safe-area inset.
            ForEach(AppTab.allCases) { item in
                tabContent(item)
                    .opacity(tab == item ? 1 : 0)
                    .scaleEffect(tab == item ? 1 : 0.985)
                    .allowsHitTesting(tab == item)
                    .zIndex(tab == item ? 1 : 0)
            }
        }
        .animation(.easeOut(duration: 0.18), value: tab)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(selection: $tab)
        }
        // Anchored to the bottom safe area (just above the tab bar) instead of
        // the top, where it would sit on the navigation bar of pushed screens.
        .overlay(alignment: .bottom) {
            ToastStack(
                toasts: model.toasts,
                onTap: { toast in
                    if let upid = toast.upid, let node = toast.node {
                        taskFocus = TaskFocus(node: node, upid: upid, title: toast.title)
                    }
                    model.dismiss(toast)
                },
                onDismiss: { model.dismiss($0) })
            .padding(.bottom, 8)
        }
        .overlay {
            if case .needsTOTP = model.connection {
                TOTPPrompt()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    .zIndex(5)
            }
        }
        .sheet(isPresented: $showServerSwitcher) { ServerSwitcherSheet() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $taskFocus) { focus in
            NavigationStack {
                TaskLogView(node: focus.node, upid: focus.upid, title: focus.title)
            }
            .presentationBackground(Palette.canvas)
        }
        .animation(Motion.snap, value: model.connection)
    }
}

extension MainShell {
    @ViewBuilder
    func tabContent(_ item: AppTab) -> some View {
        switch item {
        case .overview:
            DashboardView(showServerSwitcher: $showServerSwitcher, showSettings: $showSettings)
        case .nodes:
            NodesView()
        case .guests:
            GuestsView()
        case .storage:
            StorageView()
        case .activity:
            ActivityView()
        }
    }
}

struct TaskFocus: Identifiable, Hashable {
    var id: String { upid }
    var node: String
    var upid: String
    var title: String
}

/// Full-width bar with a material backdrop, a hairline top edge and a 2pt
/// accent marker that slides to the active item. No pill, no outline, no glow —
/// the colour change and the marker are the whole affordance.
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { item in
                let isOn = item == selection
                Button {
                    guard !isOn else { return }
                    Haptics.select()
                    withAnimation(Motion.snap) { selection = item }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 17, weight: .regular))
                            .symbolVariant(isOn ? .fill : .none)
                            .foregroundStyle(isOn ? Palette.ember : Palette.inkTertiary)
                            .frame(height: 20)
                        Text(item.title)
                            .font(.system(size: 10.5, weight: isOn ? .medium : .regular))
                            .foregroundStyle(isOn ? Palette.ink : Palette.inkTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 9)
                    .padding(.bottom, 4)
                    .overlay(alignment: .top) {
                        if isOn {
                            Capsule()
                                .fill(Palette.ember)
                                .frame(width: 18, height: 2)
                                .matchedGeometryEffect(id: "tabMarker", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 52)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(Palette.canvas.opacity(0.45)))
                .overlay(alignment: .top) { Divider1px() }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}
