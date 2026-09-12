import SwiftUI

struct ActivityView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ActivityListContent()
                .proxynDestinations()
                .handlesDeepLinks(for: .activity, path: $path)
        }
    }
}

/// Cluster task history grouped by day.
struct ActivityListContent: View {
    @Environment(AppModel.self) private var model
    @State private var filter: Filter = .all
    @State private var query = ""

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", running = "Running", failed = "Failed"
        var id: String { rawValue }
    }

    private var tasks: [PVETask] {
        let base: [PVETask]
        switch filter {
        case .all: base = model.snapshot.tasks
        case .running: base = model.snapshot.runningTasks
        case .failed: base = model.snapshot.failedTasks
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return base }
        return base.filter {
            Format.taskType($0.type).localizedCaseInsensitiveContains(q)
                || ($0.pveTargetId ?? "").localizedCaseInsensitiveContains(q)
                || ($0.node ?? "").localizedCaseInsensitiveContains(q)
                || ($0.user ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    private var days: [(title: String, tasks: [PVETask])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: tasks) { task in
            calendar.startOfDay(for: task.start ?? .distantPast)
        }
        return grouped.keys.sorted(by: >).map { day in
            (Format.dayHeading(day == .distantPast ? nil : day),
             grouped[day, default: []].sorted { ($0.startTime ?? 0) > ($1.startTime ?? 0) })
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if tasks.isEmpty {
                emptyState
            } else {
                ForEach(days, id: \.title) { day in
                    Section(day.title) {
                        ForEach(day.tasks) { task in
                            NavigationLink(value: Route.task(node: task.node ?? "", upid: task.upid,
                                                             title: Format.taskType(task.type))) {
                                TaskRow(task: task)
                            }
                        }
                    }
                }
            }
        }
        .proxynList()
        .navigationTitle("Activity")
        .searchable(text: $query, prompt: "Task, guest, node or user")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.schedules) {
                    Label("Schedules", systemImage: "calendar.badge.clock")
                }
            }
        }
        .refreshable { await model.refresh() }
        .animation(Motion.standard, value: filter)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !query.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            switch filter {
            case .failed:
                ContentUnavailableView("No Failures", systemImage: "checkmark.circle",
                                       description: Text("Every recent task completed successfully."))
            case .running:
                ContentUnavailableView("Nothing Running", systemImage: "moon.zzz",
                                       description: Text("No tasks are in progress."))
            case .all:
                ContentUnavailableView("No Activity", systemImage: "list.bullet.rectangle",
                                       description: Text("The cluster task log is empty."))
            }
        }
    }
}

/// Datacenter backup jobs and replication.
struct SchedulesView: View {
    @Environment(AppModel.self) private var model
    @State private var backupJobs: [PVEBackupJob] = []
    @State private var replication: [PVEReplicationJob] = []
    @State private var loading = true

    var body: some View {
        List {
            Section("Backup Jobs") {
                if loading && backupJobs.isEmpty {
                    ProgressView()
                } else if backupJobs.isEmpty {
                    Text("No backup jobs are configured.")
                        .foregroundStyle(.secondary)
                }
                ForEach(backupJobs) { job in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(job.comment.flatMap { $0.isEmpty ? nil : $0 } ?? "Backup job")
                                .font(.body.weight(.medium))
                            Spacer()
                            if !job.enabled {
                                Text("Disabled")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text([job.schedule, job.storage, job.all ? "all guests" : job.vmid.map { "guests \($0)" }]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let next = job.nextRun, job.enabled {
                            Text("Next run \(Format.dateTime(next))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if !replication.isEmpty {
                Section("Replication") {
                    ForEach(replication) { job in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Guest \(job.guest.map(String.init) ?? "—") → \(job.target ?? "—")")
                                .font(.body.weight(.medium))
                            Text([job.schedule.map { "every \($0)" },
                                  job.lastSync.map { "last sync \(Format.ago(Date(timeIntervalSince1970: $0)))" },
                                  job.disabled ? "disabled" : nil]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let error = job.error, !error.isEmpty {
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.critical)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .proxynList()
        .navigationTitle("Schedules")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        guard let api = model.client() else { return }
        defer { loading = false }
        async let jobs = api.backupJobs()
        async let replicationJobs = api.replicationJobs()
        backupJobs = (try? await jobs) ?? []
        replication = (try? await replicationJobs) ?? []
    }
}
