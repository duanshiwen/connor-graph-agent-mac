import Foundation

public struct MemoryOSL2FindEntitiesRequest: Codable, Sendable, Equatable {
    public var names: String

    public init(names: String) {
        self.names = names
    }
}

public struct MemoryOSL2FindEntitiesResult: Codable, Sendable, Equatable {
    public var searchedNames: [String]
    public var matches: [MemoryOSL2EntityMemoryView]
    public var message: String

    public init(searchedNames: [String], matches: [MemoryOSL2EntityMemoryView], message: String) {
        self.searchedNames = searchedNames
        self.matches = matches
        self.message = message
    }
}

public struct MemoryOSL2EntityMemoryView: Codable, Sendable, Equatable {
    public var name: String
    public var aliases: String
    public var type: String
    public var summary: String
    public var statements: [MemoryOSL2StatementMemoryView]

    public init(name: String, aliases: String = "", type: String = "entity", summary: String = "", statements: [MemoryOSL2StatementMemoryView] = []) {
        self.name = name
        self.aliases = aliases
        self.type = type
        self.summary = summary
        self.statements = statements
    }
}

public struct MemoryOSL2StatementMemoryView: Codable, Sendable, Equatable {
    public var text: String
    public var relation: String
    public var connectedEntity: String?

    public init(text: String, relation: String = "RELATED_TO", connectedEntity: String? = nil) {
        self.text = text
        self.relation = relation
        self.connectedEntity = connectedEntity
    }
}

public struct MemoryOSL2UpdateEntitiesRequest: Codable, Sendable, Equatable {
    public var entities: [MemoryOSL2EntityUpdate]

    public init(entities: [MemoryOSL2EntityUpdate]) {
        self.entities = entities
    }
}

public struct MemoryOSL2EntityUpdate: Codable, Sendable, Equatable {
    public var name: String
    public var type: String?
    public var aliases: String?
    public var summary: String?
    public var statements: [MemoryOSL2StatementUpdate]

    public init(name: String, type: String? = nil, aliases: String? = nil, summary: String? = nil, statements: [MemoryOSL2StatementUpdate] = []) {
        self.name = name
        self.type = type
        self.aliases = aliases
        self.summary = summary
        self.statements = statements
    }
}

public struct MemoryOSL2StatementUpdate: Codable, Sendable, Equatable {
    public var text: String
    public var relation: String?
    public var connectedEntity: String?
    public var connectedEntityType: String?
    public var factType: String?
    public var polarity: String?
    public var originalPhrase: String?

    public init(text: String, relation: String? = nil, connectedEntity: String? = nil, connectedEntityType: String? = nil, factType: String? = nil, polarity: String? = nil, originalPhrase: String? = nil) {
        self.text = text
        self.relation = relation
        self.connectedEntity = connectedEntity
        self.connectedEntityType = connectedEntityType
        self.factType = factType
        self.polarity = polarity
        self.originalPhrase = originalPhrase
    }
}

public struct MemoryOSL2UpdateEntitiesResult: Codable, Sendable, Equatable {
    public var accepted: Bool
    public var updatedEntities: [MemoryOSL2UpdatedEntitySummary]
    public var message: String

    public init(accepted: Bool, updatedEntities: [MemoryOSL2UpdatedEntitySummary], message: String) {
        self.accepted = accepted
        self.updatedEntities = updatedEntities
        self.message = message
    }
}

public struct MemoryOSL2UpdatedEntitySummary: Codable, Sendable, Equatable {
    public var name: String
    public var action: String
    public var statementActions: [MemoryOSL2StatementActionSummary]

    public init(name: String, action: String, statementActions: [MemoryOSL2StatementActionSummary]) {
        self.name = name
        self.action = action
        self.statementActions = statementActions
    }
}

public struct MemoryOSL2StatementActionSummary: Codable, Sendable, Equatable {
    public var text: String
    public var action: String

    public init(text: String, action: String) {
        self.text = text
        self.action = action
    }
}

public struct MemoryOSL2StoredEntity: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var type: String
    public var aliases: [String]
    public var summary: String
    public var statements: [MemoryOSL2StoredStatement]

    public init(id: String = UUID().uuidString, name: String, type: String = "entity", aliases: [String] = [], summary: String = "", statements: [MemoryOSL2StoredStatement] = []) {
        self.id = id
        self.name = name
        self.type = type
        self.aliases = aliases
        self.summary = summary
        self.statements = statements
    }
}

public struct MemoryOSL2StoredStatement: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var text: String
    public var relation: String
    public var connectedEntityName: String?
    public var metadata: [String: String]

    public init(id: String = UUID().uuidString, text: String, relation: String = "RELATED_TO", connectedEntityName: String? = nil, metadata: [String: String] = [:]) {
        self.id = id
        self.text = text
        self.relation = relation
        self.connectedEntityName = connectedEntityName
        self.metadata = metadata
    }
}

public protocol MemoryOSL2EntityMemoryRepository: AnyObject, Sendable {
    func findEntities(matchingNames names: [String]) throws -> [MemoryOSL2StoredEntity]
    func upsertEntity(_ update: MemoryOSL2EntityUpdate, aliases: [String]) throws -> (entity: MemoryOSL2StoredEntity, action: String)
    func appendStatement(_ statement: MemoryOSL2StatementUpdate, to entity: MemoryOSL2StoredEntity) throws -> MemoryOSL2StatementActionSummary
}

