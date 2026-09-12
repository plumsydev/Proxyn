import SwiftUI

/// Task status and live output. Polls while the task runs and follows the end
/// of the log unless the user scrolls away.
struct TaskLogView: View {
    @Environment(AppModel.self) private var app
    let node: String
    let upid: String
    let title: String

    @State private var lines: [PVETaskLogLine] = []
    @State private var status: PVETask?
    @State private var error: String?
    @State private var follow = true
    @State private var confirmStop = false

    private var isRunning: Bool { status?.isRunning ?? true }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            if status == nil || isRunning {
                                ProgressView().controlSize(.small)
                                Text("Running")
                            } else if status?.succeeded == true {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.positive)
                                Text("Succeeded")
                            } else {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.critical)
                                Text("Failed")
                            }
                        }
                    }
                    if let exit = status?.exitStatus, status?.succeeded == false {
                        Text(exit)
                            .font(.subheadline)
                            .foregroundStyle(Palette.critical)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Node", value: node)
                    if let user = status?.user { LabeledContent("User", value: user) }
                    if let start = status?.start { LabeledContent("Started", value: Format.dateTime(start)) }
                    LabeledContent("Duration", value: Format.duration(status?.duration))
                }

                if let error {
                    Section { InlineErrorRow(message: error, retry: nil) }
                }

                Section {
                    if lines.isEmpty {
                        Text(isRunning ? "Waiting for output…" : "No output.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(lines) { line in
                        Text(line.t.isEmpty ? " " : line.t)
                            .font(.caption.monospaced())
                            .foregroundStyle(color(for: line.t))
                            .textSelection(.enabled)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
                            .id(line.n)
                    }
                } header: {
                    Text("Output")
                }
            }
            .proxynList()
            .onChange(of: lines.count) { _, _ in
                guard follow, let last = lines.last else { return }
                withAnimation(Motion.standard) { proxy.scrollTo(last.n, anchor: .bottom) }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Follow Output", isOn: $follow)
                    Button("Copy Output", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = lines.map(\.t).joined(separator: "\n")
                        app.toast(.success, "Output copied")
                    }
                    Button("Copy Task ID", systemImage: "number") {
                        UIPasteboard.general.string = upid
                    }
                    if isRunning {
                        Divider()
                        Button("Stop Task", systemImage: "stop.circle", role: .destructive) {
                            confirmStop = true
                        }
                    }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
            }
        }
        .task { await poll() }
        .confirmationDialog("Stop this task?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop Task", role: .destructive) {
                Task {
                    await app.perform("Stop task", node: node) { api in
                        try await api.stopTask(node: node, upid: upid)
                    }
                    await load()
                }
            }
        } message: {
            Text("Interrupting some operations can leave a guest in an intermediate state.")
        }
    }

    private func color(for line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("failed") { return Palette.critical }
        if lower.contains("warn") { return Palette.warning }
        return .primary
    }

    /// `.task` cancels this loop when the view disappears.
    private func poll() async {
        await load()
        while !Task.isCancelled, isRunning {
            try? await Task.sleep(for: .seconds(2))
            await load()
        }
    }

    private func load() async {
        guard let api = app.client() else { return }
        do {
            async let statusRequest = api.taskStatus(node: node, upid: upid)
            async let logRequest = api.taskLog(node: node, upid: upid, start: 0, limit: 5_000)
            status = try await statusRequest
            let fetched = (try? await logRequest) ?? lines
            if fetched.count != lines.count { lines = fetched }
            error = nil
        } catch let failure as ProxmoxError {
            if case .cancelled = failure { return }
            error = failure.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
    }
}
