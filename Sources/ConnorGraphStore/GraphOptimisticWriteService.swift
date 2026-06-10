import Foundation
import ConnorGraphCore
import ConnorGraphMemory

public struct GraphRejectedStatement: Sendable, Equatable, Identifiable {
    public var id: String { statement.id }
    public var statement: GraphStatement
    public var errors: [GraphConstraintValidationError]

    public init(statement: GraphStatement, errors: [GraphConstraintValidationError]) {
        self.statement = statement
        self.errors = errors
    }
}

public struct GraphOptimisticWriteResult: Sendable, Equatable {
    public var committedEpisodeID: String?
    public var committedEntityIDs: [String]
    public var resolvedEntityIDs: [String: String]
    public var potentialDuplicateEntityIDs: [String: String]
    public var committedStatementIDs: [String]
    public var rejectedStatements: [GraphRejectedStatement]
    public var anomalyIDs: [String]
    public var jobIDs: [String]

    public init(
        committedEpisodeID: String? = nil,
        committedEntityIDs: [String] = [],
        resolvedEntityIDs: [String: String] = [:],
        potentialDuplicateEntityIDs: [String: String] = [:],
        committedStatementIDs: [String] = [],
        rejectedStatements: [GraphRejectedStatement] = [],
        anomalyIDs: [String] = [],
        jobIDs: [String] = []
    ) {
        self.committedEpisodeID = committedEpisodeID
        self.committedEntityIDs = committedEntityIDs
        self.resolvedEntityIDs = resolvedEntityIDs
        self.potentialDuplicateEntityIDs = potentialDuplicateEntityIDs
        self.committedStatementIDs = committedStatementIDs
        self.rejectedStatements = rejectedStatements
        self.anomalyIDs = anomalyIDs
        self.jobIDs = jobIDs
    }
}

public struct GraphOptimisticWriteService: Sendable {
    public var store: SQLiteGraphKernelStore
    public var validator: GraphConstraintValidator
    public var contradictionDetector: GraphContradictionDetector
    public var resolver: SQLiteGraphEntityResolver

    public init(store: SQLiteGraphKernelStore, validator: GraphConstraintValidator = GraphConstraintValidator(), contradictionDetector: GraphContradictionDetector = GraphContradictionDetector(), resolver: SQLiteGraphEntityResolver? = nil) {
        self.store = store
        self.validator = validator
        self.contradictionDetector = contradictionDetector
        self.resolver = resolver ?? SQLiteGraphEntityResolver(store: store)
    }

