import Foundation
import CryptoKit
import ConnorGraphCore

/// 旧版 Evernote / 印象笔记 `.enex` 导入适配器。
public struct ENEXNoteImportAdapter: NoteImportSourceAdapter {
    public let sourceKind: NoteImportSourceKind = .evernoteENEX
    public init() {}
    public func scan(_ request: NoteImportScanRequest) -> AsyncThrowingStream<ImportedNote, Error> {
        EnexStyleXMLNoteScanner(sourceKind: .evernoteENEX).scan(request)
    }
}

/// 新版印象笔记 `.notes`（印象笔记XML格式）导入适配器。
/// `.notes` 与 `.enex` 共享同一套 `en-export > note` XML 骨架，正文均为 ENML。
public struct NotesNoteImportAdapter: NoteImportSourceAdapter {
    public let sourceKind: NoteImportSourceKind = .yinxiangNotes
    public init() {}
    public func scan(_ request: NoteImportScanRequest) -> AsyncThrowingStream<ImportedNote, Error> {
        EnexStyleXMLNoteScanner(sourceKind: .yinxiangNotes).scan(request)
    }
}

/// 流式解析 `.enex` / `.notes` 的公共 XML 骨架：`en-export > note`，资源按 base64 解码为临时文件，
/// 正文 ENML 交给 `ENMLMarkdownConverter` 完整转换为 Markdown。
internal struct EnexStyleXMLNoteScanner: Sendable {
    let sourceKind: NoteImportSourceKind

    func scan(_ request: NoteImportScanRequest) -> AsyncThrowingStream<ImportedNote, Error> {
        AsyncThrowingStream { continuation in
            Task.detached(priority: .utility) {
                let delegate = EnexStyleXMLStreamDelegate(
                    sourceURL: request.sourceURL,
                    sourceKind: sourceKind,
                    continuation: continuation
                )
                guard let parser = XMLParser(contentsOf: request.sourceURL) else {
                    continuation.finish(throwing: NoteImportErrorCode.parseFailed)
                    return
                }
                parser.delegate = delegate
                parser.shouldResolveExternalEntities = false
                if !parser.parse() {
                    continuation.finish(throwing: parser.parserError ?? NoteImportErrorCode.parseFailed)
                } else {
                    continuation.finish()
                }
            }
        }
    }
}

private final class EnexStyleXMLStreamDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {
    let sourceURL: URL
    let sourceKind: NoteImportSourceKind
    let continuation: AsyncThrowingStream<ImportedNote, Error>.Continuation
    var note: EnexNoteBuilder?
    var element = ""
    var buffer = ""
    var resource: EnexResourceBuilder?

    init(sourceURL: URL, sourceKind: NoteImportSourceKind, continuation: AsyncThrowingStream<ImportedNote, Error>.Continuation) {
        self.sourceURL = sourceURL
        self.sourceKind = sourceKind
        self.continuation = continuation
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        element = elementName
        buffer = ""
        if elementName == "note" {
            note = EnexNoteBuilder()
        }
        if elementName == "content" {
            // 新版印象笔记（9.5.10+）导出的 .notes 正文可能是 encoding="base64:aes" 的加密密文。
            note?.contentEncoding = attributeDict["encoding"] ?? ""
        }
        if elementName == "resource" {
            resource = EnexResourceBuilder()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if var resource {
            switch elementName {
            case "data":
                resource.base64 = value
            case "mime":
                resource.mime = value
            case "file-name":
                resource.filename = value
            case "resource":
                do {
                    let built = try resource.build()
                    note?.resources[built.hash] = built
                } catch {
                    note?.diagnostics.append(NoteImportDiagnostic(
                        code: .attachmentMissing,
                        severity: .warning,
                        message: "附件解码失败，已跳过该资源（\(resource.filename.isEmpty ? "未知文件" : resource.filename)）"
                    ))
                }
                self.resource = nil
            default:
                break
            }
            if self.resource != nil {
                self.resource = resource
            }
        } else if var note {
            switch elementName {
            case "title":
                note.title = value
            case "content":
                note.content = buffer
            case "created":
                note.created = value
            case "updated":
                note.updated = value
            case "tag":
                if !value.isEmpty { note.tags.append(value) }
            case "guid":
                note.guid = value
            case "note":
                if let built = try? note.build(sourceURL: sourceURL, sourceKind: sourceKind) {
                    continuation.yield(built)
                }
                self.note = nil
            default:
                break
            }
            if self.note != nil {
                self.note = note
            }
        }
        buffer = ""
    }
}

private struct EnexResourceBuilder {
    var base64 = ""
    var mime = "application/octet-stream"
    var filename = ""

