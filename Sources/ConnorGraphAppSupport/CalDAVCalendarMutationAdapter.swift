import Foundation
import ConnorGraphCore

public struct CalDAVCalendarMutationAdapter: CalendarMutationAdapter, Sendable {
    public typealias CredentialProvider = @Sendable (CalendarAccount) async throws -> String?
    private let client: CalendarCalDAVHTTPClient
    private let credentialProvider: CredentialProvider
    private let uidGenerator: @Sendable () -> String
    private let resourceNameGenerator: @Sendable () -> String
    private let serializer: ICalendarEventSerializer
    private let parser: ICalendarParser

    public init(client: CalendarCalDAVHTTPClient = .init(), credentialProvider: @escaping CredentialProvider, uidGenerator: @escaping @Sendable () -> String = { UUID().uuidString }, resourceNameGenerator: @escaping @Sendable () -> String = { "\(UUID().uuidString).ics" }, serializer: ICalendarEventSerializer = .init(), parser: ICalendarParser = .init()) { self.client = client; self.credentialProvider = credentialProvider; self.uidGenerator = uidGenerator; self.resourceNameGenerator = resourceNameGenerator; self.serializer = serializer; self.parser = parser }

    public func mutate(_ request: CalendarMutationRequest, account: CalendarAccount, collection: CalendarCollection?, currentEvent: CalendarEvent?) async throws -> CalendarMutationResult {
        let credential = try await credentialProvider(account)
        switch request.operation {
        case .create:
            guard let draft = request.draft, let collection, let base = collectionURL(account: account, collection: collection), let url = URL(string: resourceNameGenerator(), relativeTo: base)?.absoluteURL else { throw CalendarMutationError.invalidInput("Missing trusted collection URL") }
            let uid = uidGenerator()
            let body = try serializer.serialize(draft: draft, uid: uid)
            _ = try await mapHTTP { try await client.put(url: url, body: body, credential: credential, ifNoneMatch: "*") }
            return try await verify(url: url, credential: credential, collection: collection, account: account, mutationKind: .createEvent)
        case .update:
            guard let event = currentEvent, let collection, let url = trustedURL(event: event, account: account, collection: collection), let expected = request.expectedVersion?.value, let patch = request.patch else { throw CalendarMutationError.invalidInput("Missing event metadata") }
            try protect(event)
            guard request.scope == .entireSeries else { throw CalendarMutationError.invalidInput("CalDAV 仅支持对整系列（entireSeries）修改/删除；单实例或未来实例操作暂不支持") }
            let remote = try await mapHTTP { try await client.get(url: url, credential: credential) }
            let actual = header("ETag", in: remote)
            guard actual == expected else { throw CalendarMutationError.conflict(expected: expected, actual: actual) }
            let uid = event.sourceMetadata?.remoteIdentifier ?? event.id.rawValue
            guard let master = try ICalendarOccurrenceEvaluator.evaluate(remote.body, start: .distantPast, end: .distantFuture, expanded: false).first(where: { $0.uid == uid }) else { throw CalendarMutationError.verificationFailed }
            // The selected occurrence may be months after DTSTART. Patch the actual series master.
            var baseline = event
            baseline.title = master.summary; baseline.location = master.location; baseline.notes = master.description; baseline.url = master.url; baseline.isAllDay = master.isAllDay
            baseline.start = .init(date: master.start.date, timeZoneIdentifier: master.start.timeZoneIdentifier)
            baseline.end = .init(date: master.end?.date ?? master.start.date, timeZoneIdentifier: master.end?.timeZoneIdentifier)
            if let id = baseline.start.timeZoneIdentifier, TimeZone(identifier: id) == nil { baseline.start.timeZoneIdentifier = nil }
            if let id = baseline.end.timeZoneIdentifier, TimeZone(identifier: id) == nil { baseline.end.timeZoneIdentifier = nil }
            baseline.recurrenceSummary = master.recurrenceRule.map(CalendarRecurrenceSummary.init(ruleDescription:))
            let draft = apply(patch: patch, to: baseline)
            let clearRecurrence: Bool
            if case .clear = patch.recurrence { clearRecurrence = true } else { clearRecurrence = false }
            let body = try ICalendarOccurrenceEvaluator.mergeSeries(original: remote.body, replacement: serializer.serialize(draft: draft, uid: uid), clearRecurrence: clearRecurrence)
            _ = try await mapHTTP { try await client.put(url: url, body: body, credential: credential, ifMatch: expected) }
            return try await verify(url: url, credential: credential, collection: collection, account: account, mutationKind: .updateEvent, eventID: event.id)
        case .delete:
            guard let event = currentEvent, let collection, let url = trustedURL(event: event, account: account, collection: collection), let expected = request.expectedVersion?.value else { throw CalendarMutationError.invalidInput("Missing event metadata") }
            try protect(event)
            guard request.scope == .entireSeries else { throw CalendarMutationError.invalidInput("CalDAV 仅支持对整系列（entireSeries）修改/删除；单实例或未来实例操作暂不支持") }
            let remote = try await mapHTTP { try await client.get(url: url, credential: credential) }
            let actual = header("ETag", in: remote)
            guard actual == expected else { throw CalendarMutationError.conflict(expected: expected, actual: actual) }
            _ = try await mapHTTP { try await client.delete(url: url, credential: credential, ifMatch: expected) }
            return CalendarMutationResult(receipt: .init(mutationKind: .deleteEvent, eventID: event.id, approved: true, summary: "Deleted calendar event \(event.id.rawValue)"), confirmedSeriesEvents: [], seriesRemoteIdentifier: event.sourceMetadata?.remoteIdentifier)
        }
    }

