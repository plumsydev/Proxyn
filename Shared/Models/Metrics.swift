import Foundation

/// One RRD row. Proxmox returns a different key set per endpoint, so we keep the
/// raw bag and expose typed accessors.
struct PVEMetricSample: Identifiable, Sendable, Hashable, Decodable {
    var time: Date
    var values: [String: Double]
    var id: Date { time }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let dict = (try? c.decode([String: JSONValue].self)) ?? [:]
        time = Date(timeIntervalSince1970: dict["time"]?.doubleValue ?? 0)
        var bag: [String: Double] = [:]
        for (k, v) in dict where k != "time" {
            if let d = v.doubleValue { bag[k] = d }
        }
        values = bag
    }

    init(time: Date, values: [String: Double]) {
        self.time = time
        self.values = values
    }

    subscript(_ key: String) -> Double? { values[key] }
}

enum PVETimeframe: String, CaseIterable, Identifiable, Sendable {
    case hour, day, week, month, year
    var id: String { rawValue }

    var label: String {
        switch self {
        case .hour: return "1H"
        case .day: return "1D"
        case .week: return "1W"
        case .month: return "1M"
        case .year: return "1Y"
        }
    }

    var accessibilityName: String {
        switch self {
        case .hour: return "Past hour"
        case .day: return "Past day"
        case .week: return "Past week"
        case .month: return "Past month"
        case .year: return "Past year"
        }
    }

    var axisStride: Calendar.Component {
        switch self {
        case .hour: return .minute
        case .day: return .hour
        case .week, .month: return .day
        case .year: return .month
        }
    }
}

/// A named series ready to be handed to Swift Charts.
struct MetricSeries: Identifiable, Sendable, Hashable {
    var id: String
    var label: String
    var points: [MetricPoint]
    var unit: MetricUnit
    var colorToken: String

    var latest: Double { points.last?.value ?? 0 }
    var peak: Double { points.map(\.value).max() ?? 0 }
    var average: Double {
        guard !points.isEmpty else { return 0 }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }
}

struct MetricPoint: Identifiable, Sendable, Hashable {
    var date: Date
    var value: Double
    var id: Date { date }
}

enum MetricUnit: Sendable, Hashable {
    case percent          // 0…1
    case bytes
    case bytesPerSecond
    case iops
    case raw

    func format(_ value: Double) -> String {
        switch self {
        case .percent: return Format.percent(value)
        case .bytes: return Format.bytes(value)
        case .bytesPerSecond: return Format.rate(value)
        case .iops: return Format.compactNumber(value) + " IO/s"
        case .raw: return Format.compactNumber(value)
        }
    }
}

extension Array where Element == PVEMetricSample {
    /// Builds a chart series from an RRD key, optionally normalised by another key.
    func series(_ key: String, label: String, unit: MetricUnit, color: String,
                dividedBy divisor: String? = nil, scale: Double = 1) -> MetricSeries {
        let pts: [MetricPoint] = compactMap { sample in
            guard let raw = sample[key] else { return nil }
            var v = raw * scale
            if let divisor, let d = sample[divisor], d > 0 { v = raw / d }
            guard v.isFinite else { return nil }
            return MetricPoint(date: sample.time, value: v)
        }
        return MetricSeries(id: key, label: label, points: pts, unit: unit, colorToken: color)
    }
}
