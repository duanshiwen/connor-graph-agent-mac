import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public enum PresentImageAgentToolError: Error, Sendable, Equatable, LocalizedError {
    case missingSource
    case unsupportedURLScheme(String)
    case invalidHTTPResponse
    case downloadFailed(Int)
    case fileTooLarge(Int64)
    case notAnImage

    public var errorDescription: String? {
        switch self {
        case .missingSource:
            return "An image source is required."
        case .unsupportedURLScheme(let scheme):
            return "Unsupported image URL scheme: \(scheme). Use a local path or an HTTP/HTTPS URL."
        case .invalidHTTPResponse:
            return "The image request did not return a valid HTTP response."
        case .downloadFailed(let statusCode):
            return "The image request failed with HTTP status \(statusCode)."
        case .fileTooLarge(let limit):
            return "The image exceeds the \(limit)-byte size limit."
        case .notAnImage:
            return "The requested resource is not a supported image."
        }
    }
}

public struct PresentImageDownload: Sendable, Equatable {
    public var data: Data
    public var mimeType: String?
    public var suggestedFilename: String?
    public var finalURL: URL

    public init(data: Data, mimeType: String?, suggestedFilename: String?, finalURL: URL) {
        self.data = data
        self.mimeType = mimeType
        self.suggestedFilename = suggestedFilename
        self.finalURL = finalURL
    }
}

public struct AnyPresentImageDownloader: Sendable {
    private let operation: @Sendable (URL, Int64) async throws -> PresentImageDownload

    public init(operation: @escaping @Sendable (URL, Int64) async throws -> PresentImageDownload) {
        self.operation = operation
    }

    public func download(from url: URL, maxBytes: Int64) async throws -> PresentImageDownload {
        try await operation(url, maxBytes)
    }

    public static let live = AnyPresentImageDownloader { url, maxBytes in
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw PresentImageAgentToolError.invalidHTTPResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw PresentImageAgentToolError.downloadFailed(response.statusCode)
        }
        guard Int64(data.count) <= maxBytes else {
            throw PresentImageAgentToolError.fileTooLarge(maxBytes)
        }
        return PresentImageDownload(
            data: data,
            mimeType: response.mimeType,
            suggestedFilename: response.suggestedFilename,
            finalURL: response.url ?? url
        )
    }
}

public struct PresentImageToolResultPayload: Codable, Sendable, Equatable {
    public var attachment: AgentMessageAttachmentRef
    public var markdown: String
    public var localFileURL: URL
    public var source: String

    public init(attachment: AgentMessageAttachmentRef, markdown: String, localFileURL: URL, source: String) {
        self.attachment = attachment
        self.markdown = markdown
        self.localFileURL = localFileURL
        self.source = source
    }
}

public struct PresentImageAgentTool: AgentTool {
    public let name = "present_image"
    public let description = "Fetch a supported image from a local workspace path or HTTP/HTTPS URL, persist it in the current Connor session, and return exact Markdown for placing it in the assistant response. Use this when a relevant existing image would materially improve a visually grounded answer, especially after image_search finds a clearly useful candidate. Include the returned Markdown near the paragraph that interprets the image; do not merely describe or link the candidate."
    public let permission: AgentPermissionCapability = .externalNetwork
    public let inputSchema = AgentToolInputSchema.closedObject(
        properties: [
            "source": .string(description: "A local image path, file URL, or HTTP/HTTPS image URL."),
            "altText": .string(description: "Concise accessible text describing the image in the response.")
        ],
        required: ["source", "altText"]
    )
    public let inputExamples: [[String: SendableJSONValue]] = [
        ["source": .string("assets/architecture.png"), "altText": .string("System architecture")],
        ["source": .string("https://example.com/chart.png"), "altText": .string("Quarterly revenue chart")]
    ]

    private let store: AppSessionAttachmentStore
    private let localWorkspacePolicy: LocalWorkspacePolicy
    private let downloader: AnyPresentImageDownloader
    private let maxBytes: Int64

