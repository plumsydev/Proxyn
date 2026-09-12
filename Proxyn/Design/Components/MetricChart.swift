import SwiftUI
import Charts

/// The app's chart.
///
/// One protagonist series in the accent, the rest stepping down in saturation;
/// horizontal grid only; no domain lines; a drag-to-scrub readout that snaps to
/// the nearest sample and reports into the legend rather than into a floating
/// bubble that covers the data.
struct MetricChart: View {
    var series: [MetricSeries]
    var timeframe: PVETimeframe
    var height: CGFloat = 150
    var showsLegend: Bool = true
    var stacked: Bool = false
    /// Pin the Y domain to 0…1 for percentages.
    var normalized: Bool = false

    @State private var scrubDate: Date?

    private var allPoints: [MetricPoint] { series.flatMap(\.points) }

    private var yMax: Double {
        if normalized { return 1 }
        let peak = allPoints.map(\.value).max() ?? 1
        return peak <= 0 ? 1 : peak * 1.15
    }

    private var scrubbed: [(MetricSeries, MetricPoint)] {
        guard let scrubDate else { return [] }
        return series.compactMap { s in
            guard let nearest = s.points.min(by: {
                abs($0.date.timeIntervalSince(scrubDate)) < abs($1.date.timeIntervalSince(scrubDate))
            }) else { return nil }
            return (s, nearest)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsLegend { legend }

            if allPoints.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.025))
                    Text("Aucune donnée RRD")
                        .font(.caption)
                        .foregroundStyle(Palette.inkTertiary)
                }
                .frame(height: height)
            } else {
                chart
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            ForEach(series) { s in
                let scrubValue = scrubbed.first(where: { $0.0.id == s.id })?.1.value
                HStack(spacing: 6) {
                    Capsule()
                        .fill(Palette.token(s.colorToken))
                        .frame(width: 10, height: 2)
                    Text(s.label)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.inkTertiary)
                    Text(s.unit.format(scrubValue ?? s.latest))
                        .font(.metric(12.5))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                }
            }
            Spacer(minLength: 0)
            Text(scrubDate.map(Format.clock) ?? " ")
                .font(.metric(12))
                .foregroundStyle(Palette.ember)
                .opacity(scrubDate == nil ? 0 : 1)
        }
        .animation(Motion.fade, value: scrubDate)
    }

    private var chart: some View {
        Chart {
            ForEach(Array(series.enumerated()), id: \.element.id) { index, s in
                // Only the lead series gets a fill; two overlapping washes read
                // as mud.
                if index == 0 {
                    ForEach(s.points) { point in
                        AreaMark(
                            x: .value("Heure", point.date),
                            y: .value(s.label, point.value),
                            series: .value("Série", s.id),
                            stacking: stacked ? .standard : .unstacked
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Palette.token(s.colorToken).opacity(0.16),
                                         Palette.token(s.colorToken).opacity(0.0)],
                                startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                        .accessibilityHidden(true)
                    }
                }

                ForEach(s.points) { point in
                    LineMark(
                        x: .value("Heure", point.date),
                        y: .value(s.label, point.value),
                        series: .value("Série", s.id)
                    )
                    .foregroundStyle(Palette.token(s.colorToken))
                    .lineStyle(StrokeStyle(lineWidth: index == 0 ? 1.8 : 1.3,
                                           lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }
                .accessibilityLabel(s.label)
            }

            if let scrubDate {
                RuleMark(x: .value("Curseur", scrubDate))
                    .foregroundStyle(Palette.ink.opacity(0.22))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(Array(scrubbed.enumerated()), id: \.offset) { _, pair in
                    PointMark(x: .value("Heure", pair.1.date),
                              y: .value(pair.0.label, pair.1.value))
                    .foregroundStyle(Palette.token(pair.0.colorToken))
                    .symbolSize(34)
                }
            }
        }
        .chartYScale(domain: 0...yMax)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.045))
                AxisValueLabel {
                    if let v = value.as(Double.self), let unit = series.first?.unit {
                        Text(unit.format(v))
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.inkTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(xLabel(date))
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.inkTertiary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    // Simultaneous and horizontal-only: an exclusive gesture
                    // would swallow the enclosing ScrollView's vertical pan.
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { drag in
                                guard abs(drag.translation.width) > abs(drag.translation.height) * 1.2
                                else { return }
                                guard let plotFrame = proxy.plotFrame else { return }
                                let origin = geo[plotFrame].origin
                                let x = drag.location.x - origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    if scrubDate == nil { Haptics.tap() }
                                    scrubDate = date
                                }
                            }
                            .onEnded { _ in
                                withAnimation(Motion.fade) { scrubDate = nil }
                            }
                    )
            }
        }
        .frame(height: height)
        .animation(Motion.glide, value: series.map(\.latest))
    }

    private func xLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        switch timeframe {
        case .hour, .day: f.dateFormat = "HH:mm"
        case .week: f.dateFormat = "E"
        case .month: f.dateFormat = "d MMM"
        case .year: f.dateFormat = "MMM"
        }
        return f.string(from: date)
    }
}

/// Chart in a card, with its title.
struct ChartCard: View {
    var title: String
    var series: [MetricSeries]
    var timeframe: PVETimeframe
    var normalized: Bool = false
    var height: CGFloat = 148

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(title)
                MetricChart(series: series, timeframe: timeframe, height: height,
                            normalized: normalized)
            }
        }
    }
}
