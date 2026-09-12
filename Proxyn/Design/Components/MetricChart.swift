import SwiftUI
import Charts

/// Time-series chart.
///
/// Selection uses Swift Charts' own `chartXSelection`, which cooperates with
/// the enclosing scroll view — a custom drag gesture either steals vertical
/// scrolling or misses horizontal scrubs.
struct MetricChart: View {
    var series: [MetricSeries]
    var timeframe: PVETimeframe
    var height: CGFloat = 160
    /// Pin the Y domain to 0…1 for percentages.
    var normalized: Bool = false

    @State private var selectedDate: Date?

    private var hasData: Bool { series.contains { !$0.points.isEmpty } }

    private var yMax: Double {
        if normalized { return 1 }
        let peak = series.flatMap(\.points).map(\.value).max() ?? 0
        return peak > 0 ? peak * 1.15 : 1
    }

    private func nearest(in s: MetricSeries, to date: Date) -> MetricPoint? {
        s.points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            legend

            if hasData {
                chart
            } else {
                ContentUnavailableView {
                    Label("No Data", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("Proxmox hasn't recorded metrics for this range yet.")
                }
                .frame(height: height)
            }
        }
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { legendItems }
            VStack(alignment: .leading, spacing: 4) { legendItems }
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private var legendItems: some View {
        ForEach(series) { s in
            let value = selectedDate.flatMap { nearest(in: s, to: $0)?.value } ?? s.latest
            HStack(spacing: 6) {
                Circle().fill(Palette.series(s.colorToken)).frame(width: 7, height: 7)
                Text(s.label).foregroundStyle(.secondary)
                Text(s.unit.format(value))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .lineLimit(1)
        }
        if let selectedDate {
            Text(Format.clock(selectedDate))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(Array(series.enumerated()), id: \.element.id) { index, s in
                ForEach(s.points) { point in
                    if index == 0 {
                        AreaMark(x: .value("Time", point.date),
                                 y: .value(s.label, point.value),
                                 series: .value("Series", s.id))
                        .foregroundStyle(LinearGradient(
                            colors: [Palette.series(s.colorToken).opacity(0.2),
                                     Palette.series(s.colorToken).opacity(0)],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    }
                    LineMark(x: .value("Time", point.date),
                             y: .value(s.label, point.value),
                             series: .value("Series", s.id))
                    .foregroundStyle(Palette.series(s.colorToken))
                    .lineStyle(StrokeStyle(lineWidth: index == 0 ? 2 : 1.5, lineCap: .round))
                    .interpolationMethod(.monotone)
                }
            }

            if let selectedDate {
                RuleMark(x: .value("Selected", selectedDate))
                    .foregroundStyle(Color(uiColor: .separator))
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYScale(domain: 0...yMax)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self), let unit = series.first?.unit {
                        Text(unit.format(v))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Self.axisLabel(date, timeframe: timeframe))
                    }
                }
            }
        }
        .frame(height: height)
        .sensoryFeedback(.selection, trigger: selectedDate == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(series.map(\.label).joined(separator: " and "))
        .accessibilityValue(series.map { "\($0.label) \($0.unit.format($0.latest))" }
            .joined(separator: ", "))
    }

    // Formatters are expensive; axis labels are rendered on every frame.
    private static let hourFormat = Date.FormatStyle.dateTime.hour().minute().locale(AppLocale.current)
    private static let dayFormat = Date.FormatStyle.dateTime.weekday(.abbreviated).locale(AppLocale.current)
    private static let dateFormat = Date.FormatStyle.dateTime.month(.abbreviated).day().locale(AppLocale.current)
    private static let monthFormat = Date.FormatStyle.dateTime.month(.abbreviated).locale(AppLocale.current)

    static func axisLabel(_ date: Date, timeframe: PVETimeframe) -> String {
        switch timeframe {
        case .hour, .day: return date.formatted(hourFormat)
        case .week: return date.formatted(dayFormat)
        case .month: return date.formatted(dateFormat)
        case .year: return date.formatted(monthFormat)
        }
    }
}
