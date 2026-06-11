import Foundation
import ConnorGraphSearch

public enum AppGraphRetrievalEvaluationRepositoryError: Error, Equatable, CustomStringConvertible {
    case duplicateCaseID(String)
    case duplicateJudgmentID(caseID: String, judgmentID: String)
    case emptyJudgments(String)

    public var description: String {
        switch self {
        case .duplicateCaseID(let id):
            "duplicateCaseID: \(id)"
        case .duplicateJudgmentID(let caseID, let judgmentID):
            "duplicateJudgmentID: \(caseID)/\(judgmentID)"
        case .emptyJudgments(let id):
            "emptyJudgments: \(id)"
        }
    }
}

public struct AppGraphRetrievalEvaluationRepository {
    public var storagePaths: AppStoragePaths
    public var fileManager: FileManager
    public var encoder: JSONEncoder
    public var decoder: JSONDecoder

    public init(storagePaths: AppStoragePaths, fileManager: FileManager = .default) {
        self.storagePaths = storagePaths
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public var evaluationDirectory: URL {
        storagePaths.graphDirectory.appendingPathComponent("evaluations", isDirectory: true)
    }

    public var manifestURL: URL {
        evaluationDirectory.appendingPathComponent("retrieval-evaluation-cases.json")
    }

    public var reportsDirectory: URL {
        evaluationDirectory.appendingPathComponent("reports", isDirectory: true)
    }

    public func ensureDirectories() throws {
        try fileManager.createDirectory(at: evaluationDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
    }

    public func loadCases() throws -> [GraphRetrievalEvaluationCase] {
        try ensureDirectories()
        guard fileManager.fileExists(atPath: manifestURL.path) else { return [] }
        let data = try Data(contentsOf: manifestURL)
        return try decoder.decode([GraphRetrievalEvaluationCase].self, from: data)
    }

    public func saveCases(_ cases: [GraphRetrievalEvaluationCase]) throws {
        try ensureDirectories()
        try validate(cases)
        let data = try encoder.encode(cases)
        try data.write(to: manifestURL, options: [.atomic])
    }

    @discardableResult
    public func saveReport(_ report: GraphRetrievalEvaluationReport, filename: String? = nil) throws -> URL {
        try ensureDirectories()
        let resolvedFilename = filename ?? "retrieval-evaluation-report-\(Self.safeTimestamp(report.generatedAt)).json"
        let url = reportsDirectory.appendingPathComponent(resolvedFilename)
        let data = try encoder.encode(report)
        try data.write(to: url, options: [.atomic])
        return url
    }

    public func validate(_ cases: [GraphRetrievalEvaluationCase]) throws {
        var caseIDs: Set<String> = []
        for evaluationCase in cases {
            if !caseIDs.insert(evaluationCase.id).inserted {
                throw AppGraphRetrievalEvaluationRepositoryError.duplicateCaseID(evaluationCase.id)
            }
            guard !evaluationCase.judgments.isEmpty else {
                throw AppGraphRetrievalEvaluationRepositoryError.emptyJudgments(evaluationCase.id)
            }
            var judgmentIDs: Set<String> = []
            for judgment in evaluationCase.judgments {
                if !judgmentIDs.insert(judgment.id).inserted {
                    throw AppGraphRetrievalEvaluationRepositoryError.duplicateJudgmentID(caseID: evaluationCase.id, judgmentID: judgment.id)
                }
            }
        }
    }

    private static func safeTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }
}
