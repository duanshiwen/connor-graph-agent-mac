import Foundation

enum ComposerTemporaryAttachmentWriterError: LocalizedError, Equatable {
    case noImages
    case createDirectoryFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noImages:
            return "剪贴板中没有可导入的图片。"
        case .createDirectoryFailed(let message):
            return "无法创建临时粘贴图片目录：\(message)"
        case .writeFailed(let message):
            return "无法写入临时粘贴图片：\(message)"
        }
    }
}

struct ComposerTemporaryAttachmentWriter {
    var fileManager: FileManager = .default
    var directoryName: String = "ConnorPastedImages"

    func writePNGImages(_ imageDataItems: [Data]) throws -> [URL] {
        guard !imageDataItems.isEmpty else { throw ComposerTemporaryAttachmentWriterError.noImages }
        let directory = fileManager.temporaryDirectory.appendingPathComponent(directoryName, isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw ComposerTemporaryAttachmentWriterError.createDirectoryFailed(String(describing: error))
        }
        return try imageDataItems.enumerated().map { index, data in
            let filename = "pasted-image-\(Self.pasteTimestamp())-\(index + 1)-\(UUID().uuidString.prefix(8)).png"
            let url = directory.appendingPathComponent(filename)
            do {
                try data.write(to: url, options: .atomic)
                return url
            } catch {
                throw ComposerTemporaryAttachmentWriterError.writeFailed(String(describing: error))
            }
        }
    }

    private static func pasteTimestamp() -> String {
        pasteTimestampFormatter.string(from: Date())
    }

    private static let pasteTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
