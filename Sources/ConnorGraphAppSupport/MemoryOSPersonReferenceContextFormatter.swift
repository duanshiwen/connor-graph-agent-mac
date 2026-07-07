import Foundation
import ConnorGraphCore

public struct MemoryOSPersonReferenceContextFormatter: Sendable {
    public init() {}

    public func content(_ content: String, personReferences: [PersonReference]) -> String {
        let block = contextBlock(personReferences: personReferences)
        guard !block.isEmpty else { return content }
        return [block, content]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    public func metadata(personReferences: [PersonReference]) -> [String: String] {
        guard !personReferences.isEmpty else { return [:] }
        var metadata: [String: String] = [
            "person_reference_ids": personReferences.map(\.personID.rawValue).joined(separator: ","),
            "person_reference_count": "\(personReferences.count)"
        ]
        if let json = encodedReferences(personReferences) {
            metadata["person_references_json"] = json
        }
        return metadata
    }

    private func contextBlock(personReferences: [PersonReference]) -> String {
        guard !personReferences.isEmpty else { return "" }
        var lines: [String] = [
            "Referenced People in Chat Message:",
            "These structured references were selected in Composer and should be used as person identity anchors during Memory OS extraction."
        ]
        for reference in personReferences {
            lines.append("- mention: \(reference.mentionText)")
            lines.append("  type: person")
            lines.append("  person_id: \(reference.personID.rawValue)")
            lines.append("  display_name: \(reference.displayName)")
            if let status = reference.status {
                lines.append("  status: \(status.rawValue)")
            }
            if let mergedIntoID = reference.mergedIntoID {
                lines.append("  merged_into_person_id: \(mergedIntoID.rawValue)")
            }
            if let memoryEntityID = reference.memoryEntityID {
                lines.append("  memory_entity_id: \(memoryEntityID)")
            }
            if let memoryStableKey = reference.memoryStableKey {
                lines.append("  memory_stable_key: \(memoryStableKey)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func encodedReferences(_ personReferences: [PersonReference]) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(personReferences) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
