import Foundation

public struct GraphExtractionDecodingResult: Sendable, Equatable {
    public var rawText: String
    public var normalizedJSON: String
    public var output: GraphStructuredExtractionOutput
    public var warnings: [String]

    public init(rawText: String, normalizedJSON: String, output: GraphStructuredExtractionOutput, warnings: [String] = []) {
        self.rawText = rawText
        self.normalizedJSON = normalizedJSON
        self.output = output
        self.warnings = warnings
    }
}

public enum GraphExtractionDecodingError: Error, Equatable, CustomStringConvertible {
    case emptyResponse
    case invalidJSON(String)
    case schemaViolation(String)

    public var description: String {
        switch self {
        case .emptyResponse:
            "emptyResponse"
        case .invalidJSON(let message):
            "invalidJSON: \(message)"
        case .schemaViolation(let message):
            "schemaViolation: \(message)"
        }
    }
}

public struct GraphExtractionDecoder: Sendable {
    public var requireStatementEvidence: Bool
    public var jsonDecoder: JSONDecoder

    public init(requireStatementEvidence: Bool = true, jsonDecoder: JSONDecoder? = nil) {
        self.requireStatementEvidence = requireStatementEvidence
        if let jsonDecoder {
            self.jsonDecoder = jsonDecoder
        } else {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            self.jsonDecoder = decoder
        }
    }

    public func normalizedJSONCandidate(from rawText: String) -> (json: String, warnings: [String])? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = normalizeJSON(from: trimmed)
        return (json: normalized.0, warnings: normalized.1)
    }

    public func decode(_ rawText: String) throws -> GraphExtractionDecodingResult {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GraphExtractionDecodingError.emptyResponse }

        let (json, warnings) = normalizeJSON(from: trimmed)
        guard let data = json.data(using: .utf8) else {
            throw GraphExtractionDecodingError.invalidJSON("response is not valid UTF-8")
        }

        do {
            let output = try jsonDecoder.decode(GraphStructuredExtractionOutput.self, from: data)
            do {
                try output.validate(requireStatementEvidence: requireStatementEvidence)
            } catch {
                throw GraphExtractionDecodingError.schemaViolation(String(describing: error))
            }
            return GraphExtractionDecodingResult(rawText: rawText, normalizedJSON: json, output: output, warnings: warnings)
        } catch let error as GraphExtractionDecodingError {
            throw error
        } catch {
            throw GraphExtractionDecodingError.invalidJSON(String(describing: error))
        }
    }

    private func normalizeJSON(from text: String) -> (String, [String]) {
        var warnings: [String] = []
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.hasPrefix("```") {
            let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if lines.count >= 2 {
                let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                let last = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if first == "```json" || first == "```" {
                    if last == "```" {
                        normalized = lines.dropFirst().dropLast().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                        warnings.append("stripped_markdown_code_fence")
                    }
                }
            }
        }

        return (normalized, warnings)
    }
}
