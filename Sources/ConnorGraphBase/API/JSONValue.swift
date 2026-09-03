import Foundation

/// 轻量 JSON 值模型（schema 默认值、记录字段值共用）。
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])

    public init?(json: Any) {
        switch json {
        case let v as NSNull:
            self = .null
        case let v as String:
            self = .string(v)
        case let v as NSNumber:
            if CFGetTypeID(v) == CFBooleanGetTypeID() {
                self = .bool(v.boolValue)
            } else {
                self = .number(v.doubleValue)
            }
        case let v as Bool:
            self = .bool(v)
        case let v as Double:
            self = .number(v)
        case let v as Int:
            self = .number(Double(v))
        case let v as [String: Any]:
            var dict: [String: JSONValue] = [:]
            for (k, val) in v {
                guard let jv = JSONValue(json: val) else { return nil }
                dict[k] = jv
            }
            self = .object(dict)
        case let v as [Any]:
            var arr: [JSONValue] = []
            for val in v {
                guard let jv = JSONValue(json: val) else { return nil }
                arr.append(jv)
            }
            self = .array(arr)
        default:
            return nil
        }
    }

    /// 还原为 Foundation 可序列化对象。
    public var jsonObject: Any {
        switch self {
        case .null:
            return NSNull()
        case .string(let s):
            return s
        case .number(let n):
            return n
        case .bool(let b):
            return b
        case .object(let dict):
            var out: [String: Any] = [:]
            for (k, v) in dict { out[k] = v.jsonObject }
            return out
        case .array(let arr):
            return arr.map { $0.jsonObject }
        }
    }
}
