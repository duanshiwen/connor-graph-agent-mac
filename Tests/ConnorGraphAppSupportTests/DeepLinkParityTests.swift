import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("Deep link parity")
struct DeepLinkParityTests {
    @Test func bareOpenSessionLinkMatchesWindowsNoteLinks() throws {
        let link = try ConnorDeepLinkNavigator().resolve(URL(string: "connor://open?session=abc-123")!)
        #expect(link.item == .home)
        #expect(link.sessionID == "abc-123")
    }
    @Test func browserDestinationRetainsBrowserRequirement() throws {
        let link = try ConnorDeepLinkNavigator().resolve(URL(string: "connor://open/browserWorkspace?session=abc-123")!)
        #expect(link.requiresBrowserVisible)
        #expect(link.sessionID == "abc-123")
    }
    @Test func rejectsAmbiguousQueryAndExtraPathSegments() {
        for value in ["connor://open/home?session=a&session=b", "connor://open/home?session=..%2Fconfig", "connor://open/home/mail?session=a", "connor://user@open/home?session=a"] {
            #expect(throws: ConnorDeepLinkNavigatorError.self) { try ConnorDeepLinkNavigator().resolve(URL(string: value)!) }
        }
    }
    @Test func queryDecodesValuesIndividually() throws {
        let link = try ConnorDeepLinkNavigator().resolve(URL(string: "connor://open/settings?focus=mail%26permissions")!)
        #expect(link.focus == "mail&permissions")
    }
}
