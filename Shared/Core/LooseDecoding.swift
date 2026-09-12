import Foundation

/// Proxmox's API is generated from Perl and is gloriously inconsistent: the same
/// field can come back as `1`, `"1"`, `1.0` or `true` depending on the endpoint
/// and the PVE version. Every model in the app decodes through these helpers so
/// a stray type never blanks out a whole screen.
extension KeyedDecodingContainer {

    func looseInt(_ key: Key) -> Int? {
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return Int(v) }
        if let v = try? decodeIfPresent(String.self, forKey: key) {
            if let i = Int(v) { return i }
            if let d = Double(v) { return Int(d) }
        }
        if let v = try? decodeIfPresent(Bool.self, forKey: key) { return v ? 1 : 0 }
        return nil
    }

    func looseDouble(_ key: Key) -> Double? {
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return Double(v) }
        if let v = try? decodeIfPresent(String.self, forKey: key) { return Double(v) }
        if let v = try? decodeIfPresent(Bool.self, forKey: key) { return v ? 1 : 0 }
        return nil
    }

    func looseString(_ key: Key) -> String? {
        if let v = try? decodeIfPresent(String.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return String(v) }
        if let v = try? decodeIfPresent(Double.self, forKey: key) {
            return v == v.rounded() ? String(Int(v)) : String(v)
        }
        if let v = try? decodeIfPresent(Bool.self, forKey: key) { return v ? "1" : "0" }
        return nil
    }

    func looseBool(_ key: Key) -> Bool? {
        if let v = try? decodeIfPresent(Bool.self, forKey: key) { return v }
        if let v = looseInt(key) { return v != 0 }
        if let v = try? decodeIfPresent(String.self, forKey: key) {
            switch v.lowercased() {
            case "1", "true", "yes", "on": return true
            case "0", "false", "no", "off": return false
            default: return nil
            }
        }
        return nil
    }
}

/// Type-erased JSON, used for endpoints where we display raw values (guest
/// config, task parameters, cluster options…) without modelling every key.
enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    var displayString: String {
        switch self {
        case .string(let v): return v
        case .number(let v): return v == v.rounded() && abs(v) < 1e15 ? String(Int(v)) : String(format: "%g", v)
        case .bool(let v): return v ? "1" : "0"
        case .array(let v): return v.map(\.displayString).joined(separator: ", ")
        case .object(let v): return v.map { "\($0.key)=\($0.value.displayString)" }.sorted().joined(separator: ",")
        case .null: return "—"
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let v): return v
        case .string(let v): return Double(v)
        case .bool(let v): return v ? 1 : 0
        default: return nil
        }
    }

    var intValue: Int? { doubleValue.map(Int.init) }
}

/// Proxmox wraps every payload in `{"data": …}`.
struct PVEEnvelope<T: Decodable>: Decodable {
    let data: T
}
