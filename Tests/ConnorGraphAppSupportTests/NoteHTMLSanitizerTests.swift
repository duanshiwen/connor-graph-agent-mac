import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Note HTML sanitizer")
struct NoteHTMLSanitizerTests {
    @Test("Strips paired and unclosed dangerous blocks")
    func stripsDangerousBlocks() {
        let html = """
        <html><head><title>t</title></head><body>
        <script>steal()</script><p>safe</p>
        <style>body{color:red}</style>
        <iframe src="https://evil.example"></iframe>
        <object data="x"></object>
        <embed src="x">
        <applet code="x"></applet>
        <template><script>again()</script></template>
        <noscript>fallback</noscript>
        <form action="/x"><input name="q"></form>
        <button>go</button>
        <select><option>1</option></select>
        <textarea>hi</textarea>
        <svg onload="x()"></svg>
        <math><mtext>x</mtext></math>
        <script>unclosed
        </body></html>
        """
        let result = NoteHTMLSanitizer.sanitize(html)
        #expect(!result.contains("<script"))
        #expect(!result.contains("<style"))
        #expect(!result.contains("iframe"))
        #expect(!result.contains("<object"))
        #expect(!result.contains("<embed"))
        #expect(!result.contains("<applet"))
        #expect(!result.contains("template"))
        #expect(!result.contains("noscript"))
        #expect(!result.contains("<form"))
        #expect(!result.contains("<input"))
        #expect(!result.contains("<button"))
        #expect(!result.contains("<select"))
        #expect(!result.contains("textarea"))
        #expect(!result.contains("<svg"))
        #expect(!result.contains("<math"))
        #expect(!result.contains("<head"))
        #expect(!result.contains("doctype"))
        #expect(result.contains("<p>safe</p>"))
    }

    @Test("Removes event attributes in all quoting styles")
    func removesEventAttributes() {
        let html = """
        <p onclick="alert(1)">a</p>
        <div onmouseover='evil()'>b</div>
        <img src="pic.png" onerror=steal()>
        """
        let result = NoteHTMLSanitizer.sanitize(html)
        #expect(!result.contains("onclick"))
        #expect(!result.contains("onmouseover"))
        #expect(!result.contains("onerror"))
        #expect(result.contains("src=\"pic.png\""))
    }

    @Test("Neutralizes unsafe protocols and keeps safe links and inline images")
    func protocolHandling() {
        let html = """
        <a href="javascript:alert(1)">bad1</a>
        <a href='vbscript:msgbox(1)'>bad2</a>
        <a href="data:text/html,<script>1</script>">bad3</a>
        <a href="https://example.com">good</a>
        <img src="data:image/png;base64,AAAA">
        """
        let result = NoteHTMLSanitizer.sanitize(html)
        #expect(!result.contains("javascript:"))
        #expect(!result.contains("vbscript:"))
        #expect(!result.contains("data:text/html"))
        #expect(result.contains("href=\"https://example.com\""))
        #expect(result.contains("src=\"data:image/png;base64,AAAA\""))
    }
}
