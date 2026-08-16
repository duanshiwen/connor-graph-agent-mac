import Foundation
import ConnorGraphCore

/// 基于系统 `/usr/bin/ditto` 的安全 ZIP 后端。
/// `entries(in:)` 直接解析 ZIP 中央目录（获取真实大小与符号链接标记），
/// `extract(archive:to:)` 交给系统 ditto 解压，随后由 SafeArchiveExtractor 做二次校验。
public struct SystemZipArchiveBackend: SafeArchiveBackend {
    public init() {}

    public func entries(in archive: URL) throws -> [SafeArchiveEntry] {
        try ZipCentralDirectoryReader.read(archive)
    }

    public func extract(archive: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SafeArchiveError.extractionFailed("ditto 解压失败（退出码 \(process.terminationStatus)）")
        }
    }
}

/// 将用户选择的 Notion 来源解析为可扫描的文件夹：如果是 .zip 则先安全解压到临时目录。
public enum NotionExportSourceResolver {
    public static func extractIfZip(_ selected: URL, extractor: SafeArchiveExtractor = .init(backend: SystemZipArchiveBackend())) throws -> URL {
        guard selected.pathExtension.lowercased() == "zip" else { return selected }
        let base = selected.deletingPathExtension().lastPathComponent.isEmpty
            ? "NotionExport"
            : selected.deletingPathExtension().lastPathComponent
        var directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConnorNotionImport-\(base)", isDirectory: true)
        var suffix = 1
        while FileManager.default.fileExists(atPath: directory.path) {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ConnorNotionImport-\(base)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        _ = try extractor.extract(selected, to: directory)
        return directory
    }
}

private enum ZipCentralDirectoryReader {
    private static let endOfCentralDirectorySignature: UInt32 = 0x06054b50
    private static let centralDirectorySignature: UInt32 = 0x02014b50
    private static let maximumEOCDSearchLength = 70_000

    static func read(_ archive: URL) throws -> [SafeArchiveEntry] {
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        guard fileSize >= 22 else { throw SafeArchiveError.unsupportedArchive("不是有效的 ZIP 文件") }

        let tailLength = min(fileSize, UInt64(maximumEOCDSearchLength))
        try handle.seek(toOffset: fileSize - tailLength)
        let tail = try readFully(handle, count: Int(tailLength))
        guard let eocdOffset = findSignature(tail, signature: endOfCentralDirectorySignature, fromEnd: true),
              eocdOffset + 22 <= tail.count else {
            throw SafeArchiveError.unsupportedArchive("找不到 ZIP 结束记录")
        }
        let totalEntries = u16(tail, at: eocdOffset + 10)
        let centralDirectorySize = u32(tail, at: eocdOffset + 12)
        let centralDirectoryOffset = u32(tail, at: eocdOffset + 16)
        if totalEntries == 0xFFFF || centralDirectorySize == 0xFFFFFFFF || centralDirectoryOffset == 0xFFFFFFFF {
            throw SafeArchiveError.unsupportedArchive("暂不支持 ZIP64 归档（条目数或文件过大）")
        }
        guard UInt64(centralDirectoryOffset) + UInt64(centralDirectorySize) <= fileSize else {
            throw SafeArchiveError.unsupportedArchive("ZIP 中央目录越界")
        }

        try handle.seek(toOffset: UInt64(centralDirectoryOffset))
        let centralData = try readFully(handle, count: Int(centralDirectorySize))
        var entries: [SafeArchiveEntry] = []
        entries.reserveCapacity(Int(totalEntries))
        var cursor = 0
        var index = 0
        while cursor + 46 <= centralData.count && index < totalEntries {
            guard u32(centralData, at: cursor) == centralDirectorySignature else {
                throw SafeArchiveError.unsupportedArchive("ZIP 中央目录解析失败")
            }
            let compressedSize = u32(centralData, at: cursor + 20)
            let uncompressedSize = u32(centralData, at: cursor + 24)
            let nameLength = Int(u16(centralData, at: cursor + 28))
            let extraLength = Int(u16(centralData, at: cursor + 30))
            let entryCommentLength = Int(u16(centralData, at: cursor + 32))
            let externalAttributes = u32(centralData, at: cursor + 38)
            let nameStart = cursor + 46
            guard nameStart + nameLength <= centralData.count else {
                throw SafeArchiveError.unsupportedArchive("ZIP 文件名越界")
            }
            let nameData = centralData.subdata(in: nameStart..<(nameStart + nameLength))
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)
            let isDirectory = name.hasSuffix("/")
            let isSymbolicLink = ((externalAttributes >> 16) & 0xF000) == 0xA000
            entries.append(.init(
                path: name,
                uncompressedSize: Int64(uncompressedSize),
                compressedSize: Int64(compressedSize),
                isDirectory: isDirectory,
                isSymbolicLink: isSymbolicLink
            ))
            cursor = nameStart + nameLength + extraLength + entryCommentLength
            index += 1
        }
        guard index == totalEntries else { throw SafeArchiveError.unsupportedArchive("ZIP 条目数量不一致") }
        return entries
    }

    private static func readFully(_ handle: FileHandle, count: Int) throws -> Data {
        var data = Data()
        data.reserveCapacity(count)
        while data.count < count {
            guard let chunk = try handle.read(upToCount: count - data.count), !chunk.isEmpty else { break }
            data.append(chunk)
        }
        return data
    }

    private static func findSignature(_ data: Data, signature: UInt32, fromEnd: Bool) -> Int? {
        let bytes = withUnsafeBytes(of: signature.littleEndian) { Data($0) }
        if fromEnd {
            var index = data.count - bytes.count
            while index >= 0 {
                if data.subdata(in: index..<(index + bytes.count)) == bytes { return index }
                index -= 1
            }
        } else {
            var index = 0
            while index + bytes.count <= data.count {
                if data.subdata(in: index..<(index + bytes.count)) == bytes { return index }
                index += 1
            }
        }
        return nil
    }

    private static func u16(_ data: Data, at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func u32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
