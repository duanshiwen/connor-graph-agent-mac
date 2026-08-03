import Foundation

public struct ForwardedChatItem: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var senderName: String
    public var senderAvatar: String
    public var createdAt: Int64
    public var kind: String
    public var text: String
    public var mediaUrl: String?
    public var thumbnailUrl: String?

    public init(id: String, senderName: String, senderAvatar: String = "", createdAt: Int64, kind: String = "text", text: String, mediaUrl: String? = nil, thumbnailUrl: String? = nil) {
        self.id = id
        self.senderName = senderName
        self.senderAvatar = senderAvatar
        self.createdAt = createdAt
        self.kind = kind
        self.text = text
        self.mediaUrl = mediaUrl
        self.thumbnailUrl = thumbnailUrl
    }

    public var previewText: String {
        switch kind.lowercased() {
        case "image": return "[图片]"
        case "video": return "[视频]"
        case "audio": return "[语音]"
        case "file": return text.isEmpty ? "[文件]" : text
        default: return String(text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).prefix(80))
        }
    }
}

public struct ForwardedChatBundle: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var sourceTitle: String
    public var caption: String
    public var items: [ForwardedChatItem]

    public init(id: String = UUID().uuidString, title: String, sourceTitle: String, caption: String = "", items: [ForwardedChatItem]) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
        self.caption = caption
        self.items = items
    }

    public var previewLines: [String] { items.prefix(4).map { "\($0.senderName)：\($0.previewText)" } }
}

public enum ForwardedChatBundleCodec {
    private static let prefix = "[[CONNOR_FORWARD_BUNDLE_V1:"
    private static let suffix = "]]"

    public static func encode(_ bundle: ForwardedChatBundle) throws -> String {
        guard !bundle.items.isEmpty else {
            throw EncodingError.invalidValue(bundle, .init(codingPath: [], debugDescription: "聊天记录不能为空"))
        }
        let data = try JSONEncoder().encode(bundle)
        let encoded = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        var lines = [prefix + encoded + suffix, "", "[聊天记录：\(bundle.title)]"]
        lines.append(contentsOf: bundle.previewLines)
        if bundle.items.count > 4 { lines.append("…共 \(bundle.items.count) 条") }
        if !bundle.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lines.append("留言：\(bundle.caption.trimmingCharacters(in: .whitespacesAndNewlines))") }
        return lines.joined(separator: "\n")
    }

    /// Keeps the card payload while exposing the full transcript to an LLM.
    public static func encodeForModel(_ bundle: ForwardedChatBundle) throws -> String {
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        timestampFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        var lines = [try encode(bundle), "", "--- 完整聊天记录（供模型阅读，时间为 UTC）---"]
        lines.append(contentsOf: bundle.items.map { item in
            let timestamp = timestampFormatter.string(
                from: Date(timeIntervalSince1970: Double(item.createdAt) / 1_000)
            )
            return "[\(timestamp)] \(item.senderName)：\(item.previewText)"
        })
        lines.append("--- 聊天记录结束 ---")
        if bundle.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("请结合以上聊天记录直接回应用户。")
        } else {
            lines.append("")
            lines.append("用户对这段记录的留言或要求：\(bundle.caption.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return lines.joined(separator: "\n")
    }

    public static func decode(_ content: String) -> ForwardedChatBundle? {
        guard let line = content.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init), line.hasPrefix(prefix), line.hasSuffix(suffix) else { return nil }
        var encoded = String(line.dropFirst(prefix.count).dropLast(suffix.count)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded), let bundle = try? JSONDecoder().decode(ForwardedChatBundle.self, from: data), !bundle.items.isEmpty else { return nil }
        return bundle
    }
}
