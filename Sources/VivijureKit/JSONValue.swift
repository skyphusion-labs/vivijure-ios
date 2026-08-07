import Foundation

/// Flexible JSON tree for opaque storyboard / prefs / modules blobs from the CONTRACT.
public enum JSONValue: Codable, Sendable, Equatable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  public init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let b = try? c.decode(Bool.self) {
      self = .bool(b)
    } else if let i = try? c.decode(Int.self) {
      self = .number(Double(i))
    } else if let d = try? c.decode(Double.self) {
      self = .number(d)
    } else if let s = try? c.decode(String.self) {
      self = .string(s)
    } else if let a = try? c.decode([JSONValue].self) {
      self = .array(a)
    } else if let o = try? c.decode([String: JSONValue].self) {
      self = .object(o)
    } else {
      throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .null: try c.encodeNil()
    case .bool(let b): try c.encode(b)
    case .number(let d): try c.encode(d)
    case .string(let s): try c.encode(s)
    case .array(let a): try c.encode(a)
    case .object(let o): try c.encode(o)
    }
  }

  public var objectValue: [String: JSONValue]? {
    if case .object(let o) = self { return o }
    return nil
  }

  public var stringValue: String? {
    if case .string(let s) = self { return s }
    return nil
  }

  public var arrayValue: [JSONValue]? {
    if case .array(let a) = self { return a }
    return nil
  }

  public var doubleValue: Double? {
    if case .number(let d) = self { return d }
    if case .string(let s) = self { return Double(s) }
    return nil
  }

  public var boolValue: Bool? {
    if case .bool(let b) = self { return b }
    return nil
  }

  public var intValue: Int? {
    if let d = doubleValue { return Int(d) }
    return nil
  }

  /// Mutating helper: set a key on an object, or replace self with a new object.
  public mutating func setObjectKey(_ key: String, _ value: JSONValue?) {
    var o = objectValue ?? [:]
    if let value {
      o[key] = value
    } else {
      o.removeValue(forKey: key)
    }
    self = .object(o)
  }

  /// Pretty JSON for UI display.
  public func prettyJSON(sortedKeys: Bool = true) -> String {
    let any = toAny()
    guard JSONSerialization.isValidJSONObject(any) else { return String(describing: any) }
    let data = try? JSONSerialization.data(
      withJSONObject: any,
      options: sortedKeys ? [.prettyPrinted, .sortedKeys] : [.prettyPrinted]
    )
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
  }

  public func toAny() -> Any {
    switch self {
    case .null: return NSNull()
    case .bool(let b): return b
    case .number(let d): return d
    case .string(let s): return s
    case .array(let a): return a.map { $0.toAny() }
    case .object(let o): return o.mapValues { $0.toAny() }
    }
  }

  public static func from(_ any: Any) -> JSONValue {
    switch any {
    case is NSNull: return .null
    case let b as Bool: return .bool(b)
    case let i as Int: return .number(Double(i))
    case let d as Double: return .number(d)
    case let s as String: return .string(s)
    case let a as [Any]: return .array(a.map { from($0) })
    case let o as [String: Any]: return .object(o.mapValues { from($0) })
    default: return .string(String(describing: any))
    }
  }
}

extension JSONValue: CustomStringConvertible {
  public var description: String { prettyJSON() }
}
