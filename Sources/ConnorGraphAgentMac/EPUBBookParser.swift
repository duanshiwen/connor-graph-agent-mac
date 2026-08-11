import Foundation
import zlib

// MARK: - EPUB 电子书解析

enum EPUBBookParserError: LocalizedError, Equatable {
    case notAZip
    case invalidZip(String)
    case unsupportedZipFeature(String)
    case missingContainer
    case missingOPF(String)
    case invalidOPF(String)
    case emptySpine
    case extractionFailed(String)
    case inflateFailed

    var errorDescription: String? {
        switch self {
        case .notAZip:
            "不是有效的 EPUB 电子书文件（无法识别 ZIP 结构）。"
        case .invalidZip(let reason):
            "EPUB 文件损坏：\(reason)"
        case .unsupportedZipFeature(let reason):
            "暂不支持该 EPUB 的 ZIP 特性：\(reason)"
        case .missingContainer:
            "EPUB 缺少 META-INF/container.xml，无法解析。"
        case .missingOPF(let path):
            "EPUB 缺少 OPF 内容清单：\(path)"
        case .invalidOPF(let reason):
            "EPUB 的内容清单无效：\(reason)"
        case .emptySpine:
            "EPUB 没有可阅读的正文章节。"
        case .extractionFailed(let reason):
            "EPUB 解压失败：\(reason)"
        case .inflateFailed:
            "EPUB 解压失败：数据损坏。"
        }
    }
}

struct EPUBChapter: Equatable, Sendable {
    /// 相对于解压目录根部的路径（可能带 #fragment）。
    var href: String
    var title: String
}

struct EPUBBook: Equatable, Sendable {
    var title: String
    var creator: String?
    var coverHref: String?
    var chapters: [EPUBChapter]
}

enum EPUBBookParser {
    static let extractionDirectoryPrefix = "connor-epub-"
    static let landingPageFilename = "__connor_epub_reader__.html"

