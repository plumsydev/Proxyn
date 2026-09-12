import SwiftUI

struct ActivityView: View {
    @Environment(AppModel.self) private var model
    var embedded: Bool = false

    @State private var path = NavigationPath()
    @State private var filter: TaskFilter = .all
    @State private var backupJobs: [PVEBackupJob] = []
    @State private var replication: [PVEReplicationJob] = []

    enum TaskFilter: Int, CaseIterable, Identifiable, Hashable {
        case all, running, failed, jobs
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .all: return "Tout"
            case .running: return "En cours"
            case .failed: return "Échecs"
            case .jobs: return "Planifié"
            }
        }
    }

    private var tasks: [PVETask] {
        switch filter {
        case .all: return model.snapshot.tasks
        case .running: return model.snapshot.runningTasks
        case .failed: return model.snapshot.failedTasks
        case .jobs: return []
        }
    }

    private var grouped: [(day: String, tasks: [PVETask])] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        let calendar = Calendar.current

        return Dictionary(grouping: tasks) { task -> String in
            guard let date = task.start else { return "—" }
            if calendar.isDateInToday(date) { return "Aujourd'hui" }
            if calendar.isDateInYesterday(date) { return "Hier" }
            return formatter.string(from: date).capitalized
        }
        .map { (day: $0.key, tasks: $0.value.sorted { ($0.startTime ?? 0) > ($1.startTime ?? 0) }) }
        .sorted { ($0.tasks.first?.startTime ?? 0) > ($1.tasks.first?.startTime ?? 0) }
    }

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                NavigationStack(path: $path) { content.proxynDestinations() }
            }
        }
        .task { await loadJobs() }
    }

    private var content: some View {
        ScreenScaffold(
            title: "Activité",
            eyebrow: model.snapshot.runningTasks.isEmpty
            ? "\(model.snapshot.tasks.count) tâches récentes"
            : "\(model.snapshot.runningTasks.count) en cours",
            statusColor: model.snapshot.failedTasks.isEmpty ? Palette.mint : Palette.rose,
            statusPulsing: !model.snapshot.runningTasks.isEmpty,
            tint: Palette.mint,
            onRefresh: { await model.refresh(); await loadJobs() }
        ) {
            SegmentedRail(items: TaskFilter.allCases, label: \.title, selection: $filter)

            if filter == .jobs {
                scheduledSection
            } else if tasks.isEmpty {
                EmptyStateView(symbol: "checkmark.seal",
                               title: filter == .failed ? "Aucun échec" : "Rien en cours",
                               message: filter == .failed
                               ? "Toutes les tâches récentes se sont terminées correctement."
                               : "Le cluster est au repos.")
            } else {
                ForEach(grouped, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(group.day, trailing: "\(group.tasks.count)")
                        GlassCard(padding: 0) {
                            RowStack(data: group.tasks, separatorInset: Metrics.rowInset + 26) { task in
                                NavigationLink(value: Route.task(node: task.node ?? "",
                                                                 upid: task.upid,
                                                                 title: Format.taskType(task.type))) {
                                    TaskRow(task: task)
                                        .padding(.horizontal, Metrics.rowInset)
                                }
                                .buttonStyle(.pressable)
                            }
                        }
                        .settleOnScroll()
                    }
                }
            }
        }
    }

    private var scheduledSection: some View {
        VStack(alignment: .leading, spacing: Metrics.stackSpacing) {
            VStack(alignment: .leading, spacing: 9) {
                SectionLabel("Sauvegardes planifiées", trailing: "\(backupJobs.count)")
                if backupJobs.isEmpty {
                    GlassCard {
                        Text("Aucun job de sauvegarde configuré au niveau du datacenter.")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.inkTertiary)
                    }
                } else {
                    ForEach(backupJobs) { job in BackupJobCard(job: job) }
                }
            }

            if !replication.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    SectionLabel("Réplication", trailing: "\(replication.count)")
                    ForEach(replication) { job in ReplicationCard(job: job) }
                }
            }
        }
    }

    private func loadJobs() async {
        guard let api = model.client() else { return }
        backupJobs = (try? await api.backupJobs()) ?? []
        replication = (try? await api.replicationJobs()) ?? []
    }
}

struct BackupJobCard: View {
    var job: PVEBackupJob

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    StatusPip(color: job.enabled ? Palette.mint : Palette.inkTertiary,
                              size: 6, hollow: !job.enabled)
                    Text(job.comment?.isEmpty == false ? job.comment! : "Sauvegarde planifiée")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    TagChip(text: job.mode ?? "snapshot")
                }
                .padding(.bottom, 8)

                DetailRow(label: "Planification", value: job.schedule ?? "—", monospaced: true)
                DetailRow(label: "Stockage", value: job.storage ?? "—")
                DetailRow(label: "Portée", value: job.all ? "toutes les instances" : (job.vmid ?? "—"))
                if let next = job.nextRun {
                    DetailRow(label: "Prochaine exécution", value: Format.dateTime(next),
                              valueColor: Palette.mint)
                }
            }
        }
    }
}

struct ReplicationCard: View {
    var job: PVEReplicationJob

    var body: some View {
        GlassCard(tint: job.error == nil ? nil : Palette.rose) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("\(job.guest.map(String.init) ?? "—") → \(job.target ?? "—")")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    if job.disabled { TagChip(text: "désactivé") }
                }
                .padding(.bottom, 8)

                DetailRow(label: "Planification", value: job.schedule ?? "—", monospaced: true)
                if let last = job.lastSync {
                    DetailRow(label: "Dernière synchronisation",
                              value: Format.ago(Date(timeIntervalSince1970: last)))
                }
                if let error = job.error, !error.isEmpty {
                    Text(error)
                        .font(.mono(12))
                        .foregroundStyle(Palette.rose)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
        }
    }
}