    public func commit(_ batch: GraphOptimisticWriteBatch) throws -> GraphOptimisticWriteResult {
        var result = GraphOptimisticWriteResult()
        var resolvedEntityIDByIncomingID: [String: String] = [:]

        if let episode = batch.episode {
            try store.upsert(episode: episode)
            result.committedEpisodeID = episode.id
        }

        for entity in batch.entities {
            let resolution = try resolver.resolve(name: entity.name, entityKind: entity.entityKind, scope: entity.scope, graphID: entity.graphID)
            switch resolution {
            case .matched(let existingID, _):
                resolvedEntityIDByIncomingID[entity.id] = existingID
                result.resolvedEntityIDs[entity.id] = existingID
            case .create:
                try store.upsert(entity: entity)
                resolvedEntityIDByIncomingID[entity.id] = entity.id
                result.committedEntityIDs.append(entity.id)
                let jobID = try enqueueIndexRefresh(graphID: batch.graphID, ownerType: .entity, ownerID: entity.id, now: batch.now)
                result.jobIDs.append(jobID)
            case .potentialDuplicate(let existingID, _):
                try store.upsert(entity: entity)
                resolvedEntityIDByIncomingID[entity.id] = entity.id
                result.committedEntityIDs.append(entity.id)
                result.potentialDuplicateEntityIDs[entity.id] = existingID
                let indexJobID = try enqueueIndexRefresh(graphID: batch.graphID, ownerType: .entity, ownerID: entity.id, now: batch.now)
                result.jobIDs.append(indexJobID)
                let mergeJobID = try enqueueEntityMergeReview(graphID: batch.graphID, incomingEntityID: entity.id, existingEntityID: existingID, now: batch.now)
                result.jobIDs.append(mergeJobID)
            }
        }

        for originalStatement in batch.statements {
            var statement = rewriteStatement(originalStatement, entityIDMap: resolvedEntityIDByIncomingID)
            let subject = try store.entity(id: statement.subjectEntityID)
            let object = try store.entity(id: statement.objectEntityID)
            let validation = validator.validate(statement: statement, subject: subject, object: object)
            if !validation.isValid {
                result.rejectedStatements.append(GraphRejectedStatement(statement: statement, errors: validation.errors))
                continue
            }

            let existing = try store.statements(graphID: batch.graphID, beliefStatus: .active)
            let conflicts = contradictionDetector.detect(incoming: statement, existingActiveStatements: existing)
            if !conflicts.isEmpty {
                statement.beliefStatus = .anomaly
                statement.confidence = max(0.0, statement.confidence * 0.5)
            }

            try store.upsert(statement: statement)
            result.committedStatementIDs.append(statement.id)
            let indexJobID = try enqueueIndexRefresh(graphID: batch.graphID, ownerType: .statement, ownerID: statement.id, now: batch.now)
            result.jobIDs.append(indexJobID)

            for conflict in conflicts {
                let anomaly = GraphAnomaly(
                    id: "anomaly-\(statement.id)-\(conflict.existingStatementID)",
                    graphID: batch.graphID,
                    anomalyType: conflict.type,
                    statementID: statement.id,
                    relatedStatementIDs: [conflict.existingStatementID],
                    severity: conflict.severity,
                    status: .open,
                    detectedAt: batch.now,
                    metadata: ["reason": conflict.reason]
                )
                try store.upsert(anomaly: anomaly)
                result.anomalyIDs.append(anomaly.id)
                let jobID = try enqueueAnomalyResolution(graphID: batch.graphID, anomalyID: anomaly.id, now: batch.now)
                result.jobIDs.append(jobID)
            }
        }

        return result
    }

    private func rewriteStatement(_ statement: GraphStatement, entityIDMap: [String: String]) -> GraphStatement {
        var rewritten = statement
        if let resolvedSubjectID = entityIDMap[statement.subjectEntityID] {
            rewritten.subjectEntityID = resolvedSubjectID
        }
        if let resolvedObjectID = entityIDMap[statement.objectEntityID] {
            rewritten.objectEntityID = resolvedObjectID
        }
        if rewritten.subjectEntityID != statement.subjectEntityID || rewritten.objectEntityID != statement.objectEntityID {
            rewritten.metadata["entity_resolution"] = "rewritten"
        }
        return rewritten
    }

    private func enqueueIndexRefresh(graphID: String, ownerType: GraphIndexOwnerType, ownerID: String, now: Date) throws -> String {
        let jobID = "job-index-\(ownerType.rawValue)-\(ownerID)"
        try store.upsert(job: GraphJobV3(
            id: jobID,
            graphID: graphID,
            type: .indexRefresh,
            status: .queued,
            priority: 1,
            payload: ["owner_type": ownerType.rawValue, "owner_id": ownerID],
            createdAt: now,
            updatedAt: now,
            nextRunAt: now
        ))
        return jobID
    }

    private func enqueueEntityMergeReview(graphID: String, incomingEntityID: String, existingEntityID: String, now: Date) throws -> String {
        let jobID = "job-entity-merge-review-\(incomingEntityID)-\(existingEntityID)"
        try store.upsert(job: GraphJobV3(
            id: jobID,
            graphID: graphID,
            type: .entityMergeReview,
            status: .queued,
            priority: 5,
            payload: ["incoming_entity_id": incomingEntityID, "existing_entity_id": existingEntityID],
            createdAt: now,
            updatedAt: now,
            nextRunAt: now
        ))
        return jobID
    }

    private func enqueueAnomalyResolution(graphID: String, anomalyID: String, now: Date) throws -> String {
        let jobID = "job-resolve-\(anomalyID)"
        try store.upsert(job: GraphJobV3(
            id: jobID,
            graphID: graphID,
            type: .anomalyResolution,
            status: .queued,
            priority: 10,
            payload: ["anomaly_id": anomalyID],
            createdAt: now,
            updatedAt: now,
            nextRunAt: now
        ))
        return jobID
    }
}