public final class MemoryOSL2EntityMemoryService: Sendable {
    private let repository: MemoryOSL2EntityMemoryRepository

    public init(repository: MemoryOSL2EntityMemoryRepository) {
        self.repository = repository
    }

    public static func splitNames(_ names: String) -> [String] {
        names
            .split { character in
                character == "," || character == "，" || character == "、" || character == ";" || character == "；" || character == "\n" || character == "\r"
            }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: []) { result, name in
                if !result.contains(name) { result.append(name) }
            }
    }

    public func findEntities(_ request: MemoryOSL2FindEntitiesRequest) throws -> MemoryOSL2FindEntitiesResult {
        let names = Self.splitNames(request.names)
        let entities = try repository.findEntities(matchingNames: names)
        let views = entities.map { entity in
            MemoryOSL2EntityMemoryView(
                name: entity.name,
                aliases: entity.aliases.joined(separator: ", "),
                type: entity.type,
                summary: entity.summary,
                statements: entity.statements.map { statement in
                    MemoryOSL2StatementMemoryView(text: statement.text, relation: statement.relation, connectedEntity: statement.connectedEntityName)
                }
            )
        }
        let message = views.isEmpty ? "No exact L2 entity match found by name or alias. Try likely aliases or original names." : "Found exact L2 matches by name or alias."
        return MemoryOSL2FindEntitiesResult(searchedNames: names, matches: views, message: message)
    }

    public func updateEntities(_ request: MemoryOSL2UpdateEntitiesRequest) throws -> MemoryOSL2UpdateEntitiesResult {
        var updated: [MemoryOSL2UpdatedEntitySummary] = []
        for update in request.entities {
            let aliases = Self.splitNames(update.aliases ?? "")
            let upsert = try repository.upsertEntity(update, aliases: aliases)
            let statementActions = try update.statements.map { statement in
                try repository.appendStatement(statement, to: upsert.entity)
            }
            updated.append(MemoryOSL2UpdatedEntitySummary(name: upsert.entity.name, action: upsert.action, statementActions: statementActions))
        }
        return MemoryOSL2UpdateEntitiesResult(accepted: true, updatedEntities: updated, message: "Updated L2 entities and statements.")
    }
}

public final class InMemoryMemoryOSL2EntityMemoryRepository: MemoryOSL2EntityMemoryRepository, @unchecked Sendable {
    private var entitiesByID: [String: MemoryOSL2StoredEntity]

    public init(entities: [MemoryOSL2StoredEntity] = []) {
        self.entitiesByID = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })
    }

    public func findEntities(matchingNames names: [String]) throws -> [MemoryOSL2StoredEntity] {
        let wanted = Set(names.map(Self.normalize))
        return entitiesByID.values
            .filter { entity in
                wanted.contains(Self.normalize(entity.name)) || entity.aliases.contains { wanted.contains(Self.normalize($0)) }
            }
            .sorted { $0.name < $1.name }
    }

    public func upsertEntity(_ update: MemoryOSL2EntityUpdate, aliases: [String]) throws -> (entity: MemoryOSL2StoredEntity, action: String) {
        let name = update.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = try findEntities(matchingNames: [name] + aliases)
        if var existing = matches.first {
            let mergedAliases = merge(existing.aliases, aliases)
            existing.aliases = mergedAliases
            if let type = update.type?.trimmingCharacters(in: .whitespacesAndNewlines), !type.isEmpty { existing.type = type }
            if let summary = update.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty { existing.summary = summary }
            entitiesByID[existing.id] = existing
            return (existing, "updated")
        }
        let entity = MemoryOSL2StoredEntity(name: name, type: update.type?.nilIfBlank ?? "entity", aliases: aliases, summary: update.summary?.nilIfBlank ?? "")
        entitiesByID[entity.id] = entity
        return (entity, "created")
    }

    public func appendStatement(_ statement: MemoryOSL2StatementUpdate, to entity: MemoryOSL2StoredEntity) throws -> MemoryOSL2StatementActionSummary {
        guard var current = entitiesByID[entity.id] else {
            return MemoryOSL2StatementActionSummary(text: statement.text, action: "missing_entity")
        }
        let text = statement.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.statements.contains(where: { $0.text == text }) {
            return MemoryOSL2StatementActionSummary(text: text, action: "skipped_duplicate")
        }
        let metadata = [
            "factType": statement.factType,
            "polarity": statement.polarity,
            "originalPhrase": statement.originalPhrase
        ].compactMapValues { $0?.nilIfBlank }
        current.statements.append(MemoryOSL2StoredStatement(text: text, relation: statement.relation?.nilIfBlank ?? "RELATED_TO", connectedEntityName: statement.connectedEntity?.nilIfBlank, metadata: metadata))
        entitiesByID[current.id] = current
        if let connectedName = statement.connectedEntity?.nilIfBlank {
            _ = try upsertEntity(MemoryOSL2EntityUpdate(name: connectedName, type: statement.connectedEntityType, aliases: nil, summary: nil, statements: []), aliases: [])
        }
        return MemoryOSL2StatementActionSummary(text: text, action: "added")
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func merge(_ lhs: [String], _ rhs: [String]) -> [String] {
        (lhs + rhs).reduce(into: []) { result, alias in
            if !result.contains(where: { Self.normalize($0) == Self.normalize(alias) }) {
                result.append(alias)
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
