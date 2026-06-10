import Foundation
import ConnorGraphCore

public struct SQLiteGraphReasoner: Sendable {
    public var store: SQLiteGraphKernelStore

    public init(store: SQLiteGraphKernelStore) {
        self.store = store
    }

    public func inferredInstanceOf(entityID: String, graphID: String, generatedAt: Date = Date()) throws -> [GraphInferredStatement] {
        let directInstanceStatements = try store.statements(graphID: graphID, predicate: .instanceOf)
            .filter { $0.subjectEntityID == entityID }
        let subclassStatements = try store.statements(graphID: graphID, predicate: .subclassOf)

        var subclassBySubject: [String: [GraphStatement]] = [:]
        for statement in subclassStatements {
            subclassBySubject[statement.subjectEntityID, default: []].append(statement)
        }

        var results: [GraphInferredStatement] = []
        var seenTargets: Set<String> = []

        for direct in directInstanceStatements {
            var stack: [(classID: String, path: [GraphStatement], confidence: Double)] = [(direct.objectEntityID, [direct], direct.confidence)]
            var visited: Set<String> = [direct.objectEntityID]

            while let current = stack.popLast() {
                for subclass in subclassBySubject[current.classID] ?? [] {
                    guard !visited.contains(subclass.objectEntityID) else { continue }
                    visited.insert(subclass.objectEntityID)
                    let path = current.path + [subclass]
                    let confidence = current.confidence * subclass.confidence * 0.95
                    if !seenTargets.contains(subclass.objectEntityID) {
                        seenTargets.insert(subclass.objectEntityID)
                        results.append(GraphInferredStatement(
                            subjectEntityID: entityID,
                            predicate: .instanceOf,
                            objectEntityID: subclass.objectEntityID,
                            confidence: confidence,
                            inferencePath: path.map(\.id),
                            generatedAt: generatedAt
                        ))
                    }
                    stack.append((subclass.objectEntityID, path, confidence))
                }
            }
        }

        return results.sorted { lhs, rhs in
            if lhs.confidence == rhs.confidence { return lhs.objectEntityID < rhs.objectEntityID }
            return lhs.confidence > rhs.confidence
        }
    }
}
