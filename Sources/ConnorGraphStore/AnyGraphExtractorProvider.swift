import Foundation
import ConnorGraphCore

public struct AnyGraphExtractorProvider: GraphExtractorProvider, Sendable {
    private let extractHandler: @Sendable (GraphExtractionSource) async throws -> GraphExtractionDraft

    public init(_ extractHandler: @escaping @Sendable (GraphExtractionSource) async throws -> GraphExtractionDraft) {
        self.extractHandler = extractHandler
    }

    public init<Extractor: GraphExtractorProvider>(_ extractor: Extractor) {
        self.extractHandler = { source in
            try await extractor.extract(from: source)
        }
    }

    public func extract(from source: GraphExtractionSource) async throws -> GraphExtractionDraft {
        try await extractHandler(source)
    }
}
