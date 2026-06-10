import Foundation
import ConnorGraphCore

/// A stub extractor that returns an empty draft (no extracted entities or statements).
/// Used for app integration where the extraction pipeline infrastructure is needed
/// but real LLM-backed extraction is not yet wired.
/// The episode is still stored via the optimistic write pipeline.
public struct StubGraphExtractor: GraphExtractorProvider, Sendable {
    public init() {}

    public func extract(from source: GraphExtractionSource) async throws -> GraphExtractionDraft {
        GraphExtractionDraft(source: source, entities: [], statements: [])
    }
}
