import Foundation

public enum BrowserAssistedTaskKind: String, Codable, Equatable, Sendable {
    case search
}

public enum BrowserAssistedTaskVisibility: String, Codable, Equatable, Sendable {
    case background
    case foreground
}

public enum BrowserAssistedTaskStatus: String, Codable, Equatable, Sendable {
    case running
    case awaitingUserIntervention
    case completed
    case failed
}

public struct BrowserAssistedTaskRequest: Equatable, Sendable {
    public var id: UUID
    public var kind: BrowserAssistedTaskKind
    public var sessionID: String
    public var urlString: String
    public var title: String
    public var visibility: BrowserAssistedTaskVisibility

    public init(
        id: UUID = UUID(),
        kind: BrowserAssistedTaskKind,
        sessionID: String,
        urlString: String,
        title: String,
        visibility: BrowserAssistedTaskVisibility = .background
    ) {
        self.id = id
        self.kind = kind
        self.sessionID = sessionID
        self.urlString = urlString
        self.title = title
        self.visibility = visibility
    }
}

public struct BrowserAssistedTaskState: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: BrowserAssistedTaskKind
    public var sessionID: String
    public var tabID: UUID
    public var urlString: String
    public var title: String
    public var status: BrowserAssistedTaskStatus
    public var statusMessage: String
    public var updatedAt: Date

    public init(
        id: UUID,
        kind: BrowserAssistedTaskKind,
        sessionID: String,
        tabID: UUID,
        urlString: String,
        title: String,
        status: BrowserAssistedTaskStatus = .running,
        statusMessage: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.sessionID = sessionID
        self.tabID = tabID
        self.urlString = urlString
        self.title = title
        self.status = status
        self.statusMessage = statusMessage
        self.updatedAt = updatedAt
    }
}

public struct BrowserAssistedTaskPlan: Equatable, Sendable {
    public var snapshot: AppBrowserStateSnapshot
    public var task: BrowserAssistedTaskState
    public var shouldRevealBrowser: Bool

    public init(snapshot: AppBrowserStateSnapshot, task: BrowserAssistedTaskState, shouldRevealBrowser: Bool) {
        self.snapshot = snapshot
        self.task = task
        self.shouldRevealBrowser = shouldRevealBrowser
    }
}

public struct BrowserAssistedTaskPlanner: Sendable {
    public init() {}

    public func start(_ request: BrowserAssistedTaskRequest, in snapshot: AppBrowserStateSnapshot, now: Date = Date()) -> BrowserAssistedTaskPlan {
        var planned = snapshot
        planned.updatedAt = now
        planned.selectionPopover = nil

        let tab = AppBrowserTabSnapshot(
            initialURLString: request.urlString,
            title: request.title,
            currentURLString: request.urlString,
            isLoading: true,
            canGoBack: false,
            canGoForward: false
        )
        planned.tabs.append(tab)
        planned.selectedTabID = tab.id

        let task = BrowserAssistedTaskState(
            id: request.id,
            kind: request.kind,
            sessionID: request.sessionID,
            tabID: tab.id,
            urlString: request.urlString,
            title: request.title,
            status: .running,
            statusMessage: "Running in background",
            updatedAt: now
        )

        return BrowserAssistedTaskPlan(
            snapshot: planned,
            task: task,
            shouldRevealBrowser: request.visibility == .foreground
        )
    }

    public func requireUserIntervention(_ task: BrowserAssistedTaskState, reason: String, now: Date = Date()) -> BrowserAssistedTaskState {
        var updated = task
        updated.status = .awaitingUserIntervention
        updated.statusMessage = reason
        updated.updatedAt = now
        return updated
    }

    public func complete(_ task: BrowserAssistedTaskState, message: String = "Completed in background", now: Date = Date()) -> BrowserAssistedTaskState {
        var updated = task
        updated.status = .completed
        updated.statusMessage = message
        updated.updatedAt = now
        return updated
    }

    public func fail(_ task: BrowserAssistedTaskState, message: String, now: Date = Date()) -> BrowserAssistedTaskState {
        var updated = task
        updated.status = .failed
        updated.statusMessage = message
        updated.updatedAt = now
        return updated
    }
}

public struct BrowserAssistedInterventionDetector: Sendable {
    public init() {}

    public func interventionReason(urlString: String, title: String, errorMessage: String? = nil) -> String? {
        let haystack = [urlString, title, errorMessage ?? ""]
            .joined(separator: " ")
            .lowercased()

        let markers = [
            "captcha",
            "recaptcha",
            "hcaptcha",
            "human verification",
            "verify you are human",
            "unusual traffic",
            "security check",
            "are you a robot",
            "robot check",
            "challenge",
            "cf-challenge",
            "cloudflare"
        ]

        guard markers.contains(where: { haystack.contains($0) }) else { return nil }
        return "Browser-assisted search needs user action: verification challenge detected."
    }
}
