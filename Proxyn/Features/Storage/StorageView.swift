import SwiftUI

struct StorageView: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()

    private var storages: [PVEResource] {
        model.snapshot.uniqueStorages.sorted { $0.diskFraction > $1.diskFraction }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScreenScaffold(
                title: "Stockage",
                eyebrow: "\(Format.bytes(model.snapshot.storageUsed)) utilisés sur \(Format.bytes(model.snapshot.storageTotal))",
                statusColor: model.snapshot.aggregateStorage > 0.9 ? Palette.rose : Palette.mint,
                tint: Palette.violet,
                onRefresh: { await model.refresh() }
            ) {
                if storages.isEmpty {
                    EmptyStateView(symbol: "internaldrive",
                                   title: "Aucun stockage",
                                   message: "Aucun stockage n'est visible avec ce compte.")
                } else {
                    summaryCard.settleOnScroll()
                    VStack(spacing: Metrics.stackSpacing) {
                        ForEach(storages) { storage in
                            NavigationLink(value: Route.storage(node: storage.node ?? "",
                                                                storage: storage.storage ?? storage.displayName)) {
                                StorageCard(storage: storage)
                            }
                            .buttonStyle(.pressable)
                            .settleOnScroll()
                        }
                    }
                }
            }
            .proxynDestinations()
        }
    }

    private var summaryCard: some View {
        let used = model.snapshot.storageUsed
        let total = model.snapshot.storageTotal
        return GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Capacité utilisée")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Palette.inkTertiary)
                    MetricText(value: Format.bytesParts(used).value,
                               unit: Format.bytesParts(used).unit,
                               size: 40, weight: .medium)
                }

                MeterBar(fraction: model.snapshot.aggregateStorage, height: 4)

                Divider1px()

                HStack(spacing: 0) {
                    HeroStat(value: Format.bytes(total), label: "capacité")
                    HeroStat(value: Format.bytes(total - used), label: "libre",
                             tint: Palette.mint)
                    HeroStat(value: Format.percent(model.snapshot.aggregateStorage),
                             label: "occupé",
                             tint: Palette.load(model.snapshot.aggregateStorage) == Palette.rose
                                   ? Palette.rose : Palette.ink)
                    HeroStat(value: "\(storages.count)", label: "volumes",
                             tint: Palette.inkSecondary)
                }
            }
        }
    }
}

struct StorageCard: View {
    var storage: PVEResource

    private var contentTypes: [String] {
        (storage.content ?? "").split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
    }

    private func contentLabel(_ raw: String) -> String {
        switch raw {
        case "images": return "disques VM"
        case "rootdir": return "conteneurs"
        case "vztmpl": return "modèles LXC"
        case "iso": return "ISO"
        case "backup": return "sauvegardes"
        case "snippets": return "snippets"
        case "import": return "import"
        default: return raw
        }
    }

    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 7) {
                    Text(storage.displayName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if storage.shared { TagChip(text: "partagé") }
                    Spacer(minLength: 8)
                    Text("\(storage.pluginType ?? "—") · \(storage.node ?? "")")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.inkTertiary)
                        .lineLimit(1)
                }

                VitalRow(label: "Occupation",
                         value: Format.bytesParts(storage.disk).value,
                         unit: Format.bytesParts(storage.disk).unit,
                         fraction: storage.diskFraction,
                         leadingDetail: "sur \(Format.bytes(storage.maxdisk))",
                         trailingDetail: Format.percent(storage.diskFraction),
                         valueSize: 19)

                if !contentTypes.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(contentTypes, id: \.self) { type in
                            TagChip(text: contentLabel(type)).fixedSize()
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}