    /// 为一次 EPUB 预览创建独立的解压目录。
    static func extractionDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(extractionDirectoryPrefix + UUID().uuidString, isDirectory: true)
    }

    /// 把 EPUB 解压到指定目录；失败时自动清理目录。
    static func extract(fileURL: URL, to directory: URL) throws {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            throw EPUBBookParserError.notAZip
        }
        do {
            try EPUBZIPReader.extract(archiveData: data, to: directory)
        } catch let error as EPUBBookParserError {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("META-INF/container.xml").path) else {
            try? FileManager.default.removeItem(at: directory)
            throw EPUBBookParserError.missingContainer
        }
    }

    /// 解析已解压的 EPUB 目录，返回书籍信息（标题、作者、封面、目录）。
    static func parseBook(at directory: URL, defaultTitle: String) throws -> EPUBBook {
        let containerURL = directory.appendingPathComponent("META-INF/container.xml")
        let container: XMLDocument
        do {
            container = try XMLDocument(contentsOf: containerURL, options: [.nodeLoadExternalEntitiesNever])
        } catch {
            throw EPUBBookParserError.missingContainer
        }
        guard let rootfilePath = try firstAttribute(
            in: container,
            xpath: "//*[local-name()='rootfile']",
            attribute: "full-path"
        ) else {
            throw EPUBBookParserError.missingOPF("container.xml 未声明 rootfile")
        }
        guard let opfURL = resolvedURL(rootfilePath, relativeTo: directory),
              FileManager.default.fileExists(atPath: opfURL.path) else {
            throw EPUBBookParserError.missingOPF(rootfilePath)
        }
        let opf: XMLDocument
        do {
            opf = try XMLDocument(contentsOf: opfURL, options: [.nodeLoadExternalEntitiesNever])
        } catch {
            throw EPUBBookParserError.invalidOPF("无法解析 \(rootfilePath)")
        }
        let opfDirectory = opfURL.deletingLastPathComponent()

        let title = (try firstText(in: opf, xpath: "//*[local-name()='metadata']/*[local-name()='title']"))
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? defaultTitle
        let creator = (try firstText(in: opf, xpath: "//*[local-name()='metadata']/*[local-name()='creator']"))
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }

        struct ManifestItem {
            let id: String
            let href: String
            let mediaType: String
            let properties: String
        }
        var itemsByID: [String: ManifestItem] = [:]
        let manifestNodes = try opf.nodes(forXPath: "//*[local-name()='manifest']/*[local-name()='item']")
        for node in manifestNodes {
            guard let id = try firstAttribute(on: node, "id"),
                  let href = try firstAttribute(on: node, "href") else { continue }
            itemsByID[id] = ManifestItem(
                id: id,
                href: href,
                mediaType: try firstAttribute(on: node, "media-type") ?? "",
                properties: try firstAttribute(on: node, "properties") ?? ""
            )
        }

        let itemrefNodes = try opf.nodes(forXPath: "//*[local-name()='spine']/*[local-name()='itemref']")
        var spineItems: [ManifestItem] = []
        for node in itemrefNodes {
            guard let idref = try firstAttribute(on: node, "idref"),
                  let item = itemsByID[idref] else { continue }
            spineItems.append(item)
        }
        guard !spineItems.isEmpty else { throw EPUBBookParserError.emptySpine }

        var coverHref: String?
        if let coverID = try opf.nodes(forXPath: "//*[local-name()='metadata']/*[local-name()='meta']")
            .first(where: { (try? firstAttribute(on: $0, "name")) == "cover" })
            .flatMap({ try? firstAttribute(on: $0, "content") }),
           let item = itemsByID[coverID] {
            coverHref = resolvedHref(item.href, relativeTo: opfDirectory, in: directory)
        }
        if coverHref == nil,
           let coverItem = itemsByID.values.first(where: {
               $0.properties.split(separator: " ").contains("cover-image")
           }) {
            coverHref = resolvedHref(coverItem.href, relativeTo: opfDirectory, in: directory)
        }

        var chapters: [EPUBChapter] = []
        if let navItem = itemsByID.values.first(where: { $0.properties.split(separator: " ").contains("nav") }),
           let navURL = resolvedURL(navItem.href, relativeTo: opfDirectory),
           let navDoc = try? XMLDocument(contentsOf: navURL, options: [.nodeLoadExternalEntitiesNever]) {
            chapters = try parseEPUB3Nav(navDoc, relativeTo: navURL.deletingLastPathComponent(), in: directory)
        }
        if chapters.isEmpty,
           let ncxItem = itemsByID.values.first(where: { $0.mediaType == "application/x-dtbncx+xml" }),
           let ncxURL = resolvedURL(ncxItem.href, relativeTo: opfDirectory),
           let ncxDoc = try? XMLDocument(contentsOf: ncxURL, options: [.nodeLoadExternalEntitiesNever]) {
            chapters = try parseNCX(ncxDoc, relativeTo: ncxURL.deletingLastPathComponent(), in: directory)
        }
        if chapters.isEmpty {
            chapters = spineItems.enumerated().compactMap { index, item in
                guard let href = resolvedHref(item.href, relativeTo: opfDirectory, in: directory) else { return nil }
                let stem = item.href.split(separator: "/").last
                    .map { String($0.split(separator: ".").first ?? "") } ?? ""
                let fallbackTitle = stem.isEmpty ? "第 \(index + 1) 章" : stem
                return EPUBChapter(href: href, title: fallbackTitle)
            }
        }
        return EPUBBook(title: title, creator: creator, coverHref: coverHref, chapters: chapters)
    }

    /// 生成阅读入口页（封面 + 目录），返回其在解压目录中的 URL。
    static func writeLandingPage(for book: EPUBBook, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(landingPageFilename)
        try landingPageHTML(for: book).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// 清理由本解析器创建的解压目录；非本应用创建的目录不会被删除。
    static func cleanupExtractedDirectoryIfNeeded(path: String?) {
        guard let path, !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        guard url.lastPathComponent.hasPrefix(extractionDirectoryPrefix) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - 阅读入口页

    static func landingPageHTML(for book: EPUBBook) -> String {
        let title = escapeHTML(book.title)
        let creator = book.creator.map { "<div class=\"author\">\(escapeHTML($0))</div>" } ?? ""
        let cover = book.coverHref.map {
            "<div class=\"cover\"><img src=\"\(escapeHTML($0))\" alt=\"封面\"></div>"
        } ?? ""
        let chapters = book.chapters.enumerated().map { _, chapter in
            "<li><a href=\"\(escapeHTML(chapter.href))\">\(escapeHTML(chapter.title))</a></li>"
        }.joined()

        return """
        <!DOCTYPE html>
        <html lang="zh">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title)</title>
        <style>
          * { box-sizing: border-box; }
          body { font-family: -apple-system, "PingFang SC", "Helvetica Neue", sans-serif; margin: 0; background: #f5f4f0; color: #1c1c1e; }
          .reader { max-width: 720px; margin: 0 auto; padding: 40px 20px 64px; }
          h1 { font-size: 26px; line-height: 1.35; margin: 0 0 8px; }
          .author { color: #6e6e73; margin-bottom: 28px; font-size: 15px; }
          .cover { text-align: center; margin-bottom: 28px; }
          .cover img { max-width: 240px; max-height: 320px; border-radius: 8px; box-shadow: 0 8px 24px rgba(0,0,0,.18); }
          .chapters { list-style: none; padding: 0; margin: 0; border-top: 1px solid #e3e2de; }
          .chapters li { border-bottom: 1px solid #e3e2de; }
          .chapters a { display: block; padding: 14px 8px; color: #0a66c2; text-decoration: none; font-size: 15px; line-height: 1.4; }
          .chapters a:hover { background: #ecebe7; }
        </style>
        </head>
        <body>
        <div class="reader">
          <h1>\(title)</h1>
          \(creator)
          \(cover)
          <ol class="chapters">
          \(chapters)
          </ol>
        </div>
        </body>
        </html>
        """
    }

    // MARK: - 目录解析

    private static func parseEPUB3Nav(_ doc: XMLDocument, relativeTo directory: URL, in root: URL) throws -> [EPUBChapter] {
        let navNodes = try doc.nodes(forXPath: "//*[local-name()='nav']")
        for nav in navNodes {
            let typeValues = try nav.nodes(forXPath: "@*[local-name()='type']").compactMap { $0.stringValue }
            guard typeValues.contains(where: { $0.split(separator: " ").contains("toc") }) else { continue }
            let linkNodes = try nav.nodes(forXPath: ".//*[local-name()='a']")
            var chapters: [EPUBChapter] = []
            for link in linkNodes {
                guard let href = try firstAttribute(on: link, "href"),
                      let resolved = resolvedHref(href, relativeTo: directory, in: root) else { continue }
                let title = link.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !title.isEmpty else { continue }
                chapters.append(EPUBChapter(href: resolved, title: title))
            }
            if !chapters.isEmpty { return chapters }
        }
        return []
    }

    private static func parseNCX(_ doc: XMLDocument, relativeTo directory: URL, in root: URL) throws -> [EPUBChapter] {
        let points = try doc.nodes(forXPath: "//*[local-name()='navMap']//*[local-name()='navPoint']")
        var chapters: [EPUBChapter] = []
        for point in points {
            let title = (try point.nodes(forXPath: ".//*[local-name()='text']").first?.stringValue)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let src = try point.nodes(forXPath: ".//*[local-name()='content']/@*[local-name()='src']").first?.stringValue,
                  let resolved = resolvedHref(src, relativeTo: directory, in: root) else { continue }
            chapters.append(EPUBChapter(href: resolved, title: title.isEmpty ? "章节" : title))
        }
        return chapters
    }

    // MARK: - 路径与辅助

    private static func resolvedURL(_ path: String, relativeTo directory: URL) -> URL? {
        let url = URL(fileURLWithPath: path, relativeTo: directory).standardizedFileURL
        let root = directory.standardizedFileURL.path
        let candidate = url.path
        guard candidate == root || candidate.hasPrefix(root + "/") else { return nil }
        return url
    }

    private static func resolvedHref(_ href: String, relativeTo directory: URL, in root: URL) -> String? {
        let parts = href.split(separator: "#", maxSplits: 1).map(String.init)
        let pathPart = parts[0]
        let fragment = parts.count > 1 ? "#" + parts[1] : ""
        guard let url = resolvedURL(pathPart, relativeTo: directory),
              let relative = relativePath(from: root, to: url) else { return nil }
        let encoded = relative.split(separator: "/")
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        return encoded + fragment
    }

    private static func relativePath(from base: URL, to target: URL) -> String? {
        let basePath = base.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path
        guard targetPath.hasPrefix(basePath + "/") else { return nil }
        return String(targetPath.dropFirst(basePath.count + 1))
    }

    private static func firstAttribute(in doc: XMLDocument, xpath: String, attribute: String) throws -> String? {
        guard let node = try doc.nodes(forXPath: xpath).first else { return nil }
        return try firstAttribute(on: node, attribute)
    }

    private static func firstAttribute(on node: XMLNode, _ name: String) throws -> String? {
        try node.nodes(forXPath: "@*[local-name()='\(name)']").first?.stringValue
    }

    private static func firstText(in doc: XMLDocument, xpath: String) throws -> String? {
        try doc.nodes(forXPath: xpath).first?.stringValue
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

// MARK: - 最小 ZIP 读取器（支持存储与 deflate 压缩）

private enum EPUBZIPReader {
    private struct ZIPEntry {
        let filename: String
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let dataOffset: Int
    }

    static func extract(archiveData: Data, to directory: URL) throws {
        let entries = try parseCentralDirectory(archiveData)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for entry in entries {
            guard !entry.filename.isEmpty else { continue }
            guard let outputURL = sanitizedOutputURL(for: entry.filename, in: directory) else { continue }
            let rangeStart = entry.dataOffset
            let rangeEnd = rangeStart + entry.compressedSize
            guard rangeStart >= 0, rangeEnd <= archiveData.count else {
                throw EPUBBookParserError.invalidZip("条目数据越界：\(entry.filename)")
            }
            let compressed = archiveData.subdata(in: rangeStart..<rangeEnd)
            let decoded: Data
            switch entry.compressionMethod {
            case 0:
                decoded = compressed
            case 8:
                decoded = try inflateRawDeflate(compressed, expectedSize: entry.uncompressedSize)
            default:
                throw EPUBBookParserError.unsupportedZipFeature(
                    "不支持的压缩方式（条目 \(entry.filename)）"
                )
            }
            try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try decoded.write(to: outputURL, options: .atomic)
        }
    }

    private static func parseCentralDirectory(_ data: Data) throws -> [ZIPEntry] {
        guard data.count >= 22, let eocd = findEndOfCentralDirectory(in: data) else {
            throw EPUBBookParserError.notAZip
        }
        let totalEntries = Int(readUInt16(data, eocd + 10))
        let cdOffset = Int(readUInt32(data, eocd + 16))
        if totalEntries == 0xFFFF || cdOffset == 0xFFFFFFFF {
            throw EPUBBookParserError.unsupportedZipFeature("暂不支持 ZIP64 电子书")
        }
        var entries: [ZIPEntry] = []
        var offset = cdOffset
        for _ in 0..<totalEntries {
            guard offset + 46 <= data.count, readUInt32(data, offset) == 0x02014b50 else {
                throw EPUBBookParserError.invalidZip("中央目录损坏")
            }
            let method = readUInt16(data, offset + 10)
            let compressedSize = Int(readUInt32(data, offset + 20))
            let uncompressedSize = Int(readUInt32(data, offset + 24))
            let filenameLength = Int(readUInt16(data, offset + 28))
            let extraLength = Int(readUInt16(data, offset + 30))
            let commentLength = Int(readUInt16(data, offset + 32))
            let localHeaderOffset = Int(readUInt32(data, offset + 42))
            let filenameStart = offset + 46
            let filenameEnd = filenameStart + filenameLength
            guard filenameEnd <= data.count else {
                throw EPUBBookParserError.invalidZip("文件名越界")
            }
            let filenameData = data.subdata(in: filenameStart..<filenameEnd)
            let filename = String(data: filenameData, encoding: .utf8)
                ?? String(data: filenameData, encoding: .isoLatin1)
                ?? ""

            guard localHeaderOffset + 30 <= data.count,
                  readUInt32(data, localHeaderOffset) == 0x04034b50 else {
                throw EPUBBookParserError.invalidZip("本地文件头损坏")
            }
            let localFilenameLength = Int(readUInt16(data, localHeaderOffset + 26))
            let localExtraLength = Int(readUInt16(data, localHeaderOffset + 28))
            let dataOffset = localHeaderOffset + 30 + localFilenameLength + localExtraLength

            entries.append(ZIPEntry(
                filename: filename,
                compressionMethod: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                dataOffset: dataOffset
            ))
            offset = filenameEnd + extraLength + commentLength
        }
        return entries
    }

    private static func sanitizedOutputURL(for filename: String, in directory: URL) -> URL? {
        let components = filename.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty, !components.contains("..") else { return nil }
        let trimmed = components.filter { $0 != "." }
        guard !trimmed.isEmpty else { return nil }
        if trimmed[0] == "__MACOSX" || trimmed.last == ".DS_Store" { return nil }
        var url = directory
        for component in trimmed {
            url.appendPathComponent(component)
        }
        return url
    }

    private static func findEndOfCentralDirectory(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let minimumOffset = max(0, data.count - 65_557)
        var offset = data.count - 22
        while offset >= minimumOffset {
            if readUInt32(data, offset) == 0x06054b50 { return offset }
            offset -= 1
        }
        return nil
    }

    private static func inflateRawDeflate(_ source: Data, expectedSize: Int) throws -> Data {
        guard !source.isEmpty else {
            if expectedSize == 0 { return Data() }
            throw EPUBBookParserError.inflateFailed
        }
        var stream = z_stream()
        let initStatus = inflateInit2_(&stream, -15, zlibVersion(), Int32(MemoryLayout<z_stream>.size))
        guard initStatus == 0 else { throw EPUBBookParserError.inflateFailed }
        defer { inflateEnd(&stream) }

        var output = Data()
        output.reserveCapacity(max(expectedSize, 0))
        var chunk = [UInt8](repeating: 0, count: 64 * 1_024)

        try source.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else {
                throw EPUBBookParserError.inflateFailed
            }
            stream.next_in = UnsafeMutablePointer<UInt8>(mutating: base.assumingMemoryBound(to: UInt8.self))
            stream.avail_in = uInt(source.count)
            var status: Int32 = 0
            repeat {
                if stream.avail_out == 0 {
                    stream.next_out = chunk.withUnsafeMutableBytes { $0.bindMemory(to: UInt8.self).baseAddress }
                    stream.avail_out = uInt(chunk.count)
                }
                let before = stream.avail_out
                status = inflate(&stream, 0)
                let produced = Int(before) - Int(stream.avail_out)
                if produced > 0 {
                    output.append(chunk, count: produced)
                }
                if status == 1 { break } // Z_STREAM_END
                // Z_OK(0) / Z_BUF_ERROR(-5) 可继续；其余视为损坏。
                guard status == 0 || status == -5 else { throw EPUBBookParserError.inflateFailed }
                if produced == 0 { throw EPUBBookParserError.inflateFailed }
            } while true
        }
        return output
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
