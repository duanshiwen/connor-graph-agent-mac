import CryptoKit
import Foundation
import ConnorGraphCore

public struct FoundationKGNodeRecord: Decodable, Sendable, Equatable {
    public var id: String
    public var kind: String
    public var package: String?
    public var labels: [String: String]
    public var descriptions: [String: String]
    public var aliases: [String: [String]]
    public var sitelinks: [String: String]
    public var salienceScore: Double?
    public var source: String?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case nodeKind = "node_kind"
        case package
        case labels
        case descriptions
        case aliases
        case sitelinks
        case salienceScore = "salience_score"
        case source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? container.decodeIfPresent(String.self, forKey: .nodeKind) ?? "entity"
        package = try container.decodeIfPresent(String.self, forKey: .package)
        labels = try container.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
        descriptions = try container.decodeIfPresent([String: String].self, forKey: .descriptions) ?? [:]
        aliases = try container.decodeIfPresent([String: [String]].self, forKey: .aliases) ?? [:]
        sitelinks = try container.decodeIfPresent([String: String].self, forKey: .sitelinks) ?? [:]
        salienceScore = try container.decodeIfPresent(Double.self, forKey: .salienceScore)
        source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    public init(id: String, kind: String, package: String? = nil, labels: [String: String] = [:], descriptions: [String: String] = [:], aliases: [String: [String]] = [:], sitelinks: [String: String] = [:], salienceScore: Double? = nil, source: String? = nil) {
        self.id = id
        self.kind = kind
        self.package = package
        self.labels = labels
        self.descriptions = descriptions
        self.aliases = aliases
        self.sitelinks = sitelinks
        self.salienceScore = salienceScore
        self.source = source
    }
}

public struct FoundationKGEdgeRecord: Decodable, Sendable, Equatable {
    public var sourceID: String
    public var predicate: String
    public var targetID: String?
    public var targetKind: String
    public var value: String?
    public var source: String?

    enum CodingKeys: String, CodingKey {
        case sourceID = "source_id"
        case predicate
        case targetID = "target_id"
        case target
        case targetKind = "target_kind"
        case value
        case source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceID = try container.decode(String.self, forKey: .sourceID)
        predicate = try container.decode(String.self, forKey: .predicate)
        targetKind = try container.decodeIfPresent(String.self, forKey: .targetKind) ?? "literal"
        let rawTargetID = try container.decodeIfPresent(String.self, forKey: .targetID)
        let rawTarget = try container.decodeIfPresent(String.self, forKey: .target)
        let rawValue = try container.decodeIfPresent(String.self, forKey: .value)
        if targetKind == "entity" {
            targetID = rawTargetID ?? rawTarget
            value = rawValue
        } else {
            targetID = rawTargetID
            value = rawValue ?? rawTarget
        }
        source = try container.decodeIfPresent(String.self, forKey: .source)
    }

    public init(sourceID: String, predicate: String, targetID: String? = nil, targetKind: String, value: String? = nil, source: String? = nil) {
        self.sourceID = sourceID
        self.predicate = predicate
        self.targetID = targetID
        self.targetKind = targetKind
        self.value = value
        self.source = source
    }
}

public struct FoundationKGExternalIDRecord: Decodable, Sendable, Equatable {
    public var nodeID: String
    public var property: String
    public var value: String
    public var source: String?

    enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case property
        case value
        case source
    }

    public init(nodeID: String, property: String, value: String, source: String? = nil) {
        self.nodeID = nodeID
        self.property = property
        self.value = value
        self.source = source
    }
}

public enum FoundationKGMemoryOSMapper {
    public static let builtinDatasetID = "foundation-kg-builtin-l4"
    public static let sourceVersion = "foundation_kg_v1"

    public static func namespacedEntityID(_ wikidataID: String) -> String { "wikidata:\(wikidataID)" }

    public static func mapEntity(_ node: FoundationKGNodeRecord, supplementalAliases: [String] = [], builtAt: Date = Date()) -> MemoryOSEntity {
        let name = preferredValue(node.labels) ?? node.id
        let summary = preferredValue(node.descriptions) ?? ""
        let aliases = mergedAliases(for: node, name: name, supplementalAliases: supplementalAliases)
        var metadata: [String: String] = [
            "builtin_dataset": builtinDatasetID,
            "source_kind": "foundation_kg",
            "source_name": "wikidata-lite",
            "source_version": sourceVersion,
            "wikidata_id": node.id,
            "foundation_kind": node.kind
        ]
        if let package = node.package { metadata["foundation_package"] = package }
        if let source = node.source { metadata["source"] = source }
        if let salienceScore = node.salienceScore { metadata["salience_score"] = String(salienceScore) }
        if !node.sitelinks.isEmpty { metadata["sitelinks_count"] = String(node.sitelinks.count) }

        return MemoryOSEntity(
            id: namespacedEntityID(node.id),
            stableKey: namespacedEntityID(node.id),
            entityType: entityType(for: node.kind),
            name: name,
            aliases: aliases,
            summary: summary,
            confidence: 0.9,
            createdAt: builtAt,
            updatedAt: builtAt,
            metadata: metadata
        )
    }