    func build() throws -> EnexResource {
        guard let data = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]) else {
            throw NoteImportErrorCode.parseFailed
        }
        let hash = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let fileName = EnexResourceBuilder.fileName(for: hash, mime: mime, preferred: filename)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-enex-resources", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(hash + "-" + AppSessionAttachmentStore.sanitizedFilename(fileName))
        try data.write(to: url, options: .atomic)
        return EnexResource(hash: hash, mime: mime, filename: fileName, url: url, bytes: Int64(data.count))
    }

    static func fileName(for hash: String, mime: String, preferred: String) -> String {
        let trimmed = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let mimeType = mime.split(separator: "/", maxSplits: 1).map(String.init)
        guard mimeType.count == 2 else { return "attachment.bin" }
        let ext = mimeType[1].lowercased()
        switch ext {
        case "jpeg": return hash + ".jpg"
        case "plain": return hash + ".txt"
        case "quicktime": return hash + ".mov"
        case "octet-stream": return hash + ".bin"
        default:
            return hash + "." + ext
        }
    }
}

private struct EnexResource {
    var hash: String
    var mime: String
    var filename: String
    var url: URL
    var bytes: Int64
}

private struct EnexNoteBuilder {
    var title = "Untitled"
    var content = ""
    var created = ""
    var updated = ""
    var guid = ""
    var tags: [String] = []
    var resources: [String: EnexResource] = [:]
    var diagnostics: [NoteImportDiagnostic] = []
    var contentEncoding = ""

    func build(sourceURL: URL, sourceKind: NoteImportSourceKind) throws -> ImportedNote {
        var allDiagnostics = diagnostics
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPayload = Self.normalizedEncryptedPayload(trimmedContent)
        let isEncrypted = contentEncoding.lowercased() == "base64:aes"
            || Self.looksLikeEncryptedPayload(normalizedPayload)

        let markdown: String
        var attachments: [ImportedNoteAttachment] = []
        if isEncrypted {
            markdown = Self.encryptedContentMessage
            if !normalizedPayload.isEmpty, let url = try? Self.writeEncryptedPayload(normalizedPayload) {
                let filename = "加密正文-" + url.deletingPathExtension().lastPathComponent + ".txt"
                attachments.append(ImportedNoteAttachment(
                    sourcePath: url.path,
                    displayName: filename,
                    mimeType: "text/plain",
                    byteCount: Int64(normalizedPayload.utf8.count)
                ))
            }
            allDiagnostics.append(NoteImportDiagnostic(
                severity: .warning,
                message: "笔记正文已加密（印象笔记 base64:aes 格式），无法解密；正文已替换为说明，原始密文已保留为附件。"
            ))
        } else {
            let markdownSource = Self.base64DecodedENML(normalizedPayload) ?? content
            let attachmentBox = MediaAttachmentBox()
            markdown = ENMLMarkdownConverter.convert(markdownSource) { media in
                guard let resource = resources[media.hash] else {
                    attachmentBox.missingMediaHashes.insert(media.hash)
                    return nil
                }
                attachmentBox.attachments.append(ImportedNoteAttachment(
                    sourcePath: resource.url.path,
                    displayName: resource.filename,
                    mimeType: resource.mime,
                    byteCount: resource.bytes,
                    metadata: ["enex_md5": media.hash]
                ))
                let isImage = resource.mime.lowercased().hasPrefix("image/")
                let label = (media.filename?.isEmpty == false ? media.filename : resource.filename) ?? "媒体"
                if isImage {
                    return "![\(label)](attachment:\(media.hash))"
                }
                return "[\(label)](attachment:\(media.hash))"
            }
            attachments = attachmentBox.attachments
            for hash in attachmentBox.missingMediaHashes.sorted() {
                allDiagnostics.append(NoteImportDiagnostic(
                    code: .attachmentMissing,
                    severity: .warning,
                    message: "正文引用了缺失的媒体资源（MD5 \(hash.prefix(8))…），已保留占位说明",
                    metadata: ["enex_md5": hash]
                ))
            }
        }
        let data = Data(markdown.utf8)
        let sourceIdentity = guid.isEmpty ? title + created : guid
        return ImportedNote(
            sourceKind: sourceKind,
            sourceIdentity: sourceIdentity,
            externalID: guid.isEmpty ? nil : guid,
            sourcePath: sourceURL.path,
            title: title,
            markdownContent: markdown,
            createdAt: Self.date(created),
            updatedAt: Self.date(updated),
            tags: tags,
            attachments: attachments,
            sourceMetadata: ["enex_notebook": sourceURL.deletingPathExtension().lastPathComponent],
            rawByteHash: SHA256.hash(data: data).hexString,
            normalizedTextHash: SHA256.hash(data: data).hexString,
            diagnostics: allDiagnostics
        )
    }

