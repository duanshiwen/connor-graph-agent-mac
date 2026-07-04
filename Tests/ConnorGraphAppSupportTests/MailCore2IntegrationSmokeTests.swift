import Testing

#if canImport(MailCore)
import MailCore
#endif

@Suite("MailCore2 Integration Smoke Tests")
struct MailCore2IntegrationSmokeTests {
    @Test func mailCore2ModuleCanBeImportedAndCreateIMAPSession() {
        #if canImport(MailCore)
        let session = MCOIMAPSession()
        session.hostname = "imap.example.com"
        #expect(session.hostname == "imap.example.com")
        #else
        Issue.record("MailCore module is not importable")
        #endif
    }
}
