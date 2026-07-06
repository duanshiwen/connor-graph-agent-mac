import Foundation
import Testing
import ConnorGraphCore

@Suite("Calendar and Contacts Capability Domain Tests")
struct CalendarContactsCapabilityDomainTests {
    @Test func connectedAccountCodableRoundTripsCapabilities() throws {
        let account = ConnectedAccount(
            id: ConnectedAccountID(rawValue: "connected-alice-example-com"),
            provider: .google,
            displayName: "Alice Google",
            primaryIdentifier: "alice@example.com",
            credentialBinding: ConnectedAccountCredentialBinding(credentialNamespace: "Connor", accountName: "alice@example.com", authMode: .oauth2),
            capabilities: [
                ConnectedAccountCapability(kind: .mail, status: .enabled),
                ConnectedAccountCapability(kind: .calendar, status: .enabled),
                ConnectedAccountCapability(kind: .contacts, status: .disabled)
            ],
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(ConnectedAccount.self, from: data)

        #expect(decoded == account)
        #expect(decoded.enabledCapabilities == [.mail, .calendar])
        #expect(decoded.capability(.contacts)?.status == .disabled)
    }

    @Test func credentialBindingsRequireCredentialNamespaceAndRejectLegacyKeychainService() throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        let mail = try decoder.decode(MailCredentialBinding.self, from: Data(#"{"credentialNamespace":"ConnorGraphAgent.MailCredentials","accountName":"mail:user@example.com","authMode":"appPassword"}"#.utf8))
        #expect(mail.credentialNamespace == "ConnorGraphAgent.MailCredentials")
        let encodedMail = String(decoding: try encoder.encode(mail), as: UTF8.self)
        #expect(encodedMail.contains("credentialNamespace"))
        #expect(!encodedMail.contains("keychainService"))
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(MailCredentialBinding.self, from: Data(#"{"keychainService":"ConnorGraphAgent.MailCredentials","accountName":"mail:user@example.com","authMode":"appPassword"}"#.utf8))
        }

        let calendar = try decoder.decode(CalendarCredentialBinding.self, from: Data(#"{"credentialNamespace":"ConnorGraphAgent.CalendarCredentials","accountName":"calendar:user@example.com","authMode":"appPassword"}"#.utf8))
        #expect(calendar.credentialNamespace == "ConnorGraphAgent.CalendarCredentials")
        let encodedCalendar = String(decoding: try encoder.encode(calendar), as: UTF8.self)
        #expect(encodedCalendar.contains("credentialNamespace"))
        #expect(!encodedCalendar.contains("keychainService"))
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(CalendarCredentialBinding.self, from: Data(#"{"keychainService":"ConnorGraphAgent.CalendarCredentials","accountName":"calendar:user@example.com","authMode":"appPassword"}"#.utf8))
        }

        let connected = try decoder.decode(ConnectedAccountCredentialBinding.self, from: Data(#"{"credentialNamespace":"ConnorGraphAgent.ConnectedAccounts","accountName":"connected:user@example.com","authMode":"oauth2"}"#.utf8))
        #expect(connected.credentialNamespace == "ConnorGraphAgent.ConnectedAccounts")
        let encodedConnected = String(decoding: try encoder.encode(connected), as: UTF8.self)
        #expect(encodedConnected.contains("credentialNamespace"))
        #expect(!encodedConnected.contains("keychainService"))
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(ConnectedAccountCredentialBinding.self, from: Data(#"{"keychainService":"ConnorGraphAgent.ConnectedAccounts","accountName":"connected:user@example.com","authMode":"oauth2"}"#.utf8))
        }
    }

    @Test func providerPresetsExposeDefaultCapabilities() {
        #expect(ConnectedAccountProviderKind.appleICloud.defaultCapabilities == [.mail, .calendar, .contacts])
        #expect(ConnectedAccountProviderKind.microsoft365.defaultCapabilities == [])
        #expect(ConnectedAccountProviderKind.google.defaultCapabilities == [])
        #expect(!ConnectedAccountProviderKind.microsoft365.isSupportedForNewConnection)
        #expect(!ConnectedAccountProviderKind.google.isSupportedForNewConnection)
        #expect(ConnectedAccountProviderKind.qq.defaultCapabilities == [.mail])
        #expect(ConnectedAccountProviderKind.netEase.defaultCapabilities == [.mail])
        #expect(ConnectedAccountProviderKind.genericIMAPSMTP.defaultCapabilities == [.mail])
    }

    @Test func calendarSourceConfigurationCodableRoundTripsReadOnlyCommercialFields() throws {
        let configuration = CalendarSourceConfiguration(
            sourceKind: .genericCalDAV,
            authMode: .appPassword,
            syncMode: .readOnly,
            serverURL: URL(string: "https://caldav.example.com")!,
            username: "shiwen@example.com",
            principalURL: URL(string: "https://caldav.example.com/principals/shiwen")!,
            calendarHomeSetURL: URL(string: "https://caldav.example.com/calendars/shiwen")!,
            subscriptionURL: nil,
            syncWindowPastDays: 30,
            syncWindowFutureDays: 365,
            enabledCollectionIDs: [CalendarID(rawValue: "calendar-work")],
            providerMetadata: ["preset": "nextcloud"]
        )

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(CalendarSourceConfiguration.self, from: data)

        #expect(decoded == configuration)
        #expect(decoded.sourceKind.supportsWrite == false)
        #expect(decoded.sourceKind.displayName == "标准 CalDAV")
    }

    @Test func calendarAccountMigratesLegacyProviderToSourceKindAndConfiguration() throws {
        let legacyJSON = """
        {
          "id": "calendar-account-macos-eventkit",
          "provider": "localFixture",
          "displayName": "本机日历",
          "health": {
            "status": "ready",
            "checkedAt": "2026-06-24T03:40:00Z",
            "summary": "已同步 macOS Calendar / EventKit",
            "blockingReasons": []
          },
          "createdAt": "2026-06-24T03:40:00Z",
          "updatedAt": "2026-06-24T03:40:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(CalendarAccount.self, from: Data(legacyJSON.utf8))

        #expect(decoded.sourceKind == .macOSEventKit)
        #expect(decoded.configuration.sourceKind == .macOSEventKit)
        #expect(decoded.configuration.syncMode == .readOnly)
        #expect(decoded.configuration.syncWindowPastDays == 30)
        #expect(decoded.configuration.syncWindowFutureDays == 365)
    }

    @Test func calendarDomainCodableRoundTripsEvent() throws {
        let event = CalendarEvent(
            id: CalendarEventID(rawValue: "event-1"),
            calendarID: CalendarID(rawValue: "calendar-work"),
            title: "产品讨论",
            start: CalendarEventDateTime(date: Date(timeIntervalSince1970: 1_000), timeZoneIdentifier: "Asia/Shanghai"),
            end: CalendarEventDateTime(date: Date(timeIntervalSince1970: 4_600), timeZoneIdentifier: "Asia/Shanghai"),
            isAllDay: false,
            location: "杭州",
            url: URL(string: "https://example.com/meet"),
            notes: "讨论 Calendar capability",
            attendees: [CalendarAttendee(id: CalendarAttendeeID(rawValue: "attendee-1"), name: "诗闻", email: "shiwen@example.com", role: .required, responseStatus: .accepted)],
            recurrenceSummary: CalendarRecurrenceSummary(ruleDescription: "每周五"),
            updatedAt: Date(timeIntervalSince1970: 5_000)
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(CalendarEvent.self, from: data)

        #expect(decoded == event)
        #expect(decoded.durationSeconds == 3_600)
    }

    @Test func timeAnalysisComputesSignedDifferencesAndOverlaps() {
        let base = Date(timeIntervalSince1970: 1_000)
        let ranges = [
            TimeAnalysisRange(id: "a", start: base, end: base.addingTimeInterval(3_600)),
            TimeAnalysisRange(id: "b", start: base.addingTimeInterval(1_800), end: base.addingTimeInterval(5_400)),
            TimeAnalysisRange(id: "c", start: base.addingTimeInterval(7_200), end: base.addingTimeInterval(8_000))
        ]

        let result = TimeRangeAnalyzer().analyze(ranges: ranges)

        #expect(result.startDifferences.first { $0.leftID == "a" && $0.rightID == "b" }?.signedSeconds == 1_800)
        #expect(result.startDifferences.first { $0.leftID == "b" && $0.rightID == "a" }?.signedSeconds == -1_800)
        let overlap = result.overlaps.first { $0.leftID == "a" && $0.rightID == "b" }
        #expect(overlap?.overlaps == true)
        #expect(overlap?.overlapSeconds == 1_800)
        #expect(result.overlaps.first { $0.leftID == "a" && $0.rightID == "c" }?.overlaps == false)
    }
}
