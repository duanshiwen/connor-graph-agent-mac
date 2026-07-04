import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("MailCore2 Backend Adapter Tests")
struct MailCore2BackendAdapterTests {
    @Test func mailCore2BackendCanBeConstructedBehindProtocol() async throws {
        let backend: any MailProtocolBackend = MailCore2MailBackend()
        #expect(backend.backendName == "mailcore2")
    }

    @Test func mailCore2FolderFlagsMapToRemoteMailboxRoles() {
        let sent = MailCore2FolderMapper.remoteMailbox(path: "Sent Messages", delimiter: "/", isInbox: false, isSent: true, isDrafts: false, isArchive: false, isTrash: false, isSpam: false)
        #expect(sent.role == .sent)
        #expect(sent.path == "Sent Messages")
        #expect(sent.delimiter == "/")

        let fallback = MailCore2FolderMapper.remoteMailbox(path: "已发送邮件", delimiter: "/", isInbox: false, isSent: false, isDrafts: false, isArchive: false, isTrash: false, isSpam: false)
        #expect(fallback.role == .sent)
    }

    @Test func legacyBackendCanBeSelectedAsFallback() {
        let strategy = MailBackendStrategy(preference: .automatic, isMailCore2Available: true)
        #expect(strategy.primaryBackendName == "mailcore2")
        #expect(strategy.fallbackBackendName == "legacy")

        let legacyOnly = MailBackendStrategy(preference: .legacy, isMailCore2Available: true)
        #expect(legacyOnly.primaryBackendName == "legacy")
        #expect(legacyOnly.fallbackBackendName == nil)
    }
}
