import Foundation
import ConnorGraphCore
import ConnorGraphMemory

public struct GraphOptimisticWriteBatch: Sendable, Equatable {
    public var graphID: String
    public var episode: GraphEpisodeV3?
    public var entities: [GraphEntity]
    public var statements: [GraphStatement]
    public var now: Date

    public init(graphID: String, episode: GraphEpisodeV3? = nil, entities: [GraphEntity] = [], statements: [GraphStatement] = [], now: Date = Date()) {
        self.graphID = graphID
        self.episode = episode
        self.entities = entities
        self.statements = statements
        self.now = now
    }
}

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
    public var committedStatementIDs: [String]
    public var rejectedStatements: [GraphRejectedStatement]
    public var anomalyIDs: [String]
    public var jobIDs: [String]

    public init(committedEpisodeID: String? = nil, committedEntityIDs: [String] = [], committedStatementIDs: [String] = [], rejectedStatements: [GraphRejectedStatement] = [], anomalyIDs: [String] = [], jobIDs: [String] = []) {
        self.committedEpisodeID = committedEpisodeID
        self.committedEntityIDs = committedEntityIDs
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

    public init(store: SQLiteGraphKernelStore, validator: GraphConstraintValidator = GraphConstraintValidator(), contradictionDetector: GraphContradictionDetector = GraphContradictionDetector()) {
        self.store = store
        self.validator = validator
        self.contradictionDetector = contradictionDetector
    }

    public func commit(_ batch: GraphOptimisticWriteBatch) throws -> GraphOptimisticWriteResult {
        var result = GraphOptimisticWriteResult()

        if let episode = batch.episode {
            try store.upsert(episode: episode)
            result.committedEpisodeID = episode.id
        }

        for entity in batch.entities {
            try store.upsert(entity: entity)
            result.committedEntityIDs.append(entity.id)
            let jobID = try enqueueIndexRefresh(graphID: batch.graphID, ownerType: .entity, ownerID: entity.id, now: batch.now)
            result.jobIDs.append(jobID)
        }

        for originalStatement in batch.statements {
            let subject = try store.entity(id: originalStatement.subjectEntityID)
            let object = try store.entity(id: originalStatement.objectEntityID)
            let validation = validator.validate(statement: originalStatement, subject: subject, object: object)
            if !validation.isValid {
                result.rejectedStatements.append(GraphRejectedStatement(statement: originalStatement, errors: validation.errors))
                continue
            }

            let existing = try store.statements(graphID: batch.graphID, beliefStatus: .active)
            let conflicts = contradictionDetector.detect(incoming: originalStatement, existingActiveStatements: existing)
            var statement = originalStatement
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
