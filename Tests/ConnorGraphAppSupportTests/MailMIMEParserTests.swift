import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("Mail MIME Parser Tests")
struct MailMIMEParserTests {
    @Test func multipartParsingNormalizesDataSlicesBeforeSubdataRanges() {
        let boundary = "----=_Part_4390460_436994253.1605718517303"
        let raw = """
        This is a MIME preamble that should be ignored.
        --\(boundary)
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: 8bit
        
        Hello from a sliced MIME part.
        --\(boundary)
        Content-Type: text/html; charset=utf-8
        Content-Transfer-Encoding: 8bit
        
        <html><body><p>Hello <b>HTML</b></p></body></html>
        --\(boundary)--

        """

        let result = MailMIMEParser().parseBodyWithHTML(
            rawData: Data(raw.utf8),
            fallbackString: "fallback",
            charset: nil,
            transferEncoding: nil,
            contentType: "multipart/alternative; boundary=\"\(boundary)\"",
            boundary: boundary
        )

        #expect(result.plainText.contains("Hello from a sliced MIME part."))
        #expect(result.htmlText?.contains("<html>") == true)
    }

    @Test func multipartParsingSupportsFinalPartWithoutClosingBoundary() {
        let boundary = "connor-alt-test"
        let raw = """
        --\(boundary)
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: 8bit
        
        Final part body without explicit trailing delimiter.
        """

        let result = MailMIMEParser().parseBodyWithHTML(
            rawData: Data(raw.utf8),
            fallbackString: "fallback",
            charset: nil,
            transferEncoding: nil,
            contentType: "multipart/alternative; boundary=\"\(boundary)\"",
            boundary: boundary
        )

        #expect(result.plainText.contains("Final part body without explicit trailing delimiter."))
    }
}
