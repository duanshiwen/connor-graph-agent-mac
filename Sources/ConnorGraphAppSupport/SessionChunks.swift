import Foundation
import CryptoKit

/// Version 1 transport shared by all four clients. Parts never become visible sessions.
enum SessionChunks {
    static let inlineBytes = 512 * 1024
    static let partBytes = 256 * 1024
    static let maxParts = 512
    static let manifestKey = "_connorSessionChunks"
    static let partKey = "_connorSessionChunk"
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func partID(_ id: String, _ hash: String, _ index: Int) -> String {
        "csp_" + String(digest(Data("\(id)\0\(hash)\0\(index)".utf8)).prefix(48))
    }
    static func project(id: String, payload: ConnorJSONValue, mail: Bool = false) throws -> [String: ConnorJSONValue] {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let normalized = try (mail ? payload : normalize(payload))
        let bytes = try encoder.encode(normalized)
        if bytes.count <= inlineBytes { return [id: normalized] }
        let count = (bytes.count + partBytes - 1) / partBytes
        guard count <= maxParts else { return [id: normalized] }
        let hash = digest(bytes)
        var records: [String: ConnorJSONValue] = [:]
        var ids: [ConnorJSONValue] = []
        for index in 0..<count {
            let key = partID(id, hash, index)
            ids.append(.string(key))
            let data = bytes.subdata(in: (index * partBytes)..<min(bytes.count, (index + 1) * partBytes))
            records[key] = .object([partKey: .object([
                "v": .number(1), "sessionId": .string(id), "sha256": .string(hash),
                "index": .number(Double(index)), "data": .string(data.base64EncodedString())
            ])])
        }
        records[id] = .object(["id": .string(id), manifestKey: .object([
            "v": .number(1), "semanticVersion": .number(2), "sha256": .string(hash), "semanticHash": .string(try mail ? SharedMailStore.semanticHash(normalized) : semanticHash(normalized)), "byteLength": .number(Double(bytes.count)), "parts": .array(ids)
        ])])
        return records
    }
    enum Failure: Error { case invalid, incomplete }
    static func normalize(_ payload: ConnorJSONValue) throws -> ConnorJSONValue {
        guard case .object(let root) = payload, case .array(let rawMessages) = root["messages"] else { throw Failure.invalid }
        let messages: [[String: ConnorJSONValue]] = rawMessages.compactMap { value in
            guard case .object(let message) = value, message["role"] == .string("user") || message["role"] == .string("assistant") else { return nil }
            return message
        }.sorted { a, b in
            guard case .number(let x) = a["createdAt"], case .number(let y) = b["createdAt"] else { return false }
            if x != y { return x < y }
            guard case .string(let xID) = a["id"], case .string(let yID) = b["id"] else { return false }
            return xID < yID
        }
        let labels: [String]
        if case .array(let values) = root["labels"] { labels = values.compactMap { if case .string(let s) = $0 { return s }; return nil } } else { labels = [] }
        var canonical = root.filter { ["id", "title", "createdAt", "updatedAt", "archived", "kind"].contains($0.key) }
        canonical["kind"] = root["kind"] ?? .string("chat"); canonical["archived"] = root["archived"] ?? .bool(false)
        canonical["labels"] = .array(Set(labels).sorted().map(ConnorJSONValue.string))
        canonical["messages"] = .array(messages.map { message in
            var result = message.filter { ["id", "content", "createdAt", "role"].contains($0.key) }; result["status"] = .string("complete"); return .object(result)
        })
        return .object(canonical)
    }
    static func resolve(id: String, payload: ConnorJSONValue, parts: inout [String: ConnorJSONValue], mail: Bool = false) throws -> ConnorJSONValue? {
        guard case .object(let root) = payload else { throw Failure.invalid }
        if case .object(let part) = root[partKey] {
            guard part["v"] == .number(1), case .string(let parent) = part["sessionId"],
                  case .string(let hash) = part["sha256"], case .number(let raw) = part["index"],
                  raw >= 0, raw < Double(maxParts), raw.rounded() == raw,
                  case .string(let encoded) = part["data"], let data = Data(base64Encoded: encoded),
                  data.count <= partBytes, partID(parent, hash, Int(raw)) == id else { throw Failure.invalid }
            parts[id] = payload
            return nil
        }
        guard case .object(let manifest) = root[manifestKey] else { return payload }
        guard manifest["v"] == .number(1), root["id"] == .string(id),
              case .array(let ids) = manifest["parts"], !ids.isEmpty, ids.count <= maxParts,
              case .string(let hash) = manifest["sha256"], case .number(let rawLength) = manifest["byteLength"],
              rawLength >= 0, rawLength <= Double(maxParts * partBytes), rawLength.rounded() == rawLength else { throw Failure.invalid }
        var bytes = Data()
        for (index, value) in ids.enumerated() {
            let key = partID(id, hash, index)
            guard value == .string(key) else { throw Failure.invalid }
            guard case .object(let stored) = parts[key], case .object(let part) = stored[partKey] else { throw Failure.incomplete }
            guard part["sessionId"] == .string(id), part["sha256"] == .string(hash), part["index"] == .number(Double(index)),
                  case .string(let encoded) = part["data"], let data = Data(base64Encoded: encoded), data.count <= partBytes else { throw Failure.invalid }
            bytes.append(data)
            guard bytes.count <= Int(rawLength) else { throw Failure.invalid }
        }
        guard bytes.count == Int(rawLength), digest(bytes) == hash else { throw Failure.invalid }
        let session = try JSONDecoder().decode(ConnorJSONValue.self, from: bytes)
        guard case .object(let object) = session, object["id"] == .string(id) else { throw Failure.invalid }
        guard (!mail && manifest["semanticVersion"] != .number(2)) || manifest["semanticHash"] == .string(try mail ? SharedMailStore.semanticHash(session) : semanticHash(session)) else { throw Failure.invalid }
        return try mail ? session : normalize(session)
    }
    static func tag(_ payload: ConnorJSONValue) -> String? {
        guard case .object(let root) = payload, case .object(let manifest) = root[manifestKey], case .string(let tag) = manifest["semanticHash"] else { return nil }; return tag
    }
    static func parent(_ payload: ConnorJSONValue) -> String? {
        guard case .object(let root) = payload, case .object(let part) = root[partKey], case .string(let parent) = part["sessionId"] else { return nil }; return parent
    }
    static func semanticHash(_ payload: ConnorJSONValue) throws -> String {
        guard case .object(var root) = try normalize(payload), case .array(let messages) = root["messages"] else { throw Failure.invalid }
        func seconds(_ value: ConnorJSONValue?) throws -> ConnorJSONValue {
            guard case .number(let n) = value, n >= Double(Int64.min), n < Double(Int64.max) else { throw Failure.invalid }
            return .number(floor(n / 1000) * 1000)
        }
        root["createdAt"] = try seconds(root["createdAt"]); root["updatedAt"] = try seconds(root["updatedAt"])
        root["messages"] = .array(try messages.map { value in guard case .object(var message) = value else { throw Failure.invalid }; message["createdAt"] = try seconds(message["createdAt"]); return .object(message) })
        guard case .object(let canonical) = try normalize(.object(root)), case .array(let labels) = canonical["labels"], case .array(let items) = canonical["messages"] else { throw Failure.invalid }
        var buffer = Data()
        func add(_ string: String) { let bytes=Data(string.utf8); let length=UInt32(bytes.count).bigEndian; Swift.withUnsafeBytes(of:length) { buffer.append(contentsOf:$0) }; buffer.append(bytes) }
        func text(_ value: ConnorJSONValue?) throws -> String {
            guard let value else { throw Failure.invalid }
            switch value {
            case .string(let s): return s
            case .number(let n) where n >= Double(Int64.min) && n < Double(Int64.max): return String(Int64(n))
            default: throw Failure.invalid
            }
        }
        for key in ["id","title","createdAt","updatedAt","kind"] { add(try text(canonical[key])) }
        add(canonical["archived"] == .bool(true) ? "1" : "0")
        add(String(labels.count)); for label in labels { add(try text(label)) }
        add(String(items.count)); for item in items { guard case .object(let message) = item else { throw Failure.invalid }; for key in ["id","role","content","createdAt"] { add(try text(message[key])) } }
        return digest(buffer)
    }

}
