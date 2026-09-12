import SwiftUI

/// Live task log. Polls `/tasks/{upid}/log` while the task runs, keeps the view
/// pinned to the bottom, and offers to kill a long-running task.
struct TaskLogView: View {
    @Environment(AppModel.self) private var app
    let node: String
    let upid: String
    let title: String

    @State private var lines: [PVETaskLogLine] = []
    @State private var status: PVETask?
    @State private var loading = true
    @State private var error: String?
    @State private var autoScroll = true
    @State private var confirmStop = false
    @State private var pollTask: Task<Void, Never>?

    private var isRunning: Bool { status?.isRunning ?? false }

    private var tint: Color {
        guard let status else { return Palette.sky }
        if status.isRunning { return Palette.sky }
        return status.succeeded ? Palette.mint : Palette.rose
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                statusCard

                if let error { ErrorBanner(message: error, retry: { Task { await load() } }) }

                logCard
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 92)
        }
        .scrollIndicators(.hidden)
        .background(AuroraBackground(tint: tint, intensity: 0.4).ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.string = lines.map(\.t).joined(separator: "\n")
                        Haptics.success()
                        app.toast(.info, "Journal copié")
                    } label: { Label("Copier le journal", systemImage: "doc.on.clipboard") }

                    Button {
                        UIPasteboard.general.string = upid
                        Haptics.tap()
                    } label: { Label("Copier l'UPID", systemImage: "number") }

                    if isRunning {
                        Divider()
                        Button(role: .destructive) { confirmStop = true } label: {
                            Label("Interrompre la tâche", systemImage: "stop.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.ember)
                }
            }
        }
        .task { await start() }
        .onDisappear { pollTask?.cancel() }
        .alert("Interrompre la tâche ?", isPresented: $confirmStop) {
            Button("Interrompre", role: .destructive) {
                Task {
                    await app.perform("Interruption", node: node) { api in
                        try await api.stopTask(node: node, upid: upid)
                    }
                    await load()
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La tâche sera tuée côté Proxmox. Selon l'opération, cela peut laisser l'instance dans un état intermédiaire.")
        }
    }

    private var statusCard: some View {
        GlassCard(tint: tint) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: isRunning ? "circle.dotted"
                          : (status?.succeeded ?? false ? "checkmark" : "xmark"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                        .symbolEffect(.rotate, options: .repeating, isActive: isRunning)
                        .frame(width: 16)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(isRunning ? "En cours d'exécution"
                             : (status?.succeeded ?? false ? "Terminée avec succès" : "Terminée en erreur"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text(status?.exitStatus ?? Format.taskType(status?.type))
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                Divider1px()

                HStack(spacing: 0) {
                    HeroStat(value: node, label: "nœud", tint: Palette.inkSecondary)
                    HeroStat(value: status?.user ?? "—", label: "utilisateur", tint: Palette.inkSecondary)
                    HeroStat(value: Format.duration(status?.duration), label: "durée")
                    HeroStat(value: "\(lines.count)", label: "lignes", tint: Palette.inkSecondary)
                }
            }
            .padding(.leading, 8)
        }
    }

    private var logCard: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SectionLabel("Journal")
                    Spacer()
                    Button {
                        Haptics.select()
                        autoScroll.toggle()
                    } label: {
                        Text(autoScroll ? "Suivre" : "Figé")
                            .font(.system(size: 13))
                            .foregroundStyle(autoScroll ? Palette.ember : Palette.inkTertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 15)
                .padding(.bottom, 12)

                Divider1px()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            if loading && lines.isEmpty {
                                ForEach(0..<6, id: \.self) { _ in
                                    SkeletonBlock(height: 11, radius: 3)
                                        .padding(.vertical, 2)
                                }
                                .padding(.horizontal, 16)
                            }
                            ForEach(lines) { line in
                                Text(line.t.isEmpty ? " " : line.t)
                                    .font(.mono(11.5))
                                    .foregroundStyle(color(for: line.t))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .id(line.n)
                            }
                            .padding(.horizontal, 16)
                            Color.clear.frame(height: 4).id("bottom")
                        }
                        .padding(.vertical, 14)
                    }
                    .frame(maxHeight: 420)
                    .onChange(of: lines.count) { _, _ in
                        guard autoScroll else { return }
                        withAnimation(Motion.fade) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }
        }
    }

    private func color(for line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("failed") || lower.contains("erreur") {
            return Palette.rose
        }
        if lower.contains("warn") { return Palette.amber }
        if lower.hasPrefix("task ok") || lower.contains("successfully") { return Palette.mint }
        return Palette.inkTertiary
    }

    private func start() async {
        await load()
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                await load()
                if !(status?.isRunning ?? false) { return }
            }
        }
    }

    private func load() async {
        guard let api = app.client() else { return }
        defer { loading = false }
        do {
            async let statusTask = api.taskStatus(node: node, upid: upid)
            async let logTask = api.taskLog(node: node, upid: upid, start: 0, limit: 800)
            status = try await statusTask
            let fetched = (try? await logTask) ?? []
            if fetched.count != lines.count {
                withAnimation(Motion.fade) { lines = fetched }
            }
            error = nil
        } catch let err as ProxmoxError {
            if case .cancelled = err { return }
            error = err.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
    }
}