    private func verify(url: URL, credential: String?, collection: CalendarCollection, account: CalendarAccount, mutationKind: CalendarMutationKind, eventID: CalendarEventID? = nil) async throws -> CalendarMutationResult {
        let response = try await mapHTTP { try await client.get(url: url, credential: credential) }
        guard let parsed = try ICalendarOccurrenceEvaluator.evaluate(response.body, start: .distantPast, end: .distantFuture, expanded: false).first else { throw CalendarMutationError.verificationFailed }
        let etag = header("ETag", in: response)
        let id = eventID ?? CalendarEventID(rawValue: "caldav-\(collection.id.rawValue)-\(parsed.uid)")
        let event = CalendarEvent(id: id, calendarID: collection.id, title: parsed.summary, start: .init(date: parsed.start.date, timeZoneIdentifier: parsed.start.timeZoneIdentifier), end: .init(date: parsed.end?.date ?? parsed.start.date, timeZoneIdentifier: parsed.end?.timeZoneIdentifier), isAllDay: parsed.isAllDay, location: parsed.location, url: parsed.url, notes: parsed.description, attendees: mappedAttendees(parsed, calendarID: collection.id), recurrenceSummary: parsed.recurrenceRule.map(CalendarRecurrenceSummary.init(ruleDescription:)), sourceMetadata: .init(sourceKind: account.sourceKind, remoteIdentifier: parsed.uid, resourceURL: url, etag: etag, isRecurring: parsed.recurrenceRule != nil, organizerEmail: parsed.organizer?.email, hasAttendees: !parsed.attendees.isEmpty))
        let receipt = CalendarWriteReceipt(mutationKind: mutationKind, eventID: event.id, approved: true, summary: mutationKind == .createEvent ? "Created calendar event \(event.id.rawValue)" : "Updated calendar event \(event.id.rawValue)")
        let now = Date()
        let occurrences = try parser.occurrences(from: response.body, windowStart: now.addingTimeInterval(-Double(account.configuration.syncWindowPastDays) * 86400), windowEnd: now.addingTimeInterval(Double(account.configuration.syncWindowFutureDays) * 86400))
        let series = occurrences.filter { $0.uid == parsed.uid }.map { occurrence in
            var row = event
            row.id = CalendarEventID(rawValue: "caldav-\(collection.id.rawValue)-\(occurrence.uid)" + (occurrence.recurrenceIdentifier.map { "-" + $0 } ?? ""))
            row.title = occurrence.summary; row.location = occurrence.location; row.notes = occurrence.description; row.url = occurrence.url
            row.start = .init(date: occurrence.start.date, timeZoneIdentifier: occurrence.start.timeZoneIdentifier)
            row.end = .init(date: occurrence.end?.date ?? occurrence.start.date, timeZoneIdentifier: occurrence.end?.timeZoneIdentifier)
            row.isAllDay = occurrence.isAllDay
            row.attendees = mappedAttendees(occurrence, calendarID: collection.id)
            row.sourceMetadata?.recurrenceIdentifier = occurrence.recurrenceIdentifier
            row.sourceMetadata?.organizerEmail = occurrence.organizer?.email
            row.sourceMetadata?.hasAttendees = !occurrence.attendees.isEmpty
            row.sourceMetadata?.isRecurring = occurrence.recurrenceRule != nil || occurrence.recurrenceIdentifier != nil
            return row
        }
        return CalendarMutationResult(receipt: receipt, confirmedEvent: event, remoteVersion: etag.map(CalendarMutationVersion.init(value:)), confirmedSeriesEvents: series, seriesRemoteIdentifier: parsed.uid)
    }

