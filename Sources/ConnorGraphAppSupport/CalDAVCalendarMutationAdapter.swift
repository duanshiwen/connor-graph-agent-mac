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
            let remote = try await mapHTTP { try await client.get(url: url, credential: credential) }
            let actual = header("ETag", in: remote)
            guard actual == expected else { throw CalendarMutationError.conflict(expected: expected, actual: actual) }
            let draft = apply(patch: patch, to: event)
            let uid = event.sourceMetadata?.remoteIdentifier ?? event.id.rawValue
            let body = try serializer.serialize(draft: draft, uid: uid)
            _ = try await mapHTTP { try await client.put(url: url, body: body, credential: credential, ifMatch: expected) }
            return try await verify(url: url, credential: credential, collection: collection, account: account, mutationKind: .updateEvent, eventID: event.id)
        case .delete:
            guard let event = currentEvent, let collection, let url = trustedURL(event: event, account: account, collection: collection), let expected = request.expectedVersion?.value else { throw CalendarMutationError.invalidInput("Missing event metadata") }
            try protect(event)
            let remote = try await mapHTTP { try await client.get(url: url, credential: credential) }
            let actual = header("ETag", in: remote)
            guard actual == expected else { throw CalendarMutationError.conflict(expected: expected, actual: actual) }
            _ = try await mapHTTP { try await client.delete(url: url, credential: credential, ifMatch: expected) }
            return CalendarMutationResult(receipt: .init(mutationKind: .deleteEvent, eventID: event.id, approved: true, summary: "Deleted calendar event \(event.id.rawValue)"))
        }
    }

    private func verify(url: URL, credential: String?, collection: CalendarCollection, account: CalendarAccount, mutationKind: CalendarMutationKind, eventID: CalendarEventID? = nil) async throws -> CalendarMutationResult {
        let response = try await mapHTTP { try await client.get(url: url, credential: credential) }
        guard let parsed = try parser.events(from: response.body).first else { throw CalendarMutationError.verificationFailed }
        let etag = header("ETag", in: response)
        let id = eventID ?? CalendarEventID(rawValue: "caldav-\(collection.id.rawValue)-\(parsed.uid)")
        let event = CalendarEvent(id: id, calendarID: collection.id, title: parsed.summary, start: .init(date: parsed.start.date, timeZoneIdentifier: parsed.start.timeZoneIdentifier), end: .init(date: parsed.end?.date ?? parsed.start.date, timeZoneIdentifier: parsed.end?.timeZoneIdentifier), isAllDay: parsed.isAllDay, location: parsed.location, url: parsed.url, notes: parsed.description, recurrenceSummary: parsed.recurrenceRule.map(CalendarRecurrenceSummary.init(ruleDescription:)), sourceMetadata: .init(sourceKind: account.sourceKind, remoteIdentifier: parsed.uid, resourceURL: url, etag: etag, isRecurring: parsed.recurrenceRule != nil, hasAttendees: !parsed.attendees.isEmpty))
        let receipt = CalendarWriteReceipt(mutationKind: mutationKind, eventID: event.id, approved: true, summary: mutationKind == .createEvent ? "Created calendar event \(event.id.rawValue)" : "Updated calendar event \(event.id.rawValue)")
        return CalendarMutationResult(receipt: receipt, confirmedEvent: event, remoteVersion: etag.map(CalendarMutationVersion.init(value:)))
    }

    private func collectionURL(account: CalendarAccount, collection: CalendarCollection) -> URL? { account.configuration.providerMetadata["collectionURL:\(collection.id.rawValue)"].flatMap(URL.init(string:)) }
    private func trustedURL(event: CalendarEvent, account: CalendarAccount, collection: CalendarCollection) -> URL? { guard let base = collectionURL(account: account, collection: collection), let url = event.sourceMetadata?.resourceURL, base.scheme?.lowercased() == url.scheme?.lowercased(), base.host?.lowercased() == url.host?.lowercased(), url.path.hasPrefix(base.path) else { return nil }; return url }
    private func protect(_ event: CalendarEvent) throws { if event.sourceMetadata?.isRecurring == true || event.recurrenceSummary != nil { throw CalendarMutationError.recurrenceUnsupported }; if event.sourceMetadata?.hasAttendees == true || !event.attendees.isEmpty || event.sourceMetadata?.organizerEmail != nil || event.sourceMetadata?.scheduleTag != nil { throw CalendarMutationError.schedulingUnsupported } }
    private func header(_ name: String, in response: CalendarCalDAVHTTPResponse) -> String? { response.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value }

    private func apply(patch: CalendarEventPatch, to event: CalendarEvent) -> CalendarEventDraft {
        func value<T>(_ patch: CalendarPatchValue<T>, current: T) -> T { if case .set(let v) = patch { return v }; return current }
        func optional<T>(_ patch: CalendarPatchValue<T>, current: T?) -> T? { switch patch { case .unchanged: current; case .clear: nil; case .set(let v): v } }
        return CalendarEventDraft(calendarID: event.calendarID, title: value(patch.title, current: event.title), start: value(patch.start, current: event.start), end: value(patch.end, current: event.end), isAllDay: value(patch.isAllDay, current: event.isAllDay), location: optional(patch.location, current: event.location), url: optional(patch.url, current: event.url), notes: optional(patch.notes, current: event.notes))
    }

    private func mapHTTP<T>(_ operation: () async throws -> T) async throws -> T {
        do { return try await operation() }
        catch CalendarCalDAVHTTPError.unauthorized { throw CalendarMutationError.authenticationRequired }
        catch CalendarCalDAVHTTPError.forbidden { throw CalendarMutationError.readOnlyCollection(nil) }
        catch CalendarCalDAVHTTPError.conflict { throw CalendarMutationError.conflict(expected: nil, actual: nil) }
        catch { throw CalendarMutationError.remoteFailure(String(describing: error)) }
    }
}
