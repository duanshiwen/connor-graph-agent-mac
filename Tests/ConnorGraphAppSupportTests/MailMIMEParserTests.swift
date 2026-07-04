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

    @Test func base64TransferEncodingIgnoresMimeLineBreaks() {
        let encodedBody = """
        aGkg5q616K+X6Ze777yMDQoN
        CuaWsOS8muWRmOS/oeaBr+W3
        sua3u+WKoO+8jA0KDQrmnInp
        l67popjmrKLov47lj4rml7bm
        sp/pgJrvvIznpZ3lpb3vvIE=
        """

        let result = MailMIMEParser().parseBodyWithHTML(
            rawData: Data(encodedBody.utf8),
            fallbackString: "fallback",
            charset: "utf-8",
            transferEncoding: "base64",
            contentType: "text/plain; charset=utf-8",
            boundary: nil
        )

        #expect(result.plainText.hasPrefix("hi 段诗闻"))
        #expect(result.plainText.contains("新会员信息已添加"))
        #expect(!result.plainText.contains("aGkg5q616K"))
    }

    @Test func multipartBase64PartIgnoresMimeLineBreaks() {
        let boundary = "connor-base64-alt"
        let raw = """
        --\(boundary)
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: base64
        
        aGkg5q616K+X6Ze777yMDQoN
        CuaWsOS8muWRmOS/oeaBr+W3
        sua3u+WKoO+8jA0KDQrmnInp
        l67popjmrKLov47lj4rml7bm
        sp/pgJrvvIznpZ3lpb3vvIE=
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

        #expect(result.plainText.hasPrefix("hi 段诗闻"))
        #expect(result.plainText.contains("新会员信息已添加"))
        #expect(!result.plainText.contains("aGkg5q616K"))
    }

    @Test func quotedPrintableTransferEncodingDecodesUTF8AndSoftLineBreaks() {
        let encodedBody = """
        hi =E6=AE=B5=E8=AF=97=E9=97=BB=EF=BC=8C
        =E6=96=B0=E4=BC=9A=E5=91=98=E4=BF=A1=E6=81=AF=E5=B7=B2=
        =E6=B7=BB=E5=8A=A0=EF=BC=8C
        """

        let result = MailMIMEParser().parseBodyWithHTML(
            rawData: Data(encodedBody.utf8),
            fallbackString: "fallback",
            charset: "utf-8",
            transferEncoding: "quoted-printable",
            contentType: "text/plain; charset=utf-8",
            boundary: nil
        )

        #expect(result.plainText.contains("hi 段诗闻"))
        #expect(result.plainText.contains("新会员信息已添加，"))
        #expect(!result.plainText.contains("=E6"))
        #expect(!result.plainText.contains("已\n添加"))
    }
}
