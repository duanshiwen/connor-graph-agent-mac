import Foundation
import ConnorGraphCore

public enum AttachmentSidecarAvailability: Sendable, Equatable {
    case available(version: String?)
    case unavailable(reason: String)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

public struct AttachmentExtractionRequest: Sendable, Equatable {
    public var sessionID: String
    public var manifest: AgentAttachmentManifest
    public var originalFileURL: URL
    public var derivativesDirectoryURL: URL
    public var requestedCapabilities: [String]

    public init(
        sessionID: String,
        manifest: AgentAttachmentManifest,
        originalFileURL: URL,
        derivativesDirectoryURL: URL,
        requestedCapabilities: [String] = []
    ) {
        self.sessionID = sessionID
        self.manifest = manifest
        self.originalFileURL = originalFileURL
        self.derivativesDirectoryURL = derivativesDirectoryURL
        self.requestedCapabilities = requestedCapabilities
    }
}

public struct AttachmentExtractionResult: Sendable, Equatable {
    public var report: AgentAttachmentExtractionReport
    public var extractedMarkdown: String?
    public var structuredJSON: String?
    public var pagesJSONL: String?
    public var mediaTranscript: String?
    public var previewText: String?

    public init(
        report: AgentAttachmentExtractionReport,
        extractedMarkdown: String? = nil,
        structuredJSON: String? = nil,
        pagesJSONL: String? = nil,
        mediaTranscript: String? = nil,
        previewText: String? = nil
    ) {
        self.report = report
        self.extractedMarkdown = extractedMarkdown
        self.structuredJSON = structuredJSON
        self.pagesJSONL = pagesJSONL
        self.mediaTranscript = mediaTranscript
        self.previewText = previewText
    }
}

public protocol AttachmentExtractionSidecar: Sendable {
    var id: String { get }
    var displayName: String { get }
    var engine: AgentAttachmentExtractionEngine { get }
    func availability() async -> AttachmentSidecarAvailability
    func extract(_ request: AttachmentExtractionRequest) async throws -> AttachmentExtractionResult
}

public struct CommandAttachmentExtractionSidecar: AttachmentExtractionSidecar {
    public var id: String
    public var displayName: String
    public var engine: AgentAttachmentExtractionEngine
    public var executableName: String
    public var arguments: @Sendable (AttachmentExtractionRequest) -> [String]

    public init(
        id: String,
        displayName: String,
        engine: AgentAttachmentExtractionEngine,
        executableName: String,
        arguments: @escaping @Sendable (AttachmentExtractionRequest) -> [String]
    ) {
        self.id = id
        self.displayName = displayName
        self.engine = engine
        self.executableName = executableName
        self.arguments = arguments
    }

    public func availability() async -> AttachmentSidecarAvailability {
        guard let path = Self.findExecutable(named: executableName) else {
            return .unavailable(reason: "\(executableName) not found in PATH")
        }
        return .available(version: path)
    }

    public func extract(_ request: AttachmentExtractionRequest) async throws -> AttachmentExtractionResult {
        guard let executable = Self.findExecutable(named: executableName) else {
            let report = AgentAttachmentExtractionReport(
                attachmentID: request.manifest.id,
                engine: engine,
                status: .unsupported,
                warnings: ["\(executableName) not found in PATH"],
                startedAt: Date(),
                completedAt: Date()
            )
            return AttachmentExtractionResult(report: report)
        }
        let output = try Self.run(executable: executable, arguments: arguments(request))
        let markdown = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let status: AgentAttachmentExtractionStatus = markdown.isEmpty ? .unsupported : .extracted
        let report = AgentAttachmentExtractionReport(
            attachmentID: request.manifest.id,
            engine: engine,
            status: status,
            capabilitiesUsed: request.requestedCapabilities,
            warnings: [],
            errors: [],
            startedAt: Date(),
            completedAt: Date()
        )
        return AttachmentExtractionResult(
            report: report,
            extractedMarkdown: markdown.isEmpty ? nil : markdown,
            previewText: Self.preview(markdown)
        )
    }

    private static func findExecutable(named name: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    private static func run(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "AttachmentExtractionSidecar", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: error])
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func preview(_ text: String, max: Int = 240) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > max ? String(trimmed.prefix(max)) + "…" : trimmed
    }
}