    public static func mapEdgeStatement(_ edge: FoundationKGEdgeRecord, sourceName: String, propertyName: String?, targetName: String?, targetExists: Bool, builtAt: Date = Date()) -> MemoryOSEntityStatement? {
        let targetValue = edge.targetID ?? edge.value
        guard let targetValue, !edge.sourceID.isEmpty else { return nil }
        let propertyDisplay = propertyName?.isEmpty == false ? propertyName! : edge.predicate
        let targetDisplay = targetName?.isEmpty == false ? targetName! : targetValue
        let objectEntityID = edge.targetKind == "entity" && targetExists ? namespacedEntityID(targetValue) : nil
        let resolution = edge.targetKind == "entity" ? (targetExists ? "resolved" : "unresolved") : "literal"
        let deterministicKey = "\(edge.sourceID)|\(edge.predicate)|\(edge.targetKind)|\(targetValue)"

        return MemoryOSEntityStatement(
            id: "foundation-kg:stmt:\(sha1(deterministicKey))",
            entityID: namespacedEntityID(edge.sourceID),
            predicate: l4Predicate(forWikidataProperty: edge.predicate, targetKind: edge.targetKind),
            objectEntityID: objectEntityID,
            text: "\(sourceName) -- \(propertyDisplay) --> \(targetDisplay)",
            assertionKind: .observed,
            confidence: 0.9,
            validAt: builtAt,
            committedAt: builtAt,
            metadata: [
                "builtin_dataset": builtinDatasetID,
                "source_kind": "foundation_kg",
                "source_name": "wikidata-lite",
                "source_version": sourceVersion,
                "statement_kind": "edge",
                "source_id": edge.sourceID,
                "predicate": edge.predicate,
                "target_kind": edge.targetKind,
                "target_value": targetValue,
                "target_resolution": resolution,
                "deterministic_key": deterministicKey
            ]
        )
    }

    public static func mapExternalIDStatement(_ externalID: FoundationKGExternalIDRecord, sourceName: String, propertyName: String?, builtAt: Date = Date()) -> MemoryOSEntityStatement {
        let propertyDisplay = propertyName?.isEmpty == false ? propertyName! : externalID.property
        let deterministicKey = "\(externalID.nodeID)|\(externalID.property)|\(externalID.value)"
        return MemoryOSEntityStatement(
            id: "foundation-kg:external:\(sha1(deterministicKey))",
            entityID: namespacedEntityID(externalID.nodeID),
            predicate: .sameAs,
            objectEntityID: nil,
            text: "\(sourceName) -- \(propertyDisplay) --> \(externalID.value)",
            assertionKind: .observed,
            confidence: 0.9,
            validAt: builtAt,
            committedAt: builtAt,
            metadata: [
                "builtin_dataset": builtinDatasetID,
                "source_kind": "foundation_kg",
                "source_name": "wikidata-lite",
                "source_version": sourceVersion,
                "statement_kind": "external_id",
                "source_id": externalID.nodeID,
                "predicate": externalID.property,
                "external_id_property": externalID.property,
                "external_id_value": externalID.value,
                "deterministic_key": deterministicKey
            ]
        )
    }

    private static func l4Predicate(forWikidataProperty property: String, targetKind: String) -> MemoryOSL4RelationPredicate {
        switch property {
        case "P31": return .instanceOf
        case "P279": return .subclassOf
        case "P361": return .partOf
        case "P527": return .hasPart
        case "P1382": return .overlapsWith
        case "P17", "P30", "P131", "P706": return .locatedIn
        case "P159", "P276", "P740": return .hasLocation
        case "P625": return .hasCoordinate
        case "P50": return .authoredBy
        case "P170": return .createdBy
        case "P176", "P178": return .developedBy
        case "P112": return .foundedBy
        case "P127": return .ownedBy
        case "P921": return .about
        case "P366": return .usedFor
        case "P101", "P106", "P425": return .fieldOfWork
        case "P452": return .inIndustry
        case "P856": return .hasOfficialWebsite
        case "P646", "P244", "P214", "P227", "P213", "P345", "P1709", "P2888": return .hasIdentifier
        case "P463": return .memberOf
        case "P460": return .saidToBeSameAs
        case "P461": return .oppositeOf
        case "P2579": return .studiedBy
        case "P1269": return .facetOf
        case "P155": return .supersedes
        case "P156": return .replaces
        case "P828": return .causes
        case "P1542": return .causes
        case "P1889": return .differentFrom
        default:
            if let predicate = MemoryOSL4RelationPredicate(rawValue: property) { return predicate }
            return targetKind == "entity" ? .relatedTo : .associatedWith
        }
    }

    private static func entityType(for kind: String) -> String {
        switch kind {
        case "class": "wikidata_class"
        case "property": "wikidata_property"
        default: "wikidata_entity"
        }
    }

    private static func preferredValue(_ values: [String: String]) -> String? {
        for language in ["zh", "zh-hans", "en", "zh-hant"] {
            if let value = values[language]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        }
        for key in values.keys.sorted() {
            if let value = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        }
        return nil
    }

    private static func mergedAliases(for node: FoundationKGNodeRecord, name: String, supplementalAliases: [String]) -> [String] {
        var seen: Set<String> = [name.lowercased()]
        var result: [String] = []
        func append(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let normalized = trimmed.lowercased()
            guard !seen.contains(normalized) else { return }
            seen.insert(normalized)
            result.append(trimmed)
        }
        for language in ["zh", "zh-hans", "en", "zh-hant"] {
            if let label = node.labels[language] { append(label) }
            for alias in node.aliases[language] ?? [] { append(alias) }
        }
        for key in node.labels.keys.sorted() { append(node.labels[key] ?? "") }
        for key in node.aliases.keys.sorted() {
            for alias in node.aliases[key] ?? [] { append(alias) }
        }
        for alias in supplementalAliases { append(alias) }
        append(node.id)
        return Array(result.prefix(64))
    }

    private static func sha1(_ value: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
