import Foundation

public protocol EmbeddingProvider: Sendable {
    var model: String { get }
    var dimensions: Int { get }

    func embedding(for text: String) async throws -> [Double]
}
