import Foundation
import ConnorGraphCore

/// One-call briefing for the final-synthesis proactive reminder: concurrently
/// loads upcoming events across ALL calendars (server-computed window) and the
/// received mail from the same look-back window across ALL accounts, so the model gets everything
/// that may need the user's immediate attention from a single tool call with
/// no arguments and no prior orchestration (no get_current_time, no
/// list_calendars, no mail_list_accounts, no parallel fan-out).
///
/// The tool is registered under the read-only `.readCalendar` capability and
/// audits the mail portion through the policy engine as `.readMail` at
/// execution time; when mail is unavailable or not permitted the brief
/// degrades gracefully to calendar-only instead of failing.
public struct AttentionBriefTool: AgentTool {
    public let calendarRuntime: any AgentCalendarRuntime
    public let mailRuntime: (any AgentMailRuntime)?
    public let recorder: (any NativeSourceReferenceRecording)?
    public static let toolName = "attention_brief"
    public static let defaultLookAheadDays = 2
    public static let maximumLookAheadDays = 31
    public static let defaultMailLimit = 10
    public var name: String { Self.toolName }
    public var description: String { "Get a one-call attention briefing: upcoming events across ALL calendars for the next \(Self.defaultLookAheadDays) days plus received mail from the previous \(Self.defaultLookAheadDays) days across ALL accounts, newest first, without mutating read state. The time windows are computed on the server, so no prior get_current_time, list_calendars, or mail_list_accounts call is needed. Use it before composing the final reply to spot anything the user must act on soon. Pass days to set both windows (1–\(Self.maximumLookAheadDays)); use calendar_read get_event or mail_get_message for selected details." }
    public var permission: AgentPermissionCapability { .readCalendar }
    public var inputSchema: AgentToolInputSchema {
        .closedObject(properties: [
            "days": .integer(description: "Optional calendar look-ahead and received-mail look-back window in days from now (default \(Self.defaultLookAheadDays), max \(Self.maximumLookAheadDays))."),
            "mailLimit": .integer(description: "Maximum recent received mail summaries to include (default \(Self.defaultMailLimit)).")
        ], required: [])
    }

    public init(calendarRuntime: any AgentCalendarRuntime, mailRuntime: (any AgentMailRuntime)? = nil, recorder: (any NativeSourceReferenceRecording)? = nil) {
        self.calendarRuntime = calendarRuntime
        self.mailRuntime = mailRuntime
        self.recorder = recorder
    }

    public var inputExamples: [[String: SendableJSONValue]] {
        [[:]]
    }

    public func normalizeLegacyArguments(_ arguments: AgentToolArguments) -> AgentToolArguments {
        arguments.normalizingAliases([
            "days": ["lookAheadDays", "windowDays", "horizonDays", "rangeDays"],
            "mailLimit": ["mailMaxResults", "maxMail", "recentMailLimit"]
        ])
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let requestedDays = arguments.int("days") ?? Self.defaultLookAheadDays
        let days = min(max(1, requestedDays), Self.maximumLookAheadDays)
        let mailLimit = NativeSearchLimitPolicy.clampSearchLimit(arguments.int("mailLimit") ?? Self.defaultMailLimit)
        let now = Date()
        let endDate = now.addingTimeInterval(TimeInterval(days) * 86_400)

        async let upcomingEvents = calendarRuntime.searchEvents(
            query: "",
            startDate: now,
            endDate: endDate,
            timePreset: nil,
            timeFilterMode: NativeSearchTemporalFilterMode.intervalOverlapsRange.rawValue,
            timeSort: NativeSearchTemporalSort.timeAscThenRelevance.rawValue,
            limit: NativeSearchLimitPolicy.defaultSearchLimit,
            runID: context.runID,
            sessionID: context.sessionID
        )
        let mailSection = await loadRecentMail(days: days, limit: mailLimit, now: now, context: context)
        let events = try await upcomingEvents

        await recorder?.record(events.map { NativeSourceReference.calendarEvent($0, query: nil, strength: .summaryCandidate, toolName: name, context: context) })
        if case .included(let messages) = mailSection {
            await recorder?.record(messages.map { NativeSourceReference.mailSummary($0, query: "attention brief", toolName: name, context: context) })
        }

        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: AttentionBriefTextRenderer.render(events: events, days: days, mail: mailSection),
            contentJSON: try AttentionBriefJSON.encode(events: events, days: days, mail: mailSection)
        )
    }

    private func loadRecentMail(days: Int, limit: Int, now: Date, context: AgentToolExecutionContext) async -> AttentionBriefMailSection {
        guard let mailRuntime else { return .unavailable("No mail runtime is connected.") }
        if !context.approvedCapabilities.contains(.readMail) {
            let decision = await context.policyEngine.evaluate(
                capability: .readMail,
                runID: context.runID,
                sessionID: context.sessionID,
                toolName: name,
                payloadJSON: "{\"section\":\"recent_received_mail\",\"days\":\(days),\"limit\":\(limit)}"
            )
            guard case .approved = decision.outcome else {
                return .unavailable("Mail was skipped because readMail is not permitted in the current session mode.")
            }
        }
        do {
            let messages = try await mailRuntime.searchMessages(
                MailRuntimeSearchRequestBridge(
                    query: "",
                    accountID: nil,
                    limit: limit,
                    startDate: now.addingTimeInterval(-TimeInterval(days) * 86_400),
                    endDate: now,
                    timeSort: NativeSearchTemporalSort.timeDescThenRelevance.rawValue
                ),
                runID: context.runID,
                sessionID: context.sessionID
            )
            return .included(messages)
        } catch {
            return .failed("Recent mail could not be loaded: \(error.localizedDescription)")
        }
    }
}