    public init(
        store: AppSessionAttachmentStore,
        localWorkspacePolicy: LocalWorkspacePolicy,
        downloader: AnyPresentImageDownloader = .live,
        maxBytes: Int64 = 20_000_000
    ) {
        self.store = store
        self.localWorkspacePolicy = localWorkspacePolicy
        self.downloader = downloader
        self.maxBytes = maxBytes
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let source = arguments.string("source")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !source.isEmpty else { throw PresentImageAgentToolError.missingSource }
        let altText = normalizedAltText(arguments.string("altText") ?? arguments.string("alt_text") ?? "Image")

        let manifest: AgentAttachmentManifest
        if let remoteURL = remoteURL(from: source) {
            let download = try await downloader.download(from: remoteURL, maxBytes: maxBytes)
            guard Int64(download.data.count) <= maxBytes else {
                throw PresentImageAgentToolError.fileTooLarge(maxBytes)
            }
            let temporaryURL = temporaryFileURL(for: download)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            try download.data.write(to: temporaryURL, options: .atomic)
            manifest = try store.importFile(at: temporaryURL, sessionID: context.sessionID, origin: .toolGenerated)
        } else {
            let localURL = try resolvedLocalURL(from: source)
            try validateLocalImageSize(localURL)
            manifest = try store.importFile(at: localURL, sessionID: context.sessionID, origin: .toolGenerated)
        }
        guard manifest.kind == .image else { throw PresentImageAgentToolError.notAnImage }

        let localFileURL = store.paths.sessionArtifactDirectories(sessionID: context.sessionID).root
            .appendingPathComponent(manifest.storedRelativePath)
        let markdown = "![\(altText)](\(localFileURL.absoluteString))"
        let payload = PresentImageToolResultPayload(
            attachment: manifest.messageRef,
            markdown: markdown,
            localFileURL: localFileURL,
            source: source
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return AgentToolResult(
            runID: context.runID,
            sessionID: context.sessionID,
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Image is ready. Place this exact Markdown at the relevant point in the final response:\n\(markdown)",
            contentJSON: String(decoding: try encoder.encode(payload), as: UTF8.self)
        )
    }

    private func remoteURL(from source: String) -> URL? {
        guard let url = URL(string: source), let scheme = url.scheme?.lowercased() else { return nil }
        return scheme == "http" || scheme == "https" ? url : nil
    }

    private func resolvedLocalURL(from source: String) throws -> URL {
        if let url = URL(string: source), let scheme = url.scheme, !scheme.isEmpty {
            guard scheme.lowercased() == "file" else {
                throw PresentImageAgentToolError.unsupportedURLScheme(scheme)
            }
            let resolved = try localWorkspacePolicy.resolvePath(url.path)
            try localWorkspacePolicy.validateReadablePath(resolved)
            return resolved
        }
        let resolved = try localWorkspacePolicy.resolvePath(source)
        try localWorkspacePolicy.validateReadablePath(resolved)
        return resolved
    }

    private func validateLocalImageSize(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard byteCount <= maxBytes else { throw PresentImageAgentToolError.fileTooLarge(maxBytes) }
    }

    private func temporaryFileURL(for download: PresentImageDownload) -> URL {
        let filename = download.suggestedFilename?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (filename?.isEmpty == false ? filename! : download.finalURL.lastPathComponent)
        let fileExtension = resolvedFileExtension(filename: base, mimeType: download.mimeType)
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("present-image-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
    }

    private func resolvedFileExtension(filename: String, mimeType: String?) -> String {
        let existing = URL(fileURLWithPath: filename).pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "ico", "tif", "tiff"].contains(existing) {
            return existing
        }
        switch mimeType?.lowercased() {
        case "image/jpeg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/heic", "image/heif": return "heic"
        case "image/bmp": return "bmp"
        case "image/x-icon", "image/vnd.microsoft.icon": return "ico"
        case "image/tiff": return "tiff"
        default: return "png"
        }
    }

    private func normalizedAltText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "Image" : trimmed
        return fallback.replacingOccurrences(of: "]", with: "\\]")
    }
}
