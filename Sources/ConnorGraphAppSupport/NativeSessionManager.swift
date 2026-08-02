import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphMemory

public protocol AgentPendingApprovalRepository: Sendable {
    func upsert(pendingApproval approval: AgentPendingApproval) throws
}

public enum NativeSessionManagerError: Error, Sendable, Equatable, LocalizedError {
    case noUserMessageToRetry
    case existingUserMessageNotFound(String)
    case runCancelled(String)

    public var errorDescription: String? {
        switch self {
        case .noUserMessageToRetry:
            "No user message is available to retry."
        case .existingUserMessageNotFound(let id):
            "The existing user message is unavailable: \(id)"
        case .runCancelled(let reason):
            reason
        }
    }
}

public struct NativeSessionRuntimeState: Codable, Sendable, Equatable {
    public var isProcessing: Bool
    public var activeRunID: String?
    public var queuedRunIDs: [String]
    public var lastRunID: String?
    public var lastStartedAt: Date?
    public var lastCompletedAt: Date?
    public var lastFailureMessage: String?
    public var cancellationReason: String?
    public var pendingApprovalCount: Int
    public var pendingPlanCount: Int

    public init(
        isProcessing: Bool = false,
        activeRunID: String? = nil,
        queuedRunIDs: [String] = [],
        lastRunID: String? = nil,
        lastStartedAt: Date? = nil,
        lastCompletedAt: Date? = nil,
        lastFailureMessage: String? = nil,
        cancellationReason: String? = nil,
        pendingApprovalCount: Int = 0,
        pendingPlanCount: Int = 0
    ) {
        self.isProcessing = isProcessing
        self.activeRunID = activeRunID
        self.queuedRunIDs = queuedRunIDs
        self.lastRunID = lastRunID
        self.lastStartedAt = lastStartedAt
        self.lastCompletedAt = lastCompletedAt
        self.lastFailureMessage = lastFailureMessage
        self.cancellationReason = cancellationReason
        self.pendingApprovalCount = pendingApprovalCount
        self.pendingPlanCount = pendingPlanCount
    }
}

public struct NativeSessionManager: Sendable {
    public var backend: AnyAgentBackend
    public var sessionRepository: AppChatSessionRepository
    public private(set) var session: AgentSession
    public private(set) var events: [AgentEvent]
    public private(set) var eventPresentations: [AgentEventPresentation]
    public private(set) var runtimeState: NativeSessionRuntimeState
    public var groupID: String
    public var permissionMode: AgentPermissionMode
    public var recentMessageLimit: Int

    // MARK: - Conversation Summary

    /// Maximum tokens available to the assembled model input after prompt and output limits.
    public var maximumInputTokens: Int
    public private(set) var conversationSummaryState: ConversationSummaryState?
    private let rollingSummaryProvider: AnyLLMProvider?
    private let rollingSummaryModelID: String?

    private let presenter: AgentEventPresenter
    private let memoryOSFacade: AppMemoryOSFacade?
    private let memoryOSIngestionWriter: MemoryOSIngestionWriter?
    private let eventRecorder: AgentEventRecorder?
    private let pendingApprovalRepository: (any AgentPendingApprovalRepository)?

    public init<Backend: AgentBackend>(
        backend: Backend,
        sessionRepository: AppChatSessionRepository,
        session: AgentSession = AgentSession(),
        groupID: String = "default",
        permissionMode: AgentPermissionMode = .askToWrite,
        recentMessageLimit: Int = .max,
        memoryOSFacade: AppMemoryOSFacade? = nil,
        memoryOSIntentNormalizer: AnyMemoryOSUserIntentNormalizer? = nil,
        eventRecorder: AgentEventRecorder? = nil,
        pendingApprovalRepository: (any AgentPendingApprovalRepository)? = nil,
        maximumInputTokens: Int = 64_000,
        conversationSummaryState: ConversationSummaryState? = nil,
        rollingSummaryProvider: AnyLLMProvider? = nil,
        rollingSummaryModelID: String? = nil
    ) {
        self.backend = AnyAgentBackend(backend)
        self.sessionRepository = sessionRepository
        self.session = session
        self.events = []
        self.eventPresentations = []
        self.runtimeState = NativeSessionRuntimeState()
        self.groupID = groupID
        self.permissionMode = permissionMode
        self.recentMessageLimit = recentMessageLimit
        self.presenter = AgentEventPresenter()
        self.memoryOSFacade = memoryOSFacade
        self.memoryOSIngestionWriter = memoryOSFacade.map { MemoryOSIngestionWriter(facade: $0, intentNormalizer: memoryOSIntentNormalizer) }
        self.eventRecorder = eventRecorder
        self.pendingApprovalRepository = pendingApprovalRepository
        self.maximumInputTokens = max(1, maximumInputTokens)
        self.conversationSummaryState = conversationSummaryState
        self.rollingSummaryProvider = rollingSummaryProvider
        self.rollingSummaryModelID = rollingSummaryModelID
    }

