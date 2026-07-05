import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("MailCore2 MIME Parser Tests")
struct MailCore2MIMEParserTests {
    @Test func parsesBase64HTMLFullMessageIntoReadableTextAndHTML() throws {
        let html = "<!DOCTYPE html><html><body><p>Apple Receipt &amp; invoice</p></body></html>"
        let encoded = Data(html.utf8).base64EncodedString()
        let raw = "From: Apple <no-reply@example.com>\r\n"
            + "Subject: Receipt\r\n"
            + "Content-Type: text/html; charset=utf-8\r\n"
            + "Content-Transfer-Encoding: base64\r\n"
            + "\r\n"
            + encoded
            + "\r\n"
        let result = try MailCore2MIMEParser().parseFullMessageBody(rawData: Data(raw.utf8), fallbackString: "")

        #expect(result.plainText.contains("Apple Receipt & invoice"))
        #expect(result.htmlText?.lowercased().contains("<!doctype html") == true)
    }

    @Test func parsesMultipartAlternativeWithPlainAndHTMLBodies() throws {
        let raw = "From: Sender <sender@example.com>\r\n"
            + "Subject: Hello\r\n"
            + "Content-Type: multipart/alternative; boundary=\"ALT\"\r\n"
            + "\r\n"
            + "--ALT\r\n"
            + "Content-Type: text/plain; charset=utf-8\r\n"
            + "\r\n"
            + "Plain hello\r\n"
            + "--ALT\r\n"
            + "Content-Type: text/html; charset=utf-8\r\n"
            + "\r\n"
            + "<html><body><p>HTML hello</p></body></html>\r\n"
            + "--ALT--\r\n"
        let result = try MailCore2MIMEParser().parseFullMessageBody(rawData: Data(raw.utf8), fallbackString: "")

        #expect(result.plainText.contains("Plain hello"))
        #expect(result.htmlText?.contains("HTML hello") == true)
    }
}
