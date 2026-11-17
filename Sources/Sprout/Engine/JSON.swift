import Foundation

/// A decoded JSON value. The Web API's sync endpoints send partial objects that are
/// merged field by field, so values stay loosely typed until a model reads them.
enum JSON: Sendable, Equatable, Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSON])
    case object([String: JSON])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSON].self))
        }
    }

    static func decode(_ data: Data) throws -> JSON {
        try JSONDecoder().decode(JSON.self, from: data)
    }

    subscript(key: String) -> JSON? {
        if case .object(let object) = self { object[key] } else { nil }
    }

    var object: [String: JSON]? {
        if case .object(let value) = self { value } else { nil }
    }

    var array: [JSON]? {
        if case .array(let value) = self { value } else { nil }
    }

    var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    var double: Double? {
        switch self {
        case .number(let value): value
        case .bool(let value): value ? 1 : 0
        default: nil
        }
    }

    var int: Int64? { double.map { Int64($0) } }

    /// The value as JSONSerialization expects it, for writing.
    var foundationValue: Any {
        switch self {
        case .string(let value): value
        case .number(let value): value
        case .bool(let value): value
        case .array(let value): value.map(\.foundationValue)
        case .object(let value): value.mapValues(\.foundationValue)
        case .null: NSNull()
        }
    }

    var bool: Bool? {
        switch self {
        case .bool(let value): value
        case .number(let value): value != 0
        default: nil
        }
    }
}

extension Dictionary where Key == String, Value == JSON {
    func string(_ key: String) -> String { self[key]?.string ?? "" }
    func double(_ key: String) -> Double { self[key]?.double ?? 0 }
    func int(_ key: String) -> Int64 { self[key]?.int ?? 0 }
}
