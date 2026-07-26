import Foundation
import ConnorGraphCore

public enum PersonProfileImageStoreError: Error, LocalizedError, Sendable, Equatable {
    case unsupportedFormat
    case fileTooLarge
    case fileUnavailable
    case invalidStoredPath

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "请选择 PNG、JPEG、HEIC、WebP、GIF、BMP 或 TIFF 图片。"
        case .fileTooLarge: "人物图片不能超过 20 MB。"
        case .fileUnavailable: "无法读取所选图片。"
        case .invalidStoredPath: "人物图片的存储路径无效。"
        }
    }
}

public struct PersonProfileImageStore: Sendable {
    public let applicationSupportDirectory: URL
    public let imagesDirectory: URL
    public var maximumByteCount: Int64

    public init(storagePaths: AppStoragePaths, maximumByteCount: Int64 = 20 * 1_024 * 1_024) {
        self.init(applicationSupportDirectory: storagePaths.applicationSupportDirectory, maximumByteCount: maximumByteCount)
    }

    public init(applicationSupportDirectory: URL, maximumByteCount: Int64 = 20 * 1_024 * 1_024) {
        self.applicationSupportDirectory = applicationSupportDirectory.standardizedFileURL
        self.imagesDirectory = applicationSupportDirectory
            .appendingPathComponent("contacts", isDirectory: true)
            .appendingPathComponent("images", isDirectory: true)
        self.maximumByteCount = maximumByteCount
    }

    public func importImage(at sourceURL: URL, personID: ContactID, fileManager: FileManager = .default) throws -> String {
        let fileExtension = sourceURL.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(fileExtension) else {
            throw PersonProfileImageStoreError.unsupportedFormat
        }
        guard fileManager.fileExists(atPath: sourceURL.path),
              let attributes = try? fileManager.attributesOfItem(atPath: sourceURL.path),
              let byteCount = attributes[.size] as? NSNumber else {
            throw PersonProfileImageStoreError.fileUnavailable
        }
        guard byteCount.int64Value <= maximumByteCount else {
            throw PersonProfileImageStoreError.fileTooLarge
        }

        let personDirectory = imagesDirectory.appendingPathComponent(Self.sanitizedComponent(personID.rawValue), isDirectory: true)
        try fileManager.createDirectory(at: personDirectory, withIntermediateDirectories: true)
        let destination = personDirectory.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
        try fileManager.copyItem(at: sourceURL, to: destination)
        return try relativePath(for: destination)
    }

    public func imageURL(for relativePath: String?, fileManager: FileManager = .default) -> URL? {
        guard let relativePath, let url = try? resolvedURL(for: relativePath), fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    public func storedImageRelativePaths(for personID: ContactID, fileManager: FileManager = .default) -> [String] {
        let personDirectory = imagesDirectory.appendingPathComponent(Self.sanitizedComponent(personID.rawValue), isDirectory: true)
        guard let urls = try? fileManager.contentsOfDirectory(
            at: personDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls
            .filter { url in
                Self.supportedExtensions.contains(url.pathExtension.lowercased())
                    && ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false)
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { try? relativePath(for: $0) }
    }

    public func removeImage(at relativePath: String?, fileManager: FileManager = .default) throws {
        guard let relativePath else { return }
        let url = try resolvedURL(for: relativePath)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func relativePath(for url: URL) throws -> String {
        let rootPath = applicationSupportDirectory.path.hasSuffix("/")
            ? applicationSupportDirectory.path
            : applicationSupportDirectory.path + "/"
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { throw PersonProfileImageStoreError.invalidStoredPath }
        return String(path.dropFirst(rootPath.count))
    }

    private func resolvedURL(for relativePath: String) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else {
            throw PersonProfileImageStoreError.invalidStoredPath
        }
        let rootPath = applicationSupportDirectory.path.hasSuffix("/")
            ? applicationSupportDirectory.path
            : applicationSupportDirectory.path + "/"
        let url = applicationSupportDirectory.appendingPathComponent(relativePath).standardizedFileURL
        guard url.path.hasPrefix(rootPath) else { throw PersonProfileImageStoreError.invalidStoredPath }
        return url
    }

    private static func sanitizedComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = value.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        return sanitized.isEmpty ? "person" : sanitized
    }

    private static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "webp", "gif", "bmp", "tif", "tiff"]
}
