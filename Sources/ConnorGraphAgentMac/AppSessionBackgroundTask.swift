import Foundation
import ConnorGraphAppSupport
import ConnorGraphStore

enum AppSessionBackgroundTaskStatus: String, Codable, Equatable, Sendable {
    case queued
    case running
    case succeeded
    case failed
    case interrupted

    var displayName: String {
        switch self {
        case .queued: "排队中"
        case .running: "运行中"
        case .succeeded: "已完成"
        case .failed: "失败"
        case .interrupted: "已中断"
        }
    }

    var systemImage: String {
        switch self {
        case .queued: "clock"
        case .running: "arrow.triangle.2.circlepath"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .interrupted: "pause.circle.fill"
        }
    }
}

struct AppSessionBackgroundTask: Identifiable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var sessionID: String
    var kind: String = "generic"
    var title: String
    var detail: String
    var status: AppSessionBackgroundTaskStatus = .queued
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var errorMessage: String?
    var payloadJSON: String = "{}"

    init(
        id: String = UUID().uuidString,
        sessionID: String,
        kind: String = "generic",
        title: String,
        detail: String,
        status: AppSessionBackgroundTaskStatus = .queued,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        errorMessage: String? = nil,
        payloadJSON: String = "{}"
    ) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.title = title
        self.detail = detail
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.errorMessage = errorMessage
        self.payloadJSON = payloadJSON
    }

    init(persisted task: PersistedSessionBackgroundTask) {
        self.init(
            id: task.id,
            sessionID: task.sessionID,
            kind: task.kind,
            title: task.title,
            detail: task.detail,
            status: AppSessionBackgroundTaskStatus(persisted: task.status),
            createdAt: task.createdAt,
            updatedAt: task.updatedAt,
            errorMessage: task.errorMessage,
            payloadJSON: task.payloadJSON
        )
    }

    var persisted: PersistedSessionBackgroundTask {
        PersistedSessionBackgroundTask(
            id: id,
            sessionID: sessionID,
            kind: kind,
            title: title,
            detail: detail,
            status: status.persisted,
            createdAt: createdAt,
            updatedAt: updatedAt,
            errorMessage: errorMessage,
            payloadJSON: payloadJSON
        )
    }
}

private extension AppSessionBackgroundTaskStatus {
    init(persisted status: PersistedSessionBackgroundTaskStatus) {
        switch status {
        case .queued: self = .queued
        case .running: self = .running
        case .succeeded: self = .succeeded
        case .failed: self = .failed
        case .interrupted: self = .interrupted
        }
    }

    var persisted: PersistedSessionBackgroundTaskStatus {
        switch self {
        case .queued: .queued
        case .running: .running
        case .succeeded: .succeeded
        case .failed: .failed
        case .interrupted: .interrupted
        }
    }
}