    /// 加密正文的占位说明：不把密文当正文导入，引导用户在客户端解密或改用 HTML 导出。
    static var encryptedContentMessage: String {
        """
        🔒 此笔记正文已加密（印象笔记 base64:aes 格式），导入时无法解密。

        请在印象笔记客户端中为该笔记解密后重新导出，或改用「导出 HTML」后再导入。原始密文已保留为附件。
        """
    }

    /// 去掉可能存在的 "base64:" / "base64:aes:" 前缀。
    static func normalizedEncryptedPayload(_ text: String) -> String {
        var candidate = text
        for prefix in ["base64:aes:", "base64:"] where candidate.hasPrefix(prefix) {
            candidate = String(candidate.dropFirst(prefix.count))
        }
        return candidate
    }

    /// 判断正文是否为印象笔记加密文本：base64 解码后以 "ENC" 开头且不是可读 UTF-8 文本。
    static func looksLikeEncryptedPayload(_ text: String) -> Bool {
        guard !text.isEmpty,
              let data = Data(base64Encoded: text, options: [.ignoreUnknownCharacters]),
              data.count >= 4,
              String(data: data.prefix(3), encoding: .utf8) == "ENC" else {
            return false
        }
        // 排除极少数恰好解码为可读文本的情况（例如普通 ASCII 正文）。
        if let decoded = String(data: data, encoding: .utf8) {
            let hasControl = decoded.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0)
            }
            if !decoded.isEmpty, !hasControl {
                return false
            }
        }
        return true
    }

    /// 部分工具导出的 `<content encoding="base64">` 是纯 base64 编码的 ENML，解码后按 ENML 处理。
    static func base64DecodedENML(_ text: String) -> String? {
        guard !text.isEmpty,
              let data = Data(base64Encoded: text, options: [.ignoreUnknownCharacters]),
              let decoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<") else { return nil }
        return trimmed
    }

    static func writeEncryptedPayload(_ payload: String) throws -> URL {
        let hash = SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-enex-resources", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("encrypted-" + String(hash.prefix(16)) + ".txt")
        try payload.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /*
     * 原 build 逻辑已按「加密正文 / base64 ENML / 普通 ENML」分派到上方实现，
     * 保留 date 解析等辅助方法。
     */
    static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.date(from: value)
    }
}

private final class MediaAttachmentBox: @unchecked Sendable {
    var attachments: [ImportedNoteAttachment] = []
    var missingMediaHashes: Set<String> = []
}

private extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