public enum MarkItDownAttachmentExtractor {
    public static func sidecar() -> CommandAttachmentExtractionSidecar {
        CommandAttachmentExtractionSidecar(
            id: "markitdown",
            displayName: "MarkItDown",
            engine: .markItDown,
            executableName: "markitdown",
            arguments: { [$0.originalFileURL.path] }
        )
    }
}

public enum DoclingAttachmentExtractor {
    public static func sidecar() -> CommandAttachmentExtractionSidecar {
        CommandAttachmentExtractionSidecar(
            id: "docling",
            displayName: "Docling",
            engine: .docling,
            executableName: "docling",
            arguments: { ["--to", "md", $0.originalFileURL.path] }
        )
    }
}

public struct AttachmentExtractionOrchestrator: Sendable {
    public var sidecars: [any AttachmentExtractionSidecar]
    public var maxBuiltinTextBytes: Int64
    public var maxBuiltinPDFBytes: Int64

    public init(
        sidecars: [any AttachmentExtractionSidecar] = [MarkItDownAttachmentExtractor.sidecar(), DoclingAttachmentExtractor.sidecar()],
        maxBuiltinTextBytes: Int64 = 512_000,
        maxBuiltinPDFBytes: Int64 = 25_000_000
    ) {
        self.sidecars = sidecars
        self.maxBuiltinTextBytes = maxBuiltinTextBytes
        self.maxBuiltinPDFBytes = maxBuiltinPDFBytes
    }

    public func extract(_ request: AttachmentExtractionRequest) async throws -> AttachmentExtractionResult {
        if AttachmentTextExtraction.supports(kind: request.manifest.kind) {
            let builtin = try AttachmentTextExtraction.extract(fileURL: request.originalFileURL, kind: request.manifest.kind, maxBytes: maxBuiltinTextBytes)
            let report = AgentAttachmentExtractionReport(
                attachmentID: request.manifest.id,
                engine: .builtinText,
                status: builtin.status,
                capabilitiesUsed: ["text"],
                startedAt: Date(),
                completedAt: Date()
            )
            return AttachmentExtractionResult(report: report, extractedMarkdown: builtin.markdown, previewText: builtin.previewText)
        }

        if AttachmentPDFTextExtraction.supports(kind: request.manifest.kind) {
            let pdf = try AttachmentPDFTextExtraction.extract(
                fileURL: request.originalFileURL,
                attachmentID: request.manifest.id,
                maxBytes: maxBuiltinPDFBytes
            )
            if pdf.report.status == .extracted || pdf.report.status == .skippedOversize || pdf.report.status == .failed {
                return pdf
            }
        }

        for sidecar in sidecars {
            let availability = await sidecar.availability()
            guard availability.isAvailable else { continue }
            let result = try await sidecar.extract(request)
            if result.report.status == .extracted { return result }
        }

        let report = AgentAttachmentExtractionReport(
            attachmentID: request.manifest.id,
            engine: .unavailable,
            status: .unsupported,
            warnings: ["No available extractor for \(request.manifest.kind.rawValue)"],
            startedAt: Date(),
            completedAt: Date()
        )
        return AttachmentExtractionResult(report: report)
    }
}

public struct FakeAttachmentExtractionSidecar: AttachmentExtractionSidecar {
    public var id: String
    public var displayName: String
    public var engine: AgentAttachmentExtractionEngine
    public var markdown: String

    public init(id: String = "fake", displayName: String = "Fake", engine: AgentAttachmentExtractionEngine = .docling, markdown: String) {
        self.id = id
        self.displayName = displayName
        self.engine = engine
        self.markdown = markdown
    }

    public func availability() async -> AttachmentSidecarAvailability { .available(version: "test") }

    public func extract(_ request: AttachmentExtractionRequest) async throws -> AttachmentExtractionResult {
        let report = AgentAttachmentExtractionReport(
            attachmentID: request.manifest.id,
            engine: engine,
            status: .extracted,
            capabilitiesUsed: request.requestedCapabilities,
            startedAt: Date(),
            completedAt: Date()
        )
        return AttachmentExtractionResult(report: report, extractedMarkdown: markdown, previewText: markdown)
    }
}