    public init<Provider: AgentModelProvider>(
        loopController: AgentLoopController<Provider>,
        sessionRepository: AppChatSessionRepository,
        session: AgentSession = AgentSession(),
        groupID: String = "default",
        memoryOSFacade: AppMemoryOSFacade? = nil
    ) {
        self.init(
            backend: AgentLoopBackend(loopController: loopController),
            sessionRepository: sessionRepository,
            session: session,
            groupID: groupID,
            permissionMode: loopController.configuration.permissionMode,
            memoryOSFacade: memoryOSFacade,
            memoryOSIntentNormalizer: AnyMemoryOSUserIntentNormalizer(MemoryOSUserIntentNormalizer(provider: AnyAgentModelProvider(loopController.modelProvider)))
        )
    }

    public func flushMemoryOSIngestion() async throws {
        try await memoryOSIngestionWriter?.flush()
    }

    @discardableResult
    public mutating func submit(_ prompt: String) async throws -> AgentLoopChatResponse {
        try await submit(prompt, sessionSummary: nil)
    }

    @discardableResult
    public mutating func submit(
        _ prompt: String,
        sessionSummary: AgentSessionSummary?,
        displayPrompt: String? = nil,
        attachments: [AgentMessageAttachmentRef] = [],
        attachmentContextPlan: AttachmentContextPlan = AttachmentContextPlan(),
        personReferences: [PersonReference] = [],
        explicitPersonContexts: [PersonContextSnapshot] = [],

        skillInstructions: String? = nil,
        activeSkillSlug: String? = nil,
        activeSkillDisplayName: String? = nil,
        existingUserMessageID: String? = nil,
        rehydratedHistoricalAttachmentIDs: Set<String> = [],
        onRunStarted: (@MainActor @Sendable (String) -> Void)? = nil,
        onAssistantMessageCreated: (@MainActor @Sendable (AgentMessage) -> Void)? = nil,
        onEventPresentation: (@MainActor @Sendable (AgentEventPresentation) -> Void)? = nil
    ) async throws -> AgentLoopChatResponse {
        let persistedSession = try? sessionRepository.loadSession(id: session.id)
        let persistedMessages = (persistedSession ?? session).messages
        let summaryRevisionBeforePreflight = conversationSummaryState?.revision
        await maybeUpdateRollingSummary(messages: persistedMessages)
        let didCompactBeforeRun = conversationSummaryState?.revision != summaryRevisionBeforePreflight
        let storedSummaryState = try? sessionRepository.loadConversationSummaryState(sessionID: session.id)
        let historySelection = ConversationSummaryHistorySelector().select(
            messages: persistedMessages,
            state: storedSummaryState ?? conversationSummaryState
        )
        conversationSummaryState = historySelection.summaryState
        let recentMessages = Array(historySelection.messages.suffix(max(0, recentMessageLimit)))
        let allowedAttachmentIDs = Set(recentMessages.flatMap(\.attachments).map(\.id) + attachments.map(\.id))
            .union(rehydratedHistoricalAttachmentIDs)
        let routedAttachmentContextPlan = attachmentContextPlan.filtered(allowedAttachmentIDs: allowedAttachmentIDs)
        let activeSkillContextSnapshot: String? = {
            let displayName = activeSkillDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let slug = activeSkillSlug?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !displayName.isEmpty || !slug.isEmpty else { return nil }
            return "Active skill: \(displayName.isEmpty ? slug : displayName)\(slug.isEmpty ? "" : " (\(slug))")"
        }()
        let userMessage: AgentMessage
        if let existingUserMessageID {
            guard let existing = session.messages.first(where: {
                $0.id == existingUserMessageID && $0.role == .user
            }) else {
                throw NativeSessionManagerError.existingUserMessageNotFound(existingUserMessageID)
            }
            userMessage = existing
        } else {
            let isFirstUserMessage = !session.messages.contains { $0.role == .user }
            userMessage = session.appendUserMessage(
                displayPrompt ?? prompt,
                attachments: attachments,
                personReferences: personReferences,
                contextSnapshot: activeSkillContextSnapshot
            )
            try persistSession()
            try await persistMemoryOSAfterUserMessage(userMessage, isFirstUserMessage: isFirstUserMessage)
        }

        let request = AgentChatRequest(
            sessionID: session.id,
            groupID: groupID,
            userMessage: prompt,
            currentUserMessageID: userMessage.id,
            sessionSummary: nil,
            recentMessages: recentMessages,
            permissionMode: permissionMode,
            attachmentRefs: attachments,
            attachmentContextPlan: routedAttachmentContextPlan,
            conversationSummaryState: conversationSummaryState,
            explicitPersonContexts: explicitPersonContexts,
            skillInstructions: skillInstructions,
            activeSkillSlug: activeSkillSlug,
            activeSkillDisplayName: activeSkillDisplayName,
            personReferences: personReferences
        )
        let now = Date()
        var runMetadata = [
            "user_message_id": userMessage.id,
            "queue": "single-session",
            "input_mode": existingUserMessageID == nil ? "appended_user_message" : "existing_user_message"
        ]
        if let activeSkillSlug, !activeSkillSlug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            runMetadata["active_skill_slug"] = activeSkillSlug
        }
        if let activeSkillDisplayName, !activeSkillDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            runMetadata["active_skill_display_name"] = activeSkillDisplayName
        }
        var run = AgentRun(
            id: request.runID,
            sessionID: session.id,
            groupID: groupID,
            status: .queued,
            startedAt: now,
            metadata: runMetadata
        )
        try sessionRepository.saveRun(run)
        defer { try? sessionRepository.deleteToolCallHistory(runID: run.id) }
        if eventRecorder == nil {
            try sessionRepository.appendJournalEvent(
                runID: run.id,
                sessionID: session.id,
                kind: .runStarted,
                action: existingUserMessageID == nil ? "message_persisted" : "existing_message_reused",
                message: existingUserMessageID == nil
                    ? "User message persisted before backend execution"
                    : "Existing user message reused for backend execution",
                metadata: ["message_id": userMessage.id]
            )
        }
        if eventRecorder == nil {
        try sessionRepository.appendJournalEvent(
                runID: run.id,
                sessionID: session.id,
                kind: .runStarted,
                action: "run_queued",
                message: "Session run queued",
                metadata: ["user_message_id": userMessage.id]
            )
        }
        runtimeState.queuedRunIDs.append(run.id)
        if let onRunStarted {
            await onRunStarted(run.id)
        }
        do {
            try throwIfRunCancelled(runID: run.id)
        } catch NativeSessionManagerError.runCancelled(let reason) {
            runtimeState.queuedRunIDs.removeAll { $0 == run.id }
            runtimeState.isProcessing = false
            runtimeState.activeRunID = nil
            runtimeState.lastRunID = run.id
            runtimeState.lastCompletedAt = Date()
            runtimeState.cancellationReason = reason
            _ = try await appendTerminationMessage(
                Self.terminationHandoffMessage(reason: reason),
                runID: run.id
            )
            throw NativeSessionManagerError.runCancelled(reason)
        }
        run.status = .running
        try sessionRepository.saveRun(run)
        if eventRecorder == nil {
        try sessionRepository.appendJournalEvent(
                runID: run.id,
                sessionID: session.id,
                kind: .runStarted,
                action: "run_started",
                message: "Session run started",
                metadata: ["user_message_id": userMessage.id]
            )
        }
        runtimeState.queuedRunIDs.removeAll { $0 == run.id }
        runtimeState.isProcessing = true
        runtimeState.activeRunID = request.runID
        runtimeState.lastRunID = request.runID
        runtimeState.lastStartedAt = now
        runtimeState.lastCompletedAt = nil
        runtimeState.lastFailureMessage = nil
        runtimeState.cancellationReason = nil

        var collectedEvents: [AgentEvent] = []
        var collectedPresentations: [AgentEventPresentation] = []
        var assistantMessage: AgentMessage?
        var generatedAttachmentRefs: [AgentMessageAttachmentRef] = []
        var promptInspectionSnapshot: AgentPromptInspectionSnapshot?

        do {
            for try await event in backend.chat(request) {
                try throwIfRunCancelled(runID: run.id)
                collectedEvents.append(event)
                events.append(event)

                try recordBackendEvent(event, sequence: collectedEvents.count - 1)
                try recordPendingApprovalIfNeeded(event)
                if case .permissionRequested = event {
                    runtimeState.pendingApprovalCount += 1
                    var waitingRun = run
                    waitingRun.status = .waitingForApproval
                    try sessionRepository.saveRun(waitingRun)
        if eventRecorder == nil {
                    try sessionRepository.appendJournalEvent(
                            runID: run.id,
                            sessionID: session.id,
                            kind: .permissionRequested,
                            action: "run_waiting_for_approval",
                            message: "Run is waiting for approval"
                        )
        }
                }

                let presentation = presenter.presentation(for: event)
                collectedPresentations.append(presentation)
                eventPresentations.append(presentation)
                if let onEventPresentation {
                    await onEventPresentation(presentation)
                }

                if case .promptAssembled(let payload) = event {
                    promptInspectionSnapshot = AgentPromptInspectionSnapshot(
                        includesSummary: payload.sections.contains { $0.id == "conversation" || $0.id == "memory" },
                        recentMessageCount: recentMessages.count,
                        currentRequest: prompt,
                        renderedPrompt: nil,
                        renderedPromptCharacterCount: 0,
                        estimatedPromptTokenCount: payload.totalEstimatedTokenCount,
                        promptBudgetStatus: AgentPromptBudgetEstimator().status(estimatedTokenCount: payload.totalEstimatedTokenCount)
                    )
                }

                if case .toolFinished(let result) = event,
                   let attachment = assistantImageAttachment(from: result, runID: run.id, sessionID: session.id),
                   !generatedAttachmentRefs.contains(where: { $0.id == attachment.id }) {
                    generatedAttachmentRefs.append(attachment)
                }

                if case .assistantMessageCreated(var message) = event,
                   !session.messages.contains(where: { $0.id == message.id }) {
                    message.runID = message.runID ?? run.id
                    message.sessionID = message.sessionID ?? session.id
                    session.appendAssistantMessage(message)
                    try persistSession()
                    if let onAssistantMessageCreated {
                        await onAssistantMessageCreated(message)
                    }
                }

                if case .textComplete(let payload) = event {
                    session.removeAssistantMessages(forRunID: run.id)
                    assistantMessage = session.appendAssistantMessage(
                        payload.text,
                        citations: payload.citations,
                        contextSnapshot: payload.contextSnapshot,
                        promptInspection: promptInspectionSnapshot,
                        attachments: generatedAttachmentRefs
                    )
                    if let messageID = assistantMessage?.id,
                       let index = session.messages.lastIndex(where: { $0.id == messageID }) {
                        session.messages[index].runID = run.id
                        session.messages[index].sessionID = session.id
                        assistantMessage = session.messages[index]
                    }
                    try persistSession()
                    if let assistantMessage {
                        try await persistMemoryOSAfterAssistantMessage(assistantMessage)
                    }
                }
            }

            try throwIfRunCancelled(runID: run.id)
            let runFailure = collectedEvents.compactMap { event -> AgentRunFailure? in
                if case .runFailed(let failure) = event { return failure }
                return nil
            }.last
            if assistantMessage == nil, let runFailure {
                assistantMessage = try await appendTerminationMessage(
                    Self.terminationHandoffMessage(reason: runFailure.message),
                    runID: run.id
                )
            }
            runtimeState.isProcessing = false
            runtimeState.activeRunID = nil
            runtimeState.lastCompletedAt = Date()
            var completedRun = run
            completedRun.status = runFailure == nil ? .completed : .failed
            completedRun.completedAt = runtimeState.lastCompletedAt
            if let runFailure {
                completedRun.metadata["failure"] = runFailure.message
                runtimeState.lastFailureMessage = runFailure.message
            }
            try sessionRepository.saveRun(completedRun)
        if eventRecorder == nil {
            try sessionRepository.appendJournalEvent(
                    runID: run.id,
                    sessionID: session.id,
                    kind: runFailure == nil ? .runCompleted : .runFailed,
                    action: runFailure == nil ? "run_completed" : "run_failed",
                    message: runFailure == nil ? "Session run completed" : (runFailure?.message ?? "Session run failed")
                )
        }
            if runFailure == nil, !didCompactBeforeRun {
                await maybeUpdateRollingSummary(messages: session.messages)
            }
            return AgentLoopChatResponse(
                session: session,
                events: collectedEvents,
                eventPresentations: collectedPresentations,
                assistantMessage: assistantMessage
            )
        } catch NativeSessionManagerError.runCancelled(let reason) {
            runtimeState.isProcessing = false
            runtimeState.activeRunID = nil
            runtimeState.lastCompletedAt = Date()
            runtimeState.cancellationReason = reason
            if var cancelledRun = try? sessionRepository.loadRun(id: run.id) {
                cancelledRun.status = .cancelled
                cancelledRun.completedAt = cancelledRun.completedAt ?? runtimeState.lastCompletedAt
                cancelledRun.metadata["cancellation_reason"] = cancelledRun.metadata["cancellation_reason"] ?? reason
                try? sessionRepository.saveRun(cancelledRun)
            }
            _ = try await appendTerminationMessage(
                Self.terminationHandoffMessage(reason: reason),
                runID: run.id
            )
            try persistSession()
            throw NativeSessionManagerError.runCancelled(reason)
        } catch {
            runtimeState.isProcessing = false
            runtimeState.activeRunID = nil
            runtimeState.lastCompletedAt = Date()
            runtimeState.lastFailureMessage = String(describing: error)
            if let existingRun = try? sessionRepository.loadRun(id: run.id), existingRun.status == .cancelled {
                let reason = existingRun.metadata["cancellation_reason"] ?? "cancelled by user"
                runtimeState.cancellationReason = reason
                _ = try await appendTerminationMessage(
                    Self.terminationHandoffMessage(reason: reason),
                    runID: run.id
                )
                try persistSession()
                throw NativeSessionManagerError.runCancelled(reason)
            }
            var failedRun = run
            failedRun.status = .failed
            failedRun.completedAt = runtimeState.lastCompletedAt
            failedRun.metadata["failure"] = String(describing: error)
            try sessionRepository.saveRun(failedRun)
        if eventRecorder == nil {
            try sessionRepository.appendJournalEvent(
                    runID: run.id,
                    sessionID: session.id,
                    kind: .runFailed,
                    action: "run_failed",
                    message: String(describing: error)
                )
        }
            // Connor owns session state. A backend failure must not roll back the user's input.
            _ = try await appendTerminationMessage(
                Self.terminationHandoffMessage(reason: String(describing: error)),
                runID: run.id
            )
            try persistSession()
            throw error
        }
    }

    @discardableResult
    public mutating func retryLastUserMessage() async throws -> AgentLoopChatResponse {
        guard let prompt = session.messages.last(where: { $0.role == .user })?.content else {
            throw NativeSessionManagerError.noUserMessageToRetry
        }
        return try await submit(prompt, sessionSummary: nil)
    }

    public mutating func cancelActiveRun(reason: String = "cancelled by user") {
        guard let runID = runtimeState.activeRunID else { return }
        cancel(runID: runID, reason: reason)
    }

    public mutating func cancel(runID: String, reason: String = "cancelled by user") {
        runtimeState.cancellationReason = reason
        runtimeState.queuedRunIDs.removeAll { $0 == runID }
        let completedAt = Date()
        if runtimeState.activeRunID == runID {
            runtimeState.isProcessing = false
            runtimeState.activeRunID = nil
            runtimeState.lastCompletedAt = completedAt
        }
        runtimeState.lastRunID = runID
        if var run = try? sessionRepository.loadRun(id: runID) {
            run.status = .cancelled
            run.completedAt = completedAt
            run.metadata["cancellation_reason"] = reason
            try? sessionRepository.saveRun(run)
            try? sessionRepository.appendJournalEvent(
                runID: runID,
                sessionID: run.sessionID,
                kind: .runFailed,
                action: "run_cancelled",
                message: reason
            )
        }
        backend.abort(runID: runID)
    }

    public mutating func hydrateRuntimeState(now: Date = Date()) throws -> SessionOSRestoreSnapshot {
        let snapshot = try sessionRepository.restoreSnapshot(sessionID: session.id, now: now)
        runtimeState.activeRunID = snapshot.activeRuns.first(where: { $0.status == .running || $0.status == .waitingForApproval })?.id
        runtimeState.queuedRunIDs = snapshot.activeRuns.filter { $0.status == .queued || $0.status == .pending }.map(\.id)
        runtimeState.isProcessing = runtimeState.activeRunID != nil
        runtimeState.pendingApprovalCount = snapshot.pendingApprovalCount
        runtimeState.pendingPlanCount = snapshot.pendingPlans.count
        runtimeState.lastRunID = runtimeState.activeRunID ?? runtimeState.queuedRunIDs.first ?? runtimeState.lastRunID
        return snapshot
    }

    private mutating func persistSession() throws {
        var sessionToPersist = session
        if let persisted = try sessionRepository.loadSession(id: session.id) {
            session.governance = persisted.governance
            session.readState = persisted.readState
            sessionToPersist.governance = persisted.governance
            sessionToPersist.readState = persisted.readState
            if let firstLoadedID = session.messages.first?.id,
               let firstLoadedIndex = persisted.messages.firstIndex(where: { $0.id == firstLoadedID }) {
                sessionToPersist.messages = Array(persisted.messages[..<firstLoadedIndex]) + session.messages
            } else if !persisted.messages.isEmpty, !session.messages.isEmpty {
                let currentIDs = Set(session.messages.map(\.id))
                sessionToPersist.messages = persisted.messages.filter { !currentIDs.contains($0.id) } + session.messages
            }
        }
        try sessionRepository.saveSession(sessionToPersist)
    }

    // MARK: - Conversation Summary

    private mutating func maybeUpdateRollingSummary(messages: [AgentMessage]) async {
        guard let provider = rollingSummaryProvider, let modelID = rollingSummaryModelID else { return }
        let conversation = messages.filter { $0.role == .user || $0.role == .assistant }

        do {
            let latestState = try sessionRepository.loadConversationSummaryState(sessionID: session.id) ?? conversationSummaryState
            let selection = ConversationSummaryHistorySelector().select(messages: conversation, state: latestState)
            let validState = selection.summaryState
            let liveTokenCount = SessionTokenCounter().estimate(messages: selection.messages).totalTokenCount
                + (validState?.summaryTokenEstimate ?? 0)
            let budget = SessionContextBudget(contextWindowSize: maximumInputTokens)
            guard budget.status(tokenCount: liveTokenCount) >= .shouldCompress else { return }
            let plan = try ConversationCompactionPlanner().plan(
                messages: conversation,
                existingState: validState,
                contextWindowTokens: maximumInputTokens
            )
            let maximumSummaryTokens = min(8_000, max(512, Int(Double(maximumInputTokens) * 0.05)))
            var summarizedAttachmentIDs = Set<String>()
            let attachmentDescriptions: [ConversationSummaryAttachment] = plan.deltaMessages.flatMap(\.attachments).compactMap { attachment in
                guard summarizedAttachmentIDs.insert(attachment.id).inserted else { return nil }
                return ConversationSummaryAttachment(
                    id: attachment.id,
                    displayName: attachment.displayName,
                    kind: attachment.kind,
                    description: attachment.previewText ?? "\(attachment.kind.rawValue) attachment, \(attachment.byteCount) bytes"
                )
            }
            let draft = try await RollingConversationSummarizer(
                provider: provider,
                modelID: modelID,
                maximumSummaryTokens: maximumSummaryTokens
            ).summarize(
                sessionID: session.id,
                plan: plan,
                attachmentDescriptions: attachmentDescriptions
            )
            guard try sessionRepository.commitConversationCompaction(
                state: draft.state,
                record: draft.record,
                expectedRevision: draft.expectedRevision
            ) else { return }
            conversationSummaryState = draft.state
        } catch RollingConversationSummaryError.noMessagesToCompact {
            return
        } catch {
            try? sessionRepository.appendJournalEvent(
                runID: UUID().uuidString,
                sessionID: session.id,
                kind: .runFailed,
                action: "conversation_summary_update_failed",
                message: String(describing: error)
            )
        }
    }

    @discardableResult
    private mutating func appendTerminationMessage(_ content: String, runID: String) async throws -> AgentMessage {
        if let last = session.messages.last,
           last.role == .assistant,
           last.content.hasPrefix("操作已终止：") {
            try persistSession()
            return last
        }
        let message = session.appendAssistantMessage(content)
        try persistSession()
        try await persistMemoryOSAfterAssistantMessage(message)
        return message
    }

    private static func terminationHandoffMessage(reason: String) -> String {
        """
        操作已终止：\(reason)

        已完成边界：本轮用户消息已保存，但未能确认整体任务完成。工具或外部状态可能已部分变化；继续前请重新检查相关持久状态。
        """
    }

    private func throwIfRunCancelled(runID: String) throws {
        guard let run = try? sessionRepository.loadRun(id: runID), run.status == .cancelled else { return }
        throw NativeSessionManagerError.runCancelled(run.metadata["cancellation_reason"] ?? "cancelled by user")
    }

    private func recordBackendEvent(_ event: AgentEvent, sequence: Int) throws {
        guard let eventRecorder else { return }
        switch event {
        case .runStarted(let payload):
            try eventRecorder.recordRun(payload.run)
        case .runCompleted(let payload):
            try eventRecorder.recordRun(payload.run)
        default:
            break
        }
        try eventRecorder.record(event, sequence: sequence)
    }

    private func assistantImageAttachment(from result: AgentToolResult, runID: String, sessionID: String) -> AgentMessageAttachmentRef? {
        guard result.runID == runID,
              result.sessionID == sessionID,
              result.error == nil,
              let contentJSON = result.contentJSON,
              let data = contentJSON.data(using: .utf8) else {
            return nil
        }
        let attachment: AgentMessageAttachmentRef?
        switch result.toolName {
        case "generate_image", "edit_image":
            attachment = (try? JSONDecoder().decode(GeneratedImageToolResultPayload.self, from: data))?.attachment
        case "present_image":
            attachment = (try? JSONDecoder().decode(PresentImageToolResultPayload.self, from: data))?.attachment
        default:
            attachment = nil
        }
        return attachment?.kind == .image ? attachment : nil
    }

    private func recordPendingApprovalIfNeeded(_ event: AgentEvent) throws {
        guard case .permissionRequested(let request) = event else { return }
        let approval = AgentPendingApproval(
            requestID: request.id,
            runID: request.runID,
            sessionID: request.sessionID,
            capability: request.capability,
            toolName: request.toolName,
            payloadJSON: request.payloadJSON
        )
        try pendingApprovalRepository?.upsert(pendingApproval: approval)
        try sessionRepository.savePendingApproval(approval)
    }

    private func persistMemoryOSAfterUserMessage(_ message: AgentMessage, isFirstUserMessage: Bool) async throws {
        guard let memoryOSIngestionWriter else { return }
        await memoryOSIngestionWriter.enqueueChatMessage(
            messageID: message.id,
            sessionID: session.id,
            role: "user",
            content: message.content,
            occurredAt: message.createdAt,
            personReferences: message.personReferences,
            sessionKind: session.governance.kind,
            isFirstUserMessage: isFirstUserMessage
        )
    }

    private func persistMemoryOSAfterAssistantMessage(_ message: AgentMessage) async throws {
        guard let memoryOSIngestionWriter else { return }
        await memoryOSIngestionWriter.enqueueChatMessage(
            messageID: message.id,
            sessionID: session.id,
            role: "assistant",
            content: message.content,
            occurredAt: message.createdAt
        )
    }
}