enum AttentionBriefMailSection: Sendable {
    case included([MailMessageSummary])
    case unavailable(String)
    case failed(String)
}

private enum AttentionBriefTextRenderer {
    static func render(events: [CalendarEvent], days: Int, mail: AttentionBriefMailSection) -> String {
        let formatter = ISO8601DateFormatter()
        var lines: [String] = []
        let window = "next \(days) day\(days == 1 ? "" : "s"), all calendars"
        if events.isEmpty {
            lines.append("Upcoming events (\(window)): none.")
        } else {
            lines.append("Upcoming events (\(window)): \(events.count)")
            for (index, event) in events.enumerated() {
                var row = "\(index + 1). \(event.title) | \(formatter.string(from: event.start.date)) – \(formatter.string(from: event.end.date))"
                if event.isAllDay { row += " | all-day" }
                if let location = event.location, !location.isEmpty { row += " | location: \(location)" }
                if let notes = event.notes, !notes.isEmpty { row += " | notes: \(String(notes.prefix(120)))" }
                row += " | eventID: \(event.id.rawValue)"
                lines.append(row)
            }
        }
        switch mail {
        case .included(let messages):
            if messages.isEmpty {
                lines.append("Received mail (previous \(days) day\(days == 1 ? "" : "s"), all accounts): none.")
            } else {
                lines.append("Received mail (previous \(days) day\(days == 1 ? "" : "s"), all accounts, newest first): \(messages.count)")
                for (index, message) in messages.enumerated() {
                    let sender = message.from.name.map { "\($0) <\(message.from.email)>" } ?? message.from.email
                    let state = message.flags.isRead ? "read" : "unread"
                    lines.append("\(index + 1). \(message.subject) | from: \(sender) | \(formatter.string(from: message.date)) | \(state) | messageID: \(message.id.rawValue)")
                }
            }
        case .unavailable(let reason), .failed(let reason):
            lines.append("Received mail for the previous \(days) days: \(reason)")
        }
        lines.append("Surface anything the user must act on soon; read state was not changed. Use calendar_read get_event or mail_get_message for details.")
        return lines.joined(separator: "\n")
    }
}

private enum AttentionBriefJSON {
    static func encode(events: [CalendarEvent], days: Int, mail: AttentionBriefMailSection) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        var eventRows = (try JSONSerialization.jsonObject(with: encoder.encode(events)) as? [[String: Any]]) ?? []
        for index in eventRows.indices {
            if let id = eventRows[index]["id"] { eventRows[index]["eventID"] = id }
        }

        var mailObject: [String: Any]
        switch mail {
        case .included(let messages):
            var messageRows = (try JSONSerialization.jsonObject(with: encoder.encode(messages)) as? [[String: Any]]) ?? []
            for index in messageRows.indices {
                if let id = messageRows[index]["id"] { messageRows[index]["messageID"] = id }
            }
            mailObject = ["status": "included", "messages": messageRows]
        case .unavailable(let reason):
            mailObject = ["status": "unavailable", "reason": reason, "messages": [[String: Any]]()]
        case .failed(let reason):
            mailObject = ["status": "failed", "reason": reason, "messages": [[String: Any]]()]
        }

        let object: [String: Any] = [
            "lookAheadDays": days,
            "mailLookBackDays": days,
            "events": eventRows,
            "mail": mailObject
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
