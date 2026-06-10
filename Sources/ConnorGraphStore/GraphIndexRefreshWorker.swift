import Foundation
import ConnorGraphCore

public enum GraphIndexRefreshAction: String, Sendable, Codable, Equatable {
    case refreshed
    case failed
    case skipped
}

public struct GraphIndexRefreshResult: Sendable, Equatable, Identifiable {
    public var id: String { jobID }
    public var jobID: String
    public var action: GraphIndexRefreshAction
    public var ownerType: GraphIndexOwnerType?
    public var ownerID: String?
    public var message: String

    public init(jobID: String, action: GraphIndexRefreshAction, ownerType: GraphIndexOwnerType? = nil, ownerID: String? = nil, message: String = "") {
        self.jobID = jobID
        self.action = action
        self.ownerType = ownerType
        self.ownerID = ownerID
        self.message = message
    }
}

public enum GraphIndexRefreshWorkerError: Error, Equatable, CustomStringConvertible {
    case invalidPayload(String)
    case missingOwner(GraphIndexOwnerType, String)

    public var description: String {
        switch self {
        case .invalidPayload(let key): "invalidPayload: \(key)"
        case .missingOwner(let type, let id): "missingOwner: \(type.rawValue)/\(id)"
        }
    }
}

public struct GraphIndexRefreshWorker: Sendable {
    public var store: SQLiteGraphKernelStore

    public init(store: SQLiteGraphKernelStore) {
        self.store = store
    }

    public func runNext(graphID: String, now: Date = Date()) throws -> GraphIndexRefreshResult? {
        guard let job = try store.runnableJobs(graphID: graphID, at: now, limit: 20).first(where: { $0.type == .indexRefresh }) else {
            return nil
        }
        return try run(job: job, now: now)
    }

    public func run(job: GraphJobV3, now: Date = Date()) throws -> GraphIndexRefreshResult {
        do {
            guard let ownerTypeRaw = job.payload["owner_type"], let ownerType = GraphIndexOwnerType(rawValue: ownerTypeRaw) else {
                throw GraphIndexRefreshWorkerError.invalidPayload("owner_type")
            }
            guard let ownerID = job.payload["owner_id"], !ownerID.isEmpty else {
                throw GraphIndexRefreshWorkerError.invalidPayload("owner_id")
            }
            try refresh(ownerType: ownerType, ownerID: ownerID)
            try mark(job: job, status: .succeeded, now: now)
            return GraphIndexRefreshResult(jobID: job.id, action: .refreshed, ownerType: ownerType, ownerID: ownerID, message: "Index refreshed")
        } catch {
            try mark(job: job, status: .failed, now: now, errorCode: "index_refresh_failed", errorMessage: String(describing: error))
            let ownerType = job.payload["owner_type"].flatMap(GraphIndexOwnerType.init(rawValue:))
            return GraphIndexRefreshResult(jobID: job.id, action: .failed, ownerType: ownerType, ownerID: job.payload["owner_id"], message: String(describing: error))
        }
    }

    private func refresh(ownerType: GraphIndexOwnerType, ownerID: String) throws {
        switch ownerType {
        case .entity:
            guard let entity = try store.entity(id: ownerID) else {
                throw GraphIndexRefreshWorkerError.missingOwner(ownerType, ownerID)
            }
            try store.upsert(entity: entity)
        case .statement:
            guard let statement = try store.statement(id: ownerID) else {
                throw GraphIndexRefreshWorkerError.missingOwner(ownerType, ownerID)
            }
            try store.upsert(statement: statement)
        case .episode:
            guard let episode = try store.episode(id: ownerID) else {
                throw GraphIndexRefreshWorkerError.missingOwner(ownerType, ownerID)
            }
            try store.upsert(episode: episode)
        }
    }

    private func mark(job: GraphJobV3, status: GraphJobV3Status, now: Date, errorCode: String? = nil, errorMessage: String? = nil) throws {
        var updated = job
        updated.status = status
        updated.updatedAt = now
        updated.finishedAt = now
        updated.errorCode = errorCode
        updated.errorMessage = errorMessage
        try store.upsert(job: updated)
    }
}
