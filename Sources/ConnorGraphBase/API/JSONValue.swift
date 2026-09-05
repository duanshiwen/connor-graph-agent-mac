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

    /// 数值提取（assert 数值比较用）：number 直取；bool 转 0/1；数字字符串按 Double 解析。
    public var numberValue: Double? {
        switch self {
        case .number(let n):
            return n
        case .bool(let b):
            return b ? 1 : 0
        case .string(let s):
            return Double(s)
        default:
            return nil
        }
    }
}

// MARK: - Codable（任意 JSON：null/bool/number/string/array/object 单值解码；
// 合成实现按 case 包装格式编解码，不适用于普通 JSON，故自实现。）

extension JSONValue {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                DecodingError.Context(codingPath: decoder.codingPath,
                                      debugDescription: "无法解码 JSONValue")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .string(let s):
            try container.encode(s)
        case .number(let n):
            try container.encode(n)
        case .bool(let b):
            try container.encode(b)
        case .object(let dict):
            try container.encode(dict)
        case .array(let arr):
            try container.encode(arr)
        }
    }
}