    private func mappedAttendees(_ parsed: ICalendarEvent, calendarID: CalendarID) -> [CalendarAttendee] {
        let roles: [String: CalendarAttendeeRole] = ["REQ-PARTICIPANT": .required, "OPT-PARTICIPANT": .optional, "NON-PARTICIPANT": .resource]
        let statuses: [String: CalendarAttendeeResponseStatus] = ["NEEDS-ACTION": .needsAction, "ACCEPTED": .accepted, "DECLINED": .declined, "TENTATIVE": .tentative, "DELEGATED": .delegated]
        return parsed.attendees.enumerated().map { index, attendee in
            .init(id: .init(rawValue: "caldav-\(calendarID.rawValue)-\(parsed.uid)-attendee-\(index)"), name: attendee.name, email: attendee.email,
                role: roles[attendee.role?.uppercased() ?? ""] ?? .unknown, responseStatus: statuses[attendee.participationStatus?.uppercased() ?? ""] ?? .unknown)
        }
    }

    private func collectionURL(account: CalendarAccount, collection: CalendarCollection) -> URL? { account.configuration.providerMetadata["collectionURL:\(collection.id.rawValue)"].flatMap(URL.init(string:)) }
    private func trustedURL(event: CalendarEvent, account: CalendarAccount, collection: CalendarCollection) -> URL? { guard let base = collectionURL(account: account, collection: collection), let url = event.sourceMetadata?.resourceURL, base.scheme?.lowercased() == url.scheme?.lowercased(), base.host?.lowercased() == url.host?.lowercased(), url.port == base.port, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, url.standardized.path.hasPrefix(base.standardized.path.hasSuffix("/") ? base.standardized.path : base.standardized.path + "/") else { return nil }; return url }
    private func protect(_ event: CalendarEvent) throws { if event.sourceMetadata?.hasAttendees == true || !event.attendees.isEmpty || event.sourceMetadata?.organizerEmail != nil || event.sourceMetadata?.scheduleTag != nil { throw CalendarMutationError.schedulingUnsupported } }
    private func header(_ name: String, in response: CalendarCalDAVHTTPResponse) -> String? { response.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value }

    private func apply(patch: CalendarEventPatch, to event: CalendarEvent) -> CalendarEventDraft {
        func value<T>(_ patch: CalendarPatchValue<T>, current: T) -> T { if case .set(let v) = patch { return v }; return current }
        func optional<T>(_ patch: CalendarPatchValue<T>, current: T?) -> T? { switch patch { case .unchanged: current; case .clear: nil; case .set(let v): v } }
        let recurrence: CalendarRecurrence?
        switch patch.recurrence {
        case .unchanged:
            if let rule = event.recurrenceSummary?.ruleDescription {
                recurrence = CalendarRecurrence(rrule: rule)
            } else {
                recurrence = nil
            }
        case .clear:
            recurrence = nil
        case .set(let value):
            recurrence = value
        }
        return CalendarEventDraft(calendarID: event.calendarID, title: value(patch.title, current: event.title), start: value(patch.start, current: event.start), end: value(patch.end, current: event.end), isAllDay: value(patch.isAllDay, current: event.isAllDay), location: optional(patch.location, current: event.location), url: optional(patch.url, current: event.url), notes: optional(patch.notes, current: event.notes), recurrence: recurrence)
    }

    private func mapHTTP<T>(_ operation: () async throws -> T) async throws -> T {
        do { return try await operation() }
        catch CalendarCalDAVHTTPError.unauthorized { throw CalendarMutationError.authenticationRequired }
        catch CalendarCalDAVHTTPError.forbidden { throw CalendarMutationError.readOnlyCollection(nil) }
        catch CalendarCalDAVHTTPError.conflict { throw CalendarMutationError.conflict(expected: nil, actual: nil) }
        catch { throw CalendarMutationError.remoteFailure(String(describing: error)) }
    }
}
